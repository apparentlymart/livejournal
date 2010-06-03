package LJ::Widget::Browse;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);

use vars qw(%GET %POST $headextra @errors @warnings);

sub need_res { qw( stc/widgets/browse.css stc/pagemodules.css ) }

sub _build_flat_tree {
    my ($parent, $level, $test_uri, $ret_ref, @categories) = @_;
    foreach my $c
        (grep { (!$parent && !$_->parent) || ($_->parent == $parent) } grep { $_ } @categories) {

            push @$ret_ref,
                {
                    name        => $c->display_name(),
                    title       => $c->title_html(),
                    url         => $c->url(),
                    summary     => LJ::Widget::CategorySummary->render( category => $c ),
                    level       => $level,
                    is_expanded => 0,
                    is_current  => ($c->uri eq $test_uri),
                };

            _build_flat_tree($c, $level+1, $test_uri, $ret_ref, @categories);
        }
}

sub render_body {
    my $class = shift;
    my %opts = @_;

    return $class->render_body_old(%opts) unless exists $opts{browse};

    my ($title, $windowtitle, $remote, $uri, $page) = @opts{qw(title windowtitle remote uri page)};

    my $template = LJ::HTML::Template->new(
        { use_expr => 1 }, # force HTML::Template::Pro with Expr support
        filename => "$ENV{'LJHOME'}/templates/Browse/index.tmpl",
        die_on_bad_params => 0,
        strict => 0,
    ) or die "Can't open template: $!";

    $$windowtitle = "Community Directory";  # TODO: multilanguage

    my $cat = LJ::Browse->load_by_url($uri); # Currently selected category

    my @categories = sort { lc $a->display_name cmp lc $b->display_name } LJ::Browse->load_all();

    my $test_uri = $uri;
    $test_uri =~ s/^\/browse//;
    $test_uri =~ s/\/$//;

    my @tmpl_categories = ();
    _build_flat_tree(undef, 0, $test_uri, \@tmpl_categories, @categories);

    my ($ad, $nav_line) = 2 x '';

    my @tmpl_communities = ();

    if ($cat) {
        # we're looking at a lower-level category
        $$windowtitle = $cat->display_name;

        # TODO: multilanguage world 'Home'.
        $nav_line = "<a href=\"$LJ::SITEROOT/browse/\"><strong>Home</strong></a> &gt; " .
            $cat->title_html();

        # show actual communities
        if ($cat->parent) {
            my @comms = $cat->communities();
            foreach my $comm (@comms) {
                next unless LJ::isu($comm);
                my $secondsold = $comm->timeupdate ? time() - $comm->timeupdate : undef;
                my $userpic = $comm->userpic ?
                    $comm->userpic->imgtag_percentagesize(0.5) :
                        LJ::run_hook('no_userpic_html', percentage => 0.5 );

                push @tmpl_communities,
                    {
                        featured            => 0,
                        userpic             => $userpic,
                        journal_name        => $comm->ljuser_display({ bold => 0, head_size => 11 }), 
                        journal_base        => $comm->journal_base(),
                        journal_title       => $comm->prop('journaltitle') || '',
                        journal_subtitle    => $comm->prop('journalsubtitle') || '',
                        updated_ago         => LJ::TimeUtil->ago_text($secondsold),
                    };
            }
        }
        $$title .= " <img src='$LJ::IMGPREFIX/beta.gif' alt='Beta' align='absmiddle'>";
        $ad = LJ::get_ads({ location => 'bml.explore/vertical', vertical => $cat->display_name, ljadwrapper => 1 });
    } else {
        $$title = "$$windowtitle <img src='$LJ::IMGPREFIX/beta.gif' align='absmiddle' alt='Beta' />";
        $ad = LJ::get_ads({ location => 'bml.explore/novertical', ljadwrapper => 1 });
    }

# TODO: paging: first, previouse, next, last pages.

    $template->param(
        communities             => \@tmpl_communities,
        page                    => $page,
        title                   => $$title,
        categories              => \@tmpl_categories,
        ad                      => $ad,
        nav_line                => $nav_line,
        popular_interests_widget=> LJ::Widget::PopularInterests->render(),
        add_community_widget    => LJ::Widget::AddCommunity->render(),
        search_widget           => LJ::Widget::Search->render(
                                    single_search   => 'interest',
                                    int             => 'myint',
                                    type            => 'yandex' ),
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
