# -*-perl-*-

use strict;
use Test::More 'no_plan';
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';
use LJ::Comment;
#use FindBin qw($Bin);

my $u = LJ::load_user("system");

# constructor tests
{
    my $c;

    $c = eval { LJ::Comment->new({}, jtalkid => 1) };
    like($@, qr/invalid user/, "invalid user from ref");

    $c = eval { LJ::Comment->new(0, jtalkid => 1) };
    like($@, qr/invalid user/, "invalid user from userid");

    $c = eval { LJ::Comment->new($u, jtalkid => 1, 'foo') };
    like($@, qr/wrong number/, "wrong number of arguments");

    $c = eval { LJ::Comment->new($u, jtalkid => undef) };
    like($@, qr/need to supply jtalkid/, "need to supply jtalkid");

    $c = eval { LJ::Comment->new($u, jtalkid => 1, foo => 1, bar => 2) };
    like($@, qr/unknown parameter/, "unknown parameters");
}

sub is_common { 1 }

1;

