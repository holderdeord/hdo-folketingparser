#!/usr/bin/env perl

use v5.10.1;
use Mojolicious::Lite;
use DBI;

my $dbfile = 'prototype.sqlite';

helper db => sub {
  my $self = shift;

  return DBI->connect('dbi:SQLite:dbname='.$dbfile, '', '', {sqlite_unicode => 1}) if
    defined $self->session->{dbfile};

  $self->redirect_to('/');
  return;
};



# Documentation browser under "/perldoc"
plugin 'PODRenderer';

get '/welcome' => sub {
  my $self = shift;
  $self->render('index');
};

app->start;
__DATA__

@@ index.html.ep
% layout 'default';
% title 'Welcome';
Welcome to Mojolicious!

@@ layouts/default.html.ep
<!DOCTYPE html>
<html>
  <head><title><%= title %></title></head>
  <body><%= content %></body>
</html>
