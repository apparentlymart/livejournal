#!/usr/bin/perl

package LJ::Memories;
use strict;

# Retreives keyword/keyids without big joins, returns a hashref.
sub get_keywords {
    my $u = shift;
    return undef unless $u;

    my $use_reader = 0;
    my $dbh = LJ::get_db_writer();
    unless ($dbh) {
        $use_reader = 1;
        $dbh = LJ::get_db_reader();
    }
    my $memkey = [$u->{userid},"memkwid:$u->{userid}"];

    my $ret = LJ::MemCache::get($memkey);
    unless (defined $ret) {
        $ret = {};
        my $sth = $dbh->prepare("SELECT DISTINCT mk.kwid FROM memorable m, memkeyword mk " .
                                "WHERE mk.memid=m.memid AND m.userid=?");
        $sth->execute($u->{userid});
        my @ids;
        push @ids, $_ while $_ = $sth->fetchrow_array;

        if (@ids) {
            my $in = join(",", @ids);
            $sth = $dbh->prepare("SELECT kwid, keyword FROM keywords WHERE kwid IN ($in)");
            $sth->execute;

            while (my ($id,$kw) = $sth->fetchrow_array) {
                $ret->{$id} = $kw;
            }
        }
        LJ::MemCache::set($memkey, $ret, 86400) unless $use_reader;
    }

    return $ret;
}

# Simply removes memcache data.
sub updated_keywords {
    my $u = shift;
    LJ::MemCache::delete([$u->{userid},"memkwid:$u->{userid}"]);
    return undef;
}
