package LJ;
use strict;

# <LJFUNC>
# name: LJ::load_userpics
# des: Loads a bunch of userpic at once.
# args: dbarg?, upics, idlist
# des-upics: hashref to load pictures into, keys being the picids
# des-idlist: [$u, $picid] or [[$u, $picid], [$u, $picid], +] objects
# also supports depreciated old method of an array ref of picids
# </LJFUNC>
sub load_userpics
{
    &nodb;
    my ($upics, $idlist) = @_;

    return undef unless ref $idlist eq 'ARRAY' && $idlist->[0];

    # deal with the old calling convention, just an array ref of picids eg. [7, 4, 6, 2]
    if (! ref $idlist->[0] && $idlist->[0]) { # assume we have an old style caller
        my $in = join(',', map { $_+0 } @$idlist);
        my $dbr = LJ::get_db_reader();
        my $sth = $dbr->prepare("SELECT userid, picid, width, height " .
                                "FROM userpic WHERE picid IN ($in)");

        $sth->execute;
        while ($_ = $sth->fetchrow_hashref) {
            my $id = $_->{'picid'};
            undef $_->{'picid'};
            $upics->{$id} = $_;
        }
        return;
    }

    # $idlist needs to be an arrayref of arrayrefs,
    # HOWEVER, there's a special case where it can be
    # an arrayref of 2 items:  $u (which is really an arrayref)
    # as well due to 'fields' and picid which is an integer.
    #
    # [$u, $picid] needs to map to [[$u, $picid]] while allowing
    # [[$u1, $picid1], [$u2, $picid2], [etc...]] to work.
    if (scalar @$idlist == 2 && ! ref $idlist->[1]) {
        $idlist = [ $idlist ];
    }

    my @load_list;
    foreach my $row (@{$idlist})
    {
        my ($u, $id) = @$row;
        next unless ref $u;

        if ($LJ::CACHE_USERPIC{$id}) {
            $upics->{$id} = $LJ::CACHE_USERPIC{$id};
        } elsif ($id+0) {
            push @load_list, [$u, $id+0];
        }
    }
    return unless @load_list;

    if (@LJ::MEMCACHE_SERVERS) {
        my @mem_keys = map { [$_->[1],"userpic.$_->[1]"] } @load_list;
        my $mem = LJ::MemCache::get_multi(@mem_keys) || {};
        while (my ($k, $v) = each %$mem) {
            next unless $v && $k =~ /(\d+)/;
            my $id = $1;
            $upics->{$id} = LJ::MemCache::array_to_hash("userpic", $v);
        }
        @load_list = grep { ! $upics->{$_->[1]} } @load_list;
        return unless @load_list;
    }

    my %db_load;
    my @load_list_d6;
    foreach my $row (@load_list) {
        # ignore users on clusterid 0
        next unless $row->[0]->{clusterid};

        if ($row->[0]->{'dversion'} > 6) {
            push @{$db_load{$row->[0]->{'clusterid'}}}, $row;
        } else {
            push @load_list_d6, $row;
        }
    }

    foreach my $cid (keys %db_load) {
        my $dbcr = LJ::get_cluster_def_reader($cid);
        unless ($dbcr) {
            print STDERR "Error: LJ::load_userpics unable to get handle; cid = $cid\n";
            next;
        }

        my (@bindings, @data);
        foreach my $row (@{$db_load{$cid}}) {
            push @bindings, "(userid=? AND picid=?)";
            push @data, ($row->[0]->{userid}, $row->[1]);
        }
        next unless @data && @bindings;

        my $sth = $dbcr->prepare("SELECT userid, picid, width, height, fmt, state, ".
                                 "       UNIX_TIMESTAMP(picdate) AS 'picdate', location, flags ".
                                 "FROM userpic2 WHERE " . join(' OR ', @bindings));
        $sth->execute(@data);

        while (my $ur = $sth->fetchrow_hashref) {
            my $id = delete $ur->{'picid'};
            $upics->{$id} = $ur;

            # force into numeric context so they'll be smaller in memcache:
            foreach my $k (qw(userid width height flags picdate)) {
                $ur->{$k} += 0;
            }
            $ur->{location} = uc(substr($ur->{location}, 0, 1));

            $LJ::CACHE_USERPIC{$id} = $ur;
            LJ::MemCache::set([$id,"userpic.$id"], LJ::MemCache::hash_to_array("userpic", $ur));
        }
    }

    # following path is only for old style d6 userpics... don't load any if we don't
    # have any to load
    return unless @load_list_d6;

    my $dbr = LJ::get_db_writer();
    my $picid_in = join(',', map { $_->[1] } @load_list_d6);
    my $sth = $dbr->prepare("SELECT userid, picid, width, height, contenttype, state, ".
                            "       UNIX_TIMESTAMP(picdate) AS 'picdate' ".
                            "FROM userpic WHERE picid IN ($picid_in)");
    $sth->execute;
    while (my $ur = $sth->fetchrow_hashref) {
        my $id = delete $ur->{'picid'};
        $upics->{$id} = $ur;

        # force into numeric context so they'll be smaller in memcache:
        foreach my $k (qw(userid width height picdate)) {
            $ur->{$k} += 0;
        }
        $ur->{location} = "?";
        $ur->{flags} = undef;
        $ur->{fmt} = {
            'image/gif' => 'G',
            'image/jpeg' => 'J',
            'image/png' => 'P',
        }->{delete $ur->{contenttype}};

        $LJ::CACHE_USERPIC{$id} = $ur;
        LJ::MemCache::set([$id,"userpic.$id"], LJ::MemCache::hash_to_array("userpic", $ur));
    }
}

# <LJFUNC>
# name: LJ::expunge_userpic
# des: Expunges a userpic so that the system will no longer deliver this userpic.  If
#   your site has off-site caching or something similar, you can also define a hook
#   "expunge_userpic" which will be called with a picid and userid when a pic is
#   expunged.
# args: u, picid
# des-picid: Id of the picture to expunge.
# des-u: User object
# returns: undef on error, or the userid of the picture owner on success.
# </LJFUNC>
sub expunge_userpic {
    # take in a picid and expunge it from the system so that it can no longer be used
    my ($u, $picid) = @_;
    $picid += 0;
    return undef unless $picid && ref $u;

    # get the pic information
    my $state;

    if ($u->{'dversion'} > 6) {
        my $dbcm = LJ::get_cluster_master($u);
        return undef unless $dbcm && $u->writer;

        $state = $dbcm->selectrow_array('SELECT state FROM userpic2 WHERE userid = ? AND picid = ?',
                                        undef, $u->{'userid'}, $picid);

        return $u->{'userid'} if $state eq 'X'; # already expunged

        # else now mark it
        $u->do("UPDATE userpic2 SET state='X' WHERE userid = ? AND picid = ?", undef, $u->{'userid'}, $picid);
        return LJ::error($dbcm) if $dbcm->err;
        $u->do("DELETE FROM userpicmap2 WHERE userid = ? AND picid = ?", undef, $u->{'userid'}, $picid);
    } else {
        my $dbr = LJ::get_db_reader();
        return undef unless $dbr;

        $state = $dbr->selectrow_array('SELECT state FROM userpic WHERE picid = ?',
                                       undef, $picid);

        return $u->{'userid'} if $state eq 'X'; # already expunged

        # else now mark it
        my $dbh = LJ::get_db_writer();
        return undef unless $dbh;
        $dbh->do("UPDATE userpic SET state='X' WHERE picid = ?", undef, $picid);
        return LJ::error($dbh) if $dbh->err;
        $dbh->do("DELETE FROM userpicmap WHERE userid = ? AND picid = ?", undef, $u->{'userid'}, $picid);
    }

    # now clear the user's memcache picture info
    LJ::MemCache::delete([$u->{'userid'}, "upicinf:$u->{'userid'}"]);

    # call the hook and get out of here
    my $rval = LJ::run_hook('expunge_userpic', $picid, $u->{'userid'});
    return ($u->{'userid'}, $rval);
}

# <LJFUNC>
# name: LJ::activate_userpics
# des: Sets/unsets userpics as inactive based on account caps
# args: uuserid
# returns: nothing
# </LJFUNC>
sub activate_userpics
{
    # this behavior is optional, but enabled by default
    return 1 if $LJ::ALLOW_PICS_OVER_QUOTA;

    my $u = shift;
    return undef unless LJ::isu($u);

    # if a userid was given, get a real $u object
    $u = LJ::load_userid($u, "force") unless isu($u);

    # should have a $u object now
    return undef unless isu($u);

    # can't get a cluster read for expunged users since they are clusterid 0,
    # so just return 1 to the caller from here and act like everything went fine
    return 1 if $u->{'statusvis'} eq 'X';

    my $userid = $u->{'userid'};

    # active / inactive lists
    my @active = ();
    my @inactive = ();
    my $allow = LJ::get_cap($u, "userpics");

    # get a database handle for reading/writing
    my $dbh = LJ::get_db_writer();
    my $dbcr = LJ::get_cluster_def_reader($u);

    # select all userpics and build active / inactive lists
    my $sth;
    if ($u->{'dversion'} > 6) {
        return undef unless $dbcr;
        $sth = $dbcr->prepare("SELECT picid, state FROM userpic2 WHERE userid=?");
    } else {
        return undef unless $dbh;
        $sth = $dbh->prepare("SELECT picid, state FROM userpic WHERE userid=?");
    }
    $sth->execute($userid);
    while (my ($picid, $state) = $sth->fetchrow_array) {
        next if $state eq 'X'; # expunged, means userpic has been removed from site by admins
        if ($state eq 'I') {
            push @inactive, $picid;
        } else {
            push @active, $picid;
        }
    }

    # inactivate previously activated userpics
    if (@active > $allow) {
        my $to_ban = @active - $allow;

        # find first jitemid greater than time 2 months ago using rlogtime index
        # ($LJ::EndOfTime - UnixTime)
        my $jitemid = $dbcr->selectrow_array("SELECT jitemid FROM log2 USE INDEX (rlogtime) " .
                                             "WHERE journalid=? AND rlogtime > ? LIMIT 1",
                                             undef, $userid, $LJ::EndOfTime - time() + 86400*60);

        # query all pickws in logprop2 with jitemid > that value
        my %count_kw = ();
        my $propid = LJ::get_prop("log", "picture_keyword")->{'id'};
        my $sth = $dbcr->prepare("SELECT value, COUNT(*) FROM logprop2 " .
                                 "WHERE journalid=? AND jitemid > ? AND propid=?" .
                                 "GROUP BY value");
        $sth->execute($userid, $jitemid, $propid);
        while (my ($value, $ct) = $sth->fetchrow_array) {
            # keyword => count
            $count_kw{$value} = $ct;
        }

        my $keywords_in = join(",", map { $dbh->quote($_) } keys %count_kw);

        # map pickws to picids for freq hash below
        my %count_picid = ();
        if ($keywords_in) {
            my $sth;
            if ($u->{'dversion'} > 6) {
                $sth = $dbcr->prepare("SELECT k.keyword, m.picid FROM userkeywords k, userpicmap2 m ".
                                      "WHERE k.keyword IN ($keywords_in) AND k.kwid=m.kwid AND k.userid=m.userid " .
                                      "AND k.userid=?");
            } else {
                $sth = $dbh->prepare("SELECT k.keyword, m.picid FROM keywords k, userpicmap m " .
                                     "WHERE k.keyword IN ($keywords_in) AND k.kwid=m.kwid " .
                                     "AND m.userid=?");
            }
            $sth->execute($userid);
            while (my ($keyword, $picid) = $sth->fetchrow_array) {
                # keyword => picid
                $count_picid{$picid} += $count_kw{$keyword};
            }
        }

        # we're only going to ban the least used, excluding the user's default
        my @ban = (grep { $_ != $u->{'defaultpicid'} }
                   sort { $count_picid{$a} <=> $count_picid{$b} } @active);

        @ban = splice(@ban, 0, $to_ban) if @ban > $to_ban;
        my $ban_in = join(",", map { $dbh->quote($_) } @ban);
        if ($u->{'dversion'} > 6) {
            $u->do("UPDATE userpic2 SET state='I' WHERE userid=? AND picid IN ($ban_in)",
                   undef, $userid) if $ban_in;
        } else {
            $dbh->do("UPDATE userpic SET state='I' WHERE userid=? AND picid IN ($ban_in)",
                     undef, $userid) if $ban_in;
        }
    }

    # activate previously inactivated userpics
    if (@inactive && @active < $allow) {
        my $to_activate = $allow - @active;
        $to_activate = @inactive if $to_activate > @inactive;

        # take the $to_activate newest (highest numbered) pictures
        # to reactivated
        @inactive = sort @inactive;
        my @activate_picids = splice(@inactive, -$to_activate);

        my $activate_in = join(",", map { $dbh->quote($_) } @activate_picids);
        if ($activate_in) {
            if ($u->{'dversion'} > 6) {
                $u->do("UPDATE userpic2 SET state='N' WHERE userid=? AND picid IN ($activate_in)",
                       undef, $userid);
            } else {
                $dbh->do("UPDATE userpic SET state='N' WHERE userid=? AND picid IN ($activate_in)",
                         undef, $userid);
            }
        }
    }

    # delete userpic info object from memcache
    LJ::MemCache::delete([$userid, "upicinf:$userid"]);

    return 1;
}

# <LJFUNC>
# name: LJ::get_userpic_info
# des: Given a user gets their user picture info
# args: uuid, opts (optional)
# des-u: user object or userid
# des-opts: hash of options, 'load_comments'
# returns: hash of userpicture information
# for efficiency, we store the userpic structures
# in memcache in a packed format.
#
# memory format:
# [
#   version number of format,
#   userid,
#   "packed string", which expands to an array of {width=>..., ...}
#   "packed string", which expands to { 'kw1' => id, 'kw2' => id, ...}
# ]
# </LJFUNC>

sub get_userpic_info
{
    my ($uuid, $opts) = @_;
    return undef unless $uuid;
    my $userid = LJ::want_userid($uuid);
    my $u = LJ::want_user($uuid); # This should almost always be in memory already
    return undef unless $u && $u->{clusterid};

    # in the cache, cool, well unless it doesn't have comments or urls
    # and we need them
    if (my $cachedata = $LJ::CACHE_USERPIC_INFO{$userid}) {
        my $good = 1;
        if ($u->{'dversion'} > 6) {
            $good = 0 if $opts->{'load_comments'} && ! $cachedata->{'_has_comments'};
            $good = 0 if $opts->{'load_urls'} && ! $cachedata->{'_has_urls'};
        }
        return $cachedata if $good;
    }

    my $VERSION_PICINFO = 3;

    my $memkey = [$u->{'userid'},"upicinf:$u->{'userid'}"];
    my ($info, $minfo);

    if ($minfo = LJ::MemCache::get($memkey)) {
        # the pre-versioned memcache data was a two-element hash.
        # since then, we use an array and include a version number.

        if (ref $minfo eq 'HASH' ||
            $minfo->[0] != $VERSION_PICINFO) {
            # old data in the cache.  delete.
            LJ::MemCache::delete($memkey);
        } else {
            my (undef, $picstr, $kwstr) = @$minfo;
            $info = {
                'pic' => {},
                'kw' => {},
            };
            while (length $picstr >= 7) {
                my $pic = { userid => $u->{'userid'} };
                ($pic->{picid},
                 $pic->{width}, $pic->{height},
                 $pic->{state}) = unpack "NCCA", substr($picstr, 0, 7, '');
                $info->{pic}->{$pic->{picid}} = $pic;
            }

            my ($pos, $nulpos);
            $pos = $nulpos = 0;
            while (($nulpos = index($kwstr, "\0", $pos)) > 0) {
                my $kw = substr($kwstr, $pos, $nulpos-$pos);
                my $id = unpack("N", substr($kwstr, $nulpos+1, 4));
                $pos = $nulpos + 5; # skip NUL + 4 bytes.
                $info->{kw}->{$kw} = $info->{pic}->{$id} if $info;
            }
        }

        if ($u->{'dversion'} > 6) {

            # Load picture comments
            if ($opts->{'load_comments'}) {
                my $commemkey = [$u->{'userid'}, "upiccom:$u->{'userid'}"];
                my $comminfo = LJ::MemCache::get($commemkey);

                if ($comminfo) {
                    my ($pos, $nulpos);
                    $pos = $nulpos = 0;
                    while (($nulpos = index($comminfo, "\0", $pos)) > 0) {
                        my $comment = substr($comminfo, $pos, $nulpos-$pos);
                        my $id = unpack("N", substr($comminfo, $nulpos+1, 4));
                        $pos = $nulpos + 5; # skip NUL + 4 bytes.
                        $info->{'pic'}->{$id}->{'comment'} = $comment;
                        $info->{'comment'}->{$id} = $comment;
                    }
                    $info->{'_has_comments'} = 1;
                } else { # Requested to load comments, but they aren't in memcache
                         # so force a db load
                    undef $info;
                }
            }

            # Load picture urls
            if ($opts->{'load_urls'} && $info) {
                my $urlmemkey = [$u->{'userid'}, "upicurl:$u->{'userid'}"];
                my $urlinfo = LJ::MemCache::get($urlmemkey);

                if ($urlinfo) {
                    my ($pos, $nulpos);
                    $pos = $nulpos = 0;
                    while (($nulpos = index($urlinfo, "\0", $pos)) > 0) {
                        my $url = substr($urlinfo, $pos, $nulpos-$pos);
                        my $id = unpack("N", substr($urlinfo, $nulpos+1, 4));
                        $pos = $nulpos + 5; # skip NUL + 4 bytes.
                        $info->{'pic'}->{$id}->{'url'} = $url;
                    }
                    $info->{'_has_urls'} = 1;
                } else { # Requested to load urls, but they aren't in memcache
                         # so force a db load
                    undef $info;
                }
            }
        }
    }

    my %minfocom; # need this in this scope
    my %minfourl;
    unless ($info) {
        $info = {
            'pic' => {},
            'kw' => {},
        };
        my ($picstr, $kwstr);
        my $sth;
        my $dbcr = LJ::get_cluster_def_reader($u);
        my $db = @LJ::MEMCACHE_SERVERS ? LJ::get_db_writer() : LJ::get_db_reader();
        return undef unless $dbcr && $db;

        if ($u->{'dversion'} > 6) {
            $sth = $dbcr->prepare("SELECT picid, width, height, state, userid, comment, url ".
                                  "FROM userpic2 WHERE userid=?");
        } else {
            $sth = $db->prepare("SELECT picid, width, height, state, userid ".
                                "FROM userpic WHERE userid=?");
        }
        $sth->execute($u->{'userid'});
        my @pics;
        while (my $pic = $sth->fetchrow_hashref) {
            next if $pic->{state} eq 'X'; # no expunged pics in list
            push @pics, $pic;
            $info->{'pic'}->{$pic->{'picid'}} = $pic;
            $minfocom{int($pic->{picid})} = $pic->{comment} if $u->{'dversion'} > 6
                && $opts->{'load_comments'} && $pic->{'comment'};
            $minfourl{int($pic->{'picid'})} = $pic->{'url'} if $u->{'dversion'} > 6
                && $opts->{'load_urls'} && $pic->{'url'};
        }


        $picstr = join('', map { pack("NCCA", $_->{picid},
                                 $_->{width}, $_->{height}, $_->{state}) } @pics);

        if ($u->{'dversion'} > 6) {
            $sth = $dbcr->prepare("SELECT k.keyword, m.picid FROM userpicmap2 m, userkeywords k ".
                                  "WHERE k.userid=? AND m.kwid=k.kwid AND m.userid=k.userid");
        } else {
            $sth = $db->prepare("SELECT k.keyword, m.picid FROM userpicmap m, keywords k ".
                                "WHERE m.userid=? AND m.kwid=k.kwid");
        }
        $sth->execute($u->{'userid'});
        my %minfokw;
        while (my ($kw, $id) = $sth->fetchrow_array) {
            next unless $info->{'pic'}->{$id};
            next if $kw =~ /[\n\r\0]/;  # used to be a bug that allowed these to get in.
            $info->{'kw'}->{$kw} = $info->{'pic'}->{$id};
            $minfokw{$kw} = int($id);
        }
        $kwstr = join('', map { pack("Z*N", $_, $minfokw{$_}) } keys %minfokw);

        $memkey = [$u->{'userid'},"upicinf:$u->{'userid'}"];
        $minfo = [ $VERSION_PICINFO, $picstr, $kwstr ];
        LJ::MemCache::set($memkey, $minfo);

        if ($u->{'dversion'} > 6) {

            if ($opts->{'load_comments'}) {
                $info->{'comment'} = \%minfocom;
                my $commentstr = join('', map { pack("Z*N", $minfocom{$_}, $_) } keys %minfocom);

                my $memkey = [$u->{'userid'}, "upiccom:$u->{'userid'}"];
                LJ::MemCache::set($memkey, $commentstr);

                $info->{'_has_comments'} = 1;
            }

            if ($opts->{'load_urls'}) {
                my $urlstr = join('', map { pack("Z*N", $minfourl{$_}, $_) } keys %minfourl);

                my $memkey = [$u->{'userid'}, "upicurl:$u->{'userid'}"];
                LJ::MemCache::set($memkey, $urlstr);

                $info->{'_has_urls'} = 1;
            }
        }
    }

    $LJ::CACHE_USERPIC_INFO{$u->{'userid'}} = $info;
    return $info;
}

# <LJFUNC>
# name: LJ::get_pic_from_keyword
# des: Given a userid and keyword, returns the pic row hashref
# args: u, keyword
# des-keyword: The keyword of the userpic to fetch
# returns: hashref of pic row found
# </LJFUNC>
sub get_pic_from_keyword
{
    my ($u, $kw) = @_;
    my $info = LJ::get_userpic_info($u);
    return undef unless $info;
    return $info->{'kw'}{$kw};
}

sub get_picid_from_keyword
{
    my ($u, $kw, $default) = @_;
    $default ||= (ref $u ? $u->{'defaultpicid'} : 0);
    return $default unless $kw;
    my $info = LJ::get_userpic_info($u);
    return $default unless $info;
    my $pr = $info->{'kw'}{$kw};
    return $pr ? $pr->{'picid'} : $default;
}

# this will return a user's userpicfactory image stored in mogile scaled down.
# if only $size is passed, will return image scaled so the largest dimension will
# not be greater than $size. If $x1, $y1... are set then it will return the image
# scaled so the largest dimension will not be greater than 100
# all parameters are optional, default size is 640. if $x1 is present, the rest of
# the points should be as well.
#
# if maxfilesize option is passed, get_upf_scaled will decrease the image quality
# until it reaches maxfilesize, in kilobytes. (only applies to the 100x100 userpic)
#
# returns [image, mime, width, height] on success, undef on failure.
#
# note: this will always keep the image's original aspect ratio and not distort it.
sub get_upf_scaled
{
    my %opts = @_;
    my $size = delete $opts{size} || 640;

    my $x1 = delete $opts{x1};
    my $y1 = delete $opts{y1};
    my $x2 = delete $opts{x2};
    my $y2 = delete $opts{y2};

    my $maxfilesize = delete $opts{maxfilesize} || 38;
    $maxfilesize *= 1024;

    print STDERR "Invalid parameters to get_upf_scaled\n" if scalar keys %opts;

    my $remote = LJ::get_remote();
    return undef unless $remote;

    my $has_magick = eval "use Image::Magick (); 1;";
    return undef unless $has_magick;

    my $key = 'upf:' . $remote->{userid};

    my $dataref = LJ::mogclient()->get_file_data($key) or return undef;

    my $imgdata = $$dataref;

    my $image = Image::Magick->new() or return undef;

    $image->BlobToImage($imgdata);

    my $mime = $image->Get('MIME');

    my $w = $image->Get('width');
    my $h = $image->Get('height');

    # compute new width and height while keeping aspect ratio
    my $getSizedCoords = sub {
        my $newsize = shift;

        my $_w = $image->Get('width');
        my $_h = $image->Get('height');

        my ($nh, $nw);

        if ($_h > $_w) {
            $nh = $newsize;
            $nw = $newsize * $_w/$_h;
        } else {
            $nw = $newsize;
            $nh = $newsize * $_h/$_w;
        }

        return ($nw, $nh);
    };

    # resize image keeping aspect ratio and ensuring that the largest bound is $newsize
    my $aspectResize = sub {
        my $newsize = shift;

        my ($nw, $nh) = $getSizedCoords->($newsize);

        if ($nw || $nh) {
            $image->Scale(width => $nw, height => $nh);
        }
    };

    if ($x1 && $x2 && $y1 && $y2) {
        # scale small coords to full-size so we can crop the high quality source image before for
        # higher quality scaled userpics.
        my ($scaledw, $scaledh) = $getSizedCoords->($size);

        $x1 *= ($w/$scaledw);
        $x2 *= ($w/$scaledw);

        $y1 *= ($h/$scaledh);
        $y2 *= ($h/$scaledh);

        my $tw = $x2 - $x1;
        my $th = $y2 - $y1;

        $image->Set('quality', 100);

        $image->Crop(
                     x => $x1,
                     y => $y1,
                     width => $tw,
                     height => $th
                     );
        $aspectResize->(100);

        # try different compression levels in a binary search pattern until we get our desired file size
        my $adjustQuality;
        my $lastbest;

        $adjustQuality = sub {
            my ($left, $right, $iters) = @_;

            # make sure we don't take too long. if it takes more than 10 iterations, oh well
            if ($iters++ > 10 || $left > $right) {
                return undef;
            }

            # work off a copy of the image so we aren't recompressing it
            my $piccopy = Image::Magick->new();
            $piccopy->BlobToImage($image->ImageToBlob);

            my $mid = ($left + $right) / 2;
            $piccopy->Set('quality' => $mid);
            my $quality = $piccopy->Get('quality');
            my $filesize = length($piccopy->ImageToBlob);

            # save a workable solution if things don't work out
            $lastbest = $quality if ($filesize < $maxfilesize);

            # not good if filesize > maxfilesize, but good if filesize < maxfilesize within 5%
            return $mid if ($maxfilesize - $filesize > 0 && $maxfilesize - $filesize < $maxfilesize * .005);

            if ($filesize > $maxfilesize) {
                return $adjustQuality->($left, $mid - 1, $iters);
            } else {
                return $adjustQuality->($mid + 1, $right, $iters);
            }
        };

        if (length($image->ImageToBlob) > $maxfilesize) {
            my $newquality = $adjustQuality->(0, 100, 0);
            if ($newquality) {
                $image->Set('quality' => $newquality);
            } elsif($lastbest) {
                $image->Set('quality' => $lastbest);
            }
        }

    } else {
        $aspectResize->($size);
    }

    my ($blob) = $image->ImageToBlob;

    return [$blob, $mime, $image->Get('width'), $image->Get('height')];
}

1;
