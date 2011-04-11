package LJ::Widget::TopEntries;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);

use LJ::TopEntries;

sub need_res {
    return qw( stc/widgets/widget-layout.css stc/widgets/topentries.css );
}

sub render_body {
    my $class = shift;
    my %opts = @_;

    return '' unless LJ::is_enabled('widget_top_entries');

    my $domain = $opts{domain};

    my $top_entries = LJ::TopEntries->new(domain => $domain);

    ## Ontd spotlights widget has its own design
    return $class->render_ontd_homepage($top_entries) 
        if $domain eq 'hmp_ontd' or not $domain; # hmp_ontd is default

    return $class->render_anythingdisney($top_entries)
        if $domain eq 'anythingdisney';

    ## TODO: Cache on 5 minutes.
    ##      !!! use lang_id in cache key.

    ## Default layout
    my $ret = qq|
        <div class="w-topentries">
            <div class="w-head">
                <h2><span class="w-head-in"><a href="$LJ::SITEROOT/browse">| . $class->ml('widget.topentries.spotlight.title') . qq|</a></span></h2>
                <i class="w-head-corner"></i></div><div class="w-content"><ul class="b-posts">|;

    my $classname = 'event';
    foreach my $post ($top_entries->get_featured_posts()) {
        ##
        my $comments = qq|<span class="i-posts-comments"><a href="$post->{comments_url}">|
                            . BML::ml('widget.topentries.comments', { count => $post->{comments} }) .
                            "</a></span>";
        ##
        my $subj = $post->{subj} ne ''
                    ? $post->{subj}
                    : $class->ml('widget.officialjournals.nosubject');

        ## period of time in well readable format.
        my $secondsago = time() - $post->{logtime};
        my $posttime = LJ::TimeUtil->ago_text($secondsago);

        ## Spotlight row
        $ret .= qq|
            <li class="$classname">
                <dl>
                    <dt><img src="$post->{userpic}" /></dt>
                    <dd>
                        <h3 class="b-posts-head"><a href="$post->{url}">$subj</a></h3>| .
                        ## add row with Vertical only if it's defined,
                        ## add tags only if ther are as well as Vertical's name and uri.
                        ($post->{vertical_uri} && $post->{vertical_name}
                            ? (qq|<p class="b-posts-vertical"><a href="$post->{vertical_uri}">$post->{vertical_name}</a>| . ($post->{tags} ? ": $post->{tags}" : "") . "</p>")
                            : ''
                        ) . qq!
                        <p class="b-posts-data">$posttime | $comments</p>
                    </dd>
                </dl>
            </li>!;

        ## switch classname
        $classname = $classname eq 'even' ? 'odd' : 'even';
    }

    $ret .= '</ul></div></div>';

    return $ret;


}

sub render_ontd_homepage {
    my $class       = shift;
    my $top_entries = shift;

    my $ret = '<div class="w-topentries w-ontd"><div class="w-head"><h2><span class="w-head-in"><a href="http://community.livejournal.com/ohnotheydidnt/">'.$class->ml('widget.topentries.title').'</a></span></h2><i class="w-head-corner"></i></div><div class="w-content"><ul class="b-posts">';

    my $classname = 'event';
    foreach my $post ($top_entries->get_featured_posts()) {
        ##
        my $comments = qq|,</span> <span class="i-posts-comments"><a href="$post->{comments_url}">|
                            . BML::ml('widget.topentries.comments', { count => $post->{comments} }) .
                            "</a></span>"; 

        ## 
        my $subj = $post->{subj} ne '' 
                    ? $post->{subj} 
                    : $class->ml('widget.officialjournals.nosubject');

        ## period of time in well readable format.
        my $secondsago = time() - $post->{logtime};
        my $posttime = LJ::TimeUtil->ago_text($secondsago);

        ## Spotlight row
        $ret .= qq(<li class="$classname"><dl><dt><img src="$post->{userpic}" /></dt><dd><h3 class="b-posts-head"><a href="$post->{url}">$subj</a></h3><p class="b-posts-data"><span class="i-post-time">$posttime | </span><span class="i-posts-user">$post->{poster}$comments</p></dd></dl></li>);
        
        ## switch classname
        $classname = $classname eq 'even' ? 'odd' : 'even';
    }

    $ret .= '</ul></div></div>';

    return $ret;
}

sub render_anythingdisney {
    my $class       = shift;
    my $top_entries = shift;

    my $ret = '<div class="w-topentries w-ontd"><div class="w-head"><h2><span class="w-head-in"><a href="http://community.livejournal.com/ohnotheydidnt/">'.$class->ml('widget.topentries.title').'</a></span></h2><i class="w-head-corner"></i></div><div class="w-content"><ul class="b-posts">';

    foreach my $post ($top_entries->get_featured_posts()) {
        ##
        my $comments = qq|,</span> <span class="i-posts-comments"><a href="$post->{comments_url}">|
                            . BML::ml('widget.topentries.comments', { count => $post->{comments} }) .
                            "</a></span>"; 

        ## 
        my $subj = $post->{subj} ne '' 
                    ? $post->{subj} 
                    : $class->ml('widget.officialjournals.nosubject');

        ## Spotlight row
        $ret .= qq(<li><dl><dd><h3 class="b-posts-head"><a href="$post->{url}">$subj</a></h3><p class="b-posts-data"><span class="i-posts-user">$post->{poster}$comments</p></dd></dl></li>);
    }

    $ret .= '</ul></div></div>';

    return $ret;
}

1;
