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
    my $bcid = $u->{blob_clusterid} or die "No blob_clusterid";
    return $bc_cache{$bcid} ||=
        _bc_from_path($LJ::BLOBINFO{clusters}->{$bcid});
}

# read-only access.  (i.e. direct HTTP connection to NetApp)
sub get_blobclient_reader {
    my $u = shift;
    my $bcid = $u->{blob_clusterid} or die "No blob_clusterid";
 
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

sub _load_bcid {
    my $u = shift;
    die "No user" unless $u;
    return if $u->{blob_clusterid};
    LJ::load_user_props($u, "blob_clusterid");
    return if $u->{blob_clusterid};
    die "Couldn't find user $u->{user}'s blob_clusterid\n";
}

# args: u, domain, fmt, bid
# des-fmt: string file extension ("jpg", "gif", etc)
# des-bid: numeric blob id for this domain
# des-domain: string name of domain ("userpic", "phonephost", etc)
sub get {
    my ($u, $domain, $fmt, $bid) = @_;
    _load_bcid($u);
    my $bc = get_blobclient_reader($u);
    return $bc->get($u->{blob_clusterid}, $u->{userid}, $domain, $fmt, $bid);
}

sub get_stream {
    my ($u, $domain, $fmt, $bid, $callback) = @_;
    _load_bcid($u);
    my $bc = get_blobclient_reader($u);
    return $bc->get_stream($u->{blob_clusterid}, $u->{userid}, $domain, $fmt, $bid, $callback);
}

sub put {
    my ($u, $domain, $fmt, $bid, $data, $errref) = @_;
    _load_bcid($u);
    my $bc = get_blobclient($u);

    my $dbcm = LJ::get_cluster_master($u);
    unless ($dbcm) {
        $$errref = "nodb";
        return 0;
    }

    unless ($bc->put($u->{blob_clusterid}, $u->{userid}, $domain, 
                     $fmt, $bid, $data, $errref)) {
        return 0;
    }

    $dbcm->do("INSERT IGNORE INTO userblob (journalid, domain, blobid, length) ".
              "VALUES (?, ?, ?, ?)", undef,
              $u->{userid}, LJ::get_blob_domainid($domain), 
              $bid, length($data));
    die "Error doing userblob accounting: " . $dbcm->errstr if $dbcm->err;
    return 1;
}

sub delete {
    my ($u, $domain, $fmt, $bid) = @_;
    _load_bcid($u);
    my $bc = get_blobclient($u);

    my $dbcm = LJ::get_cluster_master($u) or return 0;

    my $bdid = LJ::get_blob_domainid($domain);
    return 0 unless $bc->delete($u->{blob_clusterid}, $u->{userid}, $domain, 
                                $fmt, $bid);

    $dbcm->do("DELETE FROM userblob WHERE journalid=? AND domain=? AND blobid=?",
              undef, $u->{userid}, $bdid, $bid);
    die "Error doing userblob accounting: " . $dbcm->errstr if $dbcm->err;
    return 1;
}

sub get_disk_usage {
    my ($u, $domain) = @_;
    my $dbcr = LJ::get_cluster_reader($u);
    return $dbcr->selectrow_array("SELECT SUM(length) FROM userblob ".
                                  "WHERE journalid=? AND domain=?", undef,
                                  $u->{userid}, LJ::get_blob_domainid($domain));
}

1;
