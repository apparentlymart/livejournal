package LJ::Widget::Browse;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);

use vars qw(%GET %POST $headextra @errors @warnings);

#sub need_res { qw( stc/widgets/browse.css stc/pagemodules.css ) }

sub _build_tree {
    my ($parent, $level, $test_uri, $vertical, @categories) = @_;
    my @tree = ();

    foreach my $c
        (grep { (!$parent && !$_->parent) || ($_->parent == $parent) } grep { $_ } @categories) {
        #(grep { $_->parent == $parent } @categories) {
            my $c_uri = $c->uri;

            my $is_current = ($test_uri =~ m/^\Q$c_uri\E/);

            ++$level;
            push @tree,
                {
                    name            => $c->display_name(),
                    title           => $c->title_html(),
                    url             => $c->url(),
                    summary         => LJ::Widget::CategorySummary->render( category => $c ),
                    level           => $level,
                    is_expanded     => $is_current,
                    is_current      => $is_current,
                    "level$level"   => [ _build_tree($c, $level, $test_uri, $vertical, @categories) ],
                };
            --$level;
        }
    return @tree;
}

sub _get_spotlight_communities {    # Load communities saved by spotlight admin
    my @comms = ();

    my $remote = LJ::get_remote();

    my ($normal_rows, $sponsored_rows, $promoted_rows, $partner_rows) = map {
        [ LJ::JournalSpotlight->get_spotlights(
            limit => 6,
            filter  => $_,
            user => $remote ) ]
        } qw(normal sponsored promoted partner);

    my $show_sponsored = LJ::run_hook('should_see_special_content', $remote);
    my $show_promoted = LJ::run_hook('should_see_special_content', $remote);

    my $promoted_row_count = @$promoted_rows;
    my $sponsored_row_count = @$sponsored_rows;
    my $partner_row_count = @$partner_rows;

    my $showing_normal = @$normal_rows;
    my $showing_sponsored = $sponsored_row_count && $show_sponsored;
    my $showing_promoted = $promoted_row_count && $show_promoted;
    my $showing_partner = $partner_row_count && $show_sponsored;

    my @rows = ();

    if ($showing_normal || $showing_sponsored || $showing_promoted || $showing_partner) {
        push @rows, @$normal_rows       if $showing_normal;
        push @rows, @$promoted_rows     if $showing_promoted;
        push @rows, @$sponsored_rows    if $showing_sponsored;
    }

    push @rows, @$partner_rows if $showing_partner;

    my $us = LJ::load_userids(map { $_->{userid} } @rows);

    foreach my $row (@rows) {
        my $u = $us->{$row->{userid}};
        next unless $u;
        push @comms, $u;
    }
    return @comms;
}

sub render_body {
    my $class = shift;
    my %opts = @_;

    return $class->render_body_old(%opts) unless exists $opts{browse};

    my ($title, $windowtitle, $remote, $uri, $page, $post_page, $view) = @opts{qw(title windowtitle remote uri page post_page view)};

    my $template = LJ::HTML::Template->new(
        { use_expr => 1 }, # force HTML::Template::Pro with Expr support
        filename => "$ENV{'LJHOME'}/templates/Browse/index.tmpl",
        die_on_bad_params => 0,
        strict => 0,
    ) or die "Can't open template: $!";

    my $vertical = LJ::Vertical->load_by_url($uri);
    $view = "communities" unless $vertical;

    $$windowtitle = $vertical ? $vertical->name : $class->ml('widget.browse.windowtitle');

    my $cat = LJ::Browse->load_by_url($uri); # Currently selected category

    my @categories = sort { lc $a->display_name cmp lc $b->display_name } LJ::Browse->load_all($vertical);

    my $test_uri = $uri;
    $test_uri =~ s/^\/(browse|vertical)//;
    $test_uri =~ s/\/$//;

    my @tmpl_categories = _build_tree(undef, 0, $test_uri, $vertical, @categories);

    # Spotlight categories:
    #   if it found, move it to the top, add 'suggest' link to this list and
    #   expand list of subcategories by default.

    my $i = 0;
    foreach my $c (@tmpl_categories) {
        if ($c->{name} eq 'Spotlight') {
            my @spotlight = splice(@tmpl_categories, $i, 1);

            # Count root as spotlight category
            if (!$cat && $spotlight[0]->{level1} && $spotlight[0]->{level1}->[0]) {
                $spotlight[0]->{level1}->[0]->{is_current} = 1;
            }

            push @{$spotlight[0]->{level1}},
                {
                    name            => 'Suggest a Spotlight',
                    title           => 'Suggest a Spotlight',
                    url             => "$LJ::SITEROOT/misc/suggest_spotlight.bml",
                    summary         => 'Suggest a Spotlight',
                    level           => 1,
                    is_expanded     => 1,
                    is_current      => 0,
                    "level2"        => 0,
                };
            $spotlight[0]->{is_expanded} = 1;
            unshift(@tmpl_categories, $spotlight[0]);
            last;
        }
        $i++;
    }

    my ($ad, $nav_line) = 2 x '';

    my @tmpl_communities = ();
    my @tmpl_posts = ();

    my $page_size = 6;
    my $post_page_size = 10;

    my $count = 0;
    my $post_count = 0;

    my @comms = ();

    $page ||= 1;
    my $skip = ($page-1) * $page_size;
    my $last = $skip + $page_size;
    $post_page ||= 1;
    my $post_skip = ($post_page-1) * $post_page_size;
    my $post_last = $post_skip + $post_page_size;

    $$title = "$$windowtitle";

    my $search_str = undef;
    if ($opts{'post_vars'}->{'do_search'}) {
        $search_str = $opts{'post_vars'}->{'search_text'};
    } else {
        ($search_str) = $uri =~ m#.*?tag/(.*)#;
        $search_str =~ s#/?\?.*##;
    }

    if ($cat && $vertical) {
        @comms = $cat->communities( is_need_child => 1 );
        $ad = LJ::get_ads({ location => 'bml.explore/vertical', vertical => $vertical->name, ljadwrapper => 1 });
    } elsif ($vertical) {
        @comms = $vertical->get_communities( is_need_child => 1 );
        $ad = LJ::get_ads({ location => 'bml.explore/vertical', vertical => $vertical->name, ljadwrapper => 1 });
    } elsif ($cat) { # we're looking at a lower-level category

        my @cat_title = split(/&gt;/, $cat->title_html());
        shift @cat_title;

        $nav_line = "<a href=\"$LJ::SITEROOT\"><strong>".$class->ml('widget.browse.nav_bar.home')."</strong></a> : " .
                    "<a href=\"$LJ::SITEROOT/browse/\"><strong>".$class->ml('widget.browse.windowtitle')."</strong></a> : " .
                    (pop(@cat_title) || '');

        # show actual communities
        if ($cat->parent) {
            if ($cat->{'pretty_name'} eq 'lj_spotlight_community') {
                # Load communities saved by spotlight admin
                @comms = _get_spotlight_communities();  # Load communities saved by spotlight admin
            } else {
                @comms = $cat->communities;
            }
        }
        $ad = LJ::get_ads({ location => 'bml.explore/vertical', vertical => $cat->display_name, ljadwrapper => 1 });
    } else {
        @comms = _get_spotlight_communities();  # Show spotlight communities by default
        $ad = LJ::get_ads({ location => 'bml.explore/novertical', ljadwrapper => 1 });
    }

    if ($view eq 'communities') {
        foreach my $comm (@comms) {
            next unless LJ::isu($comm);

            # paging
            $count++;
            next if $count <= $skip || $count > $last;

            my $secondsold = $comm->timeupdate ? time() - $comm->timeupdate : undef;
            my $userpic = $comm->userpic ?
                $comm->userpic->imgtag_percentagesize(1) :
                    LJ::run_hook('no_userpic_html', percentage => 1 );

            push @tmpl_communities,
                {
                    featured            => 0,
                    userpic             => $userpic,
                    journal_name        => $comm->ljuser_display(),
                    journal_user        => $comm->{user},
                    journal_base        => $comm->journal_base(),
                    journal_title       => $comm->{'name'} || '',
                    journal_subtitle    => $comm->prop('comm_theme') || '',
                    updated_ago         => LJ::TimeUtil->ago_text($secondsold),
                };
        }
    } else {
        my @posts = LJ::Browse->search_posts ( [ map { $_->{userid} } @comms ], $post_page_size, $search_str );

        foreach my $entry (@posts) {
            next unless $entry;

            next unless 1;## This entry is inappropriate language in the subject or body

            $post_count++;
            next if $post_count <= $post_skip || $post_count > $post_last;

            my $poster = $entry->poster;
            my $userpic = $entry->userpic;
            my @tags = $entry->tags;
            push @tmpl_posts, {
                subject         => $entry->subject_text,
                userpic         => $userpic ? $userpic->url : '',
                posted_ago      => LJ::TimeUtil->ago_text($entry->logtime_unix),
                poster          => $poster ? LJ::ljuser($poster) : '?',
                tags            => scalar @tags ? [ map { { tag => $_ } } @tags ] : '',
                mood            => $entry->prop('current_mood') || LJ::mood_name($entry->prop('current_moodid')) || '',
                music           => $entry->prop('current_music'),
                location        => $entry->prop('current_location'),
                post_text       => $entry->event_html,
                url_to_post     => $entry->url,
                comments_count  => $entry->reply_count,
                is_need_more    => bytes::length($entry->event_text) > 800 ? 1 : 0,
            };
        }
    }

    # post paging: first, previouse, next, last pages.
    my ($post_page_first, $post_page_prev, $post_page_next, $post_page_last) = 4 x 0;
    my $post_pages = int($post_count / $post_page_size) + 1;
    $post_page = 1 unless $post_page;
    if($post_page > 1) {
        $post_page_first = 1;
        $post_page_prev = $post_page - 1;
    }

    if ($post_page < $post_pages) {
        $post_page_next = $post_page + 1;
        $post_page_last = $post_pages;
        $post_page_next = $post_page_last if $post_page_next > $post_page_last;
    }

    # paging: first, previouse, next, last pages.
    my ($page_first, $page_prev, $page_next, $page_last) = 4 x 0;
    my $pages = int($count / $page_size) + 1;
    $page = 1 unless $page;
    if($page > 1) {
        $page_first = 1;
        $page_prev = $page - 1;
    }

    if ($page < $pages) {
        $page_next = $page + 1;
        $page_last = $pages;
        $page_next = $page_last if $page_next > $page_last;
    }

    my $args = '';
    ($uri, $args) = split(/\?/, $uri);
    $args =~ s/&?(post_)?page=[^&]*//g;  # cut off page= parameter
    $args =~ s/^&//;

    # make page_* urls
    ($page_first, $page_prev, $page_next, $page_last) = map {
        $_ ? $LJ::SITEROOT . $uri . ($args ? "?$args&page=$_" : "?page=$_") : ''
    } ($page_first, $page_prev, $page_next, $page_last);

    # make post_page_* urls
    ($post_page_first, $post_page_prev, $post_page_next, $post_page_last) = map {
        $_ ? $LJ::SITEROOT . $uri . ($args ? "?$args&post_page=$_" : "?post_page=$_") : ''
    } ($post_page_first, $post_page_prev, $post_page_next, $post_page_last);

    # merge args to uri.
    $uri .= '?' . $args if $args;

    ## Prepare DATA for Featured Communities Widget
    my $comms = undef;
    my @top_comms = ();
    if ($vertical) {
        $comms = $vertical->load_communities( count => $vertical->show_entries, is_random => 1 );
        foreach my $comm (@$comms) {
            my $c = LJ::load_userid($comm->{journalid});
            next unless $c;
            my $userpic = $c->userpic;
            push @top_comms, {
                username        => $c->display_name,
                userpic         => $userpic ? $userpic->url : '',
                community       => $c->user,
                bio             => $c->bio,
            };
        }
    }

    ## Prepare DATA for Featured Posts Widget
    my $posts = undef;
    my @top_posts = ();
    if ($vertical) {
        $posts = $vertical->load_vertical_posts( count => $vertical->show_entries, is_random => 1 );
        foreach my $post (@$posts) {
            my $entry = LJ::Entry->new ($post->{journalid}, jitemid => $post->{jitemid});
            my $userpic = $entry->userpic;
            push @top_posts, {
                subject         => $entry->subject_text,
                userpic         => $userpic ? $userpic->url : '',
                updated_ago     => LJ::TimeUtil->ago_text($entry->logtime_unix),
                comments_count  => $entry->reply_count,
                ljuser          => $entry->journal->ljuser_display,
            };
        }
    }

    $template->param(
        communities             => \@tmpl_communities,
        posts                   => \@tmpl_posts,
        uri                     => $uri,
        page                    => $page,
        pages                   => $pages,
        page_first              => $page_first,
        page_prev               => $page_prev,
        page_next               => $page_next,
        page_last               => $page_last,
        post_page               => $post_page,
        post_pages              => $post_pages,
        post_page_first         => $post_page_first,
        post_page_prev          => $post_page_prev,
        post_page_next          => $post_page_next,
        post_page_last          => $post_page_last,
        title                   => $$title,
        categories              => \@tmpl_categories,
        ad                      => $ad,
        nav_line                => $nav_line,
        popular_interests_widget=> LJ::Widget::PopularInterests->render(),
        add_community_widget    => LJ::Widget::AddCommunity->render(),
        search_widget           => LJ::Widget::Search->render(type => $vertical ? "tags" : "yandex", view => $view),
        top_posts               => \@top_posts,
        top_comms               => \@top_comms,
        view                    => $view,
        poll_of_the_day         => LJ::Widget::PollOfTheDay->render(
                                        vertical_account => $vertical ? $vertical->journal : undef,
                                        vertical_name => $vertical ? $vertical->name : undef
                                    ),
        is_vertical_view        => $vertical ? 1 : 0,
    );

    return $template->output;
}

# Old render for $LJ::SITEROOT/explore/ page.
sub render_body_old {
    my $class = shift;
    my %opts = @_;

    my $u = LJ::isu($opts{user}) ? $opts{user} : LJ::get_remote();
    my $ret;

    $ret .= "<h2>" . $class->ml('widget.browse.title', { sitenameabbrev => $LJ::SITENAMEABBREV }) . "</h2>";
    $ret .= "<div class='browse-content'>";
    $ret .= LJ::Widget::Search->render( stylesheet_override => "stc/widgets/search-interestonly.css", single_search => "interest" );

    $ret .= LJ::Widget::PopularInterests->render;

    $ret .= "<div class='browse-findlinks'>";

    $ret .= "<div class='browse-findby'>";
    $ret .= "<p><strong>" . $class->ml('widget.browse.findusers') . "</strong><br />";
    $ret .= "&raquo; <a href='$LJ::SITEROOT/schools/'>" . $class->ml('widget.browse.findusers.school') . "</a><br />";
    $ret .= "&raquo; <a href='$LJ::SITEROOT/directory.bml'>" . $class->ml('widget.browse.findusers.location') . "</a></p>";
    $ret .= "</div>";

    $ret .= "<div class='browse-directorysearch'>";
    $ret .= "<p><strong>" . $class->ml('widget.browse.directorysearch') . "</strong><br />";
    $ret .= "&raquo; <a href='$LJ::SITEROOT/directorysearch.bml'>" . $class->ml('widget.browse.directorysearch.users') . "</a><br />";
    $ret .= "&raquo; <a href='$LJ::SITEROOT/community/search.bml'>" . $class->ml('widget.browse.directorysearch.communities') . "</a></p>";
    $ret .= "</div>";

    $ret .= "</div>";

    $ret .= "<div style='clear: both;'></div>";
    $ret .= "<div class='browse-extras'>";
    $ret .= "<div class='browse-randomuser'>";
    $ret .= "<img src='$LJ::IMGPREFIX/explore/randomuser.jpg' alt='' />";
    $ret .= "<p><a href='$LJ::SITEROOT/random.bml'><strong>" . $class->ml('widget.browse.extras.random') . "</strong></a><br />";
    $ret .= $class->ml('widget.browse.extras.random.desc') . "</p>";
    $ret .= "</div>";
    $ret .= LJ::run_hook('browse_widget_extras');
    $ret .= "</div>";

    $ret .= "</div>";
    return $ret;
}

1;
