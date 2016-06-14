# nuKardex
Web application for checking-in journal issues and printing barcode labels using Ex Libris Aleph and Dymo LabelWriter.

Using predefined publication patterns in Aleph it is possible to check in journal issues into Aleph and print barcodes with shelf mark and location information. It is also possible to perform issue claims via email. The application is very specific to the settings at [Aalborg University Library](http://www.aub.aau.dk) but can be used as a model or inspiration to other libraries. Screen text is currently only available in Danish but the code is mostly documented in English.

Print subscriptions are managed via a JSON file that can me maintained within the application or directly from the filesystem. To reload into the browser, please reload the application (shift+F5) when the file has been edited.

The application was presented at the [ELAG 2016](http://elag2016.org/index.php/program/) conference in Copenhagen on June 7th 2016.

nuKardex backend API and application is written in Perl using the [Dancer](http://perldancer.org/) framework. User interface is written in HTML5 using Bootstrap (originally [Flat UI Pro](http://designmodo.com/flat/) which is why the interface is not as polished as in the presentation) and jQuery for interaction with the UI, backend and label printer API.

## Installation

Grab the source code:

    git clone https://github.com/kloevschall/nuKardex
    cd nuKardex

A [perlbrew](https://perlbrew.pl/) installation of Perl is highly recommended.

Install Perl dependencies for the plugin via e.g. [cpanm](https://metacpan.org/pod/App::cpanminus). (Please stay within the nuKardex directory):

    cpanm --installdeps .

*Compilation of the Perl dependencies might require the installation of software development tools on the server (gcc).*
    
A few JavaScript requirements must also be installed:

In the directory `public/js/dymo` download and put the JS file from: http://www.labelwriter.com/software/dls/sdk/js/DYMO.Label.Framework.2.0.2.js

In the directory `public/js/jsoneditor` download and put all the files from: https://github.com/josdejong/jsoneditor/tree/master/dist

The application can be started in development mode via the provided `run.sh`script. Edit the script according to the location of `plackup` and remember to setup the Perl environment via perlbrew. The code has been tested in Perl 5.22.1. For deployment in production it is recommended to proxy the application e.g. via Nginx (socket) or Apache (localhost). Check http://search.cpan.org/dist/Dancer/lib/Dancer/Deployment.pod for examples.

Install your Dymo LableWriter printer on your PC or Mac and install the latest DLS printer driver from: http://developers.dymo.com/category/dymo-label-framework/

## Configuration

Edit the file `config.yml` and change the __username__ and __password__ settings. There is only one user! The demo user has the same password as the __password__ setting and is only available for testing and development.

Edit the __aleph_x_server__ setting to point to your Aleph installation (version 21 or later). The __aleph_adm_library__ and __aleph_logical_base__ must be configured according to your Aleph installation. The X-Service username and password must be set and created in Aleph with the appropriate permissions.

Edit the __mailer__ settings if you need to send out issue claims via email.
