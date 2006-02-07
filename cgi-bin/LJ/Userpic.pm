package LJ::Userpic;
use strict;

sub new {
    my ($class, $u, $picid) = @_;
    return bless {
        userid => $u->{userid},
        picid  => int($picid),
    };
}

sub url {
    my $self = shift;
    return "$LJ::USERPIC_ROOT/$self->{picid}/$self->{userid}";
}

sub imagedata {
    my $self = shift;

    my %upics;
    my $u = LJ::load_userid($self->{userid});
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

1;
