#!/usr/bin/perl

use FCGI;
use strict;

require 'ljlib.pl';
require 'ljprotocol.pl';

REQUEST:
    while(FCGI::accept() >= 0) 
{
    my $dbs = LJ::get_dbs();
    my $dbh = $dbs->{'dbh'};
    
    my %out = ();
    my %FORM = ();
    &get_form_data(\%FORM);

    print "Content-type: text/plain\n";
    
    LJ::do_request($dbs, \%FORM, \%out);

    if ($FORM{'responseenc'} eq "urlenc")
    {
	print "\n";
	
	foreach (sort keys %out) {
	    print LJ::eurl($_), "=", LJ::eurl($out{$_}), "&";
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


