package LJ::API::Repost;

use strict;
use warnings;

use LJ::Entry;
use LJ::API::Error;
use LJ::Entry::Repost;

sub create : method {
    my ($self, $options) = @_;

    return LJ::API::Error->get_error('invalid_params') unless
        $options->{'url'};

    my $u = LJ::get_remote();
    if ($options->{'target'}) {
        $u = LJ::load_user($options->{'target'});
    }

    return LJ::API::Error->get_error('invalid_params') unless $u;
    return LJ::API::Error->get_error('invalid_params') unless $options->{'timezone'};

    my $url   = $options->{'url'};
    my $entry = LJ::Entry->new_from_url($url);

    return LJ::API::Error->get_error('invalid_params') unless $entry;

    my $timezone = $options->{'timezone'};

    my $result = LJ::Entry::Repost->create(  $u, # destination journal
                                             $entry, # entry to be reposted
                                             $timezone ); # timezone for repost

    return $result;    
}

sub delete : method {
    my ($self, $options) = @_;

    return LJ::API::Error->get_error('invalid_params') unless
        $options->{'url'};

    my $u = LJ::get_remote();
    if ($options->{'target'}) {
        $u = LJ::load_user($options->{'target'});
    }

    return LJ::API::Error->get_error('invalid_params') unless $u;

    my $url   = $options->{'url'};
    my $entry = LJ::Entry->new_from_url($url);

    return LJ::API::Error->get_error('invalid_params') unless $entry;

    my $result = LJ::Entry::Repost->delete(  $u, # destination journal
                                             $entry,); # entry to be reposted
    return $result;
}

sub get_status : method {
    my ($self, $options) = @_;

    return LJ::API::Error->get_error('invalid_params') unless
        $options->{'url'};

    my $u = LJ::get_remote();
    if ($options->{'target'}) {
        $u = LJ::load_user($options->{'target'});
    }

    return LJ::API::Error->get_error('invalid_params') unless $u;

    my $url   = $options->{'url'};
    my $entry = LJ::Entry->new_from_url($url);

    return  LJ::API::Error->get_error('invalid_params') unless $entry;

    my $result = LJ::Entry::Repost->get_status( $u, # destination journal
                                                $entry,); # entry to be reposted
    return $result;
}

1;
