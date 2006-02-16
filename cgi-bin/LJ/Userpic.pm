package LJ::Userpic;
use strict;
use Carp qw(croak);
use Digest::MD5;

sub new {
    my ($class, $u, $picid) = @_;
    return bless {
        userid => $u->{userid},
        picid  => int($picid),
    };
}

sub max_allowed_bytes {
    my ($class, $u) = @_;
    return 40960;
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



}

sub owner {
    my $self = shift;
    return LJ::load_userid($self->{userid});
}

sub url {
    my $self = shift;
    return "$LJ::USERPIC_ROOT/$self->{picid}/$self->{userid}";
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

# returns (width, height)
sub dimensions {
    my $self = shift;

    my %upics;
    my $u = LJ::load_userid($self->{userid});
    LJ::load_userpics(\%upics, [ $u, $self->{picid} ]);
    my $up = $upics{$self->{picid}} or
        return ();

    return ($up->{width}, $up->{height});
}

# instance method:  takes a string of comma-separate keywords, or an array of keywords
# FIXME: XXX: NOT YET FINISHED (NOT YET TESTED)
sub set_keywords {
    my $self = shift;
    my $opts = ref $_[0] eq "HASH" ? {%{ $_[0] }} : {};

    my @keywords;
    if (@keywords > 1) {
        @keywords = @_;
    } else {
        @keywords = split(/,/, $_[0]);
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

package LJ::Error::Userpic::Bytesize;
sub user_caused { 1 }
sub fields      { qw(size max); }

package LJ::Error::Userpic::Dimensions;
sub user_caused { 1 }
sub fields      { qw(w h); }

package LJ::Error::Userpic::FileType;
sub user_caused { 1 }
sub fields      { qw(type); }



1;
