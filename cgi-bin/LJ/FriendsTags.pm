package LJ::FriendsTags;

use strict;
use Encode;

use constant ALLOW => 'A';
use constant DENY  => 'D';
use constant MAX_FRIENDSTAGS_SIZE => 65535;

#
# {
#   friendid1 => [
#     ('A' | 'D'),
#     [ tag1, tag2, ... ]
#   ],
#   ...
# }
#

sub load {
    my ($class, $remote) = @_;

    return undef unless $remote;
    my $prop = $remote->prop('friends_tags');
    $prop = LJ::text_uncompress($prop);

    my $data;
    if ($prop) {
        eval { $data = LJ::JSON->from_json($prop); };
    }

    unless ($data && ref($data) eq 'HASH') {
        $data = {};
    }

    my $self = bless {
        _u    => $remote,
        _data => $data,
    }, $class;

    return $self;
}

sub load_tags {
    my ($class, $remote) = @_;
    
    my $self = $class->load($remote);
    my $data = $self->{_data};
    return $data;
}

sub is_allow_mode {
    my ($class, $mode) = @_;

    return 0 if $mode && lc($mode) eq lc(DENY);
    return 1;
}

sub normalize_mode {
    my ($class, $mode) = @_;

    return $class->is_allow_mode($mode) ? ALLOW : DENY;
}

sub save {
    my ($self) = @_;

    while (my ($friendid, $arr) = each %{$self->{_data}}) {
        unless (LJ::is_friend($self->{_u}, $friendid)) {
            delete $self->{_data}->{$friendid};
        }
    }

    my $prop = LJ::JSON->to_json($self->{_data});
    $prop = LJ::text_compress($prop); 

    if (length($prop) <= MAX_FRIENDSTAGS_SIZE) {
        return $self->{_u}->set_prop(friends_tags => $prop);
    } else {
        # BML::ml('widget.addalias.too.long');
        return 0;
    }
}

sub get_tags {
    my ($self, $friendid) = @_;

    my $ret = $self->{_data}->{$friendid};
    return (undef, []) unless $ret && ref($ret) eq 'ARRAY';
    my $mode = $ret->[0];
    my $tags = $ret->[1];
    $tags = [] unless $tags && ref($tags) eq 'ARRAY';
    return ($mode, $tags);
}

sub set {
    my ($self, $friendid, $mode, $tags_str) = @_;

    my $data = $self->{_data};

    $mode = $self->normalize_mode($mode);

    $tags_str = '' unless defined $tags_str;
    $tags_str =~ s/^\s+//s;
    $tags_str =~ s/\s+$//s;
    $tags_str = $self->normalize_tag($tags_str);

    if (length($tags_str) > 0) {
        my %tags = map { lc($_) => 1 } split /\s*,\s*/, $tags_str;
        if (keys %tags) {
            $data->{$friendid} = [ $mode, [ sort grep { length($_) > 0 } keys %tags ] ];
        } else {
            delete $data->{$friendid};
        }
    } else {
        delete $data->{$friendid};
    }

    $self->{_data} = $data;
}

sub normalize_tag {
    my ($class, $tag) = @_;
    return Encode::encode('utf-8', lc(Encode::decode('utf-8', $tag)));
};

sub filter_func {
    my ($self, $friendid) = @_;

    my ($mode, $tags) = $self->get_tags($friendid);
    return undef unless defined $mode && @$tags;
    my %tags = map { $_ => 1 } @$tags;

    if ($mode eq DENY) {
        return sub {
            return 1 unless @_;
            foreach (@_) {
                return 0 if exists $tags{$self->normalize_tag($_)};
            }
            return 1;
        };
    } else {
        return sub {
            return 0 unless @_;
            foreach (@_) {
                return 1 if exists $tags{$self->normalize_tag($_)};
            }
            return 0;
        };
    }
}

1;

