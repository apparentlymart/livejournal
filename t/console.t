# -*-perl-*-

use strict;
use Test::More 'no_plan';
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';
use LJ::Console;

is(LJ::Console->run_commands_text("print one"),
   "one
");

is(LJ::Console->run_commands_text("print one two !three"),
   "one
two
error: three
");
