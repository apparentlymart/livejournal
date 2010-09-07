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

#use Data::Dumper;
#warn Dumper \%opts;

#    return '';
#    return '' unless LJ::is_enabled('widget_fb_i_like');

=head
    my $entry = LJ::Entry->new($journalu->{'userid'}, ditemid => $this->{'itemid'});
    return $null_link unless $entry->security eq 'public';
=cut
    my $entry_url = LJ::eurl($opts{journal}->journal_base);

    my $ret = qq|<iframe src="http://www.facebook.com/plugins/like.php?href=$entry_url&amp;layout=standard&amp;show_faces=true&amp;width=450&amp;action=like&amp;colorscheme=light&amp;height=80" scrolling="no" frameborder="0" style="border:none; overflow:hidden; width:450px; height:80px;" allowTransparency="true"></iframe>|;

    return $ret;


}

1;
