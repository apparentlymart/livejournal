# -*-perl-*-
use strict;
use Test::More 'no_plan';
use lib "$ENV{LJHOME}/cgi-bin";
use LJ;
use LJ::Console;
use LJ::Test qw (temp_user temp_comm);
local $LJ::T_NO_COMMAND_PRINT = 1;

my $u = temp_user();
LJ::set_remote($u);

my $run = sub {
    my $cmd = shift;
    return LJ::Console->run_commands_text($cmd);
};

my $file_contents = sub {
    my $file = shift;
    open (my $fh, $file) or die $!;
    my $ct = do { local $/; <$fh> };
    return \$ct;
};

my $upfile = "$ENV{LJHOME}/t/data/userpics/good.jpg";
die "No such file $upfile" unless -e $upfile;

my $up = LJ::Userpic->create($u, data => $file_contents->($upfile));

is($run->("expunge_userpic " . $up->url),
   "error: You are not authorized to run this command.");
$u->grant_priv("siteadmin", "userpics");

is($run->("expunge_userpic " . $up->url),
   "success: Userpic '" . $up->id . "' for '" . $u->user . "' expunged.");

ok($up->state eq "X", "Userpic actually expunged.");



