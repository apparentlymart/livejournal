package LJ::User::UserlogRecord::MassPrivacyChange;
use strict;
use warnings;

use base qw( LJ::User::UserlogRecord );

sub action {'mass_privacy_change'}

sub translate_create_data {
    my ( $class, %data ) = @_;

    $data{'extra'} = {
        's_security' => delete $data{'s_security'},
        'e_security' => delete $data{'e_security'},
        's_unixtime' => delete $data{'s_unixtime'},
        'e_unixtime' => delete $data{'e_unixtime'},
    };

    return %data;
}

sub description {
    my ($self) = @_;

    my $extra      = $self->extra_unpacked;
    my $s_security = $extra->{'s_security'};
    my $e_security = $extra->{'e_security'};

    # TODO: parse out e_unixtime and s_unixtime and display?
    # see: htdocs/editprivacy.bml, LJ::MassPrivacy
    return "Entry privacy updated (from $s_security to $e_security)";
}

1;
