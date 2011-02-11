#!/usr/bin/perl
#

package LJ;
use strict;

use lib "$ENV{LJHOME}/cgi-bin";

# load the bread crumb hash
require "crumbs.pl";

use Carp;
use LJ::Request;
use LJ::JSON;
use Class::Autouse qw(
                      LJ::Event
                      LJ::Subscription::Pending
                      LJ::M::ProfilePage
                      LJ::Directory::Search
                      LJ::Directory::Constraint
                      LJ::M::FriendsOf
                      );
use LJ::ControlStrip;
use Apache::WURFL;

# <LJFUNC>
# name: LJ::img
# des: Returns an HTML &lt;img&gt; or &lt;input&gt; tag to an named image
#      code, which each site may define with a different image file with
#      its own dimensions.  This prevents hard-coding filenames & sizes
#      into the source.  The real image data is stored in LJ::Img, which
#      has default values provided in cgi-bin/imageconf.pl but can be
#      overridden in etc/ljconfig.pl.
# args: imagecode, type?, attrs?
# des-imagecode: The unique string key to reference the image.  Not a filename,
#                but the purpose or location of the image.
# des-type: By default, the tag returned is an &lt;img&gt; tag, but if 'type'
#           is "input", then an input tag is returned.
# des-attrs: Optional hashref of other attributes.  If this isn't a hashref,
#            then it's assumed to be a scalar for the 'name' attribute for
#            input controls.
# </LJFUNC>
sub img
{
    my $ic = shift;
    my $type = shift;  # either "" or "input"
    my $attr = shift;

    my $attrs;
    my $alt;
    if ($attr) {
        if (ref $attr eq "HASH") {
            $alt = LJ::ehtml($attr->{alt}) if (exists $attr->{alt});
            foreach (keys %$attr) {
                $attrs .= " $_=\"" . LJ::ehtml($attr->{$_}) . "\""
                    unless ((lc $_) eq 'alt');
            }
        } else {
            $attrs = " name=\"$attr\"";
        }
    }

    my $i = $LJ::Img::img{$ic};
    $alt ||= LJ::Lang::string_exists($i->{'alt'}) ? LJ::Lang::ml($i->{'alt'}) : $i->{'alt'};
    if ($type eq "") {
        return "<img src=\"$LJ::IMGPREFIX$i->{'src'}\" width=\"$i->{'width'}\" ".
            "height=\"$i->{'height'}\" alt=\"$alt\" title=\"$alt\" ".
            "border='0'$attrs />";
    }
    if ($type eq "input") {
        return "<input type=\"image\" src=\"$LJ::IMGPREFIX$i->{'src'}\" ".
            "width=\"$i->{'width'}\" height=\"$i->{'height'}\" title=\"$alt\" ".
            "alt=\"$alt\" border='0'$attrs />";
    }
    return "<b>XXX</b>";
}

# <LJFUNC>
# name: LJ::date_to_view_links
# class: component
# des: Returns HTML of date with links to user's journal.
# args: u, date
# des-date: date in yyyy-mm-dd form.
# returns: HTML with yyyy, mm, and dd all links to respective views.
# </LJFUNC>
sub date_to_view_links
{
    my ($u, $date) = @_;
    return unless $date =~ /^(\d\d\d\d)-(\d\d)-(\d\d)/;

    my ($y, $m, $d) = ($1, $2, $3);
    my ($nm, $nd) = ($m+0, $d+0);   # numeric, without leading zeros
    my $user = $u->{'user'};
    my $base = LJ::journal_base($u);

    my $ret;
    $ret .= "<a href=\"$base/$y/\">$y</a>-";
    $ret .= "<a href=\"$base/$y/$m/\">$m</a>-";
    $ret .= "<a href=\"$base/$y/$m/$d/\">$d</a>";
    return $ret;
}


# <LJFUNC>
# name: LJ::auto_linkify
# des: Takes a plain-text string and changes URLs into <a href> tags (auto-linkification).
# args: str
# des-str: The string to perform auto-linkification on.
# returns: The auto-linkified text.
# </LJFUNC>
sub auto_linkify
{
    my $str = shift;
    my $match = sub {
        my $str = shift;
        if ($str =~ /^(.*?)(&(#39|quot|lt|gt)(;.*)?)$/) {
            return "<a href='$1'>$1</a>$2";
        } else {
            return "<a href='$str'>$str</a>";
        }
    };
    $str =~ s!(https?://[^\s\'\"\<\>]+[a-zA-Z0-9_/&=\-])! $match->($1); !ge;
    return $str;
}

# return 1 if URL is a safe stylesheet that S1/S2/etc can pull in.
# return 0 to reject the link tag
# return a URL to rewrite the stylesheet URL
# $href will always be present.  $host and $path may not.
sub valid_stylesheet_url {
    my ($href, $host, $path) = @_;
    unless ($host && $path) {
        return 0 unless $href =~ m!^https?://([^/]+?)(/.*)$!;
        ($host, $path) = ($1, $2);
    }

    my $cleanit = sub {
        # allow tag, if we're doing no css cleaning
        return 1 if $LJ::DISABLED{'css_cleaner'};

        # remove tag, if we have no CSSPROXY configured
        return 0 unless $LJ::CSSPROXY;

        # rewrite tag for CSS cleaning
        return "$LJ::CSSPROXY?u=" . LJ::eurl($href);
    };

    return 1 if $LJ::TRUSTED_CSS_HOST{$host};
    return $cleanit->() unless $host =~ /\Q$LJ::DOMAIN\E$/i;

    # let users use system stylesheets.
    return 1 if $host eq $LJ::DOMAIN || $host eq $LJ::DOMAIN_WEB ||
        $href =~ /^\Q$LJ::STATPREFIX\E/;

    # S2 stylesheets:
    return 1 if $path =~ m!^(/\w+)?/res/(\d+)/stylesheet(\?\d+)?$!;

    # unknown, reject.
    return $cleanit->();
}


# <LJFUNC>
# name: LJ::make_authas_select
# des: Given a u object and some options, determines which users the given user
#      can switch to.  If the list exists, returns a select list and a submit
#      button with labels.  Otherwise returns a hidden element.
# returns: string of HTML elements
# args: u, opts?
# des-opts: Optional.  Valid keys are:
#           'authas' - current user, gets selected in drop-down;
#           'label' - label to go before form elements;
#           'button' - button label for submit button;
#           others - arguments to pass to [func[LJ::get_authas_list]].
# </LJFUNC>
sub make_authas_select {
    my ($u, $opts) = @_; # type, authas, label, button

    die "make_authas_select called outside of web context"
        unless LJ::is_web_context();

    my @list = LJ::get_authas_list($u, $opts);

    # only do most of form if there are options to select from
    if (@list > 1 || $list[0] ne $u->{'user'}) {
        my $ret;
        my $label = $BML::ML{'web.authas.label'};
        $label = $BML::ML{'web.authas.label.comm'} if ($opts->{'type'} eq "C");
        $ret = ($opts->{'label'} || $label) . " ";
        $ret .= LJ::html_select({ 'name' => 'authas',
                                 'selected' => $opts->{'authas'} || $u->{'user'},
                                 'class' => 'hideable',
                                 },
                                 map { $_, $_ } @list) . " ";
        $ret .= $opts->{'button_tag'} . LJ::html_submit(undef, $opts->{'button'} || $BML::ML{'web.authas.btn'}) . $opts->{'button_close_tag'};
        return $ret;
    }

    # no communities to choose from, give the caller a hidden
    my $ret = LJ::html_hidden('authas', $opts->{'authas'} || $u->{'user'});
    $ret .= $opts->{'nocomms'} if $opts->{'nocomms'};
    return $ret;
}

# <LJFUNC>
# name: LJ::make_postto_select
# des: Given a u object and some options, determines which users the given user
#      can post to.  If the list exists, returns a select list and a submit
#      button with labels.  Otherwise returns a hidden element.
# returns: string of HTML elements
# args: u, opts?
# des-opts: Optional.  Valid keys are:
#           'postto' - current user, gets selected in drop-down;
#           'label' - label to go before form elements;
#           'button' - button label for submit button;
#           others - arguments to pass to [func[LJ::get_postto_list]].
# </LJFUNC>
sub make_postto_select {
    my ($u, $opts) = @_; # type, authas, label, button

    my @list = LJ::get_postto_list($u, $opts);

    # only do most of form if there are options to select from
    if (@list > 1) {
        return ($opts->{'label'} || $BML::ML{'web.postto.label'}) . " " .
               LJ::html_select({ 'name' => 'authas',
                                 'selected' => $opts->{'authas'} || $u->{'user'}},
                                 map { $_, $_ } @list) . " " .
               LJ::html_submit(undef, $opts->{'button'} || $BML::ML{'web.postto.btn'});
    }

    # no communities to choose from, give the caller a hidden
    return  LJ::html_hidden('authas', $opts->{'authas'} || $u->{'user'});
}

# <LJFUNC>
# name: LJ::help_icon
# des: Returns BML to show a help link/icon given a help topic, or nothing
#      if the site hasn't defined a URL for that topic.  Optional arguments
#      include HTML/BML to place before and after the link/icon, should it
#      be returned.
# args: topic, pre?, post?
# des-topic: Help topic key.
#            See doc/ljconfig.pl.txt, or [special[helpurls]] for examples.
# des-pre: HTML/BML to place before the help icon.
# des-post: HTML/BML to place after the help icon.
# </LJFUNC>
sub help_icon
{
    my $topic = shift;
    my $pre = shift;
    my $post = shift;
    return "" unless (defined $LJ::HELPURL{$topic});
    return "$pre<?help $LJ::HELPURL{$topic} help?>$post";
}

# like help_icon, but no BML.
sub help_icon_html {
    my $topic = shift;
    my $url = $LJ::HELPURL{$topic} or return "";
    my $pre = shift || "";
    my $post = shift || "";
    # FIXME: use LJ::img() here, not hard-coding width/height
    return "$pre<a href=\"$url\" class=\"helplink\" target=\"_blank\"><img src=\"$LJ::IMGPREFIX/help.gif\" alt=\"Help\" title=\"Help\" width='14' height='14' border='0' /></a>$post";
}

# <LJFUNC>
# name: LJ::bad_input
# des: Returns common BML for reporting form validation errors in
#      a bulleted list.
# returns: BML showing errors.
# args: error*
# des-error: A list of errors
# </LJFUNC>
sub bad_input
{
    my @errors = @_;
    my $ret = "";
    $ret .= "<?badcontent?>\n<ul>\n";
    foreach my $ei (@errors) {
        my $err  = LJ::errobj($ei) or next;
        $err->log;
        $ret .= $err->as_bullets;
    }
    $ret .= "</ul>\n";
    return $ret;
}


# <LJFUNC>
# name: LJ::error_list
# des: Returns an error bar with bulleted list of errors.
# returns: BML showing errors.
# args: error*
# des-error: A list of errors
# </LJFUNC>
sub error_list
{
    # FIXME: retrofit like bad_input above?  merge?  make aliases for each other?
    my @errors = @_;
    my $ret;
    $ret .= "<?errorbar ";
    $ret .= "<strong>";
    $ret .= BML::ml('error.procrequest');
    $ret .= "</strong><ul>";

    foreach my $ei (@errors) {
        my $err  = LJ::errobj($ei) or next;
        $err->log;
        $ret .= $err->as_bullets;
    }
    $ret .= " </ul> errorbar?>";
    return $ret;
}


# <LJFUNC>
# name: LJ::error_noremote
# des: Returns an error telling the user to log in.
# returns: Translation string "error.notloggedin"
# </LJFUNC>
sub error_noremote
{
    return "<?needlogin?>";
}


# <LJFUNC>
# name: LJ::warning_list
# des: Returns a warning bar with bulleted list of warnings.
# returns: BML showing warnings
# args: warnings*
# des-warnings: A list of warnings
# </LJFUNC>
sub warning_list
{
    my @warnings = @_;
    my $ret;

    $ret .= "<?warningbar ";
    $ret .= "<strong>";
    $ret .= BML::ml('label.warning');
    $ret .= "</strong><ul>";

    foreach (@warnings) {
        $ret .= "<li>$_</li>";
    }
    $ret .= " </ul> warningbar?>";
    return $ret;
}

sub tosagree_widget {
    my ($checked, $errstr) = @_;

    return
        "<div class='formitemDesc'>" .
        BML::ml('tos.mustread',
                { aopts => "target='_new' href='$LJ::SITEROOT/legal/tos.bml'" }) .
        "</div>" .
        "<iframe width='684' height='300' src='/legal/tos-mini.bml' " .
        "style='border: 1px solid gray;'></iframe>" .
        "<div>" . LJ::html_check({ name => 'agree_tos', id => 'agree_tos',
                                   value => '1', selected =>  $checked }) .
        "<label for='agree_tos'>" . BML::ml('tos.haveread') . "</label></div>" .
        ($errstr ? "<?inerr $errstr inerr?>" : '');
}

sub tosagree_html {
    my $domain = shift;

    my $ret = "<?h1 $LJ::REQUIRED_TOS{title} h1?>";

    my $html_str = LJ::tosagree_str($domain => 'html');
    $ret .= "<?p $html_str p?>" if $html_str;

    $ret .= "<div style='margin-left: 40px; margin-bottom: 20px;'>";
    $ret .= LJ::tosagree_widget(@_);
    $ret .= "</div>";

    return $ret;
}

sub tosagree_str {
    my ($domain, $key) = @_;

    return ref $LJ::REQUIRED_TOS{$domain} && $LJ::REQUIRED_TOS{$domain}->{$key} ?
        $LJ::REQUIRED_TOS{$domain}->{$key} : $LJ::REQUIRED_TOS{$key};
}

# <LJFUNC>
# name: LJ::did_post
# des: Cookies should only show pages which make no action.
#      When an action is being made, check the request coming
#      from the remote user is a POST request.
# info: When web pages are using cookie authentication, you can't just trust that
#       the remote user wants to do the action they're requesting.  It's way too
#       easy for people to force other people into making GET requests to
#       a server.  What if a user requested http://server/delete_all_journal.bml,
#       and that URL checked the remote user and immediately deleted the whole
#       journal?  Now anybody has to do is embed that address in an image
#       tag and a lot of people's journals will be deleted without them knowing.
#       Cookies should only show pages which make no action.  When an action is
#       being made, check that it's a POST request.
# returns: true if REQUEST_METHOD == "POST"
# </LJFUNC>
sub did_post
{
    return (BML::get_method() eq "POST");
}

# <LJFUNC>
# name: LJ::robot_meta_tags
# des: Returns meta tags to instruct a robot/crawler to not index or follow links.
# returns: A string with appropriate meta tags
# </LJFUNC>
sub robot_meta_tags
{
    return "<meta name=\"robots\" content=\"noindex, nofollow, noarchive\" />\n" .
           "<meta name=\"googlebot\" content=\"noindex, nofollow, noarchive, nosnippet\" />\n";
}

sub paging_bar
{
    my ($page, $pages, $opts) = @_;

    my $self_link = $opts->{'self_link'} ||
                    sub { BML::self_link({ 'page' => $_[0] }) };

    my $href_opts = $opts->{'href_opts'} || sub { '' };

    my $navcrap;
    if ($pages > 1) {
        $navcrap .= "<center><font face='Arial,Helvetica' size='-1'><b>";
        $navcrap .= BML::ml('ljlib.pageofpages',{'page'=>$page, 'total'=>$pages}) . "<br />";
        my $left = "<b>&lt;&lt;</b>";
        if ($page > 1) { $left = "<a href='" . $self_link->($page-1) . "'" . $href_opts->($page-1) . ">$left</a>"; }
        my $right = "<b>&gt;&gt;</b>";
        if ($page < $pages) { $right = "<a href='" . $self_link->($page+1) . "'" . $href_opts->($page+1) . ">$right</a>"; }
        $navcrap .= $left . " ";
        for (my $i=1; $i<=$pages; $i++) {
            my $link = "[$i]";
            if ($i != $page) { $link = "<a href='" . $self_link->($i) . "'" .  $href_opts->($i) . ">$link</a>"; }
            else { $link = "<font size='+1'><b>$link</b></font>"; }
            $navcrap .= "$link ";
        }
        $navcrap .= "$right";
        $navcrap .= "</font></center>\n";
        $navcrap = BML::fill_template("standout", { 'DATA' => $navcrap });
    }
    return $navcrap;
}

# <LJFUNC>
# class: web
# name: LJ::make_cookie
# des: Prepares cookie header lines.
# returns: An array of cookie lines.
# args: name, value, expires, path?, domain?
# des-name: The name of the cookie.
# des-value: The value to set the cookie to.
# des-expires: The time (in seconds) when the cookie is supposed to expire.
#              Set this to 0 to expire when the browser closes. Set it to
#              undef to delete the cookie.
# des-path: The directory path to bind the cookie to.
# des-domain: The domain (or domains) to bind the cookie to.
# </LJFUNC>
sub make_cookie
{
    my ($name, $value, $expires, $path, $domain) = @_;
    my $cookie = "";
    my @cookies = ();

    # let the domain argument be an array ref, so callers can set
    # cookies in both .foo.com and foo.com, for some broken old browsers.
    if ($domain && ref $domain eq "ARRAY") {
        foreach (@$domain) {
            push(@cookies, LJ::make_cookie($name, $value, $expires, $path, $_));
        }
        return;
    }

    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime($expires);
    $year+=1900;

    my @day = qw{Sunday Monday Tuesday Wednesday Thursday Friday Saturday};
    my @month = qw{Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec};

    $cookie = sprintf "%s=%s", LJ::eurl($name), LJ::eurl($value);

    # this logic is confusing potentially
    unless (defined $expires && $expires==0) {
        $cookie .= sprintf "; expires=$day[$wday], %02d-$month[$mon]-%04d %02d:%02d:%02d GMT",
                $mday, $year, $hour, $min, $sec;
    }

    $cookie .= "; path=$path" if $path;
    $cookie .= "; domain=$domain" if $domain;
    push(@cookies, $cookie);
    return @cookies;
}

sub set_active_crumb
{
    $LJ::ACTIVE_CRUMB = shift;
    return undef;
}

sub set_dynamic_crumb
{
    my ($title, $parent) = @_;
    $LJ::ACTIVE_CRUMB = [ $title, $parent ];
}

sub get_parent_crumb
{
    my $thiscrumb = LJ::get_crumb(LJ::get_active_crumb());
    return LJ::get_crumb($thiscrumb->[2]);
}

sub get_active_crumb
{
    return $LJ::ACTIVE_CRUMB;
}

sub get_crumb_path
{
    my $cur = LJ::get_active_crumb();
    my @list;
    while ($cur) {
        # get crumb, fix it up, and then put it on the list
        if (ref $cur) {
            # dynamic crumb
            push @list, [ $cur->[0], '', $cur->[1], 'dynamic' ];
            $cur = $cur->[1];
        } else {
            # just a regular crumb
            my $crumb = LJ::get_crumb($cur);
            last unless $crumb;
            last if $cur eq $crumb->[2];
            $crumb->[3] = $cur;
            push @list, $crumb;

            # now get the next one we're going after
            $cur = $crumb->[2]; # parent of this crumb
        }
    }
    return @list;
}

sub get_crumb
{
    my $crumbkey = shift;
    if (defined $LJ::CRUMBS_LOCAL{$crumbkey}) {
        return $LJ::CRUMBS_LOCAL{$crumbkey};
    } else {
        return $LJ::CRUMBS{$crumbkey};
    }
}

# <LJFUNC>
# name: LJ::check_referer
# class: web
# des: Checks if the user is coming from a given URI.
# args: uri?, referer?
# des-uri: string; the URI we want the user to come from.
# des-referer: string; the location the user is posting from.
#              If not supplied, will be retrieved with BML::get_client_header.
#              In general, you don't want to pass this yourself unless
#              you already have it or know we can't get it from BML.
# returns: 1 if they're coming from that URI, else undef
# </LJFUNC>
sub check_referer {
    my $uri = shift(@_) || '';
    my $referer = shift(@_) || BML::get_client_header('Referer');

    # get referer and check
    return 1 unless $referer;
    return 1 if $LJ::SITEROOT   && $referer =~ m!^$LJ::SITEROOT$uri!;
    return 1 if $LJ::DOMAIN     && $referer =~ m!^http://$LJ::DOMAIN$uri!;
    return 1 if $LJ::DOMAIN_WEB && $referer =~ m!^http://$LJ::DOMAIN_WEB$uri!;
    return 1 if $LJ::USER_VHOSTS && $referer =~ m!^http://([A-Za-z0-9_\-]{1,15})\.$LJ::DOMAIN$uri!;
    return 1 if $uri =~ m!^http://! && $referer eq $uri;
    return undef;
}

# <LJFUNC>
# name: LJ::form_auth
# class: web
# des: Creates an authentication token to be used later to verify that a form
#      submission came from a particular user.
# args: raw?
# des-raw: boolean; If true, returns only the token (no HTML).
# returns: HTML hidden field to be inserted into the output of a page.
# </LJFUNC>
sub form_auth {
    my $raw = shift;
    my $chal = $LJ::REQ_GLOBAL{form_auth_chal};

    unless ($chal) {
        my $remote = LJ::get_remote();
        my $id     = $remote ? $remote->id : 0;
        my $sess   = $remote && $remote->session ? $remote->session->id : LJ::UniqCookie->current_uniq;

        my $auth = join('-', LJ::rand_chars(10), $id, $sess);
        $chal = LJ::challenge_generate(86400, $auth);
        $LJ::REQ_GLOBAL{form_auth_chal} = $chal;
    }

    return $raw ? $chal : LJ::html_hidden("lj_form_auth", $chal);
}

# <LJFUNC>
# name: LJ::check_form_auth
# class: web
# des: Verifies form authentication created with [func[LJ::form_auth]].
# returns: Boolean; true if the current data in %POST is a valid form, submitted
#          by the user in $remote using the current session,
#          or false if the user has changed, the challenge has expired,
#          or the user has changed session (logged out and in again, or something).
# </LJFUNC>
sub check_form_auth {
    my $formauth = shift || $BMLCodeBlock::POST{'lj_form_auth'};
    return 0 unless $formauth;

    my $remote = LJ::get_remote();
    my $id     = $remote ? $remote->id : 0;
    my $sess   = $remote && $remote->session ? $remote->session->id : LJ::UniqCookie->current_uniq;

    # check the attributes are as they should be
    my $attr = LJ::get_challenge_attributes($formauth);
    my ($randchars, $chal_id, $chal_sess) = split(/\-/, $attr);

    return 0 unless $id   == $chal_id;
    return 0 unless $sess eq $chal_sess;

    # check the signature is good and not expired
    my $opts = { dont_check_count => 1 };  # in/out
    LJ::challenge_check($formauth, $opts);
    return $opts->{valid} && ! $opts->{expired};
}

# <LJFUNC>
# name: LJ::create_qr_div
# class: web
# des: Creates the hidden div that stores the QuickReply form.
# returns: undef upon failure or HTML for the div upon success
# args: user, remote, ditemid, stylemine, userpic
# des-u: user object or userid for journal reply in.
# des-ditemid: ditemid for this comment.
# des-stylemine: if the user has specified style=mine for this page.
# des-userpic: alternate default userpic.
# </LJFUNC>
sub create_qr_div {

    my ($user, $ditemid, $stylemine, $userpic, $viewing_thread, $text_hint) = @_;
    my $u = LJ::want_user($user);
    my $remote = LJ::get_remote();
    return undef unless $u && $remote && $ditemid;
    return undef if $remote->underage;

    $stylemine ||= 0;
    my $qrhtml;

    LJ::load_user_props($remote, "opt_no_quickreply");
    return undef if $remote->{'opt_no_quickreply'};

    $qrhtml .= "<div id='qrformdiv'><form id='qrform' name='qrform' method='POST' action='$LJ::SITEROOT/talkpost_do.bml'>";
    $qrhtml .= LJ::form_auth();

    my $stylemineuri = $stylemine ? "style=mine&" : "";
    my $basepath =  LJ::journal_base($u) . "/$ditemid.html?${stylemineuri}";
    my $usertype;

    if ($remote->is_identity && $remote->is_trusted_identity) {
        $usertype = lc($remote->identity->short_code) . '_cookie';
    } else {
        $usertype = 'cookieuser';
    }

    $qrhtml .= LJ::html_hidden({'name' => 'replyto', 'id' => 'replyto', 'value' => ''},
                               {'name' => 'parenttalkid', 'id' => 'parenttalkid', 'value' => ''},
                               {'name' => 'journal', 'id' => 'journal', 'value' => $u->{'user'}},
                               {'name' => 'itemid', 'id' => 'itemid', 'value' => $ditemid},
                               {'name' => 'usertype', 'id' => 'usertype', 'value' => $usertype },
                               {'name' => 'qr', 'id' => 'qr', 'value' => '1'},
                               {'name' => 'cookieuser', 'id' => 'cookieuser', 'value' => $remote->{'user'}},
                               {'name' => 'dtid', 'id' => 'dtid', 'value' => ''},
                               {'name' => 'basepath', 'id' => 'basepath', 'value' => $basepath},
                               {'name' => 'stylemine', 'id' => 'stylemine', 'value' => $stylemine},
                               {'name' => 'viewing_thread', 'id' => 'viewing_thread', 'value' => $viewing_thread},
                               );

    # rate limiting challenge
    {
        my ($time, $secret) = LJ::get_secret();
        my $rchars = LJ::rand_chars(20);
        my $chal = $ditemid . "-$u->{userid}-$time-$rchars";
        my $res = Digest::MD5::md5_hex($secret . $chal);
        $qrhtml .= LJ::html_hidden("chrp1", "$chal-$res");
    }

    # Start making the div itself
    $qrhtml .= "<table style='border: 1px solid black'>";
    $qrhtml .= "<tr valign='center'>";
    $qrhtml .= "<td align='right'><b>".BML::ml('/talkpost.bml.opt.from')."</b></td><td align='left'>";
    $qrhtml .= LJ::ljuser($remote->{'user'});
    $qrhtml .= "</td><td align='center'>";

    my (%userpicmap, $defaultpicurl);

    # Userpic selector
    {
        my %res;
        LJ::do_request({ "mode" => "login",
                         "ver" => ($LJ::UNICODE ? "1" : "0"),
                         "user" => $remote->{'user'},
                         "getpickws" => 1,
                         'getpickwurls' => 1, },
                       \%res, { "noauth" => 1, "userid" => $remote->{'userid'}}
                       );

        if ($res{'pickw_count'}) {
            $qrhtml .= BML::ml('/talkpost.bml.label.picturetouse2',
                               {
                                   'aopts'=>"href='$LJ::SITEROOT/allpics.bml?user=$remote->{'user'}'"});
            my @pics;
            for (my $i=1; $i<=$res{'pickw_count'}; $i++) {
                push @pics, $res{"pickw_$i"};
            }
            @pics = sort { lc($a) cmp lc($b) } @pics;
            $qrhtml .= LJ::html_select({'name' => 'prop_picture_keyword',
                                        'selected' => $userpic, 'id' => 'prop_picture_keyword', 'tabindex' => '8' },
                                       ("", BML::ml('/talkpost.bml.opt.defpic'), map { ($_, $_) } @pics));

            # userpic browse button
            $qrhtml .= qq {
                <input type="button" id="lj_userpicselect" value="Browse" onclick="QuickReply.userpicSelect()" tabindex="9" />
                } unless $LJ::DISABLED{userpicselect} || ! $remote->get_cap('userpicselect');

            $qrhtml .= LJ::help_icon_html("userpics", " ");

            foreach my $i (1 .. $res{'pickw_count'}) {
                $userpicmap{$res{"pickw_$i"}} = $res{"pickwurl_$i"};
            }

            if (my $upi = $remote->userpic) {
                $defaultpicurl = $upi->url;
            }
        }
    }

    $qrhtml .= "</td></tr>";

    $qrhtml .= "<tr><td align='right' valign='top'>";
    $qrhtml .= "<b>".BML::ml('/talkpost.bml.opt.subject')."</b></td>";
    $qrhtml .= "<td colspan='2' align='left'>";
    $qrhtml .= "<input class='textbox' type='text' size='50' maxlength='100' name='subject' id='subject' value='' tabindex='10' />";
    
    $qrhtml .= "<div id=\"subjectCaptionText\">" . $text_hint . "</div>" if $text_hint;
    
    $qrhtml .= "</td></tr>";
    
    $qrhtml .= "<tr valign='top'>";
    $qrhtml .= "<td align='right'><b>".BML::ml('/talkpost.bml.opt.message')."</b></td>";
    $qrhtml .= "<td colspan='3' style='width: 90%'>";

    $qrhtml .= "<textarea class='textbox' rows='10' cols='50' wrap='soft' name='body' id='body' style='width: 99%' tabindex='20'></textarea>";
    $qrhtml .= "</td></tr>";

    $qrhtml .= LJ::run_hook('extra_quickreply_rows', {
        'user'    => $user,
        'ditemid' => $ditemid,
    });

    $qrhtml .= "<tr><td>&nbsp;</td>";
    $qrhtml .= "<td colspan='3' align='left'>";

    $qrhtml .= LJ::html_submit('submitpost', BML::ml('/talkread.bml.button.post'),
                               { 'id' => 'submitpost',
                                 'raw' => q|onclick="if (QuickReply.check()){ QuickReply.submit() }" tabindex='30' |,
                                 });

    $qrhtml .= "&nbsp;" . LJ::html_submit('submitmoreopts', BML::ml('/talkread.bml.button.more'),
                                          { 'id' => 'submitmoreopts', 'tabindex' => '31',
                                            'raw' => 'onclick="if (QuickReply.more()){ QuickReply.submit() }"'
                                            });
    if ($LJ::SPELLER) {
        $qrhtml .= "&nbsp;<input type='checkbox' name='do_spellcheck' value='1' id='do_spellcheck' tabindex='32' /> <label for='do_spellcheck'>";
        $qrhtml .= BML::ml('/talkread.bml.qr.spellcheck');
        $qrhtml .= "</label>";
    }

    LJ::load_user_props($u, 'opt_logcommentips');
    if ($u->{'opt_logcommentips'} eq 'A') {
        $qrhtml .= '<br />';
        $qrhtml .= LJ::deemp(BML::ml('/talkpost.bml.logyourip'));
        $qrhtml .= LJ::help_icon_html("iplogging", " ");
    }

    $qrhtml .= "</td></tr></table>";
    $qrhtml .= "</form></div>";

    my $ret;
    $ret = "<script type=\"text/javascript\">\n";

    $qrhtml = LJ::ejs($qrhtml);

    # here we create some separate fields for saving the quickreply entry
    # because the browser will not save to a dynamically-created form.

    my $qrsaveform .= LJ::ejs(LJ::html_hidden(
                                      {'name' => 'saved_subject', 'id' => 'saved_subject'},
                                      {'name' => 'saved_body', 'id' => 'saved_body'},
                                      {'name' => 'saved_spell', 'id' => 'saved_spell'},
                                      {'name' => 'saved_upic', 'id' => 'saved_upic'},
                                      {'name' => 'saved_dtid', 'id' => 'saved_dtid'},
                                      {'name' => 'saved_ptid', 'id' => 'saved_ptid'},
                                      ));

    my $userpicmap = LJ::JSON->to_json(\%userpicmap);
    $ret .= qq{
               var userpicmap = $userpicmap;
               var defaultpicurl = "$defaultpicurl";
               document.write("$qrsaveform");
               var de = document.createElement('div');
               de.id = 'qrdiv';
               de.innerHTML = "$qrhtml";
               de.style.display = 'none';
               document.body.insertBefore(de, document.body.firstChild);
           };

    $ret .= "</script>";

    return $ret;
}

# <LJFUNC>
# name: LJ::make_qr_link
# class: web
# des: Creates the link to toggle the QR reply form or if
#      JavaScript is not enabled, then forwards the user through
#      to replyurl.
# returns: undef upon failure or HTML for the link
# args: dtid, basesubject, linktext, replyurl
# des-dtid: dtalkid for this comment
# des-basesubject: parent comment's subject
# des-linktext: text for the user to click
# des-replyurl: URL to forward user to if their browser
#               does not support QR.
# </LJFUNC>
sub make_qr_link
{
    my ($dtid, $basesubject, $linktext, $replyurl) = @_;

    return undef unless defined $dtid && $linktext && $replyurl;

    my $remote = LJ::get_remote();
    LJ::load_user_props($remote, "opt_no_quickreply");
    unless ($remote->{'opt_no_quickreply'}) {
        my $pid = int($dtid / 256);

        $basesubject =~ s/^(Re:\s*)*//i;
        $basesubject = "Re: $basesubject" if $basesubject;
        $basesubject = LJ::ehtml(LJ::ejs($basesubject));
        my $onclick = "return QuickReply.reply('$dtid',$pid,'$basesubject')";

        my $ju;
        $ju = LJ::load_userid(LJ::Request->notes('journalid')) if LJ::Request->is_inited and LJ::Request->notes('journalid');

        $onclick = "" if $ju->{'opt_whocanreply'} eq 'friends' and $remote and not LJ::is_friend($ju, $remote);
        return "<a href=\"$replyurl\" onclick=\"$onclick\">$linktext</a>";
    } else { # QR Disabled
        return "<a href=\"$replyurl\">$linktext</a>";
    }
}

# <LJFUNC>
# name: LJ::get_lastcomment
# class: web
# des: Looks up the last talkid and journal the remote user posted in.
# returns: talkid, jid
# args:
# </LJFUNC>
sub get_lastcomment {
    my $remote = LJ::get_remote();
    return (undef, undef) unless $remote;

    # Figure out their last post
    my $memkey = [$remote->{'userid'}, "lastcomm:$remote->{'userid'}"];
    my $memval = LJ::MemCache::get($memkey);
    my ($jid, $talkid);
    ($jid, $talkid) = split(/:/, $memval) if $memval;

    return ($talkid, $jid);
}

# <LJFUNC>
# name: LJ::make_qr_target
# class: web
# des: Returns a div usable for QuickReply boxes.
# returns: HTML for the div
# args:
# </LJFUNC>
sub make_qr_target {
    my $name = shift;

    return "<div id='ljqrt$name' name='ljqrt$name'></div>";
}

# <LJFUNC>
# name: LJ::set_lastcomment
# class: web
# des: Sets the lastcomm memcached key for this user's last comment.
# returns: undef on failure
# args: u, remote, dtalkid, life?
# des-u: Journal they just posted in, either u or userid
# des-remote: Remote user
# des-dtalkid: Talkid for the comment they just posted
# des-life: How long, in seconds, the memcached key should live.
# </LJFUNC>
sub set_lastcomment
{
    my ($u, $remote, $dtalkid, $life) = @_;

    my $userid = LJ::want_userid($u);
    return undef unless $userid && $remote && $dtalkid;

    # By default, this key lasts for 10 seconds.
    $life ||= 10;

    # Set memcache key for highlighting the comment
    my $memkey = [$remote->{'userid'}, "lastcomm:$remote->{'userid'}"];
    LJ::MemCache::set($memkey, "$userid:$dtalkid", time()+$life);

    return;
}

sub deemp {
    "<span class='de'>$_[0]</span>";
}

# <LJFUNC>
# name: LJ::entry_form
# class: web
# des: Returns a properly formatted form for creating/editing entries.
# args: head, onload, opts
# des-head: string reference for the <head> section (JavaScript previews, etc).
# des-onload: string reference for JavaScript functions to be called on page load
# des-opts: hashref of keys/values:
#           mode: either "update" or "edit", depending on context;
#           datetime: date and time, formatted yyyy-mm-dd hh:mm;
#           remote: remote u object;
#           subject: entry subject;
#           event: entry text;
#           richtext: allow rich text formatting;
#           auth_as_remote: bool option to authenticate as remote user, pre-filling pic/friend groups/etc.
# return: form to include in BML pages.
# </LJFUNC>
sub entry_form {
    my $widget = LJ::Widget::EntryForm->new;

    $widget->set_data(@_);
    return $widget->render;
}

# entry form subject
sub entry_form_subject_widget {
    my $class = shift;

    if ($class) {
        $class = qq { class="$class" };
    }
    return qq { <input name="subject" $class/> };
}

# entry form hidden date field
sub entry_form_date_widget {
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
    $year+=1900;
    $mon=sprintf("%02d", $mon+1);
    $mday=sprintf("%02d", $mday);
    $min=sprintf("%02d", $min);
    return LJ::html_hidden({'name' => 'date_ymd_yyyy', 'value' => $year, 'id' => 'update_year'},
                           {'name' => 'date_ymd_dd', 'value'  => $mday, 'id' => 'update_day'},
                           {'name' => 'date_ymd_mm', 'value'  => $mon,  'id' => 'update_mon'},
                           {'name' => 'hour', 'value' => $hour, 'id' => 'update_hour'},
                           {'name' => 'min', 'value'  => $min,  'id' => 'update_min'});
}

# entry form event text box
sub entry_form_entry_widget {
    my $class = shift;

    if ($class) {
        $class = qq { class="$class" };
    }

    return qq { <textarea cols=50 rows=10 name="event" $class></textarea> };
}


# entry form "journals can post to" dropdown
# NOTE!!! returns undef if no other journals user can post to
sub entry_form_postto_widget {
    my $remote = shift;

    return undef unless LJ::isu($remote);

    my $ret;
    # log in to get journals can post to
    my $res;
    $res = LJ::Protocol::do_request("login", {
        "ver" => $LJ::PROTOCOL_VER,
        "username" => $remote->{'user'},
    }, undef, {
        "noauth" => 1,
        "u" => $remote,
    });

    return undef unless $res;

    my @journals = map { $_, $_ } @{$res->{'usejournals'}};

    return undef unless @journals;

    push @journals, $remote->{'user'};
    push @journals, $remote->{'user'};
    @journals = sort @journals;
    $ret .= LJ::html_select({ 'name' => 'usejournal', 'selected' => $remote->{'user'}}, @journals) . "\n";
    return $ret;
}

sub entry_form_security_widget {
    my $ret = '';

    my @secs = ("public", BML::ml('label.security.public'),
                "private", BML::ml('label.security.private'),
                "friends", BML::ml('label.security.friends'));

    $ret .= LJ::html_select({ 'name' => 'security'},
                            @secs);

    return $ret;
}

sub entry_form_tags_widget {
    my $ret = '';

    return '' if $LJ::DISABLED{tags};

    $ret .= LJ::html_text({
                              'name'      => 'prop_taglist',
                              'size'      => '35',
                              'maxlength' => '255',
                          });
    $ret .= LJ::help_icon('addtags');

    return $ret;
}

# <LJFUNC>
# name: LJ::entry_form_decode
# class: web
# des: Decodes an entry_form into a protocol-compatible hash.
# info: Generate form with [func[LJ::entry_form]].
# args: req, post
# des-req: protocol request hash to build.
# des-post: entry_form POST contents.
# returns: req
# </LJFUNC>
sub entry_form_decode
{
    my ($req, $POST) = @_;

    # find security
    my $sec = "public";
    my $amask = 0;
    if ($POST->{'security'} eq "private") {
        $sec = "private";
    } elsif ($POST->{'security'} eq "friends") {
        $sec = "usemask"; $amask = 1;
    } elsif ($POST->{'security'} eq "custom") {
        $sec = "usemask";
        foreach my $bit (1..30) {
            next unless $POST->{"custom_bit_$bit"};
            $amask |= (1 << $bit);
        }
    }
    $req->{'security'} = $sec;
    $req->{'allowmask'} = $amask;

    # date/time
    my $date = LJ::html_datetime_decode({ 'name' => "date_ymd", }, $POST);
    my ($year, $mon, $day) = split( /\D/, $date);
    my ($hour, $min) = ($POST->{'hour'}, $POST->{'min'});

    # TEMP: ease golive by using older way of determining differences
    my $date_old = LJ::html_datetime_decode({ 'name' => "date_ymd_old", }, $POST);
    my ($year_old, $mon_old, $day_old) = split( /\D/, $date_old);
    my ($hour_old, $min_old) = ($POST->{'hour_old'}, $POST->{'min_old'});

    my $different = $POST->{'min_old'} && (($year ne $year_old) || ($mon ne $mon_old)
                    || ($day ne $day_old) || ($hour ne $hour_old) || ($min ne $min_old));

    # this value is set when the JS runs, which means that the user-provided
    # time is sync'd with their computer clock. otherwise, the JS didn't run,
    # so let's guess at their timezone.
    if ($POST->{'date_diff'} || $POST->{'date_diff_nojs'} || $different) {
        delete $req->{'tz'};
        $req->{'year'} = $year;
        $req->{'mon'} = $mon;
        $req->{'day'} = $day;
        $req->{'hour'} = $hour;
        $req->{'min'} = $min;
    }

    # copy some things from %POST
    foreach (qw(subject
                prop_picture_keyword prop_current_moodid
                prop_current_mood prop_current_music
                prop_opt_screening prop_opt_noemail
                prop_opt_preformatted prop_opt_nocomments prop_opt_lockcomments
                prop_current_location prop_current_coords
                prop_taglist prop_qotdid)) {
        $req->{$_} = $POST->{$_};
    }

    if ($POST->{"subject"} eq BML::ml('entryform.subject.hint2')) {
        $req->{"subject"} = "";
    }

    $req->{"prop_opt_preformatted"} ||= $POST->{'switched_rte_on'} ? 1 :
        $POST->{'event_format'} eq "preformatted" ? 1 : 0;
    $req->{"prop_opt_nocomments"}   ||= $POST->{'comment_settings'} eq "nocomments" ? 1 : 0;
    $req->{'prop_opt_lockcomments'} ||= $POST->{'comment_settings'} eq 'lockcomments' ? 1 : 0;
    $req->{"prop_opt_noemail"}      ||= $POST->{'comment_settings'} eq "noemail" ? 1 : 0;
    $req->{'prop_opt_backdated'}      = $POST->{'prop_opt_backdated'} ? 1 : 0;
    $req->{'prop_copyright'} = $POST->{'prop_copyright'} ? 'P' : 'C' if LJ::is_enabled('default_copyright', LJ::get_remote()) 
                                    && $POST->{'defined_copyright'};

    if (LJ::is_enabled("content_flag")) {
        $req->{prop_adult_content} = $POST->{prop_adult_content};
        $req->{prop_adult_content} = ""
            unless $req->{prop_adult_content} eq "none" || $req->{prop_adult_content} eq "concepts" || $req->{prop_adult_content} eq "explicit";
    }

    # nuke taglists that are just blank
    $req->{'prop_taglist'} = "" unless $req->{'prop_taglist'} && $req->{'prop_taglist'} =~ /\S/;

    # Convert the rich text editor output back to parsable lj tags.
    my $event = $POST->{'event'};
    if ($POST->{'switched_rte_on'}) {
        $req->{"prop_used_rte"} = 1;

        # We want to see if we can hit the fast path for cleaning
        # if they did nothing but add line breaks.
        my $attempt = $event;
        $attempt =~ s!<br />!\n!g;

        if ($attempt !~ /<\w/) {
            $event = $attempt;

            # Make sure they actually typed something, and not just hit
            # enter a lot
            $attempt =~ s!(?:<p>(?:&nbsp;|\s)+</p>|&nbsp;)\s*?!!gm;
            $event = '' unless $attempt =~ /\S/;

            $req->{'prop_opt_preformatted'} = 0;
        } else {
            # Old methods, left in for compatibility during code push
            $event =~ s!<lj-cut class="ljcut">!<lj-cut>!gi;

            $event =~ s!<lj-raw class="ljraw">!<lj-raw>!gi;
        }
    } else {
        $req->{"prop_used_rte"} = 0;
    }

    $req->{'event'} = $event;

    ## see if an "other" mood they typed in has an equivalent moodid
    if ($POST->{'prop_current_mood'}) {
        if (my $id = LJ::mood_id($POST->{'prop_current_mood'})) {
            $req->{'prop_current_moodid'} = $id;
            delete $req->{'prop_current_mood'};
        }
    }

    # process site-specific options
    LJ::run_hooks('decode_entry_form', $POST, $req);
    
    return $req;
}

# returns exactly what was passed to it normally.  but in developer mode,
# it includes a link to a page that automatically grants the needed priv.
sub no_access_error {
    my ($text, $priv, $privarg) = @_;
    if ($LJ::IS_DEV_SERVER) {
        my $remote = LJ::get_remote();
        return "$text <b>(DEVMODE: <a href='/admin/priv/?devmode=1&user=$remote->{user}&priv=$priv&arg=$privarg'>Grant $priv\[$privarg\]</a>)</b>";
    } else {
        return $text;
    }
}

# Data::Dumper for JavaScript
sub js_dumper {
    my $obj = shift;
    if (ref $obj) {
        return LJ::JSON->to_json($obj);
    } else {
        return ($obj =~ /^[1-9]\d*$/) ?  $obj : '"' . LJ::ejs($obj) . '"';
    }
}

{
    my %stat_cache = ();  # key -> {lastcheck, modtime}
    sub _file_modtime {
        my ($key, $now) = @_;
        if (my $ci = $stat_cache{$key}) {
            if ($ci->{lastcheck} > $now - 10) {
                return $ci->{modtime};
            }
        }

        my $file = "$LJ::HOME/htdocs/$key";
        my $mtime = (stat($file))[9];
        $stat_cache{$key} = { lastcheck => $now, modtime => $mtime };
        return $mtime;
    }
}

sub stat_src_to_url {
    my $url = shift;
    my $mtime = _file_modtime("/stc" . $url, time);
    return $LJ::STATPREFIX . $url . "?v=" . $mtime;
}


## Support for conditional file inclusion:
## e.g. LJ::need_res( {condition => 'IE'}, 'ie.css', 'myie.css') will result in
## <!--[if IE]><link rel="stylesheet" type="text/css" href="$statprefix/..." /><![endif]-->
## Support 'args' option. Example: LJ::need_res( { args => 'media="screen"' }, 'stc/ljtimes/iframe.css' );
## Results in: <link rel="stylesheet" type="text/css" href="http://stat.lj-3-32.bulyon.local/ljtimes/iframe.css?v=1285833891" media="screen"/>
## LJ::need_res( {clean_list} ) will suppress ALL previous resources and do NOTHING more!
sub need_res {
    my $opts = (ref $_[0]) ? shift : {};
    my @keys = @_;

    if ($opts->{clean_list}) {
        %LJ::NEEDED_RES = ();
        @LJ::NEEDED_RES = ();
        return;
    }

    ## Filter included res.
    ## if resource is a part of a common set, skip it here
    ## and add to page inside the set.
    @keys = grep {
                ## check common JS sources.
                if ($LJ::STRICTLY_INCLUDED_JS_H{$_}){
                    $LJ::NEEDED_RES{include_common_js} = 1;
                    0; ## include this file as a part of common sources set.
                } else {
                    1; ## include them as is.
                }
            } @keys;

    foreach my $reskey (@keys) {
        die "Bogus reskey $reskey" unless $reskey =~ m!^(js|stc)/!;
        unless (exists $LJ::NEEDED_RES{$reskey}) {
            push @LJ::NEEDED_RES, $reskey;
        }
        $LJ::NEEDED_RES{$reskey} = $opts;
    }
}

sub include_raw  {
    my $type = shift;
    my $code = shift;

    die "Bogus include type: $type"
        unless $type =~ m!^(js|css|js_link|css_link)$!;

    push @LJ::INCLUDE_RAW => [$type, $code];
}

sub res_includes {
    my $opts = shift || {};
    my $only_needed = $opts->{only_needed}; # do not include defaults

    # TODO: automatic dependencies from external map and/or content of files,
    # currently it's limited to dependencies on the order you call LJ::need_res();
    my $ret = "";
    my $do_concat = $LJ::IS_SSL ? $LJ::CONCAT_RES_SSL : $LJ::CONCAT_RES;

    # all conditions must be complete here
    # example: cyr/non-cyr flag changed at settings page
    LJ::run_hooks('sitewide_resources') unless $only_needed;

    # use correct root and prefixes for SSL pages
    my ($siteroot, $imgprefix, $statprefix, $jsprefix, $wstatprefix);
    if ($LJ::IS_SSL) {
        $siteroot = $LJ::SSLROOT;
        $imgprefix = $LJ::SSLIMGPREFIX;
        $statprefix = $LJ::SSLSTATPREFIX;
        $jsprefix = $LJ::SSLJSPREFIX;
        $wstatprefix = $LJ::SSLWSTATPREFIX;
    } else {
        $siteroot = $LJ::SITEROOT;
        $imgprefix = $LJ::IMGPREFIX;
        $statprefix = $LJ::STATPREFIX;
        $jsprefix = $LJ::JSPREFIX;
        $wstatprefix = $LJ::WSTATPREFIX;
    }

    # find current journal
    my $journal_base = '';
    my $journal = '';
    if (LJ::Request->is_inited) {
        my $journalid = LJ::Request->notes('journalid');

        my $ju;
        $ju = LJ::load_userid($journalid) if $journalid;

        if ($ju) {
            $journal_base = $ju->journal_base;
            $journal = $ju->{user};
        }
    }

    my $remote = LJ::get_remote();
    my $hasremote = $remote ? 1 : 0;
    my $remote_is_suspended = $remote && $remote->is_suspended ? 1 : 0;

    # ctxpopup prop
    my $ctxpopup = 1;
    $ctxpopup = 0 if $remote && ! $remote->prop("opt_ctxpopup");

    # poll for esn inbox updates?
    my $inbox_update_poll = $LJ::DISABLED{inbox_update_poll} ? 0 : 1;

    # are media embeds enabled?
    my $embeds_enabled = $LJ::DISABLED{embed_module} ? 0 : 1;

    # esn ajax enabled?
    my $esn_async = LJ::conf_test($LJ::DISABLED{esn_ajax}) ? 0 : 1;

    my $default_copyright = $remote ? ($remote->prop("default_copyright") || 'P') : 'P';

    my $ljentry = LJ::Request->notes('ljentry') || ''; # url
    my %site = (
                imgprefix => "$imgprefix",
                siteroot => "$siteroot",
                statprefix => "$statprefix",
                currentJournalBase => "$journal_base",
                currentJournal => "$journal",
                currentEntry => $ljentry,
                has_remote => $hasremote,
                remote_can_track_threads => $remote && $remote->get_cap('track_thread'),
                remote_is_suspended => $remote_is_suspended,
                ctx_popup => $ctxpopup,
                inbox_update_poll => $inbox_update_poll,
                media_embed_enabled => $embeds_enabled,
                esn_async => $esn_async,
                server_time => time(),
                remoteJournalBase => $remote && $remote->journal_base,
                remoteUser => $remote && $remote->user,
                );
    $site{default_copyright} = $default_copyright if LJ::is_enabled('default_copyright', $remote);
    $site{is_dev_server} = 1 if $LJ::IS_DEV_SERVER;

    $site{inbox_unread_count} = $remote->notification_inbox->unread_count if $remote and LJ::is_enabled('inbox_unread_count_in_head');

    LJ::run_hooks('add_to_site_js', \%site);

    my $site_params = LJ::js_dumper(\%site);

    # include standard JS info
    unless ( $only_needed ) {
        my $jsml_out = LJ::JSON->to_json(\%LJ::JSML);
        $ret .= qq {
            <script type="text/javascript">
                Site = window.Site || {};
                Site.ml_text = $jsml_out;
                (function(){
                    var p = $site_params, i;
                    for (i in p) Site[i] = p[i];
                })();
           </script>
        };
    }

    my $now = time();
    my %list;   # type -> condition -> args -> [list of files];
    my %oldest; # type -> condition -> args -> $oldest
    my $add = sub {
        my ($type, $what, $modtime, $opts) = @_;

        $opts ||= {};
        my $condition = $opts->{condition};
        $condition ||= ''; ## by default, no condtion is present
        
        my $args = $opts->{args};
        $args ||= '';

        # in the concat-res case, we don't directly append the URL w/
        # the modtime, but rather do one global max modtime at the
        # end, which is done later in the tags function.
        $what .= "?v=$modtime" unless $do_concat;

        push @{$list{$type}{$condition}{$args} ||= []}, $what;
        $oldest{$type}{$condition}{$args} = $modtime if $modtime > $oldest{$type}{$condition}{$args};
    };


    ## Some of basic JS sources are widely used.
    ## Include all even required only one of them.
    if ($LJ::NEEDED_RES{include_common_js}){
        foreach my $js (@LJ::STRICTLY_INCLUDED_JS){
            my $mtime = _file_modtime("js/$js", $now);
            $add->(common_js => $js, $mtime); ## without "js" prefix
        }
    }

    foreach my $key (@LJ::NEEDED_RES) {
        my $path;
        my $mtime = _file_modtime($key, $now);
        $path = $key;

        # if we want to also include a local version of this file, include that too
        if (@LJ::USE_LOCAL_RES) {
            if (grep { lc $_ eq lc $key } @LJ::USE_LOCAL_RES) {
                my $inc = $key;
                $inc =~ s/(\w+)\.(\w+)$/$1-local.$2/;
                LJ::need_res($inc);
            }
        }

        if ($path =~ m!^js/(.+)!) {
            $add->('js', $1, $mtime, $LJ::NEEDED_RES{$key});
        } elsif ($path =~ /\.css$/ && $path =~ m!^(w?)stc/(.+)!) {
            $add->("${1}stccss", $2, $mtime, $LJ::NEEDED_RES{$key});
        } elsif ($path =~ /\.js$/ && $path =~ m!^(w?)stc/(.+)!) {
            $add->("${1}stcjs", $2, $mtime, $LJ::NEEDED_RES{$key});
        }
    }

    my $tags = sub {
        my ($type, $template) = @_;
        return unless $list{$type};
        
        foreach my $cond (sort {length($a) <=> length($b)} keys %{ $list{$type} }) {
            foreach my $args (sort {length($a) <=> length($b)} keys %{ $list{$type}{$cond} }) {
                my $list = $list{$type}{$cond}{$args};
                my $start = ($cond) ? "<!--[if $cond]>" : "";
                my $end = ($cond) ? "<![endif]-->\n" : "\n";
                
                if ($do_concat) {
                    my $csep = join(',', @$list);
                    $csep .= "?v=" . $oldest{$type}{$cond}{$args};
                    my $inc = $template;
                    $inc =~ s/__+/??$csep/;
                    $inc =~ s/##/$args/;
                    $ret .= $start . $inc . $end;
                } else {
                    foreach my $item (@$list) {
                        my $inc = $template;
                        $inc =~ s/__+/$item/;
                        $inc =~ s/##/$args/;
                        $ret .= $start . $inc . $end;
                    }
                }
            }
        }
    };

    ## To ensure CSS files are downloaded in parallel, always include external CSS before external JavaScript. 
    ##  (C) http://code.google.com/speed/page-speed/
    ##
    $tags->("stccss",  "<link rel=\"stylesheet\" type=\"text/css\" href=\"$statprefix/___\" ##/>");
    $tags->("wstccss", "<link rel=\"stylesheet\" type=\"text/css\" href=\"$wstatprefix/___\" ##/>");
    $tags->("common_js", "<script type=\"text/javascript\" src=\"$jsprefix/___\"></script>");
    $tags->("js",      "<script type=\"text/javascript\" src=\"$jsprefix/___\"></script>");
    $tags->("stcjs",   "<script type=\"text/javascript\" src=\"$statprefix/___\"></script>");
    $tags->("wstcjs",  "<script type=\"text/javascript\" src=\"$wstatprefix/___\"></script>");

    return $ret if $only_needed;

    # add raw js/css
    foreach my $inc (@LJ::INCLUDE_RAW) {
        my ( $type, $code ) = @$inc;

        if ($type eq 'js'){
            $ret .= qq|<script type="text/javascript">\r\n$code</script>\r\n|;
        } elsif ($type eq 'css'){
            $ret .= qq|<style>\r\n$code</style>\n|;
        } elsif ( $type eq 'js_link' ) {
            $ret .= qq{<script type="text/javascript" src="$code"></script>\r\n};
        } elsif ( $type eq 'css_link' ) {
            $ret .= qq{<link rel="stylesheet" type="text/css" href="$code" />};
        }
    }

    return $ret;
}

# Returns HTML of a dynamic tag could given passed in data
# Requires hash-ref of tag => { url => url, value => value }
sub tag_cloud {
    my ($tags, $opts) = @_;

    # find sizes of tags, sorted
    my @sizes = sort { $a <=> $b } map { $tags->{$_}->{'value'} } keys %$tags;

    # remove duplicates:
    my %sizes = map { $_, 1 } @sizes;
    @sizes = sort { $a <=> $b } keys %sizes;

    my @tag_names = sort keys %$tags;

    my $percentile = sub {
        my $n = shift;
        my $total = scalar @sizes;
        for (my $i = 0; $i < $total; $i++) {
            next if $n > $sizes[$i];
            return $i / $total;
        }
    };

    my $base_font_size = 8;
    my $font_size_range = $opts->{font_size_range} || 25;
    my $ret .= "<div id='tagcloud' class='tagcloud'>";
    my %tagdata = ();
    foreach my $tag (@tag_names) {
        my $tagurl = $tags->{$tag}->{'url'};
        my $ct     = $tags->{$tag}->{'value'};
        my $pt     = int($base_font_size + $percentile->($ct) * $font_size_range);
        $ret .= "<a ";
        $ret .= "id='taglink_$tag' " unless $opts->{ignore_ids};
        $ret .= "href='" . LJ::ehtml($tagurl) . "' style='font-size: ${pt}pt;'><span>";
        $ret .= LJ::ehtml($tag) . "</span></a>\n";

        # build hash of tagname => final point size for refresh
        $tagdata{$tag} = $pt;
    }
    $ret .= "</div>";

    return $ret;
}

sub get_next_ad_id {
    return ++$LJ::REQ_GLOBAL{'curr_ad_id'};
}

##
## Function LJ::check_page_ad_block. Return answer (true/false) to question:
## Should we show ad of this type on this page.
## Args: uri of the page and orient of the ad block (e.g. 'App-Confirm')
##
sub check_page_ad_block {
    my $uri = shift;
    my $orient = shift;

    # The AD_MAPPING hash may contain code refs
    # This allows us to choose an ad based on some logic
    # Example: If LJ::did_post() show 'App-Confirm' type ad
    my $ad_mapping = LJ::run_hook('get_ad_uri_mapping', $uri) ||
        LJ::conf_test($LJ::AD_MAPPING{$uri});

    return 1 if $ad_mapping eq $orient;
    return 1 if ref($ad_mapping) eq 'HASH' && $ad_mapping->{$orient};
    return;
}

# returns a hash with keys "layout" and "theme"
# "theme" is empty for S1 users
sub get_style_for_ads {
    my $u = shift;

    my %ret;
    $ret{layout} = "";
    $ret{theme} = "";

    # Values for custom layers, default themes, and S1 styles
    my $custom_layout = "custom_layout";
    my $custom_theme = "custom_theme";
    my $default_theme = "default_theme";
    my $s1_prefix = "s1_";

    if ($u->prop('stylesys') == 2) {
        my %style = LJ::S2::get_style($u);
        my $public = LJ::S2::get_public_layers();

        # get layout
        my $layout = $public->{$style{layout}}->{uniq}; # e.g. generator/layout
        $layout =~ s/\/\w+$//;

        # get theme
        # if the theme id == 0, then we have no theme for this layout (i.e. default theme)
        my $theme;
        if ($style{theme} == 0) {
            $theme = $default_theme;
        } else {
            $theme = $public->{$style{theme}}->{uniq}; # e.g. generator/mintchoc
            $theme =~ s/^\w+\///;
        }

        $ret{layout} = $layout ? $layout : $custom_layout;
        $ret{theme} = $theme ? $theme : $custom_theme;
    } else {
        my $view = LJ::Request->notes->{view};
        $view = "lastn" if $view eq "";

        if ($view =~ /^(?:friends|day|calendar|lastn)$/) {
            my $pubstyles = LJ::S1::get_public_styles();
            my $styleid = $u->prop("s1_${view}_style");

            my $layout = "";
            if ($pubstyles->{$styleid}) {
                $layout = $pubstyles->{$styleid}->{styledes}; # e.g. Clean and Simple
                $layout =~ s/\W//g;
                $layout =~ s/\s//g;
                $layout = lc $layout;
                $layout = $s1_prefix . $layout;
            }

            $ret{layout} = $layout ? $layout : $s1_prefix . $custom_layout;
        }
    }

    return %ret;
}

sub get_search_term {
    my $uri = shift;
    my $search_arg = shift;

    my %search_pages = (
        '/interests.bml' => 1,
        '/directory.bml' => 1,
        '/multisearch.bml' => 1,
    );

    return "" unless $search_pages{$uri};

    my $term = "";
    my $args = LJ::Request->args;
    if ($uri eq '/interests.bml') {
        if ($args =~ /int=([^&]+)/) {
            $term = $1;
        }
    } elsif ($uri eq '/directory.bml') {
        if ($args =~ /int_like=([^&]+)/) {
            $term = $1;
        }
    } elsif ($uri eq '/multisearch.bml') {
        $term = $search_arg;
    }

    # change +'s to spaces
    $term =~ s/\+/ /;

    return $term;
}


# this returns ad html given a search string
sub search_ads {
    my %opts = @_;

    return '' if LJ::conf_test($LJ::DISABLED{content_ads});

    return '' unless $LJ::USE_JS_ADCALL_FOR_SEARCH;

    my $remote = LJ::get_remote();

    return '' unless LJ::run_hook('should_show_ad', {
        ctx  => 'app',
        user => $remote,
        type => '',
    });

    return '' unless LJ::run_hook('should_show_search_ad');

    my $query = delete $opts{query} or croak "No search query specified in call to search_ads";
    my $count = int(delete $opts{count} || 1);
    my $adcount = int(delete $opts{adcount} || 3);

    my $adid = get_next_ad_id();
    my $divid = "ad_$adid";

    my @divids = map { "ad_$_" } (1 .. $count);

    my %adcall = (
                  u  => join(',', map { $adcount } @divids), # how many ads to show in each
                  r  => rand(),
                  q  => $query,
                  id => join(',', @divids),
                  p  => 'lj',
                  add => 'lj_content_ad',
                  remove => 'lj_inactive_ad',
                  );

    if ($remote) {
        $adcall{user} = $remote->id;
    }

    my $adparams = LJ::encode_url_string(\%adcall, 
                                         [ sort { length $adcall{$a} <=> length $adcall{$b} } 
                                           grep { length $adcall{$_} } 
                                           keys %adcall ] );

    # allow 24 bytes for escaping overhead
    $adparams = substr($adparams, 0, 1_000);

    my $url = $LJ::ADSERVER . '/google/?' . $adparams;

    my $adhtml;

    my $adcall = '';
    if (++$LJ::REQ_GLOBAL{'curr_search_ad_id'} == $count) {
        $adcall .= qq { <script charset="utf-8" id="ad${adid}s" src="$url"></script>\n };
        $adcall .= qq { <script language="javascript" src="http://www.google.com/afsonline/show_afs_ads.js"></script> };
    }

    $adhtml = qq {
        <div class="lj_inactive_ad" id="$divid" style="clear: left;">
            $adcall
        </div>
        <div class='lj_inactive_ad clear'>&nbsp;</div>
    };

    return $adhtml;
}

sub get_ads {
    LJ::run_hook('ADV_get_ad_html', @_);
}

sub should_show_ad {
    LJ::run_hook('ADV_should_show_ad', @_);
}

# modifies list of interests (appends tags of sponsored questions to the list)
# sponsored question may be taken
#   1. from argument of function: $opts = { extra => {qotd => ...} }, 
#   2. from URL args of /update.bml page (/update.bml?qotd=123)
#   3. from first displayed entry on the page
sub modify_interests_for_adcall {
    my $opts = shift;
    my $list = shift;

    my $qotd;
    if (ref $opts->{extra} && $opts->{extra}->{qotd}) {
        $qotd = $opts->{extra}->{qotd};
    } elsif (LJ::Request->is_inited && LJ::Request->notes('codepath') eq 'bml.update' && $BMLCodeBlock::GET{qotd}) {
        $qotd = $BMLCodeBlock::GET{qotd};
    } elsif (@LJ::SUP_LJ_ENTRY_REQ) {
        my ($journalid, $posterid, $ditemid) = @{ $LJ::SUP_LJ_ENTRY_REQ[0] };
        my $entry = LJ::Entry->new(LJ::load_userid($journalid), ditemid => $ditemid);
        if ($entry && $entry->prop("qotdid")) {
            $qotd = $entry->prop("qotdid");
        }
    }
    
    if ($qotd) {
        $qotd = LJ::QotD->get_single_question($qotd) unless ref $qotd;
        my $tags = LJ::QotD->remove_default_tags($qotd->{tags});
        if ($tags && $qotd->{is_special} eq "Y") {
            unshift @$list, $tags;
        }
    }
}

# this function will filter out blocked interests, as well filter out interests which
# cause the 
sub interests_for_adcall {
    my $u = shift;
    my %opts = @_;

    # base ad call is 300-400 bytes, we'll allow interests to be around 600
    # which is unlikely to go over IE's 1k URL limit.
    my $max_len = $opts{max_len} || 600;

    my $int_len = 0;

    my @interest_list = $u ? $u->notable_interests(100) : ();

    modify_interests_for_adcall(\%opts, \@interest_list);

    return join(',',
                grep { 

                    # not a blocked interest
                    ! defined $LJ::AD_BLOCKED_INTERESTS{$_} && 

                    # and we've not already got over 768 bytes of interests
                    # -- +1 is for comma
                    ($int_len += length($_) + 1) <= $max_len;
                        
                    } @interest_list
                );
}

# for use when calling an ad from BML directly
sub ad_display {
    my %opts = @_;

    # can specify whether the wrapper div on the ad is used or not
    my $use_wrapper = defined $opts{use_wrapper} ? $opts{use_wrapper} : 1;

    my $ret = LJ::ads(%opts);

    my $extra;
    if ($ret =~ /"ljad ljad(.+?)"/i) {
        # Add a badge ad above all skyscrapers
        # First, try to print a badge ad in journal context (e.g. S1 comment pages)
        # Then, if it doesn't print, print it in user context (e.g. normal app pages)
        if ($1 eq "skyscraper") {
            $extra = LJ::ads(type => $opts{'type'},
                             orient => 'Journal-Badge',
                             user => $opts{'user'},
                             search_arg => $opts{'search_arg'},
                             force => '1' );
            $extra = LJ::ads(type => $opts{'type'},
                             orient => 'App-Extra',
                             user => $opts{'user'},
                             search_arg => $opts{'search_arg'},
                             force => '1' )
                        unless $extra;
        }
        $ret = $extra . $ret
    }

    my $pagetype = $opts{orient};
    $pagetype =~ s/^BML-//;
    $pagetype = lc $pagetype;

    $ret = $opts{below_ad} ? "$ret<br />$opts{below_ad}" : $ret;
    $ret = $ret && $use_wrapper ? "<div class='ljadwrapper-$pagetype'>$ret</div>" : $ret;

    return $ret;
}

sub control_strip
{   
    return $LJ::DISABLED{control_strip_new} ? control_strip_old(@_) : control_strip_new(@_);
}

sub control_strip_new
{
    my %opts = @_;

    return LJ::ControlStrip->render($opts{user});
}

sub control_strip_old
{
    my %opts = @_;
    my $user = delete $opts{user};

    my $journal = LJ::load_user($user);
    my $show_strip = 1;
    if (LJ::are_hooks("show_control_strip")) {
        $show_strip = LJ::run_hook("show_control_strip", { user => $user });
    }

    return "" unless $show_strip;

    my $remote = LJ::get_remote();

    my $args = scalar LJ::Request->args;
    my $querysep = $args ? "?" : "";
    my $uri = "http://" . LJ::Request->header_in("Host") . LJ::Request->uri . $querysep . $args;
    $uri = LJ::eurl($uri);
    my $create_link = LJ::run_hook("override_create_link_on_navstrip", $journal) || "<a href='$LJ::SITEROOT/create.bml'>" . BML::ml('web.controlstrip.links.create', {'sitename' => $LJ::SITENAMESHORT}) . "</a>";

    # Build up some common links
    my %links = (
                 'login'             => "<a href='$LJ::SITEROOT/?returnto=$uri'>$BML::ML{'web.controlstrip.links.login'}</a>",
                 'home'              => "<a href='$LJ::SITEROOT/'>" . $BML::ML{'web.controlstrip.links.home'} . "</a>&nbsp;&nbsp; ",
                 'recent_comments'   => "<a href='$LJ::SITEROOT/tools/recent_comments.bml'>$BML::ML{'web.controlstrip.links.recentcomments'}</a>",
                 'manage_friends'    => "<a href='$LJ::SITEROOT/friends/'>$BML::ML{'web.controlstrip.links.managefriends'}</a>",
                 'manage_entries'    => "<a href='$LJ::SITEROOT/editjournal.bml'>$BML::ML{'web.controlstrip.links.manageentries'}</a>",
                 'invite_friends'    => "<a href='$LJ::SITEROOT/friends/invite.bml'>$BML::ML{'web.controlstrip.links.invitefriends'}</a>",
                 'create_account'    => $create_link,
                 'syndicated_list'   => "<a href='$LJ::SITEROOT/syn/list.bml'>$BML::ML{'web.controlstrip.links.popfeeds'}</a>",
                 'learn_more'        => LJ::run_hook('control_strip_learnmore_link') || "<a href='$LJ::SITEROOT/'>$BML::ML{'web.controlstrip.links.learnmore'}</a>",
                 'explore'           => "<a href='$LJ::SITEROOT/explore/'>" . BML::ml('web.controlstrip.links.explore', { sitenameabbrev => $LJ::SITENAMEABBREV }) . "</a>",
                 );

    if ($remote && $remote->is_person) {
        $links{'post_journal'} = "<a href='$LJ::SITEROOT/update.bml'>$BML::ML{'web.controlstrip.links.post2'}</a>&nbsp;&nbsp; ";
    }

    if ($remote) {
        $links{'view_friends_page'} = "<a href='" . $remote->journal_base . "/friends/'>$BML::ML{'web.controlstrip.links.viewfriendspage2'}</a>";
        $links{'add_friend'} = "<a href='$LJ::SITEROOT/friends/add.bml?user=$journal->{user}'>$BML::ML{'web.controlstrip.links.addfriend'}</a>";
        if ($journal->is_syndicated || $journal->is_news) {
            $links{'add_friend'} = "<a href='$LJ::SITEROOT/friends/add.bml?user=$journal->{user}'>$BML::ML{'web.controlstrip.links.addfeed'}</a>";
            $links{'remove_friend'} = "<a href='$LJ::SITEROOT/friends/add.bml?user=$journal->{user}'>$BML::ML{'web.controlstrip.links.removefeed'}</a>";
        }
        if ($journal->is_community) {
            $links{'join_community'}   = "<a href='$LJ::SITEROOT/community/join.bml?comm=$journal->{user}'>$BML::ML{'web.controlstrip.links.joincomm'}</a>";
            $links{'leave_community'}  = "<a href='$LJ::SITEROOT/community/leave.bml?comm=$journal->{user}'>$BML::ML{'web.controlstrip.links.leavecomm'}</a>";
            $links{'watch_community'}  = "<a href='$LJ::SITEROOT/friends/add.bml?user=$journal->{user}'>$BML::ML{'web.controlstrip.links.watchcomm'}</a>";
            $links{'unwatch_community'}   = "<a href='$LJ::SITEROOT/community/leave.bml?comm=$journal->{user}'>$BML::ML{'web.controlstrip.links.removecomm'}</a>";
            $links{'post_to_community'}   = "<a href='$LJ::SITEROOT/update.bml?usejournal=$journal->{user}'>$BML::ML{'web.controlstrip.links.postcomm'}</a>";
            $links{'edit_community_profile'} = "<a href='$LJ::SITEROOT/manage/profile/?authas=$journal->{user}'>$BML::ML{'web.controlstrip.links.editcommprofile'}</a>";
            $links{'edit_community_invites'} = "<a href='$LJ::SITEROOT/community/sentinvites.bml?authas=$journal->{user}'>$BML::ML{'web.controlstrip.links.managecomminvites'}</a>";
            $links{'edit_community_members'} = "<a href='$LJ::SITEROOT/community/members.bml?authas=$journal->{user}'>$BML::ML{'web.controlstrip.links.editcommmembers'}</a>";
        }
    }
    my $journal_display = LJ::ljuser($journal);
    my %statustext = (
                    'yourjournal'       => $BML::ML{'web.controlstrip.status.yourjournal'},
                    'yourfriendspage'   => $BML::ML{'web.controlstrip.status.yourfriendspage'},
                    'yourfriendsfriendspage' => $BML::ML{'web.controlstrip.status.yourfriendsfriendspage'},
                    'personal'          => BML::ml('web.controlstrip.status.personal', {'user' => $journal_display}),
                    'personalfriendspage' => BML::ml('web.controlstrip.status.personalfriendspage', {'user' => $journal_display}),
                    'personalfriendsfriendspage' => BML::ml('web.controlstrip.status.personalfriendsfriendspage', {'user' => $journal_display}),
                    'community'         => BML::ml('web.controlstrip.status.community', {'user' => $journal_display}),
                    'syn'               => BML::ml('web.controlstrip.status.syn', {'user' => $journal_display}),
                    'news'              => BML::ml('web.controlstrip.status.news', {'user' => $journal_display, 'sitename' => $LJ::SITENAMESHORT}),
                    'other'             => BML::ml('web.controlstrip.status.other', {'user' => $journal_display}),
                    'mutualfriend'      => BML::ml('web.controlstrip.status.mutualfriend', {'user' => $journal_display}),
                    'friend'            => BML::ml('web.controlstrip.status.friend', {'user' => $journal_display}),
                    'friendof'          => BML::ml('web.controlstrip.status.friendof', {'user' => $journal_display}),
                    'maintainer'        => BML::ml('web.controlstrip.status.maintainer', {'user' => $journal_display}),
                    'memberwatcher'     => BML::ml('web.controlstrip.status.memberwatcher', {'user' => $journal_display}),
                    'watcher'           => BML::ml('web.controlstrip.status.watcher', {'user' => $journal_display}),
                    'member'            => BML::ml('web.controlstrip.status.member', {'user' => $journal_display}),
                    );
    # Style the status text
    foreach my $key (keys %statustext) {
        $statustext{$key} = "<span id='lj_controlstrip_statustext'>" . $statustext{$key} . "</span>";
    }

    my $ret;
    if ($remote) {
        my $remote_display  = LJ::ljuser($remote);
        if ($remote->{'defaultpicid'}) {
            my $url = "$LJ::USERPIC_ROOT/$remote->{'defaultpicid'}/$remote->{'userid'}";
            $ret .= "<td id='lj_controlstrip_userpic' style='background-image: none;'><a href='$LJ::SITEROOT/editpics.bml'><img src='$url' alt=\"$BML::ML{'web.controlstrip.userpic.alt'}\" title=\"$BML::ML{'web.controlstrip.userpic.title'}\" /></a></td>";
        } else {
            my $tinted_nouserpic_img = "";

            if ($journal->prop('stylesys') == 2) {
                my $ctx = $LJ::S2::CURR_CTX;
                my $custom_nav_strip = S2::get_property_value($ctx, "custom_control_strip_colors");

                if ($custom_nav_strip ne "off") {
                    my $linkcolor = S2::get_property_value($ctx, "control_strip_linkcolor");

                    if ($linkcolor ne "") {
                        $tinted_nouserpic_img = S2::Builtin::LJ::palimg_modify($ctx, "controlstrip/nouserpic.gif", [S2::Builtin::LJ::PalItem($ctx, 0, $linkcolor)]);
                    }
                }
            }
            $ret .= "<td id='lj_controlstrip_userpic' style='background-image: none;'><a href='$LJ::SITEROOT/editpics.bml'>";
            if ($tinted_nouserpic_img eq "") {
                $ret .= "<img src='$LJ::IMGPREFIX/controlstrip/nouserpic.gif' alt=\"$BML::ML{'web.controlstrip.nouserpic.alt'}\" title=\"$BML::ML{'web.controlstrip.nouserpic.title'}\" height='43' />";
            } else {
                $ret .= "<img src='$tinted_nouserpic_img' alt=\"$BML::ML{'web.controlstrip.nouserpic.alt'}\" title=\"$BML::ML{'web.controlstrip.nouserpic.title'}\" height='43' />";
            }
            $ret .= "</a></td>";
        }
        $ret .= "<td id='lj_controlstrip_user' nowrap='nowrap'><form id='Greeting' class='nopic' action='$LJ::SITEROOT/logout.bml?ret=1' method='post'><div>";
        $ret .= "<input type='hidden' name='user' value='$remote->{'user'}' />";
        $ret .= "<input type='hidden' name='sessid' value='$remote->{'_session'}->{'sessid'}' />"
            if $remote->session;
        my $logout = "<input type='submit' value=\"$BML::ML{'web.controlstrip.btn.logout'}\" id='Logout' />";
        $ret .= "$remote_display $logout";
        $ret .= "</div></form>\n";
        $ret .= "$links{'home'} $links{'post_journal'} $links{'view_friends_page'}";
        $ret .= "</td>\n";

        $ret .= "<td id='lj_controlstrip_actionlinks' nowrap='nowrap'>";
        if (LJ::u_equals($remote, $journal)) {
            if (LJ::Request->notes('view') eq "friends") {
                $ret .= $statustext{'yourfriendspage'};
            } elsif (LJ::Request->notes('view') eq "friendsfriends") {
                $ret .= $statustext{'yourfriendsfriendspage'};
            } else {
                $ret .= $statustext{'yourjournal'};
            }
            $ret .= "<br />";
            if (LJ::Request->notes('view') eq "friends") {
                my @filters = ("all", $BML::ML{'web.controlstrip.select.friends.all'}, "showpeople", $BML::ML{'web.controlstrip.select.friends.journals'}, "showcommunities", $BML::ML{'web.controlstrip.select.friends.communities'}, "showsyndicated", $BML::ML{'web.controlstrip.select.friends.feeds'});
                my %res;
                # FIXME: make this use LJ::Protocol::do_request
                LJ::do_request({ 'mode' => 'getfriendgroups',
                                 'ver'  => $LJ::PROTOCOL_VER,
                                 'user' => $remote->{'user'}, },
                               \%res, { 'noauth' => 1, 'userid' => $remote->{'userid'} });
                my %group;
                foreach my $k (keys %res) {
                    if ($k =~ /^frgrp_(\d+)_name/) {
                        $group{$1}->{'name'} = $res{$k};
                    }
                    elsif ($k =~ /^frgrp_(\d+)_sortorder/) {
                        $group{$1}->{'sortorder'} = $res{$k};
                    }
                }
                foreach my $g (sort { $group{$a}->{'sortorder'} <=> $group{$b}->{'sortorder'} } keys %group) {
                    push @filters, "filter:" . lc($group{$g}->{'name'}), $group{$g}->{'name'};
                }

                my $selected = "all";
                if (LJ::Request->uri eq "/friends" && LJ::Request->args ne "") {
                    $selected = "showpeople"      if LJ::Request->args eq "show=P&filter=0";
                    $selected = "showcommunities" if LJ::Request->args eq "show=C&filter=0";
                    $selected = "showsyndicated"  if LJ::Request->args eq "show=Y&filter=0";
                } elsif (LJ::Request->uri =~ /^\/friends\/?(.+)?/i) {
                    my $filter = $1 || "default view";
                    $selected = "filter:" . LJ::durl(lc($filter));
                }

                $ret .= "$links{'manage_friends'}&nbsp;&nbsp; ";
                $ret .= "$BML::ML{'web.controlstrip.select.friends.label'} <form method='post' style='display: inline;' action='$LJ::SITEROOT/friends/filter.bml'>\n";
                $ret .= LJ::html_hidden("user", $remote->{'user'}, "mode", "view", "type", "allfilters");
                $ret .= LJ::html_select({'name' => "view", 'selected' => $selected }, @filters) . " ";
                $ret .= LJ::html_submit($BML::ML{'web.controlstrip.btn.view'});
                $ret .= "</form>";
                # drop down for various groups and show values
            } else {
                $ret .= "$links{'recent_comments'}&nbsp;&nbsp; $links{'manage_entries'}&nbsp;&nbsp; $links{'invite_friends'}";
            }
        } elsif ($journal->is_personal || $journal->is_identity) {
            my $friend = LJ::is_friend($remote, $journal);
            my $friendof = LJ::is_friend($journal, $remote);

            if ($friend and $friendof) {
                $ret .= "$statustext{'mutualfriend'}<br />";
                $ret .= "$links{'manage_friends'}";
            } elsif ($friend) {
                $ret .= "$statustext{'friend'}<br />";
                $ret .= "$links{'manage_friends'}";
            } elsif ($friendof) {
                $ret .= "$statustext{'friendof'}<br />";
                $ret .= "$links{'add_friend'}";
            } else {
                if (LJ::Request->notes('view') eq "friends") {
                    $ret .= $statustext{'personalfriendspage'};
                } elsif (LJ::Request->notes('view') eq "friendsfriends") {
                    $ret .= $statustext{'personalfriendsfriendspage'};
                } else {
                    $ret .= $statustext{'personal'};
                }
                $ret .= "<br />$links{'add_friend'}";
            }
        } elsif ($journal->is_community) {
            my $watching = LJ::is_friend($remote, $journal);
            my $memberof = LJ::is_friend($journal, $remote);
            my $haspostingaccess = LJ::check_rel($journal, $remote, 'P');
            if (LJ::can_manage_other($remote, $journal)) {
                $ret .= "$statustext{'maintainer'}<br />";
                if ($haspostingaccess) {
                    $ret .= "$links{'post_to_community'}&nbsp;&nbsp; ";
                }
                $ret .= "$links{'edit_community_profile'}&nbsp;&nbsp; $links{'edit_community_invites'}&nbsp;&nbsp; $links{'edit_community_members'}";
            } elsif ($watching && $memberof) {
                $ret .= "$statustext{'memberwatcher'}<br />";
                if ($haspostingaccess) {
                    $ret .= "$links{'post_to_community'}&nbsp;&nbsp; ";
                }
                $ret .= $links{'leave_community'};
            } elsif ($watching) {
                $ret .= "$statustext{'watcher'}<br />";
                if ($haspostingaccess) {
                    $ret .= "$links{'post_to_community'}&nbsp;&nbsp; ";
                }
                $ret .= "$links{'join_community'}&nbsp;&nbsp; $links{'unwatch_community'}";
            } elsif ($memberof) {
                $ret .= "$statustext{'member'}<br />";
                if ($haspostingaccess) {
                    $ret .= "$links{'post_to_community'}&nbsp;&nbsp; ";
                }
                $ret .= "$links{'watch_community'}&nbsp;&nbsp; $links{'leave_community'}";
            } else {
                $ret .= "$statustext{'community'}<br />";
                if ($haspostingaccess) {
                    $ret .= "$links{'post_to_community'}&nbsp;&nbsp; ";
                }
                $ret .= "$links{'join_community'}&nbsp;&nbsp; $links{'watch_community'}";
            }
        } elsif ($journal->is_syndicated) {
            $ret .= "$statustext{'syn'}<br />";
            if ($remote && !LJ::is_friend($remote, $journal)) {
                $ret .= "$links{'add_friend'}&nbsp;&nbsp; ";
            } elsif ($remote && LJ::is_friend($remote, $journal)) {
                $ret .= "$links{'remove_friend'}&nbsp;&nbsp; ";
            }
            $ret .= $links{'syndicated_list'};
        } elsif ($journal->is_news) {
            $ret .= "$statustext{'news'}<br />";
            if ($remote && !LJ::is_friend($remote, $journal)) {
                $ret .= $links{'add_friend'};
            } else {
                $ret .= "&nbsp;";
            }
        } else {
            $ret .= "$statustext{'other'}<br />";
            $ret .= "&nbsp;";
        }

        $ret .= LJ::Widget::StyleAlwaysMine->render( u => $remote )
            if ($remote && $remote->{userid} != $journal->{userid});

        $ret .= LJ::run_hook('control_strip_logo', $remote, $journal);
        $ret .= "</td>";

    } else {

        my $show_login_form = LJ::run_hook("show_control_strip_login_form", $journal);
        $show_login_form = 1 if !defined $show_login_form;

        if ($show_login_form) {
            my ($form_root, $extra_fields);
            if ($LJ::USE_SSL_LOGIN) {
                $form_root = $LJ::SSLROOT;
                $extra_fields = '';
            } else {
                $form_root = $LJ::SITEROOT;
                my $chal = LJ::challenge_generate(300);
                $extra_fields = 
                    "<input type='hidden' name='chal' id='login_chal' class='lj_login_chal' value='$chal' />" .
                    "<input type='hidden' name='response' id='login_response' class='lj_login_response' value='' />";
            }
            my $contents = LJ::run_hook('control_strip_userpic_contents', $uri) || "&nbsp;";
            $ret .= <<"LOGIN_BAR";
                <td id='lj_controlstrip_userpic'>$contents</td>
                <td id='lj_controlstrip_login' style='background-image: none;' nowrap='nowrap'>
                <form id="login" class="lj_login_form" action="$form_root/login.bml?ret=1" method="post"><div>
                <input type="hidden" name="mode" value="login" />
                $extra_fields
                <table cellspacing="0" cellpadding="0" style="margin-right: 1em;"><tr><td>
                <label for="xc_user">$BML::ML{'/login.bml.login.username'}</label> <input type="text" name="user" size="7" maxlength="17" tabindex="1" id="xc_user" value="" />
                </td><td>
                <label style="margin-left: 3px;" for="xc_password">$BML::ML{'/login.bml.login.password'}</label> <input type="password" name="password" size="7" tabindex="2" id="xc_password" class='lj_login_password' />
LOGIN_BAR
            $ret .= "<input type='submit' value=\"$BML::ML{'web.controlstrip.btn.login'}\" tabindex='4' />";
            $ret .= "</td></tr>";

            $ret .= "<tr><td valign='top'>";
            $ret .= "<a href='$LJ::SITEROOT/lostinfo.bml'>$BML::ML{'web.controlstrip.login.forgot'}</a>";
            $ret .= "</td><td style='font: 10px Arial, Helvetica, sans-serif;' valign='top' colspan='2' align='right'>";
            $ret .= "<input type='checkbox' id='xc_remember' name='remember_me' style='height: 10px; width: 10px;' tabindex='3' />";
            $ret .= "<label for='xc_remember'>$BML::ML{'web.controlstrip.login.remember'}</label>";
            $ret .= "</td></tr></table>";

            $ret .= '</div></form></td>';
        } else {
            my $contents = LJ::run_hook('control_strip_loggedout_userpic_contents', $uri) || "&nbsp;";
            $ret .= "<td id='lj_controlstrip_loggedout_userpic'>$contents</td>";
        }

        $ret .= "<td id='lj_controlstrip_actionlinks' nowrap='nowrap'>";

        if ($journal->is_personal || $journal->is_identity) {
            if (LJ::Request->notes('view') eq "friends") {
                $ret .= $statustext{'personalfriendspage'};
            } elsif (LJ::Request->notes('view') eq "friendsfriends") {
                $ret .= $statustext{'personalfriendsfriendspage'};
            } else {
                $ret .= $statustext{'personal'};
            }
        } elsif ($journal->is_community) {
            $ret .= $statustext{'community'};
        } elsif ($journal->is_syndicated) {
            $ret .= $statustext{'syn'};
        } elsif ($journal->is_news) {
            $ret .= $statustext{'news'};
        } else {
            $ret .= $statustext{'other'};
        }

        $ret .= "<br />";
        $ret .= "$links{'login'}&nbsp;&nbsp; " unless $show_login_form;
        $ret .= "$links{'create_account'}&nbsp;&nbsp; $links{'learn_more'}";
        $ret .= LJ::run_hook('control_strip_logo', $remote, $journal);
        $ret .= "</td>";
    }

    LJ::run_hooks('add_extra_cells_in_controlstrip', \$ret);

    my $message;
    $message = LJ::Widget::SiteMessages->render if LJ::Widget::SiteMessages->should_render;

    my $mobile_link = '';
    if (Apache::WURFL->is_mobile()) {
        my $uri = LJ::Request->uri;
        my $hostname = LJ::Request->hostname;
        my $args = LJ::Request->args;
        my $args_wq = $args ? "?$args" : "";
        my $is_ssl = $LJ::IS_SSL = LJ::run_hook("ssl_check");
        my $proto = $is_ssl ? "https://" : "http://";
        my $url = LJ::eurl ($proto.$hostname.$uri.$args_wq);
        $mobile_link .= "<div class='b-message-mobile'><div class='b-message-mobile-wrapper'>";
	    $mobile_link .= LJ::Lang::ml('link.mobile', { url => $url });
	    $mobile_link .="</div></div>";
    }
    return "<table id='lj_controlstrip' cellpadding='0' cellspacing='0'><tr valign='top'>$ret</tr><tr><td colspan='5'>$message</td></tr></table> $mobile_link";
}

sub control_strip_js_inject
{
    my %opts = @_;
    my $user = delete $opts{user};

    LJ::need_res(qw(
                    js/livejournal.js
                    js/controlstrip.js
                    ));
}

sub journal_js_inject
{
    LJ::need_res(qw(
                    js/journal.js
                    ));

    LJ::run_hooks('extra_journal_js');
}

# For the Rich Text Editor
# Set JS variables for use by the RTE
sub rte_js_vars {
    my ($remote) = @_;

    my $ret = '';
    # The JS var canmakepoll is used by fckplugin.js to change the behaviour
    # of the poll button in the RTE.
    # Also remove any RTE buttons that have been set to disabled.
    my $canmakepoll = "true";
    $canmakepoll = "false" if ($remote && !LJ::get_cap($remote, 'makepoll'));
    $ret .= "<script type='text/javascript'>\n";
    $ret .= "    var RTEdisabled = new Array();\n";
    my $rte_disabled = $LJ::DISABLED{rte_buttons} || {};
    foreach my $key (keys %$rte_disabled) {
        $ret .= "    RTEdisabled['$key'] = true;" if $rte_disabled->{$key};
    }
    $ret .= qq^
        var canmakepoll = $canmakepoll;

        function removeDisabled(ToolbarSet) {
            for (var i=0; i<ToolbarSet.length; i++) {
                for (var j=0; j<ToolbarSet[i].length; j++) {
                    if (RTEdisabled[ToolbarSet[i][j]] == true) ToolbarSet[i].splice(j,1);
                }
            }
        }
    </script>^;

    return $ret;
}

# returns a placeholder link
sub placeholder_link {
    my (%opts) = @_;

    my $placeholder_html = LJ::ejs_all(delete $opts{placeholder_html} || '');
    my $width  = delete $opts{width}  || 100;
    my $height = delete $opts{height} || 100;
    my $link   = delete $opts{link}   || '';
    my $img    = delete $opts{img}    || "$LJ::IMGPREFIX/videoplaceholder.png";

    $width -= 2;
    $height -= 2;

    return qq {
            <span class="LJ_Placeholder_Container" style="width: ${width}px; height: ${height}px;">
                <a href="$link" onclick="return LiveJournal.placeholderClick(this, '$placeholder_html')">
                    <img src="$img" class="LJ_Placeholder" title="Click to show embedded content" alt="" />
                </a>
            </span>
        };
}

# Returns replacement for lj-replace tags
sub lj_replace {
    my $key = shift;
    my $attr = shift;

    # Return hook if hook output not undef
    if (LJ::are_hooks("lj-replace_$key")) {
        my $replace = LJ::run_hook("lj-replace_$key");
        return $replace if defined $replace;
    }

    # Return value of coderef if key defined
    my %valid_keys = ( 'first_post' => \&lj_replace_first_post );

    if (my $cb = $valid_keys{$key}) {
        die "$cb is not a valid coderef" unless ref $cb eq 'CODE';
        return $cb->($attr);
    }

    return undef;
}

# Replace for lj-replace name="first_post"
sub lj_replace_first_post {
    return unless LJ::is_web_context();
    return BML::ml('web.lj-replace.first_post', {
                   'update_link' => "href='$LJ::SITEROOT/update.bml'",
                   });
}

# this returns the right max length for a VARCHAR(255) database
# column.  but in HTML, the maxlength is characters, not bytes, so we
# have to assume 3-byte chars and return 80 instead of 255.  (80*3 ==
# 240, approximately 255).  However, we special-case Russian where
# they often need just a little bit more, and make that 100.  because
# their bytes are only 2, so 100 * 2 == 200.  as long as russians
# don't enter, say, 100 characters of japanese... but then it'd get
# truncated or throw an error.  we'll risk that and give them 20 more
# characters.
sub std_max_length {
    my $lang = eval { BML::get_language() };
    return 80  if !$lang || $lang =~ /^en/;
    return 100 if $lang =~ /\b(hy|az|be|et|ka|ky|kk|lt|lv|mo|ru|tg|tk|uk|uz)\b/i;
    return 80;
}

# Common challenge/response JavaScript, needed by both login pages and comment pages alike.
# Forms that use this should onclick='return sendForm()' in the submit button.
# Returns true to let the submit continue.
$LJ::COMMON_CODE{'chalresp_js'} = qq{
<script language="JavaScript" type="text/javascript">
    <!--
function sendForm (formid, checkuser)
{
    if (formid == null) formid = 'login';
    // 'checkuser' is the element id name of the username textfield.
    // only use it if you care to verify a username exists before hashing.

    if (! document.getElementById) return true;
    var loginform = document.getElementById(formid);
    if (! loginform) return true;
    if(document.getElementById('prop_current_location')){
        if(document.getElementById('prop_current_location').value=='detecting...') document.getElementById('prop_current_location').value='';
    }
    // Avoid accessing the password field if there is no username.
    // This works around Opera < 7 complaints when commenting.
    if (checkuser) {
        var username = null;
        for (var i = 0; username == null && i < loginform.elements.length; i++) {
            if (loginform.elements[i].id == checkuser) username = loginform.elements[i];
        }
        if (username != null && username.value == "") return true;
    }

    if (! loginform.password || ! loginform.login_chal || ! loginform.login_response) return true;
    var pass = loginform.password.value;
    var chal = loginform.login_chal.value;
    var res = MD5(chal + MD5(pass));
    loginform.login_response.value = res;
    loginform.password.value = "";  // dont send clear-text password!
    return true;
}
// -->
</script>
};

# Common JavaScript function for auto-checking radio buttons on form
# input field data changes
$LJ::COMMON_CODE{'autoradio_check'} = q{
<script language="JavaScript" type="text/javascript">
    <!--
    /* If radioid exists, check the radio button. */
    function checkRadioButton(radioid) {
        if (!document.getElementById) return;
        var radio = document.getElementById(radioid);
        if (!radio) return;
        radio.checked = true;
    }
// -->
</script>
};

# returns HTML which should appear before </body>
sub final_body_html {
    my $before_body_close = "";
    LJ::run_hooks('insert_html_before_body_close', \$before_body_close);

    if (LJ::Request->notes('codepath') eq "bml.talkread" || LJ::Request->notes('codepath') eq "bml.talkpost") {
        my $journalu = LJ::load_userid(LJ::Request->notes('journalid'));
        unless (LJ::Request->notes('bml_use_scheme') eq 'lynx') {
            my $graphicpreviews_obj = LJ::graphicpreviews_obj();
            $before_body_close .= $graphicpreviews_obj->render($journalu);
        }
    }

    return $before_body_close;
}

# return a unique per pageview string based on the remote's unique cookie
sub pageview_unique_string {
    my $cached_uniq = $LJ::REQ_GLOBAL{pageview_unique_string};
    return $cached_uniq if $cached_uniq;

    my $uniq = LJ::UniqCookie->current_uniq . time() . LJ::rand_chars(8);
    $uniq = Digest::SHA1::sha1_hex($uniq);

    $LJ::REQ_GLOBAL{pageview_unique_string} = $uniq;
    return $uniq;
}

# <LJFUNC>
# name: LJ::site_schemes
# class: web
# des: Returns a list of available BML schemes.
# args: none
# return: array
# </LJFUNC>
sub site_schemes {
    my @schemes = @LJ::SCHEMES;
    LJ::run_hooks('modify_scheme_list', \@schemes);
    @schemes = grep { !$_->{disabled} } @schemes;
    return @schemes;
}

# returns a random value between 0 and $num_choices-1 for a particular uniq
# if no uniq available, just returns a random value between 0 and $num_choices-1
sub ab_testing_value {
    my %opts = @_;

    return $LJ::DEBUG{ab_testing_value} if defined $LJ::DEBUG{ab_testing_value};

    my $num_choices = $opts{num_choices} || 2;
    my $uniq = LJ::UniqCookie->current_uniq;

    my $val;
    if ($uniq) {
        $val = unpack("I", $uniq);
        $val %= $num_choices;
    } else {
        $val = int(rand($num_choices));
    }

    return $val;
}

# sets up appropriate js for journals that need a special statusvis message at the top
# returns some js that must be added onto the journal page's head
sub statusvis_message_js {
    my $u = shift;

    return "" unless $u;

    my $statusvis = $u->statusvis;
    return "" unless $statusvis =~ /^[LMO]$/;

    my $statusvis_full = "";
    $statusvis_full = "locked" if $statusvis eq "L";
    $statusvis_full = "memorial" if $statusvis eq "M";
    $statusvis_full = "readonly" if $statusvis eq "O";

    LJ::need_res("js/statusvis_message.js");
    return "<script>Site.StatusvisMessage=\"" . LJ::Lang::ml("statusvis_message.$statusvis_full") . "\";</script>";
}

sub needlogin_redirect {
    my $uri = LJ::Request->uri;
    if (my $qs = LJ::Request->args) {
        $uri .= "?" . $qs;
    }
    $uri = LJ::eurl($uri);

    return LJ::Request->redirect("$LJ::SITEROOT/?returnto=$uri");
}

sub get_body_class_for_service_pages {
    my %opts = @_;
    
    my @classes;
    push @classes, (LJ::get_remote()) ? 'logged-in' : 'logged-out';
   
    my $uri = LJ::Request->uri;
    if ($uri =~ m!^/index\.bml$!) {
        push @classes, "index-page";
    } elsif ($uri =~ m!^/shop(/.*)?$!) {
        push @classes, "shop-page";
    } elsif ($uri =~ m!^/browse(/.*)?$!) {
        push @classes, "catalogue-page";
    } elsif ($uri =~ m!^/games(/.*)?$! || LJ::Request->header_in("Host") eq "$LJ::USERAPPS_SUBDOMAIN.$LJ::DOMAIN") {
        push @classes, 'framework-page';    
    } 
    return join(" ", @classes);
}

# Add some javascript language strings
sub need_string {
    my @strings = @_;
  
    for my $item (@strings) {
        # When comes as a hash ref, should be treated as name => value
        if(ref $item eq 'HASH') {
            for my $key (keys %$item) {
                $LJ::JSML{$key} = $item->{$key};
            }
        # When handling array ref, name the ml by the value of the second element
        } elsif(ref $item eq 'ARRAY') {
            $LJ::JSML{$$item[1]} = LJ::Lang::ml($$item[0]);
        # If scalar - use the ml named this way
        } else {
            $LJ::JSML{$item} = LJ::Lang::ml($item);
        }
    }
}

1;
