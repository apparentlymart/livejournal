#!/usr/bin/perl
#

package LJ::ModPerl;
use strict;
use lib "$ENV{'LJHOME'}/cgi-bin";
use Apache;

# pull in libraries and do per-start initialization once.
require "modperl_subs.pl";

# do per-restart initialization
LJ::ModPerl::setup_restart();

# delete itself from %INC to make sure this file is run again
# when apache is restarted
delete $INC{"$ENV{'LJHOME'}/cgi-bin/modperl.pl"};

# remember modtime of all loaded libraries
if ($LJ::IS_DEV_SERVER) {
    %LJ::LIB_MOD_TIME = ();
    while (my ($k, $file) = each %INC) {
        next if $LJ::LIB_MOD_TIME{$file};
        next unless $file =~ m!^\Q$LJ::HOME\E!;
        my $mod = (stat($file))[9];
        $LJ::LIB_MOD_TIME{$file} = $mod;
    }
}

# compatibility with old location of LJ::email_check:
*BMLCodeBlock::check_email = \&LJ::check_email;

1;
