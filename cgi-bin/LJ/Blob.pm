# Wrapper around BlobClient.

use strict;
use lib "$ENV{'LJHOME'}/cgi-bin";
use BlobClient;

package LJ::Blob;

my %clusters = ();

sub get_blobcluster {
    my $u = shift;
    my $bcid = $LJ::BLOBINFO{cluster_map}->{$u->{clusterid}};
    $clusters{$bcid} ||= new LJ::BlobCluster($bcid, $LJ::BLOBINFO{clusters}->{$bcid});
    return $clusters{$bcid};
}

sub get {
    my $u = shift;
    my $bc = get_blobcluster($u);
    return $bc->get($u, @_);
}

sub get_stream {
    my $u = shift;
    my $bc = get_blobcluster($u);
    return $bc->get_stream($u, @_);
}

sub put {
    my ($u, $domain, $fmt, $bid, $data, $errref) = @_;
    my $bc = get_blobcluster($u);

    unless ($bc->put($u, $domain, $fmt, $bid, $data, $errref)) {
        return 0;
    }

    my $dbcm = LJ::get_cluster_master($u);
    $dbcm->do("INSERT INTO userblob ".
              "(journalid, domain, blobid, length) ".
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

package LJ::BlobCluster;

use constant MAX_TRIES => 10; # number of tries to randomly find a live host

sub new {
    my ($class, $bcid, $paths) = @_;
    my $self = {};

    $self->{bcid} = $bcid;
    foreach my $path (@$paths) {
        if ($path =~ /^http/) {
            push @{$self->{clients}}, new BlobClient::Remote({ path => $path });
        } else {
            push @{$self->{clients}}, new BlobClient::Local({ path => $path });
        }
    }

    bless $self, ref $class || $class;
    return $self;
}

sub get_random_source {
    my $self = shift;
    my $clients = $self->{clients};

    my $tries = 0;
    my $client = $clients->[int(rand(scalar @$clients))];
    while ($client->is_dead) {
        return undef if $tries++ > MAX_TRIES;
        $client = $clients->[int(rand(scalar @$clients))];
    }
    return $client;
}

sub get_first_source {
    my $self = shift;
    foreach my $source (@{$self->{clients}}) {
        return $source unless ($source->is_dead);
    }
    return undef;
}

sub get {
    my $self = shift;
    my $u = shift;

    my $source = $self->get_random_source();

    my $data = $source->get($u->{clusterid}, $u->{userid}, @_);
    unless ($data) {
        $source = $self->get_first_source();
        $data = $source->get($u->{clusterid}, $u->{userid}, @_) if $source;
    }
    return $data;
}

sub get_stream {
    my $self = shift;
    my $u = shift;

    my $source = $self->get_random_source();

    my $ret = $source->get_stream($u->{clusterid}, $u->{userid}, @_);
    unless ($ret) {
        $source = $self->get_first_source();
        $ret = $source->get_stream($u->{clusterid}, $u->{userid}, @_) if $source;
    }
    return $ret;
}

sub put {
    my $self = shift;
    my ($u, $domain, $fmt, $bid, $data, $errref) = @_;

    # we succeed if we manage to put to one server.
    my $success = 0;
    foreach my $source (@{$self->{clients}}) {
        next if $source->is_dead;
        if ($source->put($u->{clusterid}, $u->{userid}, $domain, $fmt, $bid, $data, $errref)) {
            $success = 1;
        }
    }
    return $success;
}

1;
