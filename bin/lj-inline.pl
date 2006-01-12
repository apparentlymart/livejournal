#!/usr/bin/perl
#

use strict;
use lib "$ENV{LJHOME}/cgi-bin";

BEGIN {
    $LJ::HAVE_INLINE = eval 'use Inline Config => DIRECTORY => ($ENV{LJ_INLINE_DIR} || "$ENV{LJHOME}/Inline"); use Inline "C"; 1;';
}

print "This script will recompile ljcom's Inline.pm C code, if necessary.  You need a C compiler installed.\n";

unless ($LJ::HAVE_INLINE) {
    print "\nBut you don't have Inline.pm installed, so quitting now.\n";
    exit 1;
}

print "Testing your Inline install...\n";
unless (inline_test()) {
    print "Error.  Sure you have a C compiler installed?\n";
    exit 1;
}

print "ljlib/ljlib-local.pl (if anything)...\n";
require "ljlib.pl";

print "Apache::SendStats...\n";
# wrapped in eval because ap_scoreboard_image isn't around
# when not running inside apache
eval "use Apache::SendStats;";

print "Done.\n";

__DATA__
__C__

int inline_test () {
    printf("Your Inline install is good.  Proceeding...\n");
    return 1;
}
