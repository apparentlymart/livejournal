package LJ::Directory::SetHandle::Mogile;
use strict;
use base 'LJ::Directory::SetHandle';
use Class::Autouse qw (LWP::UserAgent);

sub new {
    my ($class, $conskey) = @_;

    my $self = {
        conskey => $conskey,
    };

    return bless $self, $class;
}

sub new_from_string {
    my ($class, $str) = @_;
    $str =~ s/^Mogile:// or die;
    return $class->new($str);
}

sub as_string {
    my $self = shift;
    return "Mogile:" . $self->{conskey};
}

sub set_size {
    my $self = shift;
    # TODO: do this in the same request as load_matching_uids for fewer round-trips
    my $client = LJ::mogclient() or die "No mogile client";
    my ($path) = $client->get_paths($self->mogkey);
    return undef unless $path;

    # do a HEAD reqest
    my $ua = LWP::UserAgent->new;
    my $resp = $ua->head($path);
    return undef unless $resp->code == 200;
    return $resp->header("Content-Length");
}

sub load_matching_uids {
    my ($self, $cb) = @_;
    my $client = LJ::mogclient() or die "No mogile client";
    my ($path) = $client->get_paths($self->mogkey);
    return undef unless $path;

    # stream data with LWP and call callback func with
    # streamed data
    my $ua = LWP::UserAgent->new;
    $ua->get(
             $path,
             ':content_cb' => $cb,
             );
}

sub load_pack_data {
    my ($self, $cb) = @_;
    $self->load_matching_uids(sub {
        $cb->(shift @_);
    });
}


sub mogkey {
    my $self = shift;
    return "dsh:" . $self->{conskey};
}

1;
