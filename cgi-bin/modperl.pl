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

# compatibility with old location of LJ::email_check:
*BMLCodeBlock::check_email = \&LJ::check_email;

1;
