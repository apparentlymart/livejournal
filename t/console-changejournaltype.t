# -*-perl-*-
use strict;
use Test::More 'no_plan';
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';
use LJ::Console;
use LJ::Test qw (temp_user temp_comm);
local $LJ::T_NO_COMMAND_PRINT = 1;

my $u = temp_user();
my $u2 = temp_user();
my $comm = temp_comm();

my $commname = $comm->user;
my $owner = $u2->user;
LJ::set_rel($comm, $u, 'A');
LJ::start_request();
LJ::set_remote($u);

my $run = sub {
    my $cmd = shift;
    return LJ::Console->run_commands_text($cmd);
};

# all of these should fail.
is($run->("change_journal_type $commname person $owner"),
   "error: You cannot specify a new owner for an account");
is($run->("change_journal_type $commname news $owner"),
   "error: You cannot specify a new owner for an account");
is($run->("change_journal_type $commname shared $owner"),
   "error: You cannot specify a new owner for an account");
is($run->("change_journal_type $commname community $owner"),
   "error: You cannot specify a new owner for an account");

# switching between comm and back
is($run->("change_journal_type $commname person"),
   "error: You can only convert to a community or shared journal.");
is($run->("change_journal_type $commname news"),
   "error: You can only convert to a community or shared journal.");

is($run->("change_journal_type $commname shared"),
   "success: User: " . $comm->user . " converted to a shared account.");
$comm = LJ::load_user($comm->user);
ok($comm->is_shared, "Converted to a shared journal!");

is($run->("change_journal_type $commname community"),
   "success: User: " . $comm->user . " converted to a community account.");
$comm = LJ::load_user($comm->user);
ok($comm->is_community, "Converted to a community!");
