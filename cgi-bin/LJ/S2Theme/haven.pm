package LJ::S2Theme::haven;
use strict;

use base qw(LJ::S2Theme);

sub layouts { ( "2l" => "left", "2r" => "right" ) }
sub layout_prop { "sidebar_position" }
sub cats { qw( clean modern ) }
sub designer { "Jesse Proulx" }
sub linklist_support_tab { "Sidebar" }

sub display_option_props {
    my $self = shift;
    my @props = qw( show_entry_userpic );
    return $self->_append_props("display_option_props", @props);
}

sub navigation_box_props {
    my $self = shift;
    my @props = qw( nav_bgcolor nav_fgcolor );
    return $self->_append_props("navigation_box_props", @props);
}

sub text_props {
    my $self = shift;
    my @props = qw( page_fgcolor );
    return $self->_append_props("text_props", @props);
}

sub title_box_props {
    my $self = shift;
    my @props = qw( title_bgcolor title_fgcolor title_border );
    return $self->_append_props("title_box_props", @props);
}

sub tabs_and_headers_props {
    my $self = shift;
    my @props = qw( tabs_bgcolor tabs_fgcolor );
    return $self->_append_props("tabs_and_headers_props", @props);
}

sub sidebar_props {
    my $self = shift;
    my @props = qw(
        sidebar_box_bgcolor sidebar_box_fgcolor sidebar_box_title_bgcolor sidebar_box_title_fgcolor
        sidebar_box_border sidebar_font sidebar_font_fallback
    );
    return $self->_append_props("sidebar_props", @props);
}

sub entry_props {
    my $self = shift;
    my @props = qw(
        content_bgcolor content_fgcolor content_border content_font content_font_fallback
        text_meta_music text_meta_mood text_meta_location text_meta_groups
    );
    return $self->_append_props("entry_props", @props);
}

sub comment_props {
    my $self = shift;
    my @props = qw(
        comment_bar_one_bgcolor comment_bar_one_fgcolor comment_bar_two_bgcolor comment_bar_two_fgcolor comment_bar_screened_bgcolor
        comment_bar_screened_fgcolor text_post_comment text_read_comments text_post_comment_friends text_read_comments_friends 
    );
    return $self->_append_props("comment_props", @props);
}

sub hotspot_area_props {
    my $self = shift;
    my @props = qw( accent_bgcolor accent_fgcolor );
    return $self->_append_props("hotspot_area_props", @props);
}

sub setup_props {
    my $self = shift;
    my @props = qw( sidebar_width sidebar_blurb );
    return $self->_append_props("setup_props", @props);
}

sub ordering_props {
    my $self = shift;
    my @props = qw( sidebar_position_one sidebar_position_two sidebar_position_three sidebar_position_four );
    return $self->_append_props("ordering_props", @props);
}


### Themes ###

package LJ::S2Theme::haven::blueanalogous;
use base qw(LJ::S2Theme::haven);
sub cats { qw( ) }

package LJ::S2Theme::haven::bluecomplementary;
use base qw(LJ::S2Theme::haven);
sub cats { qw( ) }

package LJ::S2Theme::haven::bluedouble_complementary;
use base qw(LJ::S2Theme::haven);
sub cats { qw( ) }

package LJ::S2Theme::haven::bluemonochromatic;
use base qw(LJ::S2Theme::haven);
sub cats { qw( ) }

package LJ::S2Theme::haven::bluesplit_complementary;
use base qw(LJ::S2Theme::haven);
sub cats { qw( ) }

package LJ::S2Theme::haven::bluetetradic;
use base qw(LJ::S2Theme::haven);
sub cats { qw( ) }

package LJ::S2Theme::haven::greenanalogous;
use base qw(LJ::S2Theme::haven);
sub cats { qw( ) }

package LJ::S2Theme::haven::greencomplementary;
use base qw(LJ::S2Theme::haven);
sub cats { qw( ) }

package LJ::S2Theme::haven::greendouble_complementary;
use base qw(LJ::S2Theme::haven);
sub cats { qw( ) }

package LJ::S2Theme::haven::greenmonochromatic;
use base qw(LJ::S2Theme::haven);
sub cats { qw( ) }

package LJ::S2Theme::haven::greensplit_complementary;
use base qw(LJ::S2Theme::haven);
sub cats { qw( ) }

package LJ::S2Theme::haven::greentetradic;
use base qw(LJ::S2Theme::haven);
sub cats { qw( ) }

package LJ::S2Theme::haven::greentriadic;
use base qw(LJ::S2Theme::haven);
sub cats { qw( ) }

package LJ::S2Theme::haven::indigoanalogous;
use base qw(LJ::S2Theme::haven);
sub cats { qw( ) }

package LJ::S2Theme::haven::indigoblue;
use base qw(LJ::S2Theme::haven);
sub cats { qw( ) }

package LJ::S2Theme::haven::indigocomplementary;
use base qw(LJ::S2Theme::haven);
sub cats { qw( ) }

package LJ::S2Theme::haven::indigodouble_complementary;
use base qw(LJ::S2Theme::haven);
sub cats { qw( ) }

package LJ::S2Theme::haven::indigomonochromatic;
use base qw(LJ::S2Theme::haven);
sub cats { qw( ) }

package LJ::S2Theme::haven::indigosplit_complementary;
use base qw(LJ::S2Theme::haven);
sub cats { qw( ) }

package LJ::S2Theme::haven::indigotetradic;
use base qw(LJ::S2Theme::haven);
sub cats { qw( ) }

package LJ::S2Theme::haven::indigotriadic;
use base qw(LJ::S2Theme::haven);
sub cats { qw( ) }

package LJ::S2Theme::haven::orangeanalogous;
use base qw(LJ::S2Theme::haven);
sub cats { qw( ) }

package LJ::S2Theme::haven::orangecomplementary;
use base qw(LJ::S2Theme::haven);
sub cats { qw( ) }

package LJ::S2Theme::haven::orangedouble_complementary;
use base qw(LJ::S2Theme::haven);
sub cats { qw( ) }

package LJ::S2Theme::haven::orangemonochromatic;
use base qw(LJ::S2Theme::haven);
sub cats { qw( ) }

package LJ::S2Theme::haven::orangesplit_complementary;
use base qw(LJ::S2Theme::haven);
sub cats { qw( ) }

package LJ::S2Theme::haven::orangetetradic;
use base qw(LJ::S2Theme::haven);
sub cats { qw( ) }

package LJ::S2Theme::haven::orangetriadic;
use base qw(LJ::S2Theme::haven);
sub cats { qw( ) }

package LJ::S2Theme::haven::redanalogous;
use base qw(LJ::S2Theme::haven);
sub cats { qw( ) }

package LJ::S2Theme::haven::redcomplementary;
use base qw(LJ::S2Theme::haven);
sub cats { qw( ) }

package LJ::S2Theme::haven::reddouble_complementary;
use base qw(LJ::S2Theme::haven);
sub cats { qw( ) }

package LJ::S2Theme::haven::redmonochromatic;
use base qw(LJ::S2Theme::haven);
sub cats { qw( ) }

package LJ::S2Theme::haven::redsplit_complementary;
use base qw(LJ::S2Theme::haven);
sub cats { qw( ) }

package LJ::S2Theme::haven::redtetradic;
use base qw(LJ::S2Theme::haven);
sub cats { qw( ) }

package LJ::S2Theme::haven::redtriadic;
use base qw(LJ::S2Theme::haven);
sub cats { qw( ) }

package LJ::S2Theme::haven::violetanalogous;
use base qw(LJ::S2Theme::haven);
sub cats { qw( ) }

package LJ::S2Theme::haven::violetcomplementary;
use base qw(LJ::S2Theme::haven);
sub cats { qw( ) }

package LJ::S2Theme::haven::violetdouble_complementary;
use base qw(LJ::S2Theme::haven);
sub cats { qw( ) }

package LJ::S2Theme::haven::violetmonochromatic;
use base qw(LJ::S2Theme::haven);
sub cats { qw( ) }

package LJ::S2Theme::haven::violetsplit_complementary;
use base qw(LJ::S2Theme::haven);
sub cats { qw( ) }

package LJ::S2Theme::haven::violettetradic;
use base qw(LJ::S2Theme::haven);
sub cats { qw( ) }

package LJ::S2Theme::haven::violettriadic;
use base qw(LJ::S2Theme::haven);
sub cats { qw( ) }

package LJ::S2Theme::haven::yellowanalogous;
use base qw(LJ::S2Theme::haven);
sub cats { qw( ) }

package LJ::S2Theme::haven::yellowcomplementary;
use base qw(LJ::S2Theme::haven);
sub cats { qw( ) }

package LJ::S2Theme::haven::yellowdouble_complementary;
use base qw(LJ::S2Theme::haven);
sub cats { qw( ) }

package LJ::S2Theme::haven::yellowmonochromatic;
use base qw(LJ::S2Theme::haven);
sub cats { qw( ) }

package LJ::S2Theme::haven::yellowsplit_complementary;
use base qw(LJ::S2Theme::haven);
sub cats { qw( ) }

package LJ::S2Theme::haven::yellowtetradic;
use base qw(LJ::S2Theme::haven);
sub cats { qw( ) }

package LJ::S2Theme::haven::yellowtriadic;
use base qw(LJ::S2Theme::haven);
sub cats { qw( ) }

1;
