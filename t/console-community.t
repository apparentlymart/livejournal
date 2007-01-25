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
my $comm2 = temp_comm();

my $refresh = sub {
    LJ::start_request();
    LJ::set_remote($u);
};

my $run = sub {
    my $cmd = shift;
    return LJ::Console->run_commands_text($cmd);
};

LJ::set_rel($comm, $u, 'A');
LJ::clear_rel($comm2, $u, 'A');
$refresh->();

is($run->("community " . $comm->user . " add " . $u->user),
   "error: Adding users to communities with the console is disabled.");
is($run->("community " . $comm2->user . " remove " . $u2->user),
   "error: You cannot remove users from this community.");

LJ::join_community($comm, $u2);
is($run->("community " . $comm->user . " remove " . $u2->user),
   "success: User " . $u2->user . " removed from " . $comm->user);
ok(!LJ::is_friend($comm, $u2), "User removed from community.");

# test case where user's removing themselves
LJ::join_community($comm2, $u);
is($run->("community " . $comm2->user . " remove " . $u->user),
   "success: User " . $u->user . " removed from " . $comm2->user);
ok(!LJ::is_friend($comm2, $u), "User removed self from community.");
