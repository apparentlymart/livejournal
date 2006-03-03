package LJ::Userpic;
use strict;
use Carp qw(croak);
use Digest::MD5;

my %MimeTypeMap = (
                   'image/gif'  => 'gif',
                   'G'          => 'gif',
                   'image/jpeg' => 'jpg',
                   'J'          => 'jpg',
                   'image/png'  => 'png',
                   'P'          => 'png',
                   );

sub new {
    my ($class, $u, $picid) = @_;
    return bless {
        userid => $u->{userid},
        picid  => int($picid),
    };
}

sub new_from_row {
    my ($class, $row) = @_;
    my $self = LJ::Userpic->new(LJ::load_userid($row->{userid}), $row->{picid});
    $self->absorb_row($row);
    return $self;
}

sub absorb_row {
    my ($self, $row) = @_;
    for my $f(qw(userid picid width height comment location state)) {
        $self->{$f} = $row->{$f};
    }
    $self->{_ext} = $MimeTypeMap{$row->{fmt} || $row->{contenttype}};
    return $self;
}

# accessors

sub id {
    return $_[0]->{picid};
}

sub inactive {
    my $self = shift;
    return $self->state eq 'I';
}

sub state {
    my $self = shift;
    return $self->{state} if defined $self->{state};
    $self->load_row;
    return $self->{state};
}

sub comment {
    my $self = shift;
    return $self->{comment} if defined $self->{comment};
    $self->load_row;
    return $self->{comment};
}

sub width {
    my $self = shift;
    my @dims = $self->dimensions;
    return undef unless @dims;
    return $dims[0];
}

sub height {
    my $self = shift;
    my @dims = $self->dimensions;
    return undef unless @dims;
    return $dims[0];
}

# returns (width, height)
sub dimensions {
    my $self = shift;

    # width and height probably loaded from DB
    return ($self->{width}, $self->{height}) if ($self->{width} && $self->{height});

    my %upics;
    my $u = LJ::load_userid($self->{userid});
    LJ::load_userpics(\%upics, [ $u, $self->{picid} ]);
    my $up = $upics{$self->{picid}} or
        return ();

    return ($up->{width}, $up->{height});
}

sub max_allowed_bytes {
    my ($class, $u) = @_;
    return 40960;
}

sub owner {
    my $self = shift;
    return LJ::load_userid($self->{userid});
}

sub url {
    my $self = shift;
    return "$LJ::USERPIC_ROOT/$self->{picid}/$self->{userid}";
}

# in scalar context returns comma-seperated list of keywords or "pic#12345" if no keywords defined
# in list context returns list of keywords ( (pic#12345) if none defined )
sub keywords {
    my $self = shift;

    my $picinfo = LJ::get_userpic_info($self->{userid}, {load_comments => 0});

    # $picinfo is a hashref of userpic data
    # keywords are stored in the "kw" field in the format keyword => {hash of some picture info}

    # create a hash of picids => keywords
    my $keywords = {};
    foreach my $keyword (keys %{$picinfo->{kw}}) {
        my $picid = $picinfo->{kw}->{$keyword}->{picid};
        $keywords->{$picid} = [] unless $keywords->{$picid};
        push @{$keywords->{$picid}}, $keyword if ($keyword && $picid);
    }

    # return keywords for this picid
    my @pickeywords = $keywords->{$self->id} ? @{$keywords->{$self->id}} : ();

    if (wantarray) {
        # if list context return the array
        return ("pic#" . $self->id) unless @pickeywords;

        return @pickeywords;
    } else {
        # if scalar context return comma-seperated list of keywords, or "pic#12345" if no keywords
        return ("pic#" . $self->id) unless @pickeywords;

        return join(',', @pickeywords);
    }
}

sub imagedata {
    my $self = shift;

    my %upics;
    my $u = $self->owner;
    LJ::load_userpics(\%upics, [ $u, $self->{picid} ]);
    my $pic = $upics{$self->{picid}} or
        return undef;

    return undef if $pic->{'userid'} != $self->{userid} || $pic->{state} eq 'X';

    if ($pic->{location} eq "M") {
        my $key = $u->mogfs_userpic_key( $self->{picid} );
        my $data = LJ::mogclient()->get_file_data( $key );
        return $$data;
    }

    my %MimeTypeMap = (
                       'image/gif' => 'gif',
                       'image/jpeg' => 'jpg',
                       'image/png' => 'png',
                       );
    my %MimeTypeMapd6 = (
                         'G' => 'gif',
                         'J' => 'jpg',
                         'P' => 'png',
                         );

    my $data;
    if ($LJ::USERPIC_BLOBSERVER) {
        my $fmt = ($u->{'dversion'} > 6) ? $MimeTypeMapd6{ $pic->{fmt} } : $MimeTypeMap{ $pic->{contenttype} };
        $data = LJ::Blob::get($u, "userpic", $fmt, $self->{picid});
        return $data if $data;
    }

    my $dbb = LJ::get_cluster_reader($u)
        or return undef;

    $data = $dbb->selectrow_array("SELECT imagedata FROM userpicblob2 WHERE ".
                                  "userid=? AND picid=?", undef, $self->{userid},
                                  $self->{picid});
    return undef;
}

# does the user's dataversion support userpic comments?
sub supports_comments {
    my $self = shift;

    my $u = $self->owner;
    return $u->{dversion} > 6;
}

# class method
# does this user's dataversion support usepic comments?
sub user_supports_comments {
    my ($class, $u) = @_;

    return undef unless ref $u;

    return $u->{dversion} > 6;
}

# TODO: add in lazy peer loading here
sub load_row {
    my $self = shift;
    my $u = $self->owner;
    my $row;
    if ($u->{'dversion'} > 6) {
        $row = $u->selectrow_hashref("SELECT userid, picid, width, height, state, fmt, comment, location " .
                                     "FROM userpic2 WHERE userid=? AND picid=?", undef,
                                     $u->{userid}, $self->{picid});
    } else {
        my $dbh = LJ::get_db_writer();
        $row = $dbh->selectrow_hashref("SELECT userid, picid, width, height, state, contenttype " .
                                       "FROM userpic WHERE userid=? AND picid=?", undef,
                                       $u->{userid}, $self->{picid});
    }
    $self->absorb_row($row);
}

sub load_user_userpics {
    my ($class, $u) = @_;
    local $LJ::THROW_ERRORS = 1;
    my @ret;

    # select all of their userpics and iterate through them
    my $sth;
    if ($u->{'dversion'} > 6) {
        $sth = $u->prepare("SELECT userid, picid, width, height, state, fmt, comment, location " .
                           "FROM userpic2 WHERE userid=?");
    } else {
        my $dbh = LJ::get_db_writer();
        $sth = $dbh->prepare("SELECT userid, picid, width, height, state, contenttype " .
                             "FROM userpic WHERE userid=?");
    }
    $sth->execute($u->{'userid'});
    while (my $rec = $sth->fetchrow_hashref) {
        # ignore anything expunged
        next if $rec->{state} eq 'X';
        push @ret, LJ::Userpic->new_from_row($rec);
    }
    return @ret;
}

# FIXME: XXX: NOT YET FINISHED
sub create {
    my ($class, $u, %opts) = @_;
    local $LJ::THROW_ERRORS = 1;

    my $dataref = delete $opts{'data'};
    $dataref = \$dataref unless ref $dataref;
    croak("Unknown options: " . join(", ", scalar keys %opts)) if %opts;

    my $err = sub {
        my $msg = shift;
    };

    my ($w, $h, $filetype) = Image::Size::imgsize($dataref);
    my $MAX_UPLOAD = LJ::Userpic->max_allowed_bytes($u);

    my $size = length $$dataref;

    my @errors;
    if ($size > $MAX_UPLOAD) {
        push @errors, LJ::errobj("Userpic::ByteSize",
                                 size => $size,
                                 max  => $MAX_UPLOAD);
    }

    unless ($w >= 1 && $w <= 100 && $h >= 1 && $h <= 100) {
        push @errors, LJ::errobj("Userpic::Dimensions",
                                 w => $w, h => $h);
    }

    unless ($filetype eq "GIF" || $filetype eq "JPG" || $filetype eq "PNG") {
        push @errors, LJ::errobj("Userpic::FileType",
                                 type => $filetype);
    }

    LJ::throw(@errors);

    my $base64 = Digest::MD5::md5_base64($$dataref);


    my $target;
    if ($u->{dversion} > 6 && $LJ::USERPIC_MOGILEFS) {
        $target = 'mogile';
    } elsif ($LJ::USERPIC_BLOBSERVER) {
        $target = 'blob';
    }

    my $dbh = LJ::get_db_writer();

    # see if it's a duplicate
    my $picid;
    my $contenttype;
    if ($u->{'dversion'} > 6) {
        if ($filetype eq "GIF") { $contenttype = 'G'; }
        elsif ($filetype eq "PNG") { $contenttype = 'P'; }
        elsif ($filetype eq "JPG") { $contenttype = 'J'; }

        my $dbcr = LJ::get_cluster_def_reader($u);
        $picid = $dbcr->selectrow_array("SELECT picid FROM userpic2 " .
                                        "WHERE userid=? AND fmt=? " .
                                        "AND md5base64=?",
                                        undef, $u->{'userid'}, $contenttype, $base64);
    } else {
        if ($filetype eq "GIF") { $contenttype = "image/gif"; }
        elsif ($filetype eq "PNG") { $contenttype = "image/png"; }
        elsif ($filetype eq "JPG") { $contenttype = "image/jpeg"; }

        $picid = $dbh->selectrow_array("SELECT picid FROM userpic " .
                                       "WHERE userid=? AND contenttype=? " .
                                       "AND md5base64=?",
                                       undef, $u->{'userid'}, $contenttype, $base64);
    }

    # return it if it exists

    # if doesn't exist, make it

    $picid = LJ::alloc_global_counter('P');

    @errors = (); # TEMP: FIXME: remove... using exceptions

    my $dberr = 0;
    if ($u->{'dversion'} > 6) {
        $u->do("INSERT INTO userpic2 (picid, userid, fmt, width, height, " .
               "picdate, md5base64, location) VALUES (?, ?, ?, ?, ?, NOW(), ?, ?)",
               undef, $picid, $u->{'userid'}, $contenttype, $w, $h, $base64, $target);
        if ($u->err) {
            push @errors, $err->($u->errstr);
            $dberr = 1;
        }
    } else {
        $dbh->do("INSERT INTO userpic (picid, userid, contenttype, width, height, " .
                 "picdate, md5base64) VALUES (?, ?, ?, ?, ?, NOW(), ?)",
                 undef, $picid, $u->{'userid'}, $contenttype, $w, $h, $base64);
        if ($dbh->err) {
            push @errors, $err->($dbh->errstr);
            $dberr = 1;
        }
    }

    my $clean_err = sub {
        if ($u->{'dversion'} > 6) {
            $u->do("DELETE FROM userpic2 WHERE userid=? AND picid=?",
                   undef, $u->{'userid'}, $picid) if $picid;
        } else {
            $dbh->do("DELETE FROM userpic WHERE picid=?", undef, $picid) if $picid;
        }
        return $err->(@_);
    };

    ### insert the blob
    if ($target eq 'mogile' && !$dberr) {
        my $fh = LJ::mogclient()->new_file($u->mogfs_userpic_key($picid), 'userpics');
        if (defined $fh) {
            $fh->print($$dataref);
            my $rv = $fh->close;
            push @errors, $clean_err->("Error saving to storage server: $@") unless $rv;
        } else {
            # fatal error, we couldn't get a filehandle to use
            push @errors, $clean_err->("Unable to contact storage server.  Your picture has not been saved.");
        }
    } elsif ($target eq 'blob' && !$dberr) {
        my $et;
        my $fmt = lc($filetype);
        my $rv = LJ::Blob::put($u, "userpic", $fmt, $picid, $$dataref, \$et);
        push @errors, $clean_err->("Error saving to media server: $et") unless $rv;
    } elsif (!$dberr) {
        my $dbcm = LJ::get_cluster_master($u);
        return $err->($BML::ML{'error.nodb'}) unless $dbcm;
        $u->do("INSERT INTO userpicblob2 (userid, picid, imagedata) " .
               "VALUES (?, ?, ?)",
               undef, $u->{'userid'}, $picid, $$dataref);
        push @errors, $clean_err->($u->errstr) if $u->err;
    } else { # We should never get here!
        push @errors, "User picture uploading failed for unknown reason";
    }

    # now that we've created a new pic, invalidate the user's memcached userpic info
    LJ::Userpic->delete_memcache($u);
}

# make this picture the default
sub make_default {
    my $self = shift;
    my $u = $self->owner;

    LJ::update_user($u, { defaultpicid => $self->id });
    $u->{'defaultpicid'} = $self->id;
}

# returns true if this picture if the default userpic
sub is_default {
    my $self = shift;
    my $u = $self->owner;

    return $u->{'defaultpicid'} == $self->id;
}

sub delete_memcache {
    my ($class, $u) = @_;
    my $memkey = [$u->{'userid'},"upicinf:$u->{'userid'}"];
    LJ::MemCache::delete($memkey);
    $memkey = [$u->{'userid'},"upiccom:$u->{'userid'}"];
    LJ::MemCache::delete($memkey);
    $memkey = [$u->{'userid'},"upicurl:$u->{'userid'}"];
    LJ::MemCache::delete($memkey);

}

####
# error classes:

package LJ::Error::Userpic::TooManyKeywords;

sub user_caused { 1 }
sub fields      { qw(userpic lost); }

sub number_lost {
    my $self = shift;
    return scalar @{ $self->field("lost") };
}

sub lost_keywords_as_html {
    my $self = shift;
    return join(", ", map { LJ::ehtml($_) } @{ $self->field("lost") });
}

sub as_html {
    my $self = shift;
    my $num_words = $self->number_lost;
    return BML::ml("/editpics.bml.error.toomanykeywords", {
        numwords => $self->number_lost,
        words    => $self->lost_keywords_as_html,
        max      => $LJ::MAX_USERPIC_KEYWORDS,
    });
}

package LJ::Error::Userpic::Bytesize;
sub user_caused { 1 }
sub fields      { qw(size max); }
sub as_html {
    my $self = shift;
    return BML::ml('/editpics.bml.error.filetoolarge',
                   { 'maxsize' => $self->{'max'} .
                         BML::ml('/editpics.bml.kilobytes')} );
}

package LJ::Error::Userpic::Dimensions;
sub user_caused { 1 }
sub fields      { qw(w h); }
sub as_html {
    my $self = shift;
    return BML::ml('/editpics.bml.error.imagetoolarge', {
        imagesize => $self->{'w'} . 'x' . $self->{'h'}
        });
}

package LJ::Error::Userpic::FileType;
sub user_caused { 1 }
sub fields      { qw(type); }
sub as_html {
    my $self = shift;
    return BML::ml("/editpics.bml.error.unsupportedtype",
                          { 'filetype' => $self->{'type'} });
}


__END__

# instance method:  takes a string of comma-separate keywords, or an array of keywords
# FIXME: XXX: NOT YET FINISHED (NOT YET TESTED)
sub set_keywords {
    my $self = shift;
    my $opts = ref $_[0] eq "HASH" ? {%{ $_[0] }} : {};

    my @keywords;
    if (@keywords > 1) {
        @keywords = @_;
    } else {
        @keywords = split(',', $_[0]);
    }
    @keywords = grep { s/^\s+//; s/\s+$//; $_; } @keywords;

    my $on_warn = delete $opts->{'onwarn'} || sub {};
    Carp::croak("Unknown options") if %$opts;

    my $u = $self->owner;
    my $sth;
    my $dbh;

    if ($u->{'dversion'} > 6) {
        $sth = $u->prepare("SELECT kwid, picid FROM userpicmap2 WHERE userid=?");
    } else {
        $dbh = LJ::get_db_writer();
        $sth = $dbh->prepare("SELECT kwid, picid FROM userpicmap WHERE userid=?");
    }
    $sth->execute($u->{'userid'});

    my %exist_kwids;
    while (my ($kwid, $picid) = $sth->fetchrow_array) {
        $exist_kwids{$kwid} = $picid;
    }

    my (@bind, @data, @kw_errors);
    my $c = 0;
    my $picid = $self->{picid};

    foreach my $kw (@keywords) {
        my $kwid = ($u->{'dversion'} > 6) ? LJ::get_keyword_id($u, $kw) : LJ::get_keyword_id($kw);
        next unless $kwid; # FIXME: fire some warning that keyword was bogus

        if (++$c > $LJ::MAX_USERPIC_KEYWORDS) {
            push @kw_errors, $kw;
            next;
        }

        if ($exist_kwids{$kwid}) { # Already used on another picture
            my $ekw = LJ::ehtml($kw);
            #push @errors, BML::ml(".error.keywords", {'ekw' => $ekw});
            next;
        } else { # New keyword, so save it
            push @bind, '(?, ?, ?)';
            push @data, $u->{'userid'}, $kwid, $picid;
        }

    }

    # Let the user know about any we didn't save
    if (@kw_errors) {
        my $num_words = scalar(@kw_errors);
        $on_warn->(LJ::errobj("Userpic::TooManyKeywords",
                               userpic => $self,
                               lost    => \@kw_errors));


        #push @errors, BML::ml(".error.toomanykeywords", {'numwords' => $num_words, 'words' => $kws, 'max' => $LJ::MAX_USERPIC_KEYWORDS});
    }

    return 1 unless @data;
    my $bind = join(',', @bind);

    if ($u->{'dversion'} > 6) {
        return $u->do("INSERT INTO userpicmap2 (userid, kwid, picid) VALUES $bind",
                      undef, @data);
    } else {
        return $dbh->do("INSERT INTO userpicmap (userid, kwid, picid) VALUES $bind",
                        undef, @data);
    }
}


sub set_keywords {
    my ($self, $keywords) = @_;

            if (%picid_of_kwid) {
                if ($u->{'dversion'} > 6) {
                    $u->do("REPLACE INTO userpicmap2 (userid, kwid, picid) VALUES " .
                           join(",", map { "(" .
                                               join(",",
                                                    $dbcm->quote($u->{'userid'}),
                                                    $dbcm->quote($_),
                                                    $dbcm->quote($picid_of_kwid{$_})) .
                                                    ")"
                                                }
                                keys %picid_of_kwid)
                           );
                } else {
                    $dbh->do("REPLACE INTO userpicmap (userid, kwid, picid) VALUES " .
                             join(",", map { "(" .
                                                 join(",",
                                                      $dbh->quote($u->{'userid'}),
                                                      $dbh->quote($_),
                                                      $dbh->quote($picid_of_kwid{$_})) .
                                                      ")"
                                                  }
                                  keys %picid_of_kwid)
                             );
                }
            }

            # Delete keywords that are no longer being used
            my @kwid_del;


            if (@kwid_del) {
                my $kwid_del = join(",", @kwid_del);
                if ($u->{'dversion'} > 6) {
                    $u->do("DELETE FROM userpicmap2 WHERE userid=$u->{userid} " .
                           "AND kwid IN ($kwid_del)");
                } else {
                    $dbh->do("DELETE FROM userpicmap WHERE userid=$u->{userid} " .
                             "AND kwid IN ($kwid_del)");
                }
            }

}

sub set_comment {
    my ($self, $comment) = @_;
    return 0 unless $u->{'dversion'} > 6;
    my $comment = LJ::text_trim($POST{"com_$pic->{'picid'}"}, LJ::BMAX_UPIC_COMMENT, LJ::CMAX_UPIC_COMMENT);
    $u->do("UPDATE userpic2 SET comment=? WHERE userid=? AND picid=?",
           undef, $comment, $u->{'userid'}, $pic->{'picid'});
}

sub set_fullurl {
    my ($self, $url) = @_;
    return 0 unless $u->{'dversion'} > 6;
    $u->do("UPDATE userpic2 SET $set WHERE userid=? AND picid=?",
           undef, @data, $u->{'userid'}, $picid);
}

# delete this userpic
# TODO: error checking/throw errors on failure
sub delete {
    my $self = shift;

    my $fmt;
    if ($u->{'dversion'} > 6) {
        $fmt = {
            'G' => 'gif',
            'J' => 'jpg',
            'P' => 'png',
        }->{$ctype{$picid}};
    } else {
        $fmt = {
            'image/gif' => 'gif',
            'image/jpeg' => 'jpg',
            'image/png' => 'png',
        }->{$ctype{$picid}};
    }

    my $deleted = 0;

    my $id_in;
    if ($u->{'dversion'} > 6) {
        $id_in = join(", ", map { $dbcm->quote($_) } @delete);
    } else {
        $id_in = join(", ", map { $dbh->quote($_) } @delete);
    }


    # try and delete from either the blob server or database,
    # and only after deleting the image do we delete the metadata.
    if ($locations{$picid} eq 'mogile') {
        $deleted = 1
            if LJ::mogclient()->delete($u->mogfs_userpic_key($picid));
    } elsif ($LJ::USERPIC_BLOBSERVER &&
             LJ::Blob::delete($u, "userpic", $fmt, $picid)) {
        $deleted = 1;
    } elsif ($u->do("DELETE FROM userpicblob2 WHERE ".
                    "userid=? AND picid=?", undef,
                    $u->{userid}, $picid) > 0) {
        $deleted = 1;
    }

    # now delete the metadata if we got the real data
    if ($deleted) {
        if ($u->{'dversion'} > 6) {
            $u->do("DELETE FROM userpic2 WHERE picid=? AND userid=?",
                   undef, $picid, $u->{'userid'});
        } else {
            $dbh->do("DELETE FROM userpic WHERE picid=?", undef, $picid);
        }
        $u->do("DELETE FROM userblob WHERE journalid=? AND blobid=? " .
               "AND domain=?", undef, $u->{'userid'}, $picid,
               LJ::get_blob_domainid('userpic'));

        # decrement $count to reflect deletion
        $count--;
    }

    # if we didn't end up deleting, it's either because of
    # some transient error, or maybe there was nothing to delete
    # for some bizarre reason, in which case we should verify
    # that and make sure they can delete their metadata
    if (! $deleted) {
        my $present;
        if ($locations{$picid} eq 'mogile') {
            my $blob = LJ::mogclient()->get_file_data($u->mogfs_userpic_key($picid));
            $present = length($blob) ? 1 : 0;
        } elsif ($LJ::USERPIC_BLOBSERVER) {
            my $blob = LJ::Blob::get($u, "userpic", $fmt, $picid);
            $present = length($blob) ? 1 : 0;
        }
        $present ||= $dbcm->selectrow_array("SELECT COUNT(*) FROM userpicblob2 WHERE ".
                                            "userid=? AND picid=?", undef, $u->{'userid'},
                                            $picid);
        if (! int($present)) {
            if ($u->{'dversion'} > 6) {
                $u->do("DELETE FROM userpic2 WHERE picid=? AND userid=?",
                       undef, $picid, $u->{'userid'});
            } else {
                $dbh->do("DELETE FROM userpic WHERE picid=?", undef, $picid);
            }
        }
    }
}


1;
