# -*-perl-*-
use strict;
use Test::More 'no_plan';
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';
use LJ::Console;
use LJ::Test qw (temp_user temp_comm memcache_stress);

my $u = temp_user();
my $u2 = temp_user();
my $comm = temp_comm();
my $comm2 = temp_comm();
local $LJ::T_NO_COMMAND_PRINT = 1;

my $refresh = sub {
    LJ::start_request();
    LJ::set_remote($u);
};

my $run = sub {
    my $cmd = shift;
    return LJ::Console->run_commands_text($cmd);
};

# check that it requires a login
is($run->("ban_list"), "error: You must be logged in to run this command.");
my $dbh = LJ::get_db_writer();
$refresh->();

# ----------- ALLOWOPENPROXY FUNCTIONS -----------
is($run->("allow_open_proxy 127.0.0.1"),
   "error: You are not authorized to run this command.");
$u->grant_priv("allowopenproxy");
is($run->("allow_open_proxy 127.0.0.1"),
   "error: That IP address is not an open proxy.");
is($run->("allow_open_proxy 127001"),
   "error: That is an invalid IP address.");

$dbh->do("REPLACE INTO openproxy (addr, status, asof, src) VALUES (?,?,?,?)", undef,
         "127.0.0.1", "proxy", time(), "Marking as open proxy for test");
is(LJ::is_open_proxy("127.0.0.1"), 1,
   "Verified IP as open proxy.");
$dbh->do("REPLACE INTO openproxy (addr, status, asof, src) VALUES (?,?,?,?)", undef,
         "127.0.0.2", "proxy", time(), "Marking as open proxy for test");
is(LJ::is_open_proxy("127.0.0.2"), 1,
   "Verified IP as open proxy.");

is($run->("allow_open_proxy 127.0.0.1"),
   "success: 127.0.0.1 cleared as an open proxy for the next 24 hours");
is(LJ::is_open_proxy("127.0.0.1"), 0,
   "Verified IP has been cleared as open proxy.");

is($run->("allow_open_proxy 127.0.0.2 forever"),
   "success: 127.0.0.2 cleared as an open proxy forever");
is(LJ::is_open_proxy("127.0.0.2"), 0,
   "Verified IP has been cleared as open proxy.");

$dbh->do("DELETE FROM openproxy WHERE addr IN (?, ?)",
         undef, "127.0.0.1", "127.0.0.2");
$u->revoke_priv("allowopenproxy");


# ------------ BAN FUNCTIONS --------------
is($run->("ban_set " . $u2->user),
   "success: User " . $u2->user . " banned from " . $u->user);
is($run->("ban_set " . $u2->user . " from " . $comm->user),
   "error: You are not a maintainer of this account");

is(LJ::set_rel($comm, $u, 'A'), '1', "Set user as maintainer");
# obligatory hack until whitaker commits patch to clear $LJ::REQ_CACHE_REL
LJ::start_request();
LJ::set_remote($u);

is($run->("ban_set " . $u2->user . " from " . $comm->user),
   "success: User " . $u2->user . " banned from " . $comm->user);
is($run->("ban_list"),
   "info: " . $u2->user);
is($run->("ban_list from " . $comm->user),
   "info: " . $u2->user);
is($run->("ban_unset " . $u2->user),
   "success: User " . $u2->user . " unbanned from " . $u->user);
is($run->("ban_unset " . $u2->user . " from " . $comm->user),
   "success: User " . $u2->user . " unbanned from " . $comm->user);
is($run->("ban_list"),
   "info: " . $u->user . " has not banned any other users.");
is($run->("ban_list from " . $comm->user),
   "info: " . $comm->user . " has not banned any other users.");

is($run->("ban_list from " . $comm2->user),
   "error: You are not a maintainer of this account");
$u->grant_priv("finduser", "");
is($run->("ban_list from " . $comm2->user),
   "info: " . $comm2->user . " has not banned any other users.");
$u->revoke_priv("finduser", "");


# ------------ CHANGECOMMUNITYADMIN FUNCTIONS -----
LJ::clear_rel($comm, $u, 'A');
$refresh->();
is(LJ::can_manage($u, $comm), undef, "Verified that user is not maintainer");
is($run->("change_community_admin " . $comm->user . " " . $u->user),
   "error: You are not authorized to run this command.");
$u->grant_priv("communityxfer");
is($run->("change_community_admin " . $u2->user . " " . $u->user),
   "error: Given community doesn't exist or isn't a community.");
is($run->("change_community_admin " . $comm->user . " " . $comm2->user),
   "error: New owner doesn't exist or isn't a person account.");
LJ::update_user($u, { 'status' => 'T' });
is($run->("change_community_admin " . $comm->user . " " . $u->user),
   "error: New owner's email address isn't validated.");
LJ::update_user($u, { 'status' => 'A' });
is($run->("change_community_admin " . $comm->user . " " . $u->user),
   "success: Transferred maintainership of '" . $comm->user . "' to '" . $u->user . "'.");
$refresh->();
is(LJ::can_manage($u, $comm), 1, "Verified user is maintainer");
is($u->email_raw, $comm->email_raw, "Addresses match");
is($comm->password, undef, "Password cleared");
$u->revoke_priv("communityxfer");


# ------------ CHANGEJOURNALSTATUS FUNCTIONS -------------
$u2->set_visible;                  # so we know where we're starting
$u2 = LJ::load_user($u2->user);    # reload this user
is($run->("change_journal_status " . $u2->user . " normal"),
   "error: You are not authorized to run this command.");
$u->grant_priv("siteadmin", "users");
is($run->("change_journal_status " . $u2->user . " deleted"),
   "error: Invalid status. Consult the reference.");
is($run->("change_journal_status " . $u2->user . " normal"),
   "error: Account is already in that state.");
is($run->("change_journal_status " . $u2->user . " locked"),
   "success: Account has been marked as locked");
is($u2->is_locked, 1, "Verified account is locked");
is($run->("change_journal_status " . $u2->user . " memorial"),
   "success: Account has been marked as memorial");
is($u2->is_memorial, 1, "Verified account is memorial");
is($run->("change_journal_status " . $u2->user . " normal"),
   "success: Account has been marked as normal");
is($u2->is_visible, 1, "Verified account is normal");


# ---------- COMMUNITY FUNCTIONS -------------------------
# ... We set $u as the maintainer of $comm above!
is($run->("community " . $comm->user . " add " . $u->user),
   "error: Adding users to communities with the console is disabled.");
is($run->("community " . $comm2->user . " remove " . $u2->user),
   "error: You cannot remove users from this community.");

LJ::join_community($comm, $u2);
is($run->("community " . $comm->user . " remove " . $u2->user),
   "success: User " . $u2->user . " removed from " . $comm->user);
is(LJ::is_friend($comm, $u2), '0', "User is no longer a member");

# test case where user's removing themselves
is($run->("community " . $comm2->user . " remove " . $u->user),
   "success: User " . $u->user . " removed from " . $comm2->user);


# --------- FIND USER CLUSTER --------------------------
is($run->("find_user_cluster " . $u2->user),
   "error: You are not authorized to run this command.");
$u->grant_priv("supporthelp");
is($run->("find_user_cluster " . $u2->user),
   "success: " . $u2->user . " is on the " . LJ::get_cluster_description($u2->{clusterid}, 0) . " cluster");
$u->revoke_priv("supporthelp");
$u->grant_priv("supportviewscreened");
is($run->("find_user_cluster " . $u2->user),
   "success: " . $u2->user . " is on the " . LJ::get_cluster_description($u2->{clusterid}, 0) . " cluster");
$u->revoke_priv("supportviewscreened");


# ------------ FINDUSER ---------------------
is($run->("finduser " . $u->user),
   "error: You are not authorized to run this command.");
$u->grant_priv("finduser");
LJ::update_user($u, { 'email' => $u->user . "\@$LJ::DOMAIN", 'status' => 'A' });
$u = LJ::load_user($u->user);   # reload the user, since we changed validation status for another test
is($run->("finduser " . $u->user),
   "info: User: " . $u->user . " (" . $u->id . "), journaltype: " . $u->journaltype . ", statusvis: " .
   $u->statusvis . ", email: (" . $u->email_status . ") " . $u->email_raw);
is($run->("finduser " . $u->email_raw),
   "info: User: " . $u->user . " (" . $u->id . "), journaltype: " . $u->journaltype . ", statusvis: " .
   $u->statusvis . ", email: (" . $u->email_status . ") " . $u->email_raw);
is($run->("finduser user " . $u->user),
   "info: User: " . $u->user . " (" . $u->id . "), journaltype: " . $u->journaltype . ", statusvis: " .
   $u->statusvis . ", email: (" . $u->email_status . ") " . $u->email_raw);
is($run->("finduser email " . $u->email_raw),
   "info: User: " . $u->user . " (" . $u->id . "), journaltype: " . $u->journaltype . ", statusvis: " .
   $u->statusvis . ", email: (" . $u->email_status . ") " . $u->email_raw);
is($run->("finduser userid " . $u->id),
   "info: User: " . $u->user . " (" . $u->id . "), journaltype: " . $u->journaltype . ", statusvis: " .
   $u->statusvis . ", email: (" . $u->email_status . ") " . $u->email_raw);
is($run->("finduser timeupdate " . $u->user),
   "info: User: " . $u->user . " (" . $u->id . "), journaltype: " . $u->journaltype . ", statusvis: " .
   $u->statusvis . ", email: (" . $u->email_status . ") " . $u->email_raw . "\n" .
   "info:   Last updated: Never");
is($run->("finduser timeupdate " . $u->email_raw),
   "info: User: " . $u->user . " (" . $u->id . "), journaltype: " . $u->journaltype . ", statusvis: " .
   $u->statusvis . ", email: (" . $u->email_status . ") " . $u->email_raw . "\n" .
   "info:   Last updated: Never");


# ------------ PRINT FUNCTIONS ---------------
is($run->("print one"), "info: Welcome to 'print'!\nsuccess: one");
is($run->("print one !two"), "info: Welcome to 'print'!\nsuccess: one\nerror: !two");


# ----------- SUSPEND/UNSUSPEND FUNCTIONS -----------
is($run->("suspend " . $u2->user . " 'because'"),
   "error: You are not authorized to run this command.");
$u->grant_priv("suspend");
$u2->set_email( $u2->user . "\@$LJ::DOMAIN" );
$u2->set_visible;
$refresh->();

is($run->("suspend " . $u2->user . " \"because\""),
   "info: User '" . $u2->user . "' suspended.");
$u2 = LJ::load_user($u2->user);
ok($u2->is_suspended, "User indeed suspended.");

is($run->("suspend " . $u2->email_raw . " \"because\""),
   "info: Acting on users matching email " . $u2->email_raw . "\n"
   . "info:    " . $u2->user . "\n"
   . "info: To actually confirm this action, please do this again:\n"
   . "info:    suspend " . $u2->email_raw . " \"because\" confirm");
is($run->("suspend " . $u2->email_raw . " \"because\" confirm"),
   "info: Acting on users matching email " . $u2->email_raw . "\n"
   . "error: " . $u2->user . " is already suspended.");

is($run->("unsuspend " . $u2->user . " \"because\""),
   "info: User '" . $u2->user . "' unsuspended.");
$u2 = LJ::load_user($u2->user);
ok(!$u2->is_suspended, "User is no longer suspended.");

is($run->("suspend " . $u2->user . " \"because\""),
   "info: User '" . $u2->user . "' suspended.");
$u2 = LJ::load_user($u2->user);
ok($u2->is_suspended, "User suspended again.");

is($run->("unsuspend " . $u2->email_raw . " \"because\""),
   "info: Acting on users matching email " . $u2->email_raw . "\n"
   . "info:    " . $u2->user . "\n"
   . "info: To actually confirm this action, please do this again:\n"
   . "info:    unsuspend " . $u2->email_raw . " \"because\" confirm");
is($run->("unsuspend " . $u2->email_raw . " \"because\" confirm"),
   "info: Acting on users matching email " . $u2->email_raw . "\n"
   . "info: User '" . $u2->user . "' unsuspended.");
ok(!$u2->is_suspended, "User is no longer suspended.");



