#!/usr/bin/perl
#

use strict;
require "$ENV{'LJHOME'}/cgi-bin/ljlib.pl";

my $dbh = LJ::get_dbh("master");

print "
This tool will create your LiveJournal 'system' account and
set its password.  Or, if you already have a system user, it'll change
its password to whatever you specify.
";

print "Enter password for the 'system' account: ";
my $pass = <STDIN>;
chomp $pass;

print "\n";

print "Creating system account...\n";
unless (LJ::create_account($dbh, { 'user' => 'system',
				   'name' => 'System Account',
				   'password' => $pass }))
{
    print "Already exists.\nModifying 'system' account...\n";
    my $qp = $dbh->quote($pass);
    $dbh->do("UPDATE user SET password=$qp WHERE user='system'");
}
print "Done.\n\n";

my $u = LJ::load_userid($dbh, 1);

unless ($u && $u->{'user'} eq "system")
{
    my $user = $u ? $u->{'user'} : "(nobody)";
    print "WARNING:  your system account is not userid 1.  userid \#1 is $user.\n";
    print "          $user will have full privileges, not 'system'\n";
    print "\n";
}



