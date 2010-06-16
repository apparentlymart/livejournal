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

        
        foreach my $message (@messages) {
            my $ml_key = $class->ml_key("$message->{mid}.text");
            $ret .= "<p class='b-message b-message-suggestion b-message-system'><span><img width='16' height='14' alt='' src='$LJ::IMGPREFIX/message-system-alert.gif' />";   
            $ret .= $class->ml($ml_key);
            $ret .= "</p>";
        }
    # -- same as below -- } elsif ($opts{substitude}) {
    } else {
        my $message = LJ::SiteMessages->get_open_message;

        if ($message) {
            $ret .= "<p class='b-message b-message-suggestion b-message-system'><span><img width='16' height='14' alt='' src='$LJ::IMGPREFIX/message-system-alert.gif' />";
            my $ml_key = $class->ml_key("$message->{mid}.text");
            $ret .= $class->ml($ml_key);
            $ret .= "<i class=\"close\" onclick=\"LiveJournal.closeSiteMessage(this, event, '$message->{mid}')\"></i></span></p>";
        }
    }

    return $ret;
}

sub should_render {
    my $class = shift;
    my %opts = @_;

    return 1 if $opts{all}; # always show at admin pages

    return LJ::SiteMessages->get_open_message ? 1 : 0;
}

1;
