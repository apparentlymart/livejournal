#!/usr/bin/perl

use FCGI;
use strict;
use vars qw($dbh);

require 'ljlib.pl';
require 'ljprotocol.pl';

REQUEST:
    while(FCGI::accept() >= 0) 
{
    &connect_db;
    
    my %out = ();
    my %FORM = ();
    &get_form_data(\%FORM);

    print "Content-type: text/plain\n";
    
    LJ::do_request($dbh, \%FORM, \%out);

    if ($FORM{'responseenc'} eq "urlenc")
    {
	print "\n";
	
	foreach (sort keys %out) {
	    print &eurl($_), "=", &eurl($out{$_}), "&";
	}
    } 
    else 
    {
	my $length = 0;
	foreach (sort keys %out) {
	    $length += length($_)+1;
	    $length += length($out{$_})+1;
	}
	
	print "Content-length: $length\n\n";
	
	foreach (sort keys %out) {
	    print $_, "\n", $out{$_}, "\n";
	}
    }
}


