package LJ::S2Theme::punquin;
use strict;

use base qw(LJ::S2Theme);

sub layouts { ( "2lnh" => "left", "2rnh" => "right" ) }
sub layout_prop { "sidebar_position" }
sub cats { qw( clean cool ) }
sub designer { "punquin" }

sub display_option_props {
    my $self = shift;
    my @props = qw( show_recent_userpic );
    return $self->_append_props("display_option_props", @props);
}

sub text_props {
    my $self = shift;
    my @props = qw( main_fgcolor link_color vlink_color alink_color );
    return $self->_append_props("text_props", @props);
}

sub entry_props {
    my $self = shift;
    my @props = qw( subject_color title_color border_color border_color_entries date_format time_format );
    return $self->_append_props("entry_props", @props);
}

sub comment_props {
    my $self = shift;
    my @props = qw(
        comment_bar_one_bgcolor comment_bar_two_fgcolor comment_bar_two_bgcolor comment_bar_one_fgcolor comment_bar_screened_bgcolor
        comment_bar_screened_fgcolor text_post_comment text_read_comments text_post_comment_friends text_read_comments_friends
        text_left_comments text_btwn_comments text_right_comments datetime_comments_format
    );
    return $self->_append_props("comment_props", @props);
}


### Themes ###
1;
