package LJ::Widget::TopEntries;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);

use LJ::TopEntries;

sub render_body {
    my $class = shift;
    my %opts = @_;

    return '' unless LJ::is_enabled('widget_top_entries');

    my $journal = $opts{'journal'};
    my $remote = LJ::get_remote();

    my $top_entries = LJ::TopEntries->new(journal => $journal);

    my $ret = '';
    $ret .= <<EOT;
<table>
<tr><td>Featured posts</td><td>Browse all</td></tr>
EOT

    foreach my $post ($top_entries->get_featured_posts()) {

    my $comments = $post->{comments} ? "$post->{comments} comment(s)<br />" : '';

    $ret .= <<EOT;
<tr><td colspan='2'>
<table>
<tr><td><img src=\"$post->{userpic}\" /></td><td>$post->{subj}<br />$comments posted by $post->{poster}</td></tr>
</table>
</td></tr>
EOT
    }

    $ret .= <<EOT;
</table>
EOT

    return $ret;
}

1;
