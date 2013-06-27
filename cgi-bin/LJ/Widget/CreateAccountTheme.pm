package LJ::Widget::CreateAccountTheme;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);
use Class::Autouse qw( LJ::Customize );

sub need_res { qw( stc/widgets/createaccounttheme.css ) }

sub render_body {
    my $class = shift;
    my %opts = @_;

    my $u = LJ::get_effective_remote();
    my $current_theme = LJ::Customize->get_current_theme($u);

    my $ret;
    $ret .= "<div class='rounded-box'><div class='rounded-box-tr'><div class='rounded-box-bl'><div class='rounded-box-br'>";
    $ret .= "<div class='rounded-box'><div class='rounded-box-tr'><div class='rounded-box-bl'><div class='rounded-box-br'>";

    $ret .= "<div class='rounded-box-content'>";
    $ret .= "<h2>" . $class->ml('widget.createaccounttheme.title') . "</h2>";
    $ret .= "<p>" . $class->ml('widget.createaccounttheme.info') . "</p>";

    my @featured = LJ::S2Theme->load_by_cat("featured");
    my @theme_ids = (LJ::SUP->is_sup_enabled($u)) ? @LJ::SUP_DEFAULT_THEMES_PERSONAL : @LJ::DEFAULT_THEMES_PERSONAL;
    my %main_themes = map { $_ => 1 } @theme_ids;
    for (my $i = 0; $i < @featured; $i++) {
        next unless $main_themes{$featured[$i]->uniq};
        splice(@featured, $i, 1);
        $i--; # just deleted element from array
    }
    my @random;
    foreach (0 .. 7) {
        my $index = int(rand(scalar(@featured)));
        push @random, splice(@featured, $index, 1);
    }
    my @theme__ids = (LJ::SUP->is_sup_enabled($u)) ? @LJ::SUP_DEFAULT_THEMES_PERSONAL : @LJ::DEFAULT_THEMES_PERSONAL;
    unshift @random, LJ::S2Theme->load_by_uniq($_) foreach @theme__ids;

    my $count = 0;
    $ret .= "<table cellspacing='3' cellpadding='0' align='center'>\n";
    foreach my $theme (@random) {
        my $uniq = $theme->uniq;
        my $image_class = $theme->uniq;
        $image_class =~ s/\//_/;
        my $name = $theme->name . ", " . $theme->layout_name;

        my @checked = $current_theme->uniq eq $uniq ? ( checked => "checked" ) : ();

        $ret .= "<tr>" if $count % 3 == 0;
        $ret .= "<td class='theme-box'>";
        $ret .= "<div class='theme-box-inner'>";
        $ret .= "<label for='theme_$image_class'><img src='" . $theme->preview_imgurl . "' width='90' height='68' class='theme-image' alt='$name' title='$name' /></label><br />";
        $ret .= "<a href='$LJ::SITEROOT/customize/preview_redirect.bml?themeid=" . $theme->themeid . "' target='_blank' onclick='window.open(href, \"theme_preview\", \"resizable=yes,status=yes,toolbar=no,location=no,menubar=no,scrollbars=yes\"); return false;' class='theme-preview-link' title='" . $class->ml('widget.createaccounttheme.preview') . "'>";
        $ret .= "<img src='$LJ::IMGPREFIX/customize/preview-theme.gif?v=12565' class='theme-preview-image' /></a>";
        $ret .= $class->html_check(
            name => 'theme',
            id => "theme_$image_class",
            type => 'radio',
            value => $uniq,
            style => "margin-bottom: 5px;",
            @checked,
        );
        $ret .= "</div>";
        $ret .= "</td>";
        $ret .= "</tr>" if $count % 3 == 2;

        $count++;
    }
    $ret .= "</table>\n";
    $ret .= "</div>";

    $ret .= "</div></div></div></div>";
    $ret .= "</div></div></div></div>";

    return $ret;
}

sub handle_post {
    my $class = shift;
    my $post = shift;
    my %opts = @_;

    my $u = LJ::get_effective_remote();

    if ($post->{theme}) {
        my $theme = LJ::S2Theme->load_by_uniq($post->{theme});
        die "Invalid theme selection" unless $theme;

        LJ::Customize->apply_theme($u, $theme);
    }

    return;
}

1;
