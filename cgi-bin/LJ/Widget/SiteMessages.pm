package LJ::Widget::SiteMessages;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);
use Class::Autouse qw( LJ::SiteMessages );

sub need_res {
    return qw( stc/widgets/sitemessages.css );
}

sub _format_one_message {
    my $class = shift;
    my $message = shift;

    my $lang;
    my $remote = LJ::get_remote();
    $lang = $remote->prop("browselang") if $remote; # exlude s2 context language from opportunities,
        # because S2 journal code executes BML::set_language($lang, \&LJ::Lang::get_text) with its own language

    my $mid = $message->{'mid'};
    my $text = $class->ml( $class->ml_key("$mid.text"), undef, $lang );
    $text .= "<i class='close' lj-sys-message-close='1'></i>";
    ## LJ::CleanHTML::clean* will fix broken HTML and expand 
    ## <lj user> tags and lj-sys-message-close attributes
    LJ::CleanHTML::clean_event(\$text, { 'lj_sys_message_id' => $mid });

    my $is_office = LJ::SiteMessages->has_mask('OfficeOnly', $message->{accounts}) ? '<b>[Only for office]</b> ' : '';

    return 
        "<p class='b-message b-message-suggestion b-message-system'>" .
        "<span class='b-message-wrap'>" .
        "<img width='16' height='14' alt='' src='$LJ::IMGPREFIX/message-system-alert.gif' />" .
        $is_office . $text .
        "</span></p>";
}

sub render_body {
    my $class = shift;
    my %opts = @_;
    my $ret;

    if ($opts{all}) {
        foreach my $message (LJ::SiteMessages->get_messages) {
            $ret .= $class->_format_one_message($message);
        }
    } else {
        my $message = LJ::SiteMessages->get_open_message;
        if ($message) {
            $ret .= $class->_format_one_message($message);
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
