#!/usr/bin/perl
#
# <LJDEP>
# lib: cgi-bin/ljlib.pl
# </LJDEP>

use strict;
use Getopt::Long;
use lib "$ENV{'LJHOME'}/cgi-bin";
require 'ljlib.pl';
use LJ::User::Rename;

sub usage {
    die "Usage: [--swap --force] <from_user> <to_user>\n";
}

my %args = ( swap => 0, force => 0 );
usage() unless
    GetOptions('swap' => \$args{swap},
               'force' => \$args{force},
               );

my $error;

my $from = shift @ARGV;
my $to = shift @ARGV;
usage() unless $from =~ /^\w{1,15}$/ && $to =~ /^\w{1,15}$/;

my $dbh = LJ::get_db_writer();

my $opts = { token => '[manual: bin/renameuser.pl]' };
unless ($args{swap}) {
    if (LJ::User::Rename::basic_rename($from, $to, $opts)) {
        print "Success.  Renamed $from -> $to.\n";
    } else {
        print "Failed: $opts->{error}\n";
    }
    exit;
}

### check that emails/passwords match, and that at least one is verified
unless ($args{force}) {
    my @acct = grep { $_ } LJ::no_cache(sub {
        return (LJ::load_user($from),
                LJ::load_user($to));
    });
    unless (@acct == 2) {
        print "Both accounts aren't valid.\n";
        exit 1;
    }
    unless (lc($acct[0]->email_raw) eq lc($acct[1]->email_raw)) {
        print "Email addresses don't match.\n";
        print "   " . $acct[0]->raw_email . "\n";
        print "   " . $acct[1]->raw_email . "\n";
        exit 1;
    }
    unless ($acct[0]->password eq $acct[1]->password) {
        print "Passwords don't match.\n";
        exit 1;
    }
    unless ($acct[0]->{'status'} eq "A" || $acct[1]->{'status'} eq "A") {
        print "At least one account isn't verified.\n";
        exit 1;
    }
}

print "Swapping 1/3...\n";
my $dummy_username = LJ::User::Rename::get_unused_name();
unless ($dummy_username) {
    print "Couldn't find a swap username\n";
    exit 1;
}
unless (LJ::User::Rename::basic_rename($from, $dummy_username, $opts)) {
    print "Couldn't rename $from to $dummy_username: $opts->{error}\n";
    exit 1;
}


print "Swapping 2/3...\n";
unless (LJ::User::Rename::basic_rename($to, $from, $opts)) {
    print "Swap failed in the middle, $to -> $from failed: $opts->{error}.\n";
    exit 1;
}

print "Swapping 3/3...\n";
unless (LJ::User::Rename::basic_rename($dummy_username, $to, $opts)) {
    print "Swap failed in the middle, $dummy_username -> $to failed: $opts->{error}.\n";
    exit 1;
}

# check for circular 'renamedto' references
{

    # if the fromuser had redirection on, make sure it points to the new $to user
    my $fromu = LJ::load_user($from, 'force');
    LJ::load_user_props($fromu, 'renamedto');
    if ($fromu->{renamedto} && $fromu->{renamedto} ne $to) {
        print "Setting redirection: $from => $to\n";
        $from_u->set_prop( 'renamedto' => $to );
    }

    # if the $to user had redirection, they shouldn't anymore
    my $tou = LJ::load_user($to, 'force');
    LJ::load_user_props($tou, 'renamedto');
    if ($tou->{renamedto}) {
        print "Removing redirection for user: $to\n";
        unless (LJ::set_userprop($tou, 'renamedto' => undef)) {
            print "Error setting 'renamedto' userprop for $to\n";
            exit 1;
        }
    }
}

print "Swapped.\n";
exit 0;



