package nuKardex;

use Dancer ':syntax';
use Dancer::Exception qw(:all);
use Dancer::Plugin::Database;
use POSIX qw(locale_h);
use LWP::UserAgent();
use LWP::Simple();
use URI::Encode qw(uri_decode);
use XML::Simple qw(:strict);
use MIME::Lite::TT::HTML;
use Data::Dumper;
use File::Slurper;
use File::Copy;
use DateTime;

our $VERSION = '1.1.0';

# Set Danish locale
setlocale(LC_ALL, 'da_DK');

# Login
any ['get', 'post'] => '/login' => sub {
	my $error;
	session 'user' => '';

	if ( config->{testing}{disable_authentication} ) {
		# log the user automatically into the system
		session 'logged_in' => true;
		session 'user' => setting('demousername');
		return redirect '/';
	}

	# if this is a login attempt
	if ( request->method() eq 'POST' ) {
		# check username and password
		if ( params->{username} ne setting('username') && params->{username} ne setting('demousername') ) {
			$error = "Ugyldigt brugernavn / password";
		}
		elsif ( params->{password} ne setting('password') ) {
			$error = "Ugyldigt brugernavn / password";
		}
		# credentials are OK
		else {
			# log the user into the system
			session 'logged_in' => true;
			session 'user' => params->{username};
			return redirect '/';
		}
		# wait for next login attempt
		sleep 5 if $error;
	}

	# display the login form
	set layout => 'login';
	template 'login.tt', { 'error' => $error, 'version' => $VERSION };
};


# Logout
get '/logout' => sub {
	# destroy session and redirect to /
	session->destroy;
	return redirect '/login';
};

# Restart
get '/restart' => sub {
	return redirect '/';
};

# Main program
get '/' => sub {
	# Redirect to /login if user is not signed in
	return redirect '/login' if ( ! session('logged_in') );

	my ( $admsys, $bibsys, $error, $item_ref );
	$admsys = params->{admsys} if params->{admsys};
	$bibsys = params->{bibsys} if params->{bibsys};

	if ( $admsys or $bibsys ) {
		($error, $item_ref) = get_items({ admsys => $admsys, bibsys => $bibsys });
	}

	set layout => 'main';
	template 'index', { items => $item_ref, error => $error };
};

# Re-print a barcode label
get '/genudskriv' => sub {
	# Redirect to /login if user is not signed in
	return redirect '/login' if ( ! session('logged_in') );

	set layout => 'main';
	template 'genudskriv', { attach_printer => 1 };
};

# Admin area
get '/admin' => sub {
	# Redirect to /login if user is not signed in
	return redirect '/login' if ( ! session('logged_in') );

	set layout => 'admin';
	template 'admin', { };
};

#
# nuKardex API
#

post '/opret' => sub {
	send_error("Forbidden", 403) if ( ! session('logged_in') );

	set serializer => 'JSON';
	my %resp;

	my $row = database->quick_select('barcode', {id => 1});
	my $barcode = $row->{current};

	# Update or create item in Aleph
	my $result;
	if ( params->{barcode} ) {
		$result = update_item( { 
			barcode => params->{barcode},
			new_barcode => $barcode,
			admsys => params->{admsys},
			record => params->{record},
			processstatus => params->{processstatus},
			} );
	}
	else {
		$result = new_item( {
			new_barcode => $barcode,
			admsys => params->{admsys},
			year => params->{year},
			volume => params->{volume},
			issue => params->{issue},
			sublibrary => params->{label_library},
			collection => params->{label_sublibrary},
			itemstatus => params->{item_status},
			processstatus => params->{processstatus},
			} );
	}

	# Increment barcode in the database if the update_item was successful
	if ( $result->{success} ) {
		database->quick_update('barcode', { id => 1}, { current => $barcode+1 } );
	}
	
	# Set response from update_item
	$resp{success} = $result->{success};
	$resp{status} = $result->{status};

	# Set return parameters from this API
	$resp{barcode} = $barcode;
	$resp{record} = params->{record};
	$resp{admsys} = params->{admsys};
	$resp{volume} = params->{volume};
	$resp{issue} = params->{issue};
	$resp{year} = params->{year};
	$resp{title} = params->{title};
	$resp{collection} = params->{collection};
	$resp{library} = params->{label_library};
	$resp{sublibrary} = params->{label_sublibrary};
	$resp{shelfmark} = params->{label_shelfmark};
	$resp{itemstatus} = params->{item_status};

	return \%resp;
};

post '/ryk' => sub {
	send_error("Forbidden", 403) if ( ! session('logged_in') );

	set serializer => 'JSON';

	my %resp;
	$resp{success} = 1;
	$resp{record} = params->{record};
	$resp{volume} = params->{volume};
	$resp{issue} = params->{issue};
	$resp{year} = params->{year};
	$resp{email} = params->{email};

	if ( is_demo_user() ) {
		$resp{email} = config->{demouser_email};
	}

	# Get the parameters from the form
	my %params = params;

	# Set Template Toolkit options
	my %options;
	$options{INCLUDE_PATH} = 'lib/';

	# Compose message using templates and send
	my $message = MIME::Lite::TT::HTML->new(
		From		=> config->{mailer}{sender},
		To			=> $resp{email},
		Cc			=> is_demo_user() ? '' : config->{mailer}{cc},
		Subject		=> config->{mailer}{subject},
		TimeZone	=> config->{mailer}{tz},
		Encoding	=> '8bit',
		Template	=> {
			html	=> 'rykker.html.tt',
			text	=> 'rykker.text.tt',
			},
			TmplOptions	=> \%options,
			TmplParams	=> \%params,
			Charset		=> 'utf8',
			);

	try {
		if ( config->{mailer}{smtp} ) {
			$message->send('smtp', config->{mailer}{smtp}, Timeout => 60 );
		}
		else {
			$message->send;
		}
	} catch {
		error 'Died in ' . __PACKAGE__ . ' sending mail : ' . $_[0] if ( $_[0] );
		$resp{success} = 0;
	};

	# Erite the reminder to the database and return
	database->quick_insert('reminder', { record => params->{record}, admsys => params->{admsys}, timestamp => time() } ) if $resp{success};
	return \%resp;
};

post '/slet' => sub {
	send_error("Forbidden", 403) if ( ! session('logged_in') );

	set serializer => 'JSON';
	my %resp;

	my $row = database->quick_select('barcode', {id => 1});
	my $barcode = $row->{current};

	if ( is_demo_user() ) {
		$resp{success} = 0;
		$resp{status} = "Demo mode";
		return \%resp;
	}

	# Delete item in Aleph

	my $result = delete_item( { 
		barcode => params->{barcode}
		} );
	
	# Set response from update_item
	$resp{success} = $result->{success};
	$resp{status} = $result->{status};
	$resp{record} = params->{record};
	$resp{volume} = params->{volume};
	$resp{issue} = params->{issue};
	$resp{year} = params->{year};

	return \%resp;
};

post '/subscriptions' => sub {
	send_error("Forbidden", 403) if ( ! session('logged_in') );

	set serializer => 'JSON';
	my %resp;
	$resp{success} = 0;

	my $json = params->{subscriptions};

	if ( $json and ! is_demo_user() ) {
		my $backup_id = time();
		if ( -f "public/data/subscriptions_$backup_id.json" ) {
			unlink "public/data/subscriptions_$backup_id.json";
		}
		if ( -f "public/data/subscriptions.json" ) {
			move("public/data/subscriptions.json", "public/data/subscriptions_$backup_id.json");
		}
		try {
			# Try to write the new subscriptions.json file to disk
			$resp{success} = 1;
			File::Slurper::write_text("public/data/subscriptions.json", $json, "UTF-8");
		} catch {
			# If it fails then restore the backup to the now possibly truncated subscriptions.json file
			$resp{success} = 0;
			if ( -f "public/data/subscriptions_$backup_id.json" ) {
				unlink "public/data/subscriptions.json";
				move("public/data/subscriptions_$backup_id.json", "public/data/subscriptions.json");
			}
		};
	}

	# Done
	return \%resp;
};

#
# nuKardex helper subs and hooks
#

sub get_items {
	my $p = shift;

	my $doc_num;

	if ( $p->{bibsys} ) {
		$doc_num = $p->{bibsys};
	}
	else {
		$doc_num = $p->{admsys};
	}

	# Get item data
	my $content = LWP::Simple::get( 
		setting('aleph_x_server') .
		"/?op=item-data&doc_num=" . $doc_num .
		"&base=" . setting('aleph_logical_base') .
		"&translate=N" );

	if ( $content ) {
		my $item_ref = XML::Simple::XMLin( $content, KeyAttr => {}, ForceArray => ['item'] );
		
		#debug Data::Dumper::Dumper($item_ref);

		# Get error message if present
		my $error = $item_ref->{error} // '';

		my @items;
		foreach my $i ( @{$item_ref->{item}} ) {
			# Only get items that are not yet arrived
			if ( $i->{expected} eq 'Y' ) {
				# Get most recent outstanding reminder - if any
				my $reminder = database->quick_select('reminder', { record => $i->{'rec-key'} }, { order_by => { desc => 'timestamp' }, columns => [qw(timestamp)] });
				push @items, { 
					record => $i->{'rec-key'},
					# The pseudo-generated barcode is our identifier to read the item later on via
					# the Aleph X-service
					barcode => $i->{'barcode'},
					# Volume / issue / year might be empty and turn up as an empty hash from XMLin
					# so we must be able to check for this and present a scalar instead (admsys: 128928)
					volume => ref $i->{'enumeration-a'} eq '' ? $i->{'enumeration-a'} : "",
					issue => ref $i->{'enumeration-b'} eq '' ? $i->{'enumeration-b'} : "",
					year => ref $i->{'chronological-i'} eq '' ? $i->{'chronological-i'} : "",
					sub_library => $i->{'sub-library'},
					collection => ref $i->{'collection'} eq '' ? $i->{'collection'} : "",
					item_status => $i->{'item-status'},
					reminder => $reminder->{timestamp}
				}
			}
		}

		return ($error, \@items);
	}
}

sub update_item {
	my $p = shift;

	# Get item data
	my $content = LWP::Simple::get( 
		setting('aleph_x_server') .
		"/?op=read-item&barcode=" . $p->{barcode} .
		"&library=" . setting('aleph_adm_library') .
		"&translate=N" );

	# Check if we get a valid item record in return (is the barcode and admsys matching the record?)
	if ( $content and $content =~ m{<z30-barcode>$p->{barcode}</z30-barcode>} and $content =~ m{$p->{admsys}</z30-doc-number>} ) {

		debug "Existing item record: $content";

		# Change the read-item to an update-item record
		$content =~ s{read-item>}{update-item>}g;

		# Change the pseudo-generated barcode to the new barcode
		$content =~ s{<z30-barcode>$p->{barcode}</z30-barcode>}{<z30-barcode>$p->{new_barcode}</z30-barcode>};

		my $date = DateTime->now(time_zone => "local")->ymd('');

		# Update arrival dates
		$content =~ s{<z30-issue-date>\d*?</z30-issue-date>}{<z30-issue-date>$date</z30-issue-date>};
		$content =~ s{<z30-expected-arrival-date>\d*?</z30-expected-arrival-date>}{<z30-expected-arrival-date>$date</z30-expected-arrival-date>};
		$content =~ s{<z30-arrival-date>\d*?</z30-arrival-date>}{<z30-arrival-date>$date</z30-arrival-date>};

		# Update cataloger
		my $cataloger = setting('aleph_user_name');
		$content =~ s{<z30-cataloger>\w*?</z30-cataloger>}{<z30-cataloger>$cataloger</z30-cataloger>};

		#debug "Process-status " . $p->{processstatus};

		# Update process status
		if ( $p->{processstatus} ) {
			$content =~ s{<z30-item-process-status></z30-item-process-status>}{<z30-item-process-status>$p->{processstatus}</z30-item-process-status>};
		}
		
		debug "Updated item record: $content";

		# Demo user just returns with success
		if ( is_demo_user() ) {
			#database->quick_delete('reminder', { record => params->{record} } );
			return { success => 1, status => "Item has been updated successfully" };
		}

		# We need to use LWP::UserAgent as we need to be able to POST
		my $ua = LWP::UserAgent->new( timeout => 30, ssl_opts => { verify_hostname => 0 } );

		# Set the parameters to the X-service
		my %form;
		$form{'xml_full_req'} = $content ;
		$form{'op'} = 'update_item' ;
		$form{'library'} = setting('aleph_adm_library');
		# It is required that the adm_doc_number is zero-padded in Aleph 21 (at least)
		$form{'adm_doc_number'} = sprintf( "%09d", $p->{admsys} );
		$form{'user_name'} = setting('aleph_user_name');
		$form{'user_password'} = setting('aleph_user_password');
		$form{'translate'} = 'N';

		debug \%form;

		# Send to X-service
		my $response = $ua->post(setting('aleph_x_server'), \%form);

		if ( $response->is_success) {
			# The LWP::UserAgent response was a success
			my $result = $response->decoded_content;
			# Check if Aleph puts out an error
			if ( $result =~ m{<error>(.+?)</error>}s ) {
				my $message = $1;
				# A success is also an error, so discard "Item has been updated successfully." as an error
				if ( $message =~ m{updated successfully} ) {
					database->quick_delete('reminder', { record => $p->{record} } );
					return { success => 1, status => uri_decode($message) };
				}
				else {
					return { success => 0, status => uri_decode($message) };
				}
			}
		}

		debug Dumper(\$response);
	}

	return { success => 0, status => "No valid item returned from Aleph op=read_item" };
}

sub new_item {
	my $p = shift;

	$p->{volume} = '^' unless $p->{volume};
	my $date = DateTime->now(time_zone => "local")->ymd('');

	# Payload
	my $content;
	$content .= '<?xml version="1.0" encoding="UTF-8" ?>' . "\n";
	$content .= '<z30>' . "\n";
	$content .= '  <z30-doc-number>' . $p->{admsys} . '</z30-doc-number>' . "\n";
	$content .= '  <z30-barcode>' . $p->{new_barcode} . '</z30-barcode>' . "\n";
	$content .= '  <z30-sub-library>' . $p->{sublibrary} .'</z30-sub-library>' . "\n";
	$content .= '  <z30-material>ISSUE</z30-material>' . "\n";
	$content .= '  <z30-item-status>' . $p->{itemstatus} .'</z30-item-status>' . "\n";
	$content .= '  <z30-collection>' . $p->{collection} . '</z30-collection>' . "\n";
	$content .= '  <z30-description>' . $p->{year}  . ' ' . $p->{volume} . ' ' . $p->{issue} . '</z30-description>' . "\n";
	$content .= '  <z30-issue-date>' . $date . '</z30-issue-date>' . "\n";
	$content .= '  <z30-expected-arrival-date>' . $date . '</z30-expected-arrival-date>' . "\n";
	$content .= '  <z30-arrival-date>' . $date . '</z30-arrival-date>' . "\n";
	$content .= '  <z30-item-process-status>' . $p->{processstatus} . '</z30-item-process-status>' . "\n" if $p->{processstatus};
	$content .= '  <z30-enumeration-a>' . $p->{volume} . '</z30-enumeration-a>' . "\n";
	$content .= '  <z30-enumeration-b>' . $p->{issue} . '</z30-enumeration-b>' . "\n";
	$content .= '  <z30-enumeration-c />' . "\n";
	$content .= '  <z30-enumeration-d />' . "\n";
	$content .= '  <z30-enumeration-e />' . "\n";
	$content .= '  <z30-enumeration-f />' . "\n";
	$content .= '  <z30-enumeration-g />' . "\n";
	$content .= '  <z30-enumeration-h />' . "\n";
	$content .= '  <z30-chronological-i>' . $p->{year} . '</z30-chronological-i>' . "\n";
	$content .= '  <z30-chronological-j />' . "\n";
	$content .= '  <z30-chronological-k />' . "\n";
	$content .= '  <z30-chronological-l />' . "\n";
	$content .= '  <z30-chronological-m />' . "\n";
	$content .= '  <z30-hol-doc-number>000000000</z30-hol-doc-number>' . "\n";
	$content .= '  <z30-doc-number-2>000000000</z30-doc-number-2>' . "\n";
	$content .= '</z30>' . "\n";

	debug $content;
	# Demo user just returns with success
	if ( is_demo_user() ) {
		return { success => 1, status => "Item has been created successfully" };
	}
	
	# We need to use LWP::UserAgent as we need to be able to POST
	my $ua = LWP::UserAgent->new( timeout => 30, ssl_opts => { verify_hostname => 0 } );

	# Set the parameters to the X-service
	my %form;
	$form{'xml_full_req'} = $content ;
	$form{'op'} = 'create_item' ;
	$form{'adm_library'} = setting('aleph_adm_library');
	# It is required that the adm_doc_number is zero-padded in Aleph 21 (at least)
	$form{'adm_doc_number'} = sprintf( "%09d", $p->{admsys} );
	$form{'user_name'} = setting('aleph_user_name');
	$form{'user_password'} = setting('aleph_user_password');
	$form{'translate'} = 'N';

	debug \%form;

	# Send to X-service
	my $response = $ua->post(setting('aleph_x_server'), \%form);

	debug $response;

	if ( $response->is_success) {
		# The LWP::UserAgent response was a success
		my $result = $response->decoded_content;
		# Check if Aleph puts out an error
		if ( $result =~ m{<error>(.+?)</error>}s ) {
			my $message = $1;
			# A success is also an error, so discard "Item has been created successfully." as an error
			if ( $message =~ m{created successfully} ) {
				return { success => 1, status => uri_decode($message) };
			}
			else {
				return { success => 0, status => uri_decode($message) };
			}
		}
	}
}

sub delete_item {
	my $p = shift;

	# Get item data
	my $content = LWP::Simple::get( 
		setting('aleph_x_server') .
		"/?op=delete-item&item_barcode=" . $p->{barcode} .
		"&library=" . setting('aleph_adm_library') .
		"&user_name=" . setting('aleph_user_name') .
		"&user_password=" . setting('aleph_user_password') .
		"&translate=N" );

	debug $content;

	if ( $content and $content =~m {<error>(.+?)</error>} ) {
		my $message = $1;
		# A success is also an error, so discard "Item has been deleted successfully." as an error
		if ( $message =~ m{deleted successfully} ) {
			database->quick_delete('reminder', { record => $p->{record} } );
			return { success => 1, status => uri_decode($message) };
		}
		return { success => 0, status => uri_decode($message) };
	}
	return { success => 0, status => "No valid answer from Aleph op=delete_item" };
}

sub is_demo_user {
	return 1 if ( session('user') eq setting('demousername') );
}

hook 'database_connected' => sub {
	my $dbh = shift;
	$dbh->do('CREATE TABLE IF NOT EXISTS barcode ( id INTEGER PRIMARY KEY NOT NULL, current INTEGER NOT NULL );');
	$dbh->do('INSERT OR IGNORE INTO barcode ( id, current ) VALUES ( 1, ' . setting('barcode_seed') . ' );');
	$dbh->do('CREATE TABLE IF NOT EXISTS reminder ( id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, record INTEGER NOT NULL, admsys INTEGER NOT NULL, timestamp INTEGER NOT NULL );');
};

true;
