package LJ::NotificationMethod::Email;

use strict;
use Carp qw/ croak /;
use base 'LJ::NotificationMethod';
require "$ENV{LJHOME}/cgi-bin/weblib.pl";

sub can_digest { 1 };

# takes a $u
sub new {
    my $class = shift;

    croak "no args passed"
        unless @_;

    my $u = shift;
    croak "invalid user object passed"
        unless LJ::isu($u);

    my $self = { u => $u };

    return bless $self, $class;
}

sub title { 'Email' }

sub new_from_subscription {
    my $class = shift;
    my $subs = shift;

    return $class->new($subs->owner);
}

sub u {
    my $self = shift;
    croak "'u' is an object method"
        unless ref $self eq __PACKAGE__;

    if (my $u = shift) {
        croak "invalid 'u' passed to setter"
            unless LJ::isu($u);

        $self->{u} = $u;
    }
    croak "superfluous extra parameters"
        if @_;

    return $self->{u};
}

# send emails for events passed in
sub notify {
    my $self = shift;
    croak "'notify' is an object method"
        unless ref $self eq __PACKAGE__;

    my $u = $self->u;

    my @events = @_;
    croak "'notify' requires one or more events"
        unless @events;

    foreach my $ev (@events) {
        croak "invalid event passed" unless ref $ev;

        my $footer = "\n\n--\n$LJ::SITENAME Team\n$LJ::SITEROOT";
        $footer .= LJ::run_hook("esn_email_footer");
        $footer .= "\n\nIf you prefer not to get these updates, you can change your preferences at $LJ::SITEROOT/manage/subscriptions/";

        $footer .= "\n\nSCHWARTZ ID: " . $self->{_sch_jobid}
            if $LJ::DEBUG{'esn_notif_include_sch_ids'} && $self->{_sch_jobid};

        my $plain_body = $ev->as_email_string($u);
        $plain_body .= $footer;

        if ($LJ::_T_EMAIL_NOTIFICATION) {
            $LJ::_T_EMAIL_NOTIFICATION->($u, $plain_body);
         } elsif ($u->{opt_htmlemail} eq 'N') {
            LJ::send_mail({
                to       => $u->{email},
                from     => $LJ::BOGUS_EMAIL,
                fromname => scalar($ev->as_email_from_name($u)),
                wrap     => 1,
                charset  => 'utf-8',
                subject  => scalar($ev->as_email_subject($u)),
                headers  => scalar($ev->as_email_headers($u)),
                body     => $plain_body,
            }) or die "unable to send notification email";
         } else {
            my $html_body = $ev->as_email_html($u);
            $html_body =~ s/\n/\n<br\/>/g unless $html_body =~ m!<br!i;

            my $html_footer = LJ::auto_linkify($footer);
            $html_footer =~ s/\n/\n<br\/>/g;

            # convert newlines in HTML mail
            $html_body =~ s/\n/\n<br\/>/g unless $html_body =~ m!<br!i;
            $html_body .= $html_footer;

            LJ::send_mail({
                to       => $u->{email},
                from     => $LJ::BOGUS_EMAIL,
                fromname => scalar($ev->as_email_from_name($u)),
                wrap     => 1,
                charset  => 'utf-8',
                subject  => scalar($ev->as_email_subject($u)),
                headers  => scalar($ev->as_email_headers($u)),
                html     => $html_body,
                body     => $plain_body,
            }) or die "unable to send notification email";
        }
    }

    return 1;
}

sub configured {
    my $class = shift;

    # FIXME: should probably have more checks
    return $LJ::BOGUS_EMAIL && $LJ::SITENAMESHORT ? 1 : 0;
}

sub configured_for_user {
    my $class = shift;
    my $u = shift;

    return length $u->{email} ? 1 : 0;
}

1;
