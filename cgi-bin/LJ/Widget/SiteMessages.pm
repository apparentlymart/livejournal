package LJ::Widget::SiteMessages;

use strict;
use warnings;

use base qw(LJ::Widget);
use Carp qw(croak);
use Class::Autouse qw( LJ::SiteMessages );

sub need_res {
    return qw( stc/widgets/sitemessages.css );
}

sub _format_one_message {
    my ($class, $message, $opts ) = @_;
    my $lang;
    my $remote = LJ::get_remote();

    if ( $remote ) {
        $lang = $remote->prop("browselang"); # exlude s2 context language from opportunities,
        # because S2 journal code executes BML::set_language($lang, \&LJ::Lang::get_text) with its own language
    }
    else {
        $lang = LJ::locale_to_lang($opts->{'locale'});
    }

    my $mid = $message->{'mid'};
    my $text = $class->ml( $class->ml_key("$mid.text"), undef, $lang );

    # override wrong code for journals that being moving
    $text = $message->{text} if $message->{in_move};
    $text .= "<i class='close' lj-sys-message-close='1'></i>";

    ## LJ::CleanHTML::clean* will fix broken HTML and expand 
    ## <lj user> tags and lj-sys-message-close attributes
    LJ::CleanHTML::clean_event(\$text, { 'lj_sys_message_id' => $mid });

    my $is_office = LJ::SiteMessages->has_mask('OfficeOnly', $message->{accounts}) ? '<b>[Only for office]</b> ' : '';

    if ($remote && LJ::SiteMessages->has_mask('NewPhotohosting', $message->{accounts}))  {
        my $url = $remote->journal_base . "/pics/new_photo_service";
        $text = "<a href=$url>$text</a>"
    }

    return
        "<p class='b-message b-message-suggestion b-message-system'>" .
        "<span class='b-message-wrap'>" .
        "<img width='16' height='14' alt='' src='$LJ::IMGPREFIX/message-system-alert.gif?v=9067' />" .
        $is_office . $text .
        "</span></p>";
}

sub render_body {
    my $class = shift;
    my %opts = @_;
    my $ret;

    if ( $opts{all} ) {
        foreach my $message (LJ::SiteMessages->get_messages) {
            $ret .= $class->_format_one_message($message, \%opts);
        }
    }
    else {
        my $message = LJ::SiteMessages->get_open_message($opts{journal});

        ## quick hack for just one message
        ## can be removed after r92.
        eval {
            my $uri = LJ::Request->uri;
            ## show this message only on /update.bml page
            $message = '' if $message and $message->{mid} eq 88 and $uri !~ m|/update.bml|;
        };

        if ($message) {
            $ret .= $class->_format_one_message($message, \%opts);
        }
    }

    return $ret;
}

sub should_render {
    my ( $class, %opts ) = @_;

    # always show at admin pages
    return 1 if $opts{all};
    return LJ::SiteMessages->get_open_message($opts{journal}) ? 1 : 0;
}

1;

