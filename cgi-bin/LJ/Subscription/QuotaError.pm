package LJ::Subscription::QuotaError;

use strict;
use Carp qw(confess);

sub new {
    my ($class, $u) = @_;
    return bless({
        'u' => $u,
    }, $class);
}

sub user {
    my ($self) = @_;
    return $self->{'u'};
}

sub as_string { confess "unspecified quota error"; }

1;

package LJ::Subscription::QuotaError::Active;

use base 'LJ::Subscription::QuotaError';

sub as_string {
    my ($self) = @_;
    my $u = $self->user;

    my $mlstring = LJ::run_hook('esn_quota_error', $u) ||
        LJ::Lang::ml('esn.error.quota', {
            'quota' => LJ::get_cap($u, 'subscriptions'),
            'aopts' => qq{ href="$LJ::SITEROOT/manage/settings/?cat=notifications"},
        });
}

1;

package LJ::Subscription::QuotaError::Total;

use base 'LJ::Subscription::QuotaError';

sub as_string {
    my ($self) = @_;
    my $u = $self->user;

    my $mlstring = LJ::Lang::ml('esn.error.quota_total', {
        'quota' => LJ::get_cap($u, 'subscriptions_total'),
        'aopts' => qq{ href="$LJ::SITEROOT/manage/settings/?cat=notifications"},
    });
}

1;
