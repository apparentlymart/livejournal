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
my $u3 = temp_user();
LJ::set_remote($u);

my $run = sub {
    my $cmd = shift;
    return LJ::Console->run_commands_text($cmd);
};

is($run->("priv grant admin:* " . $u2->user),
   "error: You are not authorized to run this command.");
is($run->("priv_package list"),
   "error: You are not authorized to run this command.");
$u->grant_priv("admin", "supporthelp");

################ PRIV PACKAGES ######################
my $pkg = $u->user; # random pkg name just to ensure uniqueness across tests

is($run->("priv_package create $pkg"),
   "success: Package '$pkg' created.");
is($run->("priv_package list $pkg"),
   "info: Contents of #$pkg:", "package is empty");
is($run->("priv_package remove $pkg supporthelp:bananas"),
   "error: Privilege does not exist in package.");
is($run->("priv_package add $pkg supporthelp:bananas"),
   "success: Privilege (supporthelp:bananas) added to package #$pkg.");
is($run->("priv_package list $pkg"),
   "info: Contents of #$pkg:\ninfo:    supporthelp:bananas", "package populated");
is($run->("priv_package remove $pkg supporthelp:bananas"),
   "success: Privilege (supporthelp:bananas) removed from package #$pkg.");
is($run->("priv_package list $pkg"),
   "info: Contents of #$pkg:", "package is empty again");
is($run->("priv_package delete $pkg"),
   "success: Package '#$pkg' deleted.");
ok($run->("priv_package list") !~ $pkg, "Package no longer exists.");


########### PRIV GRANTING #####################
$u->grant_priv("admin", "supportread/bananas");

# one user, one priv
is($run->("priv grant supporthelp:test " . $u2->user),
   "info: Granting: 'supporthelp' with arg 'test' for user '" . $u2->user . "'.");
ok(LJ::check_priv($u2, "supporthelp", "test"), "has priv");

is($run->("priv revoke supporthelp:test " . $u2->user),
   "info: Denying: 'supporthelp' with arg 'test' for user '" . $u2->user . "'.");
ok(!LJ::check_priv($u2, "supporthelp", "test"), "no longer privved");

#one priv, one user
#many privs, many users
#priv package, one user
#priv/packages, many users
#privs, one priv you can't grant
