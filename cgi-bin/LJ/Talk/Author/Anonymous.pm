package LJ::Talk::Author::Anonymous;
use strict;

use base qw(LJ::Talk::Author);

sub display_params {
    my ($class, $opts) = @_;

    my $remote = LJ::get_remote();
    my $form = $opts->{'form'};

    my $whocheck;
    $whocheck = 1 if $form->{'usertype'} eq 'anonymous';
    $whocheck = 1 if ( !$form->{'usertype'} && !$remote );

    return {
        'whocheck_anonymous' => $whocheck,
    };
}

sub want_user_input {
    my ($class, $usertype) = @_;
    return $usertype eq 'anonymous';
}

sub handle_user_input {
    # we don't care; the poster is anonymous, which means "undef" as
    # the user posting

    return;
}

1;
