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
our $USER_COUNT;
our $LOAD_LIMIT;
our $SLOPPY;

{
    local @STATUSVIS = qw(V);
    local $PREFIX = "No Whammy's";
    local $MUTUALS_SEPARATE = 0;
    local $USER_COUNT = 50;
    local $LOAD_LIMIT = 500;
    local $SLOPPY = 0;
    memcache_stress(\&run_all);
}

{
    local @STATUSVIS = qw(V D);
    local $PREFIX = "Visible & Deleted";
    local $MUTUALS_SEPARATE = 0;
    local $USER_COUNT = 50;
    local $LOAD_LIMIT = 500;
    local $SLOPPY = 0;
    memcache_stress(\&run_all);
}

{
    local @STATUSVIS = qw(V D);
    local $PREFIX = "Mutuals separate";
    local $MUTUALS_SEPARATE = 1;
    local $USER_COUNT = 50;
    local $LOAD_LIMIT = 500;
    local $SLOPPY = 0;
    memcache_stress(\&run_all);
}

{
    local @STATUSVIS = qw(V D);
    local $PREFIX = "Cropped";
    local $MUTUALS_SEPARATE = 1;
    local $USER_COUNT = 50;
    local $LOAD_LIMIT = 5;
    local $SLOPPY = 0;
    memcache_stress(\&run_all);
}

{
    local @STATUSVIS = qw(V D);
    local $PREFIX = "Cropped & Sloppy";
    local $MUTUALS_SEPARATE = 1;
    local $USER_COUNT = 50;
    local $LOAD_LIMIT = 5;
    local $SLOPPY = 1;
    memcache_stress(\&run_all);
}

sub run_all {
    LJ::start_request();

    my $u = temp_user();

    my @rels = map{ temp_user() } (1..$USER_COUNT);

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
    my $fo_m = LJ::M::FriendsOf->new($u, sloppy => $SLOPPY, load_cap => $LOAD_LIMIT, mutuals_separate => $MUTUALS_SEPARATE, friends => { %friends });

    {
        my @friendofs = map { $_->id } $fo_m->friend_ofs;
        is_in([sort @friendofs], [sort @expected_friendofs], "$PREFIX: Friendofs");
    }

    {
        my $friendofs = $fo_m->friend_ofs;
        is($friendofs, @expected_friendofs, "$PREFIX: Friendofs count");
    }

    {
        my @mutual_friends = map { $_->id} $fo_m->mutual_friends;
        is_in([sort @mutual_friends], [sort @expected_mutual], "$PREFIX: Mutual friends");
    }

    {
        my $mutual_friends = $fo_m->mutual_friends;
        is($mutual_friends, @expected_mutual, "$PREFIX: Mutual friends count");
    }
}

sub is_in {
    my ($l, $r, $description) = @_;

    $description .= " (sloppy)" if $SLOPPY;

    my $cropped = $LOAD_LIMIT < $USER_COUNT;
    $description .= " (cropped)" if $LOAD_LIMIT < $USER_COUNT;


    return is_deeply($l, $r, $description) unless $SLOPPY || $cropped;

    my $left_count = @$l;
    my $right_count = @$r;

    return fail("$description: left side longer than right") if $left_count > $right_count;

    my %r = map { $_, 1 } @$r;
    my @failed;
    foreach my $check (@$l) {
        next if $r{$check};
        push @failed, $check;
    }

    return fail("$description: " . scalar @failed . " items were in left and not in right.") if @failed;
    return pass("$description matched $left_count of $right_count possible.");
}

# vim: filetype=perl
