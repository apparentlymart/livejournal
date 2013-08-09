#!/usr/bin/perl
#

package LJ::Syn;
use strict;

#get_feeds_rating ( { offset => '', length => '', sort_by => '', search_name => '' } )
sub get_feeds_rating_segment {
    my $args = shift;
    my $offset = $args->{"offset"} || 0;
    my $length = $args->{"length"} || 5;
    my $sort_by = $args->{"sort_by"} || "soccap";

    ##### Search mode if set search_name parameter ####
    my $search_id;
    my $search_name = $args->{"search_name"};
    if ($search_name) {
        my $user = LJ::load_user($search_name);
        $search_id = $user->id() if LJ::isu($user);
    }
    ###################################################

    my @data = @{_get_feeds_from_db()};
    my $total = scalar @data;

    my @uids = map { $_->[0]} @data;
    my $users = LJ::User->get_authority_multi( \@uids );
    foreach (@data) {
        $_->[3] = $users->{$_->[0]};
    }

    ###### by default values sorting by number of watchers, if we are need sorting by social capital then do it.
    @data = reverse sort { $a->[3] <=> $b->[3] } @data if $sort_by eq "soccap";

    my $search_res;
    my $position = 1;
    foreach (@data) {
        $_ = {
            position => $position,
            journal_id => $_->[0],
            xml_url => $_->[1],
            watchers => $_->[2],
            soccap => $_->[3],
        };
        $position++;

        ##### in search mode we are trying find needed position
        if ( $_->{"journal_id"} == $search_id ) {
            $search_res = $_->{"position"};
            $_->{"found"} = 1;
            $offset = POSIX::floor( $search_res / $length ) * $length;
        }
    }

    my @data = splice(@data, $offset, $length);

    my $result = \@data;
    return { total => $total, data => $result, search_res => $search_res };
}

sub get_popular_feeds
{
    my $popsyn = LJ::MemCache::get("popsyn");
    unless ($popsyn) {
        $popsyn = _get_feeds_from_db();

        # load u objects so we can get usernames
        my %users;
        LJ::load_userids_multiple([ map { $_, \$users{$_} } map { $_->[0] } @$popsyn ]);
        unshift @$_, $users{$_->[0]}->{'user'}, $users{$_->[0]}->{'name'} foreach @$popsyn;
        # format is: [ user, name, userid, synurl, numreaders ]
        # set in memcache
        my $expire = time() + 3600; # 1 hour
        LJ::MemCache::set("popsyn", $popsyn, $expire);
    }
    return $popsyn;
}

sub get_popular_feed_ids {
    my $popsyn_ids = LJ::MemCache::get("popsyn_ids");
    unless ($popsyn_ids) {
        my $popsyn = _get_feeds_from_db();
        @$popsyn_ids = map { $_->[0] } @$popsyn;

        # set in memcache
        my $expire = time() + 3600; # 1 hour
        LJ::MemCache::set("popsyn_ids", $popsyn_ids, $expire);
    }
    return $popsyn_ids;
}

sub _get_feeds_from_db {
    my $popsyn = [];

    my $dbr = LJ::get_db_reader();
    my $sth = $dbr->prepare("SELECT userid, synurl, numreaders FROM syndicated ".
                            "WHERE numreaders > 0 ".
                            "AND lastnew > DATE_SUB(NOW(), INTERVAL 14 DAY) ".
                            "ORDER BY numreaders DESC LIMIT 1000");
    $sth->execute();
    while (my @row = $sth->fetchrow_array) {
        push @$popsyn, [ @row ];
    }

    return $popsyn;
}

1;