# Wrapper around BlobClient.

use strict;
use lib "$ENV{'LJHOME'}/cgi-bin";
use BlobClient;

package LJ::Blob;

my %bc_cache = ();
my %bc_reader_cache = ();

# read-write (i.e. HTTP connection to BlobServer, with NetApp NFS mounted)
sub get_blobclient {
    my $u = shift;
    my $bcid = $LJ::BLOBINFO{cluster_map}->{$u->{clusterid}} ||
        $LJ::BLOBINFO{cluster_map}->{_default};
    return $bc_cache{$bcid} ||=
        _bc_from_path($LJ::BLOBINFO{clusters}->{$bcid});
}

# read-only access.  (i.e. direct HTTP connection to NetApp)
sub get_blobclient_reader {
    my $u = shift;
    my $bcid = $LJ::BLOBINFO{cluster_map}->{$u->{clusterid}} ||
        $LJ::BLOBINFO{cluster_map}->{_default};
 
    return $bc_reader_cache{$bcid} if $bc_reader_cache{$bcid};

    my $path = $LJ::BLOBINFO{clusters}->{"$bcid-GET"} ||
        $LJ::BLOBINFO{clusters}->{$bcid};
    
    return $bc_reader_cache{$bcid} = _bc_from_path($path);
}

sub _bc_from_path {
    my $path = shift;
    if ($path =~ /^http/) {
        return BlobClient::Remote->new({ path => $path });
    } elsif ($path) {
        return BlobClient::Local->new({ path => $path });
    }
    return undef;
}

# args: u, domain, fmt, bid
# des-fmt: string file extension ("jpg", "gif", etc)
# des-bid: numeric blob id for this domain
# des-domain: string name of domain ("userpic", "phonephost", etc)
sub get {
    my ($u, $domain, $fmt, $bid) = @_;
    my $bc = get_blobclient_reader($u);
    return $bc->get($u->{clusterid}, $u->{userid}, $domain, $fmt, $bid);
}

sub get_stream {
    my ($u, $domain, $fmt, $bid, $callback) = @_;
    my $bc = get_blobclient_reader($u);
    return $bc->get($u->{clusterid}, $u->{userid}, $domain, $fmt, $bid, $callback);
}

sub put {
    my ($u, $domain, $fmt, $bid, $data, $errref) = @_;
    my $bc = get_blobclient($u);

    my $dbcm = LJ::get_cluster_master($u);
    unless ($dbcm) {
        $$errref = "nodb";
        return 0;
    }

    unless ($bc->put($u->{clusterid}, $u->{userid}, $domain, 
                     $fmt, $bid, $data, $errref)) {
        return 0;
    }

    $dbcm->do("INSERT INTO userblob (journalid, domain, blobid, length) ".
              "VALUES (?, ?, ?, ?)", undef,
              $u->{userid}, $LJ::BLOBINFO{blobdomain_ids}->{$domain},
              $bid, length($data));
    return 1;
}

sub get_disk_usage {
    my ($u, $domain) = shift;
    my $dbcr = LJ::get_cluster_reader($u);
    return $dbcr->selectrow_array(
                    "SELECT SUM(length) FROM userblob ".
                    "WHERE journalid=? AND domain=?", undef,
                    $u->{userid}, $LJ::BLOBINFO{blobdomain_ids}->{$domain});
}

1;
