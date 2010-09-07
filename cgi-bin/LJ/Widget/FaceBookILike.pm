package LJ::Widget::FaceBookILike;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);

sub need_res {
    return qw( );
}

sub render_body {
    my $class = shift;
    my %opts = @_;

    my $entry_url = LJ::eurl($opts{journal}->journal_base);
    my $width = $opts{width} || 450;
    my $height = $opts{height} || 80;
    my $color = $opts{color} || "light";

    my $ret = qq|<iframe src="http://www.facebook.com/plugins/like.php?href=$entry_url&amp;layout=standard&amp;show_faces=true&amp;width=$width&amp;action=like&amp;colorscheme=$color&amp;height=$height" scrolling="no" frameborder="0" style="border:none; overflow:hidden; width:${width}px; height:${height}px;" allowTransparency="true"></iframe>|;

    return $ret;


}

1;
