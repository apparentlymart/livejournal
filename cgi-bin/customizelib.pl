#!/usr/bin/perl
#

package LJ::cmize;
use strict;

# Returns a list of style ids and names, suitable for html_select
sub s1_get_style_list
{
    my ($u, $view) = @_;

    my $capstyles = LJ::get_cap($u, "styles");
    my $pubstyles = LJ::S1::get_public_styles();
    my %pubstyles = ();
    foreach (sort { $a->{'styledes'} cmp $b->{'styledes'} } values %$pubstyles) {
        push @{$pubstyles{$_->{'type'}}}, $_;
    }

    my $userstyles = LJ::S1::get_user_styles($u);
    my %userstyles = ();
    foreach (sort { $a->{'styledes'} cmp $b->{'styledes'} } values %$userstyles) {
        push @{$userstyles{$_->{'type'}}}, $_;
    }
    my @list = map { $_->{'styleid'}, $_->{'styledes'} } @{$pubstyles{$view} || []};
    if (@{$userstyles{$view} || []}) {
        my @user_list = map { $_->{'styleid'}, $_->{'styledes'} }
        grep { $capstyles || $u->{"s1_${view}_style"} == $_->{'styleid'} }
        @{$userstyles{$view} || []};
        push @list, { value    => "",
                      text     => "--- " . BML::ml('/modify_do.bml.availablestyles.userstyles') . " ---",
                      disabled => 1 }, @user_list
                          if @user_list;
        my @disabled_list =
            map { { value    => $_->{'styleid'},
                    text     => $_->{'styledes'},
                    disabled => 1 } }
        grep { ! $capstyles && $u->{"s1_${view}_style"} != $_->{'styleid'} }
                                @{$userstyles{$view} || []};
        push @list, { value    => '',
                      text     => "--- " . BML::ml('/modify_do.bml.availablestyles.disabledstyles') . " ---",
                      disabled => 1 }, @disabled_list
                          if @disabled_list;
    }
    return @list;
}

# Returns a hash of colors for a custom S1 theme
sub s1_get_customcolors
{
    my $u = shift;

    my %custcolors = ();
    my $dbr = LJ::get_db_reader();
    if ($u->prop('themeid') == 0) {
        my $stor = $u->selectrow_array("SELECT color_stor FROM s1usercache WHERE userid=?",
                                       undef, $u->{'userid'});
        if ($stor) {
            %custcolors = %{ Storable::thaw($stor) };
        } else {
            # ancient table.
            my $sth = $dbr->prepare("SELECT coltype, color FROM themecustom WHERE user=?");
            $sth->execute($u->{'user'});
            $custcolors{$_->{'coltype'}} = $_->{'color'} while $_ = $sth->fetchrow_hashref;
        }
    } else {
        my $sth = $dbr->prepare("SELECT coltype, color FROM themedata WHERE themeid=?");
        $sth->execute($u->{'themeid'});
        $custcolors{$_->{'coltype'}} = $_->{'color'} while $_ = $sth->fetchrow_hashref;
    }

    return %custcolors;
}

# Returns a list of S1 theme ids and names, suitable for html_select
sub s1_get_theme_list
{
    my @list;
    my $dbr = LJ::get_db_reader();
    my $sth = $dbr->prepare("SELECT themeid, name FROM themelist ORDER BY name");
    $sth->execute;
    while ($_ = $sth->fetchrow_hashref) {
        push @list, ($_->{'themeid'}, $_->{'name'});
    }
    return @list;
}

# Common "create s2 style" skeleton
sub s2_implicit_style_create
{
    my ($u, %style) = @_;
    my $pub     = LJ::S2::get_public_layers();
    my $userlay = LJ::S2::get_layers_of_user($u);

    my $s2_style;
    # create new style if necessary
    unless ($u->prop('s2_style')) {
        my $layid = $style{'layout'};
        my $lay = $pub->{$layid} || $userlay->{$layid};
        my $uniq = (split("/", $lay->{'uniq'}))[0] || $lay->{'s2lid'};
        unless ($s2_style = LJ::S2::create_style($u, "wizard-$uniq")) {
            die "Can't create style";
        }
        $u->set_prop("s2_style", $s2_style);
    }
    # save values in %style to db
    LJ::S2::set_style_layers($u, $s2_style, %style);

    return 1;
}

# Get the lang code for the user's style
sub s2_get_lang {
    my ($u, $styleid) = @_;
    my $pub     = LJ::S2::get_public_layers();
    my $userlay = LJ::S2::get_layers_of_user($u);

    foreach ($userlay, $pub) {
        return $_->{$styleid}->{'langcode'} if
            $_->{$styleid} && $_->{$styleid}->{'langcode'};
    }
    return undef;
}

# custom layers will be shown in the "Custom Layers" and "Disabled Layers" groups
# depending on the user's account status.  if they don't have the s2styles cap, then
# they will have all layers disabled, except for the one they are currently using.
sub s2_custom_layer_list {
    my ($u, $type, $ptype) = @_;
    my @layers = ();

    my $has_cap = LJ::get_cap($u, "s2styles");
    my $pub     = LJ::S2::get_public_layers();
    my $userlay = LJ::S2::get_layers_of_user($u);
    my %style   = LJ::S2::get_style($u, "verify");

    my @user = map { $_, $userlay->{$_}->{'name'} ? $userlay->{$_}->{'name'} : "\#$_" }
    sort { $userlay->{$a}->{'name'} cmp $userlay->{$b}->{'name'} || $a <=> $b }
    grep { /^\d+$/ && $userlay->{$_}->{'b2lid'} == $style{$ptype} &&
               $userlay->{$_}->{'type'} eq $type &&
               ($has_cap || $_ == $style{$type}) }
    keys %$userlay;
    if (@user) {
        push @layers, { value    => "",
                        text     => "--- Custom Layers: ---",
                        disabled => 1 }, @user;
    }

    unless ($has_cap) {
        my @disabled =
            map { { value    => $_,
                    text     => $userlay->{$_}->{'name'} ? $userlay->{$_}->{'name'} : "\#$_",
                    disabled => 1 } }
        sort { $userlay->{$a}->{'name'} cmp $userlay->{$b}->{'name'} ||
                   $userlay->{$a}->{'s2lid'} <=> $userlay->{$b}->{'s2lid'} }
        grep { /^\d+$/ && $userlay->{$_}->{'b2lid'} == $style{$ptype} &&
                   $userlay->{$_}->{'type'} eq $type && $_ != $style{$type} }
        keys %$userlay;
        if (@disabled) {
            push @layers, { value    => "",
                            text     => "--- Disabled Layers: ---",
                            disabled => 1 }, @disabled;
        }
    }
    return @layers;
}

# Spoof checking for mood theme ids
sub validate_moodthemeid {
    my ($u, $themeid) = @_;
    my $dbr = LJ::get_db_reader();
    if ($themeid) {
        my ($mownerid, $mpublic) = $dbr->selectrow_array("SELECT ownerid, is_public FROM moodthemes ".
                                                         "WHERE moodthemeid=?", undef, $themeid);
        $themeid = 0 unless $mpublic eq 'Y' || $mownerid == $u->{'userid'};
    }
    return $themeid
}

# Returns a list of moodthemes that the user can select from, suitable for html_select
sub get_moodtheme_select_list
{
    my $u = shift;

    my $dbr = LJ::get_db_reader();
    my $sth = $dbr->prepare("SELECT moodthemeid, name FROM moodthemes WHERE is_public='Y'");
    $sth->execute;

    my @themes = ({ 'moodthemeid' => 0, 'name' => '(None)' });
    push @themes, $_ while ($_ = $sth->fetchrow_hashref);
    ### user's private themes
    {
        my @theme_user;
        $sth = $dbr->prepare("SELECT moodthemeid, name FROM moodthemes WHERE ownerid=? AND is_public='N'");
        $sth->execute($u->{'userid'});
        push @theme_user, $_ while ($_ = $sth->fetchrow_hashref);
        if (@theme_user) {
            push @themes, { 'moodthemeid' => 0, 'name' => "--- " . BML::ml('/modify.bml.moodicons.personal'). " ---" };
            push @themes, @theme_user;
        }
    }

    return @themes;
}

# Function to determine the correct redirect when clicking on a tab link
sub js_redirect
{
    my $POST = shift;
    my %redirect = (
                    "display_index" => "index.bml",
                    "display_style" => "style.bml",
                    "display_options" => "options.bml",
                    "display_advanced" => "advanced.bml",
                    );
    if ($POST->{"action:redir"} ne "" && $redirect{$POST->{"action:redir"}}) {
        BML::redirect("/customizetmp/" . $redirect{$POST->{"action:redir"}});
    }
}

# Get style thumbnail information from per-process caches, or load if not available
sub get_style_thumbnails
{
    my $now = time;
    return \%LJ::CACHE_STYLE_THUMBS if $LJ::CACHE_STYLE_THUMBS{'_loaded'} > $now - 300;
    %LJ::CACHE_STYLE_THUMBS = ();

    open (my $pfh, "$LJ::HOME/htdocs/img/stylepreview/pics.autogen.dat") or return undef;
    while (my $line = <$pfh>) {
        chomp $line;
        my ($style, $url) = split(/\t/, $line);
        $LJ::CACHE_STYLE_THUMBS{$style} = $url;
    }
    $LJ::CACHE_STYLE_THUMBS{'_loaded'} = $now;
    return \%LJ::CACHE_STYLE_THUMBS;
}

### HTML helper functions

# Returns a block of HTML that summarizes the user's current display options
sub display_current_summary
{
    my $u = shift;
    my $ret;
    $ret .= "<?standout <strong>Current Display Summary:</strong>";

    $ret .= "<table><tr>";
    my $style_settings = "None";
    if ($u->prop('stylesys') == 2) {
        my $ustyle = LJ::S2::load_user_styles($u);
        if (%$ustyle) {
            $style_settings = $ustyle->{$u->prop('s2_style')};
        }
    } else {
        my $dbr = LJ::get_db_reader();
        my $style_settings = $u->selectrow_array("SELECT styledes FROM s1style WHERE styleid=?",
                                                 undef, $u->prop('s1_lastn_style'));
    }
    $ret .= "<tr><th>Name:</th><td>" . LJ::ehtml($style_settings) . "</td></tr>";

    my $style_type = $u->prop('stylesys') == 2 ? "Wizard" : "Template" ;
    $ret .= "<th>Type:</th><td>$style_type</td></tr>";

    my $mood_settings = "None";
    my $dbr = LJ::get_db_reader();
    if ($u->prop('moodthemeid') > 0) {
        $mood_settings = $dbr->selectrow_array("SELECT name FROM moodthemes WHERE moodthemeid=?",
                                               undef, $u->prop('moodthemeid'));
    }
    $ret .= "<tr><th>Mood Theme:</th><td>" . LJ::ehtml($mood_settings) . "</td></tr>";
    my $comment_settings = $u->prop('opt_showtalklinks') == "Y" ? "Enabled" : "Disabled";
    $ret .= "<tr><th>Comments:</th><td>$comment_settings</td></tr>";

    $ret .= "</table> standout?>";
    return $ret;
}

# Common HTML for links on top of tabs
sub html_tablinks
{
    my ($page, $getextra) = @_;
    my $ret;

    my %strings = (
                   "index" => "Basics",
                   "style" => "Look and Feel",
                   "options" => "Custom Options",
                   "advanced" => "Advanced",
                   );

    $ret .= "<ul id='Tabs'>";
    foreach my $tab ( "index", "style", "options", "advanced" ) {
        if ($page eq $tab) {
            $ret .= "<li class='SelectedTab'>$strings{$tab}</li>";
        } else {
            $ret .= "<li><a id='display_$tab' href='$tab.bml$getextra'>$strings{$tab}</a></li>";
        }
    }
    $ret .= "</ul>";
    return $ret;
}

# common HTML for the "save changes" button in a tab
sub html_save
{
    my $ret;
    $ret .= LJ::html_hidden({ 'name' => "action:redir", value => "", 'id' => "action:redir" });
    $ret .= "<div style='text-align: center'>";
    $ret .= LJ::html_submit('action:save', "Save Changes", { 'id' => "action:save" });
    $ret .= "</div>";
}

1;
