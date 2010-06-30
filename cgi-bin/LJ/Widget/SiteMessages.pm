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
            $ret .= "<p class='b-message b-message-suggestion b-message-system'><span class='b-message-wrap'><img width='16' height='14' alt='' src='$LJ::IMGPREFIX/message-system-alert.gif' />";   
            my $text = $class->ml($ml_key);
			LJ::CleanHTML::clean_subject(\$text);
			$ret .= $text;
            $ret .= "<i class=\"close\" onclick=\"LiveJournal.closeSiteMessage(this, event, '$message->{mid}')\"></i></span></p>";
        }
    # -- same as below -- } elsif ($opts{substitude}) {
    } else {
        my $message = LJ::SiteMessages->get_open_message;
		### ATTENTION!
		# If you want to change 'LJ::CleanHTML::clean_subject(\$text);' line, make sure you test the following message body:
		# News in <lj user="news/>
		# -- note the missing attribute trailing quote
		# Before introducing the HTML-cleaning, ALL pages on site were FULLY BROKEN by this type of the message. The reason 
		# is that the head of each page contains the most recent site message; so form for managing the is broken - you will not be able to correct
		# the mistake. Again: easy mistyping and you cannot correct your mistake.
		# The solution is clean HTML using the rules for subjects of entries

        if ($message) {
            $ret .= "<p class='b-message b-message-suggestion b-message-system'><span class='b-message-wrap'><img width='16' height='14' alt='' src='$LJ::IMGPREFIX/message-system-alert.gif' />";
            my $ml_key = $class->ml_key("$message->{mid}.text");
            my $text = $class->ml($ml_key);
			LJ::CleanHTML::clean_subject(\$text);
			$ret .= $text;
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
