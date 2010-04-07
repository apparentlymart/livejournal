package LJ::Widget::SiteMessages;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);
use Class::Autouse qw( LJ::SiteMessages );

sub need_res {
    return qw( stc/widgets/sitemessages.css );
}

sub render_body {
    my $class = shift;
    my %opts = @_;
    my $ret;

    if ($opts{all}) {
        my @messages = LJ::SiteMessages->get_messages;

        $ret .= "<ul class='nostyle'>";
        foreach my $message (@messages) {
            my $ml_key = $class->ml_key("$message->{mid}.text");
            $ret .= "<li>" . $class->ml($ml_key) . "</li>";
        }
        $ret .= "</ul>";
    # -- same as below -- } elsif ($opts{substitude}) {
    } else {
        my $message = LJ::SiteMessages->get_open_message;

        if ($message) {
            $ret .= "<div id='sm$message->{mid}'>";
            my $ml_key = $class->ml_key("$message->{mid}.text");
            $ret .= $class->ml($ml_key);
            $ret .= "</div>";
        }
    }

    return $ret;
}

sub should_render {
    my $class = shift;

    return LJ::SiteMessages->get_open_message ? 1 : 0;
}

1;
