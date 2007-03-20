package LJ::Widget::SiteMessages;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);
use Class::Autouse qw( LJ::SiteMessages );

sub need_res { }

sub render_body {
    my $class = shift;
    my %opts = @_;
    my $ret;

    my @messages = LJ::SiteMessages->get_messages;

    $ret .= "<h2>" . $class->ml('widget.sitemessages.title') . "</h2>";
    $ret .= "<ul>";
    foreach my $message (@messages) {
        $ret .= "<li>" . $class->ml($class->ml_key($message->{mid})) . "</li>";
    }
    $ret .= "</ul>";

    return $ret;
}

sub should_render {
    my $class = shift;

    my @messages = LJ::SiteMessages->get_messages;

    return 1 if @messages;
    return 0;
}

1;
