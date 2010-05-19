package LJ::Widget::TopEntries;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);

use LJ::TopEntries;

sub need_res {
    return qw( js/widgets/widget-layout.css stc/widgets/topentries.css );
}

sub render_body {
    my $class = shift;
    my %opts = @_;

    return '' unless LJ::is_enabled('widget_top_entries');

    my $journal = $opts{'journal'};
    my $remote = LJ::get_remote();

    my $top_entries = LJ::TopEntries->new(journal => $journal);

    my $ret = '';

    $ret .= '<div class="w-topentries"><div class="w-head"><h2><span class="w-head-in">'.$class->ml('widget.topentries.title').'</span></h2><i class="w-head-corner"></i></div><div class="w-content"><ul class="b-posts">';

    my $counter = 1;
    my $classname = '';

    foreach my $post ($top_entries->get_featured_posts()) {
        my $comments = $post->{comments} ? '<p class="b-posts-comments">'.$post->{comments}.' comments</p>' : '';
        my $subj = ($post->{subj} ne '') ? $post->{subj} : $class->ml('widget.officialjournals.nosubject');
        if ($counter % 2) {$classname = 'odd';} else {$classname = 'even';}
        $ret .= '<li class="'.$classname.'"><dl><dt><img src="'.$post->{userpic}.'" /></dt><dd><h3 class="b-posts-head"><a href="'.$post->{url}.'">'.$subj.'</a></h3>'.$comments.'<p class="b-posts-user">'.$class->ml('widget.topentries.postedby').' '.$post->{poster}.'</p></dd></dl></li>';
        $counter = $counter + 1;
    }

    $ret .= '</ul><p class="b-more">'.$class->ml('widget.topentries.morein').' <a href="http://community.livejournal.com/ohnotheydidnt/">ONTD</a></p></div></div>';

    return $ret;
}

1;
