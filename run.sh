#!/bin/bash

PLACK_ENV=development

#PLACK_SERVER=Starman
#PLACK_SERVER=Gazelle
#PLACK_SERVER=HTTP::Server::Simple
PLACK_SERVER=HTTP::Server::PSGI

WATCH_FOLDERS='./lib,./views,config.yml'
APP_PATH=`pwd`
HOSTNAME=`hostname`
DEFAULT_PORT=7070
PLACKUP=/u1/perl/perls/perl-5.22.1/bin/plackup

if [[ $1 ]]; then
	PORT=$1
else
	PORT=$DEFAULT_PORT
fi

export PLACK_ENV
export PLACK_SERVER

cd $APP_PATH
$PLACKUP -R $WATCH_FOLDERS --host $HOSTNAME --port $PORT bin/app.pl
