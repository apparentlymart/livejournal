# -*-perl-*-

use strict;
use Test::More 'no_plan';
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';
use FindBin qw($Bin);
use LJ::Test qw(memcache_stress temp_user);
use LJ::M::FriendsOf;

our @STATUSVIS;
our $PREFIX;
our $MUTUALS_SEPARATE;

{
    local @STATUSVIS = qw(V);
    local $PREFIX = "No Whammy's";
    local $MUTUALS_SEPARATE = 0;
    memcache_stress(\&run_all);
}

{
    local @STATUSVIS = qw(V D);
    local $PREFIX = "Visible & Deleted";
    local $MUTUALS_SEPARATE = 0;
    memcache_stress(\&run_all);
}

{
    local @STATUSVIS = qw(V D);
    local $PREFIX = "Mutuals separate, Visible & Deleted";
    local $MUTUALS_SEPARATE = 1;
    memcache_stress(\&run_all);
}

sub run_all {
    LJ::start_request();

    my $u = temp_user();

    my @rels = map{ temp_user() } (1..50);

    my @expected_friends;
    my @expected_friendofs;
    my @expected_mutual;

    foreach my $f (@rels) {
        my $statusvis = @STATUSVIS[rand @STATUSVIS];
        LJ::update_user( $f, { statusvis => $statusvis } );

        my $rand = rand();
        if ($rand < .33) {
            LJ::add_friend($u, $f) or die;
            LJ::add_friend($f, $u) or die;
            push @expected_mutual, $f->id if $statusvis eq 'V';
            push @expected_friends, $f->id;
            push @expected_friendofs, $f->id if ($statusvis eq 'V' and !$MUTUALS_SEPARATE);
        } elsif ($rand < .67) {
            LJ::add_friend($u, $f) or die;
            push @expected_friends, $f->id;
        } else {
            LJ::add_friend($f, $u) or die;
            push @expected_friendofs, $f->id if $statusvis eq 'V';
        }
    }

    my @friends = $u->friends;

    is_deeply([sort(map {$_->id} @friends)], [sort @expected_friends], "$PREFIX: Friends");

    my %friends = map { $_->id, $_ } @friends;
    my $fo_m = LJ::M::FriendsOf->new($u, sloppy => 0, load_cap => 500, mutuals_separate => $MUTUALS_SEPARATE, friends => { %friends });

    my @friendofs = $fo_m->friend_ofs;

    is_deeply([sort map { $_->id } @friendofs], [sort @expected_friendofs], "$PREFIX: Friendofs");

    my @mutual_friends = sort $fo_m->mutual_friends;

    is_deeply([sort map { $_->id } @mutual_friends], [sort @expected_mutual], "$PREFIX: Mutual friends");

}

# vim: filetype=perl
