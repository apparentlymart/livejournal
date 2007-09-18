package LJ::Widget::ThemeChooser;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);
use Class::Autouse qw( LJ::S2Theme LJ::Customize );

sub ajax { 1 }
sub authas { 1 }
sub need_res { qw( stc/widgets/themechooser.css ) }

sub render_body {
    my $class = shift;
    my %opts = @_;

    my $u = $class->get_effective_remote();
    die "Invalid user." unless LJ::isu($u);

    my $remote = LJ::get_remote();
    my $getextra = $u->user ne $remote->user ? "?authas=" . $u->user : "";
    my $getsep = $getextra ? "&" : "?";

    # filter criteria
    my $cat = defined $opts{cat} ? $opts{cat} : "";
    my $layoutid = defined $opts{layoutid} ? $opts{layoutid} : 0;
    my $designer = defined $opts{designer} ? $opts{designer} : "";
    my $filter_available = defined $opts{filter_available} ? $opts{filter_available} : 0;
    my $page = defined $opts{page} ? $opts{page} : 1;

    my $filterarg = $filter_available ? "&filter_available=1" : "";

    my $viewing_featured = !$cat && !$layoutid && !$designer;

    my %cats = LJ::Customize->get_cats;
    my $num_per_page = 12;
    my $ret .= "<div class='theme-selector-content pkg'>";

    my @getargs;
    my @themes;
    if ($cat eq "all") {
        push @getargs, "cat=all";
        @themes = LJ::S2Theme->load_all($u);
    } elsif ($cat eq "custom") {
        push @getargs, "cat=custom";
        @themes = LJ::S2Theme->load_by_user($u);
    } elsif ($cat) {
        push @getargs, "cat=$cat";
        @themes = LJ::S2Theme->load_by_cat($cat);
    } elsif ($layoutid) {
        push @getargs, "layoutid=$layoutid";
        @themes = LJ::S2Theme->load_by_layoutid($layoutid, $u);
    } elsif ($designer) {
        $designer = LJ::durl($designer);
        push @getargs, "designer=$designer";
        @themes = LJ::S2Theme->load_by_designer($designer);
    } else { # category is "featured"
        @themes = LJ::S2Theme->load_by_cat("featured");
    }

    if ($filter_available) {
        push @getargs, "filter_available=$filter_available";
        @themes = LJ::S2Theme->filter_available($u, @themes);
    }

    # sort themes with custom at the end, then alphabetically
    @themes =
        sort { $a->is_custom <=> $b->is_custom }
        sort { lc $a->name cmp lc $b->name } @themes;

    LJ::run_hook("modify_theme_list", \@themes, user => $u, cat => $cat);

    # remove any themes from the array that are not defined or whose layout or theme is not active
    for (my $i = 0; $i < @themes; $i++) {
        my $layout_is_active = LJ::run_hook("layer_is_active", $themes[$i]->layout_uniq);
        my $theme_is_active = LJ::run_hook("layer_is_active", $themes[$i]->uniq);

        unless ((defined $themes[$i]) &&
            (!defined $layout_is_active || $layout_is_active) &&
            (!defined $theme_is_active || $theme_is_active)) {

            splice(@themes, $i, 1);
            $i--; # we just removed an element from @themes
        }
    }

    my $current_theme = LJ::Customize->get_current_theme($u);
    my $index_of_first_theme = $num_per_page * ($page - 1);
    my $index_of_last_theme = ($num_per_page * $page) - 1;
    my @themes_this_page = @themes[$index_of_first_theme..$index_of_last_theme];

    $ret .= "<ul class='theme-paging theme-paging-top nostyle'>";
    $ret .= $class->print_paging(
        themes => \@themes,
        num_per_page => $num_per_page,
        page => $page,
        getargs => \@getargs,
        getextra => $getextra,
    );
    $ret .= "</ul>";

    if ($cat eq "all") {
        $ret .= "<h3>" . $class->ml('widget.themechooser.header.all') . "</h3>";
    } elsif ($cat eq "custom") {
        $ret .= "<h3>" . $class->ml('widget.themechooser.header.custom') . "</h3>";
    } elsif ($cat) {
        $ret .= "<h3>$cats{$cat}->{text}</h3>";
    } elsif ($layoutid) {
        my $layout_name = LJ::Customize->get_layout_name($layoutid, user => $u);
        $ret .= "<h3>$layout_name</h3>";
    } elsif ($designer) {
        $ret .= "<h3>$designer</h3>";
    } else { # category is "featured"
        $ret .= "<h3>$cats{featured}->{text}</h3>";
    }

    $ret .= "<p class='detail'>" . $class->ml('widget.themechooser.desc') . "</p>";

    $ret .= "<div class='themes-area'>";
    foreach my $theme (@themes_this_page) {
        next unless defined $theme;

        # figure out the type(s) of theme this is so we can modify the output accordingly
        my %theme_types;
        if ($theme->themeid) {
            $theme_types{current} = 1 if $theme->themeid == $current_theme->themeid;
        } elsif (!$theme->themeid && !$current_theme->themeid) {
            $theme_types{current} = 1 if $theme->layoutid == $current_theme->layoutid;
        }
        $theme_types{upgrade} = 1 if !$filter_available && !$theme->available_to($u);
        $theme_types{special} = 1 if LJ::run_hook("layer_is_special", $theme->uniq);

        my ($theme_class, $theme_options, $theme_icons) = ("", "", "");

        $theme_icons .= "<div class='theme-icons'>" if $theme_types{upgrade} || $theme_types{special};
        if ($theme_types{current}) {
            $theme_class .= " current";
            $theme_options .= "<strong><a href='$LJ::SITEROOT/customize2/options.bml$getextra'>" . $class->ml('widget.themechooser.theme.customize') . "</a></strong>";
        }
        if ($theme_types{upgrade}) {
            $theme_class .= " upgrade";
            $theme_options .= "<br />" if $theme_options;
            $theme_options .= LJ::run_hook("customize_special_options");
            $theme_icons .= LJ::run_hook("customize_special_icons", $u, $theme);
        }
        if ($theme_types{special}) {
            $theme_class .= " special" if $viewing_featured && LJ::run_hook("should_see_special_content", $u);
            $theme_icons .= LJ::run_hook("customize_available_until", $theme);
        }
        $theme_icons .= "</div><!-- end .theme-icons -->" if $theme_icons;

        my $theme_layout_name = $theme->layout_name;
        my $theme_designer = $theme->designer;

        $ret .= "<div class='theme-item$theme_class'>";
        $ret .= "<img src='" . $theme->preview_imgurl . "' class='theme-preview' />";
        $ret .= "<h4>" . $theme->name . "</h4>";

        my $preview_redirect_url;
        if ($theme->themeid) {
            $preview_redirect_url = "$LJ::SITEROOT/customize2/preview_redirect.bml?user=" . $u->id . "&themeid=" . $theme->themeid;
        } else {
            $preview_redirect_url = "$LJ::SITEROOT/customize2/preview_redirect.bml?user=" . $u->id . "&layoutid=" . $theme->layoutid;
        }
        $ret .= "<a href='$preview_redirect_url' target='_blank' class='theme-preview-link' title='" . $class->ml('widget.themechooser.theme.preview') . "'>";

        $ret .= "<img src='$LJ::IMGPREFIX/customize/preview-theme.gif' class='theme-preview-image' /></a>";
        $ret .= $theme_icons;

        my $layout_link = "<a href='$LJ::SITEROOT/customize2/$getextra${getsep}layoutid=" . $theme->layoutid . "$filterarg' class='theme-layout'><em>$theme_layout_name</em></a>";
        my $special_link_opts = "href='$LJ::SITEROOT/customize2/$getextra${getsep}cat=special$filterarg' class='theme-cat'";
        $ret .= "<p class='theme-desc'>";
        if ($theme_designer) {
            my $designer_link = "<a href='$LJ::SITEROOT/customize2/$getextra${getsep}designer=" . LJ::eurl($theme_designer) . "$filterarg' class='theme-designer'>$theme_designer</a>";
            if ($theme_types{special}) {
                $ret .= $class->ml('widget.themechooser.theme.specialdesc', {'aopts' => $special_link_opts, 'designer' => $designer_link});
            } else {
                $ret .= $class->ml('widget.themechooser.theme.desc', {'layout' => $layout_link, 'designer' => $designer_link});
            }
        } elsif ($theme_layout_name) {
            $ret .= $layout_link;
        }
        $ret .= "</p>";

        if ($theme_options) {
            $ret .= $theme_options;
        } else { # apply theme form
            $ret .= $class->start_form( class => "theme-form" );
            $ret .= $class->html_hidden(
                apply_themeid => $theme->themeid,
                apply_layoutid => $theme->layoutid,
            );
            $ret .= $class->html_submit(
                apply => $class->ml('widget.themechooser.theme.apply'),
                { raw => "class='theme-button' id='theme_btn_" . $theme->layoutid . $theme->themeid . "'" },
            );
            $ret .= $class->end_form;
        }
        $ret .= "</div><!-- end .theme-item -->";
    }
    $ret .= "</div>";

    $ret .= "<ul class='theme-paging theme-paging-bottom nostyle'>";
    $ret .= $class->print_paging(
        themes => \@themes,
        num_per_page => $num_per_page,
        page => $page,
        getargs => \@getargs,
        getextra => $getextra,
    );
    $ret .= "</ul>";

    $ret .= "</div><!-- end .theme-selector-content -->";

    return $ret;
}

sub print_paging {
    my $class = shift;
    my %opts = @_;

    my $themes = $opts{themes};
    my $page = $opts{page};
    my $num_per_page = $opts{num_per_page};

    my $max_page = POSIX::ceil(scalar(@$themes) / $num_per_page) || 1;
    return "" if $page == 1 && $max_page == 1;

    my $page_padding = 2; # number of pages to show on either side of the current page
    my $start_page = $page - $page_padding > 1 ? $page - $page_padding : 1;
    my $end_page = $page + $page_padding < $max_page ? $page + $page_padding : $max_page;

    my $getargs = $opts{getargs};
    my $getextra = $opts{getextra};

    my $q_string = join("&", @$getargs);
    my $q_sep = $q_string ? "&" : "";
    my $getsep = $getextra ? "&" : "?";

    my $url = "$LJ::SITEROOT/customize2/$getextra$getsep$q_string$q_sep";

    my $ret;
    if ($page - 1 >= 1) {
        $ret .= "<li class='first'><a href='${url}page=" . ($page - 1) . "' class='theme-page'>&lt;</a></li>";
    }
    if ($page - $page_padding > 1) {
        $ret .= "<li><a href='${url}page=1' class='theme-page'>1</a></li><li>&hellip;</li>";
    }
    for (my $i = $start_page; $i <= $end_page; $i++) {
        my $li_class = " class='on'" if $i == $page;
        if ($i == $page) {
            $ret .= "<li$li_class>$i</li>";
        } else {
            $ret .= "<li$li_class><a href='${url}page=$i' class='theme-page'>$i</a></li>";
        }
    }
    if ($page + $page_padding < $max_page) {
        $ret .= "<li>&hellip;</li><li><a href='${url}page=$max_page' class='theme-page'>$max_page</a></li>";
    }
    if ($page + 1 <= $max_page) {
        $ret .= "<li class='last'><a href='${url}page=" . ($page + 1) . "' class='theme-page'>&gt;</a></li>";
    }

    return $ret;
}

sub handle_post {
    my $class = shift;
    my $post = shift;
    my %opts = @_;

    my $u = $class->get_effective_remote();
    die "Invalid user." unless LJ::isu($u);

    my $themeid = $post->{apply_themeid}+0;
    my $layoutid = $post->{apply_layoutid}+0;

    my $theme;
    if ($themeid) {
        $theme = LJ::S2Theme->load_by_themeid($themeid, $u);
    } elsif ($layoutid) {
        $theme = LJ::S2Theme->load_custom_layoutid($layoutid, $u);
    } else {
        die "No theme id or layout id specified.";
    }

    LJ::Customize->apply_theme($u, $theme);

    return;
}

sub js {
    q [
        initWidget: function () {
            var self = this;

            var filter_links = DOM.getElementsByClassName(document, "theme-cat");
            filter_links = filter_links.concat(DOM.getElementsByClassName(document, "theme-layout"));
            filter_links = filter_links.concat(DOM.getElementsByClassName(document, "theme-designer"));
            filter_links = filter_links.concat(DOM.getElementsByClassName(document, "theme-page"));

            // add event listeners to all of the category, layout, designer, and page links
            // adding an event listener to page is done separately because we need to be sure to use that if it is there,
            //     and we will miss it if it is there but there was another arg before it in the URL
            filter_links.forEach(function (filter_link) {
                var getArgs = LiveJournal.parseGetArgs(filter_link.href);
                if (getArgs["page"]) {
                    DOM.addEventListener(filter_link, "click", function (evt) { Customize.ThemeNav.filterThemes(evt, "page", getArgs["page"]) });
                } else {
                    for (var arg in getArgs) {
                        if (!getArgs.hasOwnProperty(arg)) continue;
                        if (arg == "authas" || arg == "filter_available") continue;
                        DOM.addEventListener(filter_link, "click", function (evt) { Customize.ThemeNav.filterThemes(evt, arg, getArgs[arg]) });
                        break;
                    }
                }
            });

            // add event listeners to all of the apply theme forms
            var apply_forms = DOM.getElementsByClassName(document, "theme-form");
            apply_forms.forEach(function (form) {
                DOM.addEventListener(form, "submit", function (evt) { self.applyTheme(evt, form) });
            });

            // add event listeners to the preview links
            var preview_links = DOM.getElementsByClassName(document, "theme-preview-link");
            preview_links.forEach(function (preview_link) {
                DOM.addEventListener(preview_link, "click", function (evt) { self.previewTheme(evt, preview_link.href) });
            });
        },
        applyTheme: function (evt, form) {
            var given_themeid = form.Widget_ThemeChooser_apply_themeid.value;
            var given_layoutid = form.Widget_ThemeChooser_apply_layoutid.value;
            $("theme_btn_" + given_layoutid + given_themeid).disabled = true;
            DOM.addClassName($("theme_btn_" + given_layoutid + given_themeid), "theme-button-disabled");

            this.doPost({
                apply_themeid: given_themeid,
                apply_layoutid: given_layoutid
            });

            Event.stop(evt);
        },
        onData: function (data) {
            Customize.ThemeNav.updateContent({
                cat: Customize.cat,
                layoutid: Customize.layoutid,
                designer: Customize.designer,
                filter_available: Customize.filter_available,
                page: Customize.page,
                theme_chooser_id: $('theme_chooser_id').value
            });
            Customize.CurrentTheme.updateContent({
                filter_available: Customize.filter_available
            });
            Customize.LayoutChooser.updateContent({
                ad_layout_id: $('ad_layout_id').value
            });
        },
        previewTheme: function (evt, href) {
            window.open(href, 'theme_preview', 'resizable=yes,status=yes,toolbar=no,location=no,menubar=no,scrollbars=yes');
            Event.stop(evt);
        },
        onRefresh: function (data) {
            this.initWidget();
        }
    ];
}

1;
