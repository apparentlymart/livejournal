package LJ::Widget::ThemeNav;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);
use Class::Autouse qw( LJ::Customize );

sub ajax { 1 }
sub authas { 1 }
sub need_res { qw( stc/widgets/themenav.css ) }

sub render_body {
    my $class = shift;
    my %opts = @_;

    my $u = $class->get_effective_remote();
    die "Invalid user." unless LJ::isu($u);

    my $theme_chooser_id = defined $opts{theme_chooser_id} ? $opts{theme_chooser_id} : 0;
    my $headextra = $opts{headextra};

    my $remote = LJ::get_remote();
    my $getextra = $u->user ne $remote->user ? "?authas=" . $u->user : "";
    my $getsep = $getextra ? "&" : "?";

    # filter criteria
    my $cat = defined $opts{cat} ? $opts{cat} : "";
    my $layoutid = defined $opts{layoutid} ? $opts{layoutid} : 0;
    my $designer = defined $opts{designer} ? $opts{designer} : "";
    my $filter_available = defined $opts{filter_available} ? $opts{filter_available} : 0;
    my $page = defined $opts{page} ? $opts{page} : 1;

    my $filterarg = $filter_available ? "filter_available=1" : "";

    # we want to have "All" selected if we're filtering by layout or designer
    my $viewing_all = $layoutid || $designer;

    my $theme_chooser = LJ::Widget::ThemeChooser->new( id => $theme_chooser_id );
    $theme_chooser_id = $theme_chooser->{id} unless $theme_chooser_id;
    $$headextra .= $theme_chooser->wrapped_js( page_js_obj => "Customize" ) if $headextra;

    # sort cats by specificed order key, then alphabetical order
    my %cats = LJ::Customize->get_cats;
    my @cats_sorted =
        sort { $cats{$a}->{order} <=> $cats{$b}->{order} }
        sort { lc $cats{$a}->{text} cmp lc $cats{$b}->{text} } keys %cats;

    # pull the main cats out of the full list
    my @main_cats_sorted;
    for (my $i = 0; $i < @cats_sorted; $i++) {
        my $c = $cats_sorted[$i];

        if (defined $cats{$c}->{main}) {
            my $el = splice(@cats_sorted, $i, 1);
            push @main_cats_sorted, $el;
            $i--; # we just removed an element from @cats_sorted
        }
    }

    my $ret;
    $ret .= "<h2 class='widget-header'>" . $class->ml('widget.themenav.title');
    $ret .= $class->start_form;
    $ret .= "<span>" . $class->html_check( name => "filter_available", id => "filter_available", selected => $filter_available );
    $ret .= " <label for='filter_available'>" . $class->ml('widget.themenav.filteravailable') . "</label>";
    $ret .= " " . $class->html_submit( "filter" => $class->ml('widget.themenav.btn.filteravailable'), { id => "filter_btn" }) . "</span>";
    $ret .= $class->end_form;
    $ret .= "</h2>";

    $ret .= "<div class='theme-selector-nav'>";

    $ret .= "<ul class='theme-nav nostyle'>";
    $ret .= $class->print_cat_list(
        user => $u,
        selected_cat => $cat,
        viewing_all => $viewing_all,
        cat_list => \@main_cats_sorted,
        getextra => $getextra,
        filterarg => $filterarg,
    );
    $ret .= "</ul>";

    $ret .= "<div class='theme-nav-separator'><hr /></div>";

    $ret .= "<ul class='theme-nav nostyle'>";
    $ret .= $class->print_cat_list(
        user => $u,
        selected_cat => $cat,
        viewing_all => $viewing_all,
        cat_list => \@cats_sorted,
        getextra => $getextra,
        filterarg => $filterarg,
    );
    $ret .= "</ul>";

    $ret .= "<div class='theme-nav-separator'><hr /></div>";

    $ret .= "<ul class='theme-nav-small nostyle'>";
    $ret .= "<li class='first'><a href='$LJ::SITEROOT/customize/advanced/'>" . $class->ml('widget.themenav.developer') . "</a>";
    $ret .= LJ::run_hook('customize_advanced_area_upsell', $u) . "</li>";
    $ret .= "<li class='last'><a href='$LJ::SITEROOT/customize2/switch_system.bml$getextra'>" . $class->ml('widget.themenav.switchtos1') . "</a></li>";
    $ret .= "</ul>";

    $ret .= "</div>";

    $ret .= $class->html_hidden({ name => "theme_chooser_id", value => $theme_chooser_id, id => "theme_chooser_id" });
    $ret .= $theme_chooser->render(
        cat => $cat,
        layoutid => $layoutid,
        designer => $designer,
        filter_available => $filter_available,
        page => $page,
    );

    return $ret;
}

sub print_cat_list {
    my $class = shift;
    my %opts = @_;

    my $cat_list = $opts{cat_list};

    my %cats = LJ::Customize->get_cats;

    my @special_themes = LJ::S2Theme->load_by_cat("special");
    my $special_themes_exist = 0;
    foreach my $special_theme (@special_themes) {
        my $layout_is_active = LJ::run_hook("layer_is_active", $special_theme->layout_uniq);
        my $theme_is_active = LJ::run_hook("layer_is_active", $special_theme->uniq);

        if ($layout_is_active && $theme_is_active) {
            $special_themes_exist = 1;
            last;
        }
    }

    my @custom_themes = LJ::S2Theme->load_by_user($opts{user});

    my $ret;

    for (my $i = 0; $i < @$cat_list; $i++) {
        my $c = $cat_list->[$i];

        next if $c eq "special" && !$special_themes_exist;
        next if $c eq "custom" && !@custom_themes;

        my $li_class = "";
        $li_class .= " on" if
            ($c eq $opts{selected_cat}) ||
            ($c eq "featured" && !$opts{selected_cat} && !$opts{viewing_all}) ||
            ($c eq "all" && $opts{viewing_all});
        $li_class .= " first" if $i == 0;
        $li_class .= " last" if $i == @$cat_list - 1;
        $li_class =~ s/^\s//; # remove the first space
        $li_class = " class='$li_class'" if $li_class;

        my $arg = "";
        $arg = "cat=$c" unless $c eq "featured";
        if ($arg || $opts{filterarg}) {
            my $allargs = $arg;
            $allargs .= "&" if $arg && $opts{filterarg};
            $allargs .= $opts{filterarg};

            $arg = $opts{getextra} ? "&$allargs" : "?$allargs";
        }

        $ret .= "<li$li_class><a href='$LJ::SITEROOT/customize2/$opts{getextra}$arg' class='theme-nav-cat'>$cats{$c}->{text}</a></li>";
    }

    return $ret;
}

sub handle_post {
    my $class = shift;
    my $post = shift;
    my %opts = @_;

    # get query string and remove filter_available and page from it if they're there
    my $q_string = BML::get_query_string();
    my $filter_available = 0;

    if ($q_string =~ s/&?filter_available=\d//g) {
        $filter_available = 1;
    }
    $q_string =~ s/&?page=\d+//g;
    $q_string =~ s/^&//;

    my $layoutid = $post->{layout_filter};
    if ($layoutid) {
        if ($q_string =~ /&?authas=(\w+)/) {
            $q_string = "authas=$1&layoutid=$layoutid";
        } else {
            $q_string = "layoutid=$layoutid";
        }
    }

    my $url;
    if ($post->{filter_available} || ($layoutid && $filter_available)) {
        $url = $q_string ? "$LJ::SITEROOT/customize2/?$q_string&filter_available=1" : "$LJ::SITEROOT/customize2/?filter_available=1";
        return BML::redirect($url);
    } else {
        $url = $q_string ? "$LJ::SITEROOT/customize2/?$q_string" : "$LJ::SITEROOT/customize2/";
        return BML::redirect($url);
    }

    return;
}

sub js {
    q [
        initWidget: function () {
            var self = this;

            $('filter_btn').style.display = "none";
            DOM.addEventListener($('filter_available'), "click", function (evt) { self.filterThemes(evt, "filter_available", $('filter_available').checked) });

            var filter_links = DOM.getElementsByClassName(document, "theme-nav-cat");

            // add event listeners to all of the category links
            filter_links.forEach(function (filter_link) {
                var evt_listener_added = 0;
                var getArgs = LiveJournal.parseGetArgs(filter_link.href);
                for (var arg in getArgs) {
                    if (!getArgs.hasOwnProperty(arg)) continue;
                    if (arg == "authas" || arg == "filter_available") continue;
                    DOM.addEventListener(filter_link, "click", function (evt) { self.filterThemes(evt, arg, getArgs[arg]) });
                    evt_listener_added = 1;
                    break;
                }

                // if there was no listener added to a link, add it without any args (for the 'featured' category)
                if (!evt_listener_added) {
                    DOM.addEventListener(filter_link, "click", function (evt) { self.filterThemes(evt, "", "") });
                }
            });
        },
        filterThemes: function (evt, key, value) {
            // filtering by availability and page uses the values of the other filters, so do not reset them in that case
            if (key == "filter_available") {
                if (value) {
                    Customize.filter_available = 1;
                } else {
                    Customize.filter_available = 0;
                }

                // need to go back to page 1 if the filter was switched because
                // the current page may no longer have any themes to show on it
                Customize.page = 1;
            } else if (key != "page") {
                Customize.resetFilters();
            }

            // do not do anything with a layoutid of 0
            if (key == "layoutid" && value == 0) {
                Event.stop(evt);
                return;
            }

            if (key == "cat") Customize.cat = value;
            if (key == "layoutid") Customize.layoutid = value;
            if (key == "designer") Customize.designer = value;
            if (key == "page") Customize.page = value;

            this.updateContent({
                cat: Customize.cat,
                layoutid: Customize.layoutid,
                designer: Customize.designer,
                filter_available: Customize.filter_available,
                page: Customize.page,
                theme_chooser_id: $('theme_chooser_id').value
            });

            Event.stop(evt);

            Customize.cursorHourglass(evt);
        },
        onData: function (data) {
            Customize.hideHourglass();
        },
        onRefresh: function (data) {
            this.initWidget();
            Customize.ThemeChooser.initWidget();
        }
    ];
}

1;
