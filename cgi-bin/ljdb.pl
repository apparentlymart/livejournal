#!/usr/bin/perl
#

use strict;
use lib "$ENV{LJHOME}/cgi-bin";
use DBI::Role;
use DBI;

require "$ENV{LJHOME}/cgi-bin/ljconfig.pl";

package LJ::DB;

our $DBIRole = new DBI::Role {
    'timeout' => 2,
    'sources' => \%LJ::DBINFO,
    'default_db' => "livejournal",
    'time_check' => 60,
};

sub dbh_by_role {
    return $DBIRole->get_dbh( @_ );
}

sub dbh_by_name {
    my $name = shift;
    my $dbh = dbh_by_role("master")
	or die "Couldn't contact master to find name of '$name'\n";

    my $fdsn = $dbh->selectrow_array("SELECT fdsn FROM dbinfo WHERE name=?", undef, $name);
    die "No fdsn found for db name '$name'\n" unless $fdsn;

    return $DBIRole->get_dbh_conn($fdsn);
  
}

sub dbh_by_fdsn {
    my $fdsn = shift;
    return $DBIRole->get_dbh_conn($fdsn);
}

sub root_dbh_by_name {
    my $name = shift;
    my $dbh = dbh_by_role("master")
	or die "Couldn't contact master to find name of '$name'";
   
    my $fdsn = $dbh->selectrow_array("SELECT rootfdsn FROM dbinfo WHERE name=?", undef, $name);
    die "No rootfdsn found for db name '$name'\n" unless $fdsn;

    return $DBIRole->get_dbh_conn($fdsn);
}


1;


