# -*-perl-*-

use strict;
use Test::More 'no_plan';
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';
require 'talklib.pl';
require 'ljprotocol.pl';
use LJ::Comment;
use LJ::Test qw(memcache_stress temp_user);

my $u = temp_user();

sub run_tests {
    # constructor tests
    {
        my $c;

        $c = eval { LJ::Comment->new({}, jtalkid => 1) };
        like($@, qr/invalid journalid/, "invalid journalid parameter");

        $c = eval { LJ::Comment->new(0, jtalkid => 1) };
        like($@, qr/invalid journalid/, "invalid user from userid");

        $c = eval { LJ::Comment->new($u, jtalkid => 1, 'foo') };
        like($@, qr/wrong number/, "wrong number of arguments");

        $c = eval { LJ::Comment->new($u, jtalkid => undef) };
        like($@, qr/need to supply jtalkid/, "need to supply jtalkid");

        $c = eval { LJ::Comment->new($u, jtalkid => 1, foo => 1, bar => 2) };
        like($@, qr/unknown parameter/, "unknown parameters");
    }

    # post a comment
    {
        my $e1 = $u->t_post_fake_entry;
        ok($e1, "Posted entry");

        my $c1 = $e1->t_enter_comment;
        ok($c1, "Posted comment");

        # check that the comment happened in the last 60 seconds
        my $c1time = $c1->unixtime;
        ok($c1time, "Got comment time");
        ok(POSIX::abs($c1time - time()) < 60, "Comment happened in last minute");
    }
}

memcache_stress {
    run_tests();
};

1;

