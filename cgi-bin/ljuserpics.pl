package LJ;
use strict;

use Digest::MD5 qw(md5_hex);
use HTTP::Request::Common qw/GET/;

# <LJFUNC>
# name: LJ::fetch_userpic
# des: Fetch source content of userpic by url or post
# args: userpic, src, urlpic
# return: hashref: { content, size }
# </LJFUNC>
sub fetch_userpic {
    my %args = @_;

    my $size = 0;
    my $content = undef;
    if ($args{userpic}){
        ## Read uploaded image
        my $upload = LJ::Request->upload('userpic');

        return { undef, -1 }
            unless $upload;

        $size = $upload->size;

        # upload image as temp file to mogileFS. this file is used in lj_upf_resize worker.
        seek $upload->fh, 0,0;
        read $upload->fh, $content, $upload->size; # read content

        return {
            content => $content,
            size    => $upload->size,
        }

    } elsif ($args{'src'} eq "url") {
        ## Get image somewhere from internet

        my $ua = LJ::get_useragent(
                                   role     => 'userpic',
                                   max_size => $args{maxupload} + 1024,
                                   timeout  => 10,
                                   );

        my $res = $ua->get($args{urlpic});
        if ($res && $res->is_success) {
            # read downloaded file
            $content = $res->content;
            $size    = length $content;
        }

        return {
            content => $content,
            size    => $size,
        }
    }
}

# <LJFUNC>
# name: LJ::load_userpics
# des: Loads a bunch of userpics at once.
# args: dbarg?, upics, idlist
# des-upics: hashref to load pictures into, keys being the picids.
# des-idlist: [$u, $picid] or [[$u, $picid], [$u, $picid], +] objects
#             also supports deprecated old method, of an array ref of picids.
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

    ## avoid requesting upic multiple times.
    ## otherwise memcached returns it multiple times too.
    ##
    ## don't load (non-existent) upics with negative id
    ## see also LJSUP-5502 and hook 'control_default_userpic'
    my %uniq = ();
    $idlist = [ grep { 
                        my $u = $_->[0];
                        my $upicid = $_->[1];
                        $upicid>0 && not $uniq{$u}->{$upicid}++ 
                    } @$idlist ];

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
#      your site has off-site caching or something similar, you can also define a hook
#      "expunge_userpic" which will be called with a picid and userid when a pic is
#      expunged.
# args: u, picid
# des-picid: ID of the picture to expunge.
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
        return undef unless $state; # invalid pic
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
        return undef unless $state; # invalid pic
        return $u->{'userid'} if $state eq 'X'; # already expunged

        # else now mark it
        my $dbh = LJ::get_db_writer();
        return undef unless $dbh;
        $dbh->do("UPDATE userpic SET state='X' WHERE picid = ?", undef, $picid);
        return LJ::error($dbh) if $dbh->err;
        $dbh->do("DELETE FROM userpicmap WHERE userid = ? AND picid = ?", undef, $u->{'userid'}, $picid);
    }

    # now clear the user's memcache picture info
    LJ::Userpic->delete_cache($u);
    LJ::MemCache::delete([$picid, "userpic.$picid"]);

    ## if this was the default userpic, "undefault" it
    if ($u->{'defaultpicid'} && $u->{'defaultpicid'}==$picid) {
        LJ::update_user($u, { defaultpicid => 0 });
    }

    # call the hook and get out of here
    my @rval = LJ::run_hooks('expunge_userpic', $picid, $u->{'userid'});
    return ($u->{'userid'}, map {$_->[0]} grep {$_ && @$_ && $_->[0]} @rval);
}

# <LJFUNC>
# name: LJ::activate_userpics
# des: des: Wrapper around [func[LJ::User::activate_userpics]] for compatibility.
# args: uuserid
# returns: undef on failure 1 on success
# </LJFUNC>
sub activate_userpics
{
    my $u = shift;
    return undef unless LJ::isu($u);

    # if a userid was given, get a real $u object
    $u = LJ::load_userid($u, "force") unless isu($u);

    # should have a $u object now
    return undef unless isu($u);

    return $u->activate_userpics;
}

# <LJFUNC>
# name: LJ::get_userpic_info
# des: Given a user, gets their userpic information.
# args: uuid, opts?
# des-uuid: userid, or user object.
# des-opts: Optional; hash of options, 'load_comments'.
# returns: hash of userpicture information;
#          for efficiency, we store the userpic structures
#          in memcache in a packed format.
# info: memory format:
#       [
#       version number of format,
#       userid,
#       "packed string", which expands to an array of {width=>..., ...}
#       "packed string", which expands to { 'kw1' => id, 'kw2' => id, ...}
#       ]
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

                if (defined $comminfo) {
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

                if (defined $urlinfo) {
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
# des: Given a userid and keyword, returns the pic row hashref.
# args: u, keyword
# des-keyword: The keyword of the userpic to fetch.
# returns: hashref of pic row found
# </LJFUNC>
sub get_pic_from_keyword
{
    my ($u, $kw) = @_;
    my $info = LJ::get_userpic_info($u) or
        return undef;

    if (my $pic = $info->{'kw'}{$kw}) {
        return $pic;
    }

    # the lame "pic#2343" thing when they didn't assign a keyword
    if ($kw =~ /^pic\#(\d+)$/) {
        my $picid = $1;
        if (my $pic = $info->{'pic'}{$picid}) {
            return $pic;
        }
    }

    return undef;
}

sub get_picid_from_keyword
{
    my ($u, $kw, $default) = @_;
    $default ||= (ref $u ? $u->{'defaultpicid'} : 0);

    LJ::run_hook('control_default_userpic', \$default);

    return $default unless $kw;

    my $pic = LJ::get_pic_from_keyword($u, $kw)
        or return $default;
    return $pic->{'picid'};
}

# this will return a user's userpicfactory image stored in mogile scaled down.
# if only $size is passed, will return image scaled so the largest dimension will
# not be greater than $size. If $x1, $y1... are set then it will return the image
# scaled so the largest dimension will not be greater than 100
# all parameters are optional, default size is 640.
#
# if maxfilesize option is passed, get_upf_scaled will decrease the image quality
# until it reaches maxfilesize, in kilobytes. (only applies to the 100x100 userpic)
#
# returns [imageref, mime, width, height] on success, undef on failure.
#
# note: this will always keep the image's original aspect ratio and not distort it.
sub get_upf_scaled {
    my @args = @_;

    my $gc = LJ::gearman_client();

    # no gearman, do this in-process
    return LJ::_get_upf_scaled(@args)
        unless $gc;

    # invoke gearman
    my $u = LJ::get_remote()
        or die "No remote user";
    unshift @args, "userid" => $u->id;

    my $result;
    my $arg = Storable::nfreeze(\@args);
    my $task = Gearman::Task->new('lj_upf_resize', \$arg,
                                  {
                                      uniq => '-',
                                      on_complete => sub {
                                          my $res = shift;
                                          return unless $res;
                                          $result = Storable::thaw($$res);
                                      }
                                  });

    my $ts = $gc->new_task_set();
    $ts->add_task($task);
    $ts->wait(timeout => 30); # 30 sec timeout;

    # job failed ... error reporting?
    die "Could not resize image down\n" unless $result;

    return $result;
}

# <LJFUNC>
# name: _get_upf_scaled
# des: Crop and scale images
# agrs:
#   size - max width of target image or [ width x height, ...]
#   x1, x2, y1, y2 - coords in a source image for crop
#   border (bool) - is it need to add border to target image
#   save_to_FB (bool) - is it need to save to FB (FotoBilder)
#   fb_gallery - gallery to save target image
#   auto_crop - is it need to auto_crop image
#   cancel_size - if size of picture is equal or smaller => cancel processing, caller will not use such small picture
#                 returns status 'small'
#####
# Sample for use as auto-crop:
#
#    my $res = LJ::get_upf_scaled(
#            source      => \$content,
#            size        => [ "140x105" ],
#            save_to_FB  => 1,
#            fb_gallery  => 'test_gal',
#            auto_crop   => 1,
#    );
#####
# </LJFUNC>
sub _get_upf_scaled
{
    my %opts = @_;
    my $dataref = delete $opts{source};
    my $size = delete $opts{size} || 640;
    my $x1 = delete $opts{x1};
    my $y1 = delete $opts{y1};
    my $x2 = delete $opts{x2};
    my $y2 = delete $opts{y2};
    my $border = delete $opts{border} || 0;
    my $maxfilesize = delete $opts{maxfilesize} || 38;
    my $u = LJ::want_user(delete $opts{userid} || delete $opts{u}) || LJ::get_remote();
    my $mogkey = delete $opts{mogkey};
    my $downsize_only = delete $opts{downsize_only};
    my $save_to_FB = delete $opts{save_to_FB} || 0;
    my $fb_gallery = delete $opts{fb_gallery};
    my $fb_username = delete $opts{fb_username}; 
    my $fb_password = delete $opts{fb_password};
    my $auto_crop = delete $opts{auto_crop};
    my $cancel_size = delete $opts{cancel_size};
    croak "No userid or remote" unless $u || $mogkey || $dataref;

    $maxfilesize *= 1024;

    croak "Invalid parameters to get_upf_scaled\n" if scalar keys %opts;

    my $mode = ($x1 || $y1 || $x2 || $y2 || $auto_crop) ? "crop" : "scale";

    eval { require Image::Magick }
        or return undef;

    eval { require Image::Size }
        or return undef;

    $mogkey ||= 'upf:' . $u->{userid};
    $dataref = LJ::mogclient()->get_file_data($mogkey)
        unless $dataref;

    return undef
        unless $dataref;

    # original width/height
    my ($ow, $oh) = Image::Size::imgsize($dataref);
    return undef unless $ow && $oh;

    my @cancel_size = split /x/, $cancel_size;
    return { status => 'small' }
        if $cancel_size[0] and $ow < $cancel_size[0] or $cancel_size[1] and $oh < $cancel_size[1];

    # converts an ImageMagick object to the form returned to our callers
    my $imageParams = sub {
        my $im = shift;
        my $blob = $im->ImageToBlob;
        return [\$blob, $im->Get('MIME'), $im->Get('width'), $im->Get('height')];
    };

    # compute new width and height while keeping aspect ratio
    my $getSizedCoords = sub {
        my $newsize = shift;

        my $fromw = $ow;
        my $fromh = $oh;

        my $img = shift;
        if ($img) {
            $fromw = $img->Get('width');
            $fromh = $img->Get('height');
        }

        return (int($newsize * $fromw/$fromh), $newsize) if $fromh > $fromw;
        return ($newsize, int($newsize * $fromh/$fromw));
    };

    # get the "medium sized" width/height.  this is the size which
    # the user selects from
    my @sizes = split /x/, $size;
    my ($medw, $medh) = scalar @sizes > 1 ? @sizes : $getSizedCoords->($size);
    return undef unless $medw && $medh;

    # simple scaling mode
    if ($mode eq "scale") {
        my $image = Image::Magick->new(size => "${medw}x${medh}")
            or return undef;

        $image->BlobToImage($$dataref);
        unless ($downsize_only && ($medw > $ow || $medh > $oh)) {
            $image->Resize(width => $medw, height => $medh);
        }
        return $imageParams->($image);
    }

    # else, we're in 100x100 cropping mode

    # scale user coordinates  up from the medium pixelspace to full pixelspace
    $x1 *= ($ow/$medw);
    $x2 *= ($ow/$medw);
    $y1 *= ($oh/$medh);
    $y2 *= ($oh/$medh);

    # cropping dimensions from the full pixelspace
    my $tw = $x2 - $x1;
    my $th = $y2 - $y1;

    # but if their selected region in full pixelspace is 800x800 or something
    # ridiculous, no point decoding the JPEG to its full size... we can
    # decode to a smaller size so we get 100px when we crop
    my $min_dim = $tw < $th ? $tw : $th;
    my ($decodew, $decodeh) = ($ow, $oh);
    if ($auto_crop) {
        $decodew = $sizes[0];
        $decodeh = $sizes[1];
    } else {
        my $wanted_size = 100;
        if ($min_dim > $wanted_size) {
            # then let's not decode the full JPEG down from its huge size
            my $de_scale = $wanted_size / $min_dim;

            $decodew = int($de_scale * $decodew);
            $decodeh = int($de_scale * $decodeh);

            $_ *= $de_scale foreach ($x1, $x2, $y1, $y2);
        }
    }

    $_ = int($_) foreach ($x1, $x2, $y1, $y2, $tw, $th);

    # make the pristine (uncompressed) 100x100 image
    my $timage = $auto_crop ? Image::Magick->new() : Image::Magick->new(size => "${decodew}x${decodeh}");
    return undef unless $timage;

    $timage->BlobToImage($$dataref);
    $timage->Set(magick => 'PNG');

    if ($auto_crop) {
        my ($crop_w, $crop_h) = ();
        if ($oh <= $decodeh and $ow <= $decodew) {
            ; # nothing to do
        # else one (or two) size is bigger
        } elsif ($oh < $decodeh) { # than ow > decodew
            $crop_h = $oh;
            $crop_w = $decodew;
            $x1 = ($ow - $crop_w) / 2;
            $y1 = 0;
        } elsif ($ow < $decodew) { # than oh > decodeh
            $crop_w = $ow;
            $crop_h = $decodeh;
            $y1 = ($oh - $crop_h) / 2;
            $x1 = 0;
        } elsif ($ow / $decodew >= $oh / $decodeh) {
            $crop_w = $oh * $decodew / $decodeh;
            $crop_h = $oh;
            $x1 = ($ow - $crop_w) / 2;
            $y1 = 0;
        } else {
            $crop_w = $ow;
            $crop_h = $ow * $decodeh / $decodew;
            $y1 = ($oh - $crop_h) / 2;
            $x1 = 0;
        }
        if ($oh > $decodeh or $ow > $decodew) {
            $timage->Crop($crop_w."x".$crop_h."+$x1+$y1");
            if ($crop_h > $decodeh or $crop_w > $decodew) {
                $timage->Scale(width => $decodew, height => $decodeh);
            }
        }
    } else {
        my $w = ($x2 - $x1);
        my $h = ($y2 - $y1);
        $timage->Scale(width => $decodew, height => $decodeh);
        $timage->Mogrify(crop => "${w}x${h}+$x1+$y1");
    }

    if ($save_to_FB) {
        my $im_blob = $timage->ImageToBlob;
        my $res = upload_to_fb (
            dataref  => $im_blob,
            gals     => $fb_gallery,
            username => $fb_username,
            password => $fb_password,
        );
        return $res;
    }

    my $targetSize = $border ? 98 : 100;

    my ($nw, $nh) = $getSizedCoords->($targetSize, $timage);
    $timage->Scale(width => $nw, height => $nh);

    # add border if desired
    $timage->Border(geometry => "1x1", color => 'black') if $border;

    # we are PNG here
    # test, if we can skip compression
    my $piccopy = $timage->Clone();
    my $ret = $imageParams->($piccopy);
    unless ( length(${ $ret->[0] }) < $maxfilesize ) {
        $timage->Set(magick => 'JPG'); # need compression
    }

    foreach my $qual (qw(100 90 85 75)) {
        # work off a copy of the image so we aren't recompressing it
        $piccopy = $timage->Clone();
        $piccopy->Set('quality' => $qual);
        $ret = $imageParams->($piccopy);
        last if length(${ $ret->[0] }) < $maxfilesize;
    }

    return $ret;
}

sub format_magic {
    my $magic = shift;
    my $default = shift;

    my $magic_ref = (ref $magic) ? $magic : \$magic;
    my $mime = $default || 'text/plain'; # default value
    # image formats
    $mime = 'image/jpeg' if $$magic_ref =~ /^\xff\xd8/; # JPEG
    $mime = 'image/gif'  if $$magic_ref =~ /^GIF8/;     # GIF
    $mime = 'image/png'  if $$magic_ref =~ /^\x89PNG/;  # PNG

    return $mime;
}

sub get_challenge
{
    my $username = shift;
    
    my $ua = LWP::UserAgent->new;
    $ua->agent("FotoBilder_Uploader/0.2");

    my $req = HTTP::Request->new(GET => "$LJ::FB_SITEROOT/interface/simple");
    $req->push_header("X-FB-Mode" => "GetChallenge");
    $req->push_header("X-FB-User" => $username);

    my $res = $ua->request($req);
    die "HTTP error: " . $res->content . "\n"
        unless $res->is_success;

    my $xmlres = XML::Simple::XMLin($res->content);
    my $methres = $xmlres->{GetChallengeResponse};

    if (my $err = $xmlres->{Error} || $methres->{Error}) {
        use Data::Dumper;
        die Dumper $err;
    }

    return $methres->{Challenge};
}

sub make_auth
{
    my $chal = shift;
    my $password = shift;
    return "crp:$chal:" . md5_hex($chal . md5_hex($password));
}

sub upload_to_fb {
    my %opts = @_;

    my $dataref = $opts{dataref};
    my $gals    = $opts{gals} || [];

    my $username = $opts{username} || $LJ::FB_USER;
    my $password = $opts{password} || $LJ::FB_PASS;

    my $chal = "";
    unless ($chal) {
        $chal = get_challenge($username)
            or die "No challenge string available.\n";
    }

    my $ua = LWP::UserAgent->new;
    $ua->agent("FotoBilder_Uploader/0.2");

    # Create a request
    my $req = HTTP::Request->new(PUT => "$LJ::FB_SITEROOT/interface/simple");
    $req->push_header("X-FB-Mode" => "UploadPic");
    $req->push_header("X-FB-User" => $username);
    $req->push_header("X-FB-Auth" => make_auth($chal, $password));
    $req->push_header("X-FB-GetChallenge" => 1);

    # picture security
    my $sec = 255; ## public
    $req->push_header("X-FB-UploadPic.PicSec" => $sec);

    # add to galleries
    if (@$gals) {

        # initialize galleries struct array
        $req->push_header(":X-FB-UploadPic.Gallery._size" => scalar(@$gals));

        # add individual galleries
        foreach my $idx (0..@$gals-1) {
            my $gal = $gals->[$idx];

            my @path = split(/\0/, $gal);
            my $galname = pop @path;

            $req->push_header
                ("X-FB-UploadPic.Gallery.$idx.GalName" => $galname);
            $req->push_header
                ("X-FB-UploadPic.Gallery.$idx.GalDate" => time());
            $req->push_header
                ("X-FB-UploadPic.Gallery.$idx.GalSec" => $sec);

            if (@path) {
                $req->push_header
                    (":X-FB-UploadPic.Gallery.$idx.Path._size" => scalar(@path));
                foreach (0..@path-1) {
                    $req->push_header
                        (":X-FB-UploadPic.Gallery.$idx.Path.$_" => $path[$_]);
                }

            }
        }
    }

    $req->push_header("X-FB-UploadPic.ImageLength" => length($dataref));
    $req->push_header("Content-Length" => length($dataref));
    $req->content($dataref);

    my $res = $ua->request($req);
    die "HTTP error: " . $res->content . "\n"
        unless $res->is_success;

    my $xmlres = XML::Simple::XMLin($res->content);
    my $methres = $xmlres->{UploadPicResponse};
    my $chalres = $xmlres->{GetChallengeResponse};

    $chal = $chalres->{Challenge};

    if (my $err = $xmlres->{Error} || $methres->{Error} || $chalres->{Error}) {
        return {
            picid  => -1,
            url    => undef,
            status => 'error',
            errstr => ref $err eq 'HASH' ? $err->{content} : (ref $err eq 'ARRAY' ? $err->[0] : $err),
            opts => \%opts,
        }
    }

    return {
        picid  => $methres->{PicID},
        url    => $methres->{URL},
        status => 'ok',
    }
}

# get picture from internet $opts{source} and crop it to $opts{size},
# than save result into $opts{galleries} (arrayref) of scrapbook of $opts{username}, using $opts{password}
# returns result of &upload_to_fb
sub crop_picture_from_web {
    my %opts = @_;
    my $data;

    my $source = LJ::trim($opts{source});

    if ($source) {
        return {
            url    => '',
            status => 'ok',
        } unless $source;

        ## fetch a photo from Net
        my $ua = LJ::get_useragent( role     => 'crop_picture',
                                    max_size => 10 * 1024 * 1024,
                                    timeout  => 10,
                                  );
        my $result = $ua->request(GET($source));
        unless ($result and $result->is_success) {
            return {
                picid  => -1,
                url    => undef,
                status => 'error',
                errstr => $result ? $result->status_line : 'unknown error in downloading',
            };
        }
        $data       = $result->content;
        $opts{data} = $result->content;
    } else {
        $data = ${$opts{'dataref'}};
    }
    my $res = LJ::_get_upf_scaled(
                    source      => \$data,
                    size        => $opts{size},
                    cancel_size => $opts{cancel_size},
                    save_to_FB  => 1,
                    auto_crop   => 1,
                    fb_username => $opts{username},
                    fb_password => $opts{password},
                    fb_gallery  => $opts{galleries},
              );
    unless ($res) {
        return {
            picid  => -1,
            url    => undef,
            status => 'error',
            errstr => 'probably bad picture',
        };
    }
    # need to repeat? (because of bad auth in CentOS-32 ScrapBook)
    # DELETE THIS IN FUTURE!!!
    if ($res->{picid} == -1) {
        warn $res->{errstr} if $LJ::IS_DEV_SERVER;
        return upload_to_fb(%{$res->{opts}});
    }
    return $res;
}

1;

