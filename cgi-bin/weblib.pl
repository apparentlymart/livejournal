#!/usr/bin/perl
#

package LJ;
use strict;

# load the bread crumb hash
require "$ENV{'LJHOME'}/cgi-bin/crumbs.pl";

# <LJFUNC>
# name: LJ::img
# des: Returns an HTML &lt;img&gt; or &lt;input&gt; tag to an named image
#      code, which each site may define with a different image file with
#      its own dimensions.  This prevents hard-coding filenames & sizes
#      into the source.  The real image data is stored in LJ::Img, which
#      has default values provided in cgi-bin/imageconf.pl but can be
#      overridden in cgi-bin/ljconfig.pl.
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
    if ($attr) {
        if (ref $attr eq "HASH") {
            foreach (keys %$attr) {
                $attrs .= " $_=\"" . LJ::ehtml($attr->{$_}) . "\"";
            }
        } else {
            $attrs = " name=\"$attr\"";
        }
    }

    my $i = $LJ::Img::img{$ic};
    if ($type eq "") {
        return "<img src=\"$LJ::IMGPREFIX$i->{'src'}\" width=\"$i->{'width'}\" ".
            "height=\"$i->{'height'}\" alt=\"$i->{'alt'}\" title=\"$i->{'alt'}\" ".
            "border='0'$attrs />";
    }
    if ($type eq "input") {
        return "<input type=\"image\" src=\"$LJ::IMGPREFIX$i->{'src'}\" ".
            "width=\"$i->{'width'}\" height=\"$i->{'height'}\" title=\"$i->{'alt'}\" ".
            "alt=\"$i->{'alt'}\" border='0'$attrs />";
    }
    return "<b>XXX</b>";
}

# <LJFUNC>
# name: LJ::date_to_view_links
# class: component
# des: Returns HTML of date with links to user's journal.
# args: u, date
# des-date: date in yyyy-mm-dd form.
# returns: HTML with yyy, mm, and dd all links to respective views.
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
# des: Takes a plain-text string and changes URLs into <a href> tags (auto-linkification)
# args: str
# arg-str: The string to perform auto-linkification on.
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
    $str =~ s!https?://[^\s\'\"\<\>]+[a-zA-Z0-9_/&=\-]! $match->($&); !ge;
    return $str;
}


# <LJFUNC>
# name: LJ::make_authas_select
# des: Given a u object and some options, determines which users the given user
#      can switch to.  If the list exists, returns a select list and a submit
#      button with labels.  Otherwise returns a hidden element.
# returns: string of html elements
# args: u, opts?
# des-opts: Optional.  Valid keys are:
#           'authas' - current user, gets selected in drop-down
#           'label' - label to go before form elements
#           'button' - button label for submit button
#           others - arguments to pass to LJ::get_authas_list
# </LJFUNC>
sub make_authas_select {
    my ($u, $opts) = @_; # type, authas, label, button

    my @list = LJ::get_authas_list($u, $opts);

    # only do most of form if there are options to select from
    if (@list > 1) {
        return ($opts->{'label'} || 'Work as user:') . " " . 
               LJ::html_select({ 'name' => 'authas',
                                 'selected' => $opts->{'authas'} || $u->{'user'}},
                                 map { $_, $_ } @list) . " " .
               LJ::html_submit(undef, $opts->{'button'} || 'Switch');
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
# des-topic: Help topic key.  See doc/ljconfig.pl.txt for examples.
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


# <LJFUNC>
# name: LJ::bad_input
# des: Returns common BML for reporting form validation errors in
#      a bulletted list.
# returns: BML showing errors.
# args: error*
# des-error: A list of errors
# </LJFUNC>
sub bad_input
{
    my @errors = @_;
    my $ret = "";
    $ret .= "<?badcontent?>\n<ul>\n";
    foreach (@errors) {
        $ret .= "<li>$_</li>\n";
    }
    $ret .= "</ul>\n";
    return $ret;
}


# <LJFUNC>
# name: LJ::error_list
# des: Returns an error bar with bulleted list of errors
# returns: BML showing errors
# args: error*
# des-error: A list of errors
# </LJFUNC>
sub error_list
{
    my @errors = @_;
    my $ret;
    $ret .= "<?errorbar ";
    $ret .= "<strong>";
    $ret .= BML::ml('error.procrequest');
    $ret .= "</strong><ul>";

    foreach (@errors) {
        $ret .= "<li>$_</li>";
    }
    $ret .= " </ul> errorbar?>";
    return $ret;
}

# <LJFUNC>
# name: LJ::warning_list
# des: Returns a warning bar with bulleted list of warnings
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

}

sub tosagree_widget {
    my ($checked, $errstr) = @_;

    return 
        "<div class='formitemDesc'>" .
        BML::ml('tos.mustread', 
                { aopts => "target='_new' href='$LJ::SITEROOT/legal/tos.bml'" }) . 
        "</div>" .
        "<iframe width='600' height='300' src='/legal/tos-mini.bml' " .
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
# des: When web pages using cookie authentication, you can't just trust that
#      the remote user wants to do the action they're requesting.  It's way too
#      easy for people to force other people into making GET requests to
#      a server.  What if a user requested http://server/delete_all_journal.bml
#      and that URL checked the remote user and immediately deleted the whole
#      journal.  Now anybody has to do is embed that address in an image
#      tag and a lot of people's journals will be deleted without them knowing.
#      Cookies should only show pages which make no action.  When an action is
#      being made, check that it's a POST request.
# returns: true if REQUEST_METHOD == "POST"
# </LJFUNC>
sub did_post
{
    return (BML::get_method() eq "POST");
}

# <LJFUNC>
# name: LJ::robot_meta_tags
# des: Returns meta tags to block a robot from indexing or following links
# returns: A string with appropriate meta tags
# </LJFUNC>
sub robot_meta_tags
{
    return "<meta name=\"robots\" content=\"noindex, nofollow, noarchive\" />\n" .
           "<meta name=\"googlebot\" content=\"nosnippet\" />\n";
}

sub paging_bar
{
    my ($page, $pages, $opts) = @_;

    my $self_link = $opts->{'self_link'} ||
                    sub { BML::self_link({ 'page' => $_[0] }) };

    my $navcrap;
    if ($pages > 1) {
        $navcrap .= "<center><font face='Arial,Helvetica' size='-1'><b>";
        $navcrap .= BML::ml('ljlib.pageofpages',{'page'=>$page, 'total'=>$pages}) . "<br />";
        my $left = "<b>&lt;&lt;</b>";
        if ($page > 1) { $left = "<a href='" . $self_link->($page-1) . "'>$left</a>"; }
        my $right = "<b>&gt;&gt;</b>";
        if ($page < $pages) { $right = "<a href='" . $self_link->($page+1) . "'>$right</a>"; }
        $navcrap .= $left . " ";
        for (my $i=1; $i<=$pages; $i++) {
            my $link = "[$i]";
            if ($i != $page) { $link = "<a href='" . $self_link->($i) . "'>$link</a>"; }
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

# <LJFUNC>
# name: LJ::set_interests
# des: Change a user's interests
# args: dbarg?, u, old, new
# arg-old: hashref of old interests (hashing being interest => intid)
# arg-new: listref of new interests
# returns: 1 on success, undef on failure
# </LJFUNC>
sub set_interests
{
    my ($u, $old, $new) = @_;

    $u = LJ::want_user($u);
    my $userid = $u->{'userid'};
    return undef unless $userid;

    return undef unless ref $old eq 'HASH';
    return undef unless ref $new eq 'ARRAY';

    my $dbh = LJ::get_db_writer();
    my %int_new = ();
    my %int_del = %$old;  # assume deleting everything, unless in @$new

    # user interests go in a different table than user interests,
    # though the schemas are the same so we can run the same queries on them
    my $uitable = $u->{'journaltype'} eq 'C' ? 'comminterests' : 'userinterests';

    # track if we made changes to refresh memcache later.
    my $did_mod = 0;

    foreach my $int (@$new)
    {
        $int = lc($int);       # FIXME: use utf8?
        $int =~ s/^i like //;  # *sigh*
        next unless $int;
        next if $int =~ / .+ .+ .+ /;  # prevent sentences
        next if $int =~ /[\<\>]/;
        my ($bl, $cl) = LJ::text_length($int);
        next if $bl > LJ::BMAX_INTEREST or $cl > LJ::CMAX_INTEREST;
        $int_new{$int} = 1 unless $old->{$int};
        delete $int_del{$int};
    }

    ### were interests removed?
    if (%int_del)
    {
        ## easy, we know their IDs, so delete them en masse
        my $intid_in = join(", ", values %int_del);
        $dbh->do("DELETE FROM $uitable WHERE userid=$userid AND intid IN ($intid_in)");
        $dbh->do("UPDATE interests SET intcount=intcount-1 WHERE intid IN ($intid_in)");
        $did_mod = 1;
    }

    ### do we have new interests to add?
    if (%int_new)
    {
        $did_mod = 1;

        ## difficult, have to find intids of interests, and create new ints for interests
        ## that nobody has ever entered before
        my $int_in = join(", ", map { $dbh->quote($_); } keys %int_new);
        my %int_exist;
        my @new_intids = ();  ## existing IDs we'll add for this user

        ## find existing IDs
        my $sth = $dbh->prepare("SELECT interest, intid FROM interests WHERE interest IN ($int_in)");
        $sth->execute;
        while (my ($intr, $intid) = $sth->fetchrow_array) {
            push @new_intids, $intid;       # - we'll add this later.
            delete $int_new{$intr};         # - so we don't have to make a new intid for
                                            #   this next pass.
        }

        if (@new_intids) {
            my $sql = "";
            foreach my $newid (@new_intids) {
                if ($sql) { $sql .= ", "; }
                else { $sql = "REPLACE INTO $uitable (userid, intid) VALUES "; }
                $sql .= "($userid, $newid)";
            }
            $dbh->do($sql);

            my $intid_in = join(", ", @new_intids);
            $dbh->do("UPDATE interests SET intcount=intcount+1 WHERE intid IN ($intid_in)");
        }
    }

    ### do we STILL have interests to add?  (must make new intids)
    if (%int_new)
    {
        foreach my $int (keys %int_new)
        {
            my $intid;
            my $qint = $dbh->quote($int);

            $dbh->do("INSERT INTO interests (intid, intcount, interest) ".
                     "VALUES (NULL, 1, $qint)");
            if ($dbh->err) {
                # somebody beat us to creating it.  find its id.
                $intid = $dbh->selectrow_array("SELECT intid FROM interests WHERE interest=$qint");
                $dbh->do("UPDATE interests SET intcount=intcount+1 WHERE intid=$intid");
            } else {
                # newly created
                $intid = $dbh->{'mysql_insertid'};
            }
            if ($intid) {
                ## now we can actually insert it into the userinterests table:
                $dbh->do("INSERT INTO $uitable (userid, intid) ".
                         "VALUES ($userid, $intid)");
            }
        }
    }

    ### if journaltype is community, clean their old userinterests from 'userinterests'
    if ($u->{'journaltype'} eq 'C') {
        $dbh->do("DELETE FROM userinterests WHERE userid=?", undef, $u->{'userid'});
    }

    LJ::memcache_kill($u, "intids") if $did_mod;
    return 1;
}

# $opts is optional, with keys:
#    forceids => 1   : don't use memcache for loading the intids
#    forceints => 1   : don't use memcache for loading the interest rows
#    justids => 1 : return arrayref of intids only, not names/counts
# returns otherwise an arrayref of interest rows, sorted by interest name
sub get_interests
{
    my ($u, $opts) = @_;
    $opts ||= {};
    return undef unless $u;
    my $uid = $u->{userid};
    my $uitable = $u->{'journaltype'} eq 'C' ? 'comminterests' : 'userinterests';

    # load the ids
    my $ids;
    my $mk_ids = [$uid, "intids:$uid"];
    $ids = LJ::MemCache::get($mk_ids) unless $opts->{'forceids'};
    unless ($ids && ref $ids eq "ARRAY") {
        $ids = [];
        my $dbh = LJ::get_db_writer();
        my $sth = $dbh->prepare("SELECT intid FROM $uitable WHERE userid=?");
        $sth->execute($uid);
        push @$ids, $_ while ($_) = $sth->fetchrow_array;
        LJ::MemCache::add($mk_ids, $ids, 3600*12);
    }
    return $ids if $opts->{'justids'};

    # load interest rows
    my %need;
    $need{$_} = 1 foreach @$ids;
    my @ret;

    unless ($opts->{'forceints'}) {
        if (my $mc = LJ::MemCache::get_multi(map { [$_, "introw:$_"] } @$ids)) {
            while (my ($k, $v) = each %$mc) {
                next unless $k =~ /^introw:(\d+)/;
                delete $need{$1};
                push @ret, $v;
            }
        }
    }

    if (%need) {
        my $ids = join(",", map { $_+0 } keys %need);
        my $dbr = LJ::get_db_reader();
        my $sth = $dbr->prepare("SELECT intid, interest, intcount FROM interests ".
                                "WHERE intid IN ($ids)");
        $sth->execute;
        my $memc_store = 0;
        while (my ($intid, $int, $count) = $sth->fetchrow_array) {
            # minimize latency... only store 25 into memcache at a time
            # (too bad we don't have set_multi.... hmmmm)
            my $aref = [$intid, $int, $count];
            if ($memc_store++ < 25) {
                # if the count is fairly high, keep item in memcache longer,
                # since count's not so important.
                my $expire = $count < 10 ? 3600*12 : 3600*48;
                LJ::MemCache::add([$intid, "introw:$intid"], $aref, $expire);
            }
            push @ret, $aref;
        }
    }

    @ret = sort { $a->[1] cmp $b->[1] } @ret;
    return \@ret;
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
# des-uri: string; the URI we want the user to come from
# des-referer: string; the location the user is posting from.  if not supplied,
#   will be retrieved with BML::get_client_header.  in general, you don't want to
#   pass this yourself unless you already have it or know we can't get it from BML.
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
    return 1 if $uri =~ m!^http://! && $referer eq $uri;
    return undef;
}

# <LJFUNC>
# name: LJ::form_auth
# class: web
# des: Creates an authentication token to be used later to verify that a form
#   submission came from a particular user.
# returns: HTML hidden field to be inserted into the output of a page.
# </LJFUNC>
sub form_auth {
    my $remote = LJ::get_remote()    or return "";
    my $sess = $remote->{'_session'} or return "";
    my $auth = join('-',
                    LJ::rand_chars(10),
                    $remote->{userid},
                    $sess->{auth});
    return LJ::html_hidden("lj_form_auth", LJ::challenge_generate(86400, $auth));
}

# <LJFUNC>
# name: LJ::check_form_auth
# class: web
# des: Verifies form authentication created with LJ::form_auth.
# returns: Boolean; true if the current data in %POST is a valid form submitted
#   by the user in $remote using the current session, false if the user has changed,
#   the challenge has expired, or the user has changed session (logged out and in
#   again, or something).
# </LJFUNC>
sub check_form_auth {
    my $remote = LJ::get_remote()    or return 0;
    my $sess = $remote->{'_session'} or return 0;
    my $formauth = $BMLCodeBlock::POST{'lj_form_auth'} or return 0;

    # check the attributes are as they should be
    my $attr = LJ::get_challenge_attributes($formauth);
    my ($randchars, $userid, $sessauth) = split(/\-/, $attr);
    return 0 unless $userid == $remote->{userid} &&
        $sessauth eq $sess->{auth};

    # check the signature is good and not expired
    my $opts = { dont_check_count => 1 };  # in/out
    LJ::challenge_check($formauth, $opts);
    return $opts->{valid} && ! $opts->{expired};
}

# <LJFUNC>
# name: LJ::create_qr_div
# class: web
# des: Creates the hidden div that stores the Quick Reply form
# returns: undef upon failure or HTML for the div upon success
# args: user, remote, ditemid, stylemine, userpic
# des-u: user object or userid for journal reply in
# des-ditemid: ditemid for this comment
# des-stylemine: if the user has specified style=mine for this page
# des-userpic: alternate default userpic
# </LJFUNC>
sub create_qr_div {

    my ($user, $ditemid, $stylemine, $userpic, $viewing_thread) = @_;
    my $u = LJ::want_user($user);
    my $remote = LJ::get_remote();
    return undef unless $u && $remote && $ditemid;
    return undef if $remote->underage;

    $stylemine ||= 0;
    my $qrhtml;

    LJ::load_user_props($remote, "opt_no_quickreply");
    return undef if $remote->{'opt_no_quickreply'};

    my $stylemineuri = $stylemine ? "style=mine&" : "";
    my $basepath = LJ::journal_base($u) . "/$ditemid.html?${stylemineuri}replyto=";
    $qrhtml .= LJ::html_hidden({'name' => 'replyto', 'id' => 'replyto', 'value' => ''},
                               {'name' => 'parenttalkid', 'id' => 'parenttalkid', 'value' => ''},
                               {'name' => 'itemid', 'id' => 'itemid', 'value' => $ditemid},
                               {'name' => 'usertype', 'id' => 'usertype', 'value' => 'cookieuser'},
                               {'name' => 'userpost', 'id' => 'userpost', 'value' => $remote->{'user'}},
                               {'name' => 'qr', 'id' => 'qr', 'value' => '1'},
                               {'name' => 'cookieuser', 'id' => 'cookieuser', 'value' => $remote->{'user'}},
                               {'name' => 'dtid', 'id' => 'dtid', 'value' => ''},
                               {'name' => 'basepath', 'id' => 'basepath', 'value' => $basepath},
                               {'name' => 'stylemine', 'id' => 'stylemine', 'value' => $stylemine},
                               {'name' => 'saved_subject', 'id' => 'saved_subject'},
                               {'name' => 'saved_body', 'id' => 'saved_body'},
                               {'name' => 'saved_spell', 'id' => 'saved_spell'},
                               {'name' => 'saved_upic', 'id' => 'saved_upic'},
                               {'name' => 'saved_dtid', 'id' => 'saved_dtid'},
                               {'name' => 'saved_ptid', 'id' => 'saved_ptid'},
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
    $qrhtml .= "<div id='qrdiv' name='qrdiv' style='display:none;'>";
    $qrhtml .= "<table style='border: 1px solid black'>";
    $qrhtml .= "<tr valign='center'>";
    $qrhtml .= "<td align='right'><b>".BML::ml('/talkpost.bml.opt.from')."</b></td><td align='left'>";
    $qrhtml .= LJ::ljuser($remote->{'user'});
    $qrhtml .= "</td><td align='center'>";

    # Userpic selector
    {
        my %res;
        LJ::do_request({ "mode" => "login",
                         "ver" => ($LJ::UNICODE ? "1" : "0"),
                         "user" => $remote->{'user'},
                         "getpickws" => 1, },
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
                                        'selected' => $userpic, 'id' => 'prop_picture_keyword' },
                                       ("", BML::ml('/talkpost.bml.opt.defpic'), map { ($_, $_) } @pics));

            $qrhtml .= ' ' . BML::fill_template('help', { 'DATA' => $LJ::HELPURL{'userpics'} } )
                if defined $LJ::HELPURL{'userpics'};
        }
    }

    $qrhtml .= "</td></tr>";

    $qrhtml .= "<tr><td align='right'>";
    $qrhtml .= "<b>".BML::ml('/talkpost.bml.opt.subject')."</b></td>";
    $qrhtml .= "<td colspan='2' align='left'>";
    $qrhtml .= "<input class='textbox' type='text' size='50' maxlength='100' name='subject' id='subject' value='' />";
    $qrhtml .= "</td></tr>";

    $qrhtml .= "<tr valign='top'>";
    $qrhtml .= "<td align='right'><b>".BML::ml('/talkpost.bml.opt.message')."</b></td>";
    $qrhtml .= "<td colspan='3' style='width: 90%'>";

    $qrhtml .= "<textarea class='textbox' rows='10' cols='50' wrap='soft' name='body' id='body' style='width: 99%'></textarea>";
    $qrhtml .= "</td></tr>";

    $qrhtml .= "<tr><td>&nbsp;</td>";
    $qrhtml .= "<td colspan='3' align='left'>";

    $qrhtml .= LJ::html_submit('submitpost', BML::ml('/talkread.bml.button.post'),
                               { "id" => "submitpost",
                                 "raw" => "onclick='if (checkLength()) {submitform();}'"
                                 });

    $qrhtml .= "&nbsp;" . LJ::html_submit('submitmoreopts', BML::ml('/talkread.bml.button.more'),
                                          { "id" => "submitmoreopts",
                                            "raw" => "onclick='if (moreopts()) {submitform();}'"
                                            });
    if ($LJ::SPELLER) {
        $qrhtml .= "&nbsp;<input type='checkbox' name='do_spellcheck' value='1' id='do_spellcheck' /> <label for='do_spellcheck'>";
        $qrhtml .= BML::ml('/talkread.bml.qr.spellcheck');
        $qrhtml .= "</label>";
    }

    LJ::load_user_props($u, 'opt_logcommentips');
    if ($u->{'opt_logcommentips'} eq 'A') {
        $qrhtml .= '<br />';
        $qrhtml .= BML::fill_template('de', { 'DATA' => BML::ml('/talkpost.bml.logyourip') } );
        $qrhtml .= ' ' . BML::fill_template('help', { 'DATA' => $LJ::HELPURL{'iplogging'} } )
            if defined $LJ::HELPURL{'iplogging'};
    }

    $qrhtml .= "</td></tr></table>";
    $qrhtml .= "</div>";

    my $ret;
    $ret = "<script language='JavaScript'>\n";
    $ret .= "<!--\n";
    $qrhtml = LJ::ejs($qrhtml);
    $ret .= "document.write('$qrhtml');\n";
    $ret .= "-->\n";
    $ret .= "</script>";
    return $ret;
}

# <LJFUNC>
# name: LJ::make_qr_link
# class: web
# des: Creates the link to toggle the QR reply form or if
# JavaScript is not enabled, then forwards the user through
# to replyurl.
# returns: undef upon failure or HTML for the link
# args: dtid, basesubject, linktext, replyurl
# des-dtid: dtalkid for this comment
# des-basesubject: parent comment's subject
# des-linktext: text for the user to click
# des-replyurl: URL to forward user to if their browser
# does not support QR
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
        $basesubject = LJ::ejs($basesubject);
        my $onclick = "return quickreply('$dtid', $pid, '$basesubject')";
        $onclick = LJ::ehtml($onclick);
        return "<a onclick='$onclick' href='$replyurl' >$linktext</a>";
    } else { # QR Disabled
        return "<a href='$replyurl' >$linktext</a>";
    }
}

# <LJFUNC>
# name: LJ::get_lastcomment
# class: web
# des: Looks up the last talkid and journal the remote user posted in
# returns: talkid, jid
# args:
# </LJFUNC>
sub get_lastcomment {
    my $remote = LJ::get_remote;
    return (undef, undef) unless $remote;

    # Figure out their last post
    my $memkey = [$remote->{'userid'}, "lastcomm:$remote->{'userid'}"];
    my $memval = LJ::MemCache::get($memkey);
    my ($jid, $talkid) = split(/:/, $memval) if $memval;

    return ($talkid, $jid);
}

# <LJFUNC>
# name: LJ::make_qr_target
# class: web
# des: Returns a div usable for Quick Reply boxes
# returns: HMTML for the div
# args:
# </LJFUNC>
sub make_qr_target {
    my $name = shift;

    return "<div id='$name' name='$name'></div>";
}

# <LJFUNC>
# name: LJ::set_lastcomment
# class: web
# des: Sets the lastcomm Memcache key for this user's last comment
# returns: undef on failure
# args: u, remote, dtalkid, life?
# des-u: Journal they just posted in, either u or userid
# des-remote: Remote user
# des-dtalkid: Talkid for the comment they just posted
# des-life: How long, in seconds, the Memcache key should live
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

# <LJFUNC>
# name: LJ::entry_form
# class: web
# des: Returns a properly formatted form for creating/editing entries
# args: opts, head
# des-head: string reference for the <head> section (javascript previews, etc)
# des-onload: string reference for javascript functions to be called on page load
# des-opts: hashref of keys/values:
#   mode: either "update" or "edit", depending on context
#   datetime: date and time, formatted yyyy-mm-dd hh:mm
#   remote: remote u object
#   subject: entry subject
#   event: entry text
#   richtext: allow rich text formatting
#   richtext_on: rich text formatting has been turned on
#   auth_as_remote: bool option to authenticate as remote user, prefilling pic/friend groups/etc
# return: form to include in BML pages
# </LJFUNC>
sub entry_form {
    my ($opts, $head, $onload, $errors) = @_;

    my $out = "";
    my $remote = $opts->{'remote'};
    my ($moodlist, $moodpics, $userpics);

    # usejournal has no point if you're trying to use the account you're logged in as,
    # so disregard it so we can assume that if it exists, we're trying to post to an
    # account that isn't us
    if ($remote && $opts->{usejournal} && $remote->{user} eq $opts->{usejournal}) {
        delete $opts->{usejournal};
    }

    my $tabnum = 1;
    my $tabindex = sub { return $tabnum++; };
    $opts->{'event'} = LJ::durl($opts->{'event'}) if $opts->{'mode'} eq "edit";
    
    # 15 minute auth token, should be adequate
    my $chal = LJ::challenge_generate(900);
    $out .= "<input type='hidden' name='chal' id='login_chal' value='$chal' />";
    $out .= "<input type='hidden' name='response' id='login_response' value='' />";

    $out .= "<div id='EntryForm'>";
    $out .= "<table id='MetaInfo' cellpadding='0' cellspacing='0'>\n<tr valign='top'>";
    ### Meta Information Column 1
    {
        $out .= "<td style='width: 50%;'><table cellspacing='0' cellpadding='2' style='width: 100%; text-align: left' border='0'>";

        # Authentication box
        $out .= $opts->{'auth'};
        $out .= "<tr><th></th><td style='font-size: 0.85em;'><?inerr $errors->{'auth'} inerr?></td></tr>\n" if $errors->{'auth'};
        # Date / Time
        {
            my ($year, $mon, $mday, $hour, $min) = split( /\D/, $opts->{'datetime'});
            # date entry boxes / formatting note
            my $datetime = LJ::html_datetime({ 'name' => "date_ymd", 'notime' => 1, 'default' => "$year-$mon-$mday", 'disabled' => $opts->{'disabled_save'}}) . "&nbsp;" x 5;
            $datetime .=   LJ::html_text({ size => 2, maxlength => 2, value => $hour, name => "hour", tabindex => $tabindex->(), disabled => $opts->{'disabled_save'} }) . ":"; 
            $datetime .=   LJ::html_text({ size => 2, maxlength => 2, value => $min, name => "min", tabindex => $tabindex->(), disabled => $opts->{'disabled_save'} });
            
            $out .= "<tr valign='top'><th>" . BML::ml('entryform.date') . "</th>";
            $out .= "<td id='datetime_box' nowrap='nowrap'>$datetime <?de " . BML::ml('entryform.date.24hournote') . " de?>";
            $out .= "<noscript><br /><span style='font-size: 0.85em;'>" . BML::ml('entryform.nojstime.note') . "</span></noscript></td></tr>\n";
        }
    
        ### Subject
        $out .= "<tr valign='top'><th>" . BML::ml('entryform.subject') . "</th><td>";
        $out .= LJ::html_text({ 'name' => 'subject', 'value' => $opts->{'subject'},
                                'size' => '60', 'maxlength' => '100', 'tabindex' => $tabindex->(), 'disabled' => $opts->{'disabled_save'} }) . "\n";
        $out .= "</td></tr>";
        $out .= "</table></td>";
    }
    ### Meta Information Column 2
    {    
        $out .= "<td id='infobox'>";
        $out .= LJ::run_hook('entryforminfo');
        $out .= "</td>";
    }
    
    $out .= "</tr></table>\n";

    ### Display Spell Check Results:
    $out .= "<p><b>" . BML::ml('entryform.spellchecked') . "</b><br />$opts->{'spellcheck_html'}</p>" 
        if $opts->{'spellcheck_html'};
    $out .= "<p><?inerr " . BML::ml('Error') . " inerr?><br />$errors->{'entry'}</p>" 
        if $errors->{'entry'};
    
    ### Event Text Area:
    $out .= "<p><b>" . BML::ml('entryform.entry') . "</b></p>" unless $opts->{'richtext_on'};
    if ($opts->{'richtext_on'}) {
        my $jevent = $opts->{'event'};
        
        # manually typed tags
        $jevent =~ s/<lj user=['"]?(\w{1,15})['"]?\s?\/?>/&lt;lj user="$1" \/&gt;/ig;
        $jevent =~ s/<(\/)?lj-cut(.*?)(?: \/)?>/&lt;$1lj-cut$2&gt;/ig;
        
        $jevent = LJ::ejs($jevent);
        my $rte_nosupport = LJ::ejs(BML::fill_template("de", { DATA => BML::ml('entryform.htmlokay.rte_nosupport') }));
        
        $out .= LJ::html_hidden('richtext', '1') . "\n";
        $out .= LJ::html_hidden('saved_entry', '') . "\n";
        
        $out .= <<RTE;
        <iframe id="testFrame" style="position: absolute; visibility: hidden; width: 0px; height: 0px;"></iframe>
            <script language="JavaScript" type="text/javascript" src="$LJ::JSPREFIX/browserdetect.js"></script>
            <script language='JavaScript' type='text/javascript'>
            <!--
            var siteroot = "$LJ::SITEROOT";
        //-->
            </script>
            <script language="JavaScript" type="text/javascript" src="$LJ::JSPREFIX/richtext.js"></script>
            <script language='JavaScript' type='text/javascript'>
            <!--
            writeRichText('rte', 'event', '$jevent', '99%', 300, true, "Entry:");
        if (isRichText == false) {
            document.write("$rte_nosupport");
        }
        //-->
            </script>
            <noscript>
RTE
    }
    $out .= LJ::html_textarea({ 'name' => 'event', 'value' => $opts->{'event'},
                                'rows' => '20', 'cols' => '50', 'style' => 'width: 100%', 
                                'wrap' => 'soft', 'tabindex' => $tabindex->(),
                                'disabled' => $opts->{'disabled_save'}});

    $out .= '</noscript>' if $opts->{'richtext_on'};
    $out .= LJ::html_hidden('prop_opt_preformatted', '1') if $opts->{'richtext_on'};

    my $jrich = LJ::ejs(BML::fill_template("de", {
        DATA => BML::ml("entryform.htmlokay.rich", { 'opts' => 'href="#" onClick="enable_rte()"' })
    }));
    my $jnorich = LJ::ejs(BML::fill_template("de", { DATA => BML::ml('entryform.htmlokay.norich') }));

    unless ( $opts->{'richtext_on'}   ||
             $opts->{'disabled_save'} ||
             ! $opts->{'richtext'}    ||
             ( $opts->{'did_spellcheck'} && $opts->{'richtext_on'} )
           ) {
        $out .= <<RTE;
        <script language='JavaScript' type='text/javascript'>
            <!--
            var t = document.getElementById;
        if (t) {
            document.write('<input type="hidden" name="switched_rte_on" value="" />');
            document.write("$jrich");
        } else {
            document.write("$jnorich");
        }
        //-->
            </script>
RTE
            $out .= '<noscript><?de ' . BML::ml('entryform.htmlokay.norich') . ' de?></noscript>';
    }
    $out .= '<br />';

    # do a login action to get pics and usejournals, but only if using remote
    my $res;
    if ($opts->{'auth_as_remote'}) {
        $res = LJ::Protocol::do_request("login", {
            "ver" => $LJ::PROTOCOL_VER,
            "username" => $remote->{'user'},
            "getpickws" => 1,
            "getpickwurls" => 1,
        }, undef, { 
            "noauth" => 1, 
            "u" => $remote,
        });
    }

    if (!$opts->{'disabled_save'}) {
        ### Options
        $out .= "<b>" . BML::ml('entryform.options') . "</b><br />";
        $out .= "<table style='width: 100%' id='Options'><tr valign='top'>";
        
        ### Options Column 1
        {
            $out .= "<td style='border-right: 1px dashed #999; text-align: center; width: 50%' id='column_one_td'>";
                $out .= "<table style='text-align: left' id='column_one_table'>";
            
            # Security
            {
                my @secs = ("public", BML::ml('label.security.public'), "private", BML::ml('label.security.private'),
                            "friends", BML::ml('label.security.friends'));
                
                my @secopts;
                if ($res && ref $res->{'friendgroups'} eq 'ARRAY' && scalar @{$res->{'friendgroups'}} && !$opts->{'usejournal'}) {
                    push @secs, ("custom", BML::ml('label.security.custom'));
                    push @secopts, ("onchange" => "customboxes()");
                }
                
                $out .= "<tr valign='top'><th>" . LJ::help_icon("security", "", " ") . BML::ml('entryform.security') . "</th><td>";
                $out .= LJ::html_select({ 'id' => "Security", 'name' => 'security', 
                                          
                                          'selected' => $opts->{'security'}, 
                                          'tabindex' => $tabindex->(), @secopts }, @secs);
                
                # if custom security groups available, show them in a hideable div
                if ($res && ref $res->{'friendgroups'} eq 'ARRAY' && scalar @{$res->{'friendgroups'}}) {
                    my $display = $opts->{'security'} eq "custom" ? "block" : "none";
                    $out .= "<div id='custom_boxes' style='display: $display;'>";
                    foreach my $fg (@{$res->{'friendgroups'}}) {
                        $out .= LJ::html_check({ 'name' => "custom_bit_$fg->{'id'}",
                                                 'id' => "custom_bit_$fg->{'id'}",
                                                 'selected' => $opts->{"custom_bit_$fg->{'id'}"} || $opts->{'security_mask'}+0 & 1 << $fg->{'id'} }) . " ";
                        $out .= "<label for='custom_bit_$fg->{'id'}'>" . LJ::ehtml($fg->{'name'}) . "</label><br />";
                    }
                    $out .= "</div>";
                }
                $out .= "</td></tr>";
            }
            # Text Formatting
            unless ($opts->{'richtext_on'}) {
                my $format_selected = $opts->{'prop_opt_preformatted'} ? "preformatted" : "";
                $format_selected ||= $opts->{'event_format'};
                
                $out .= "<tr valign='top'><th><label for='event_format'>" . BML::ml('entryform.format') . "</label></th><td>";
                $out .= LJ::html_select({ 'name' => "event_format", 'id' => "event_format", 
                                          'selected' => $format_selected, 'tabindex' => $tabindex->() },
                                        "auto", BML::ml('entryform.format.auto'), "preformatted", BML::ml('entryform.format.preformatted'));
                $out .= "</td></tr>";
            }
            # Current Music
            $out .= "<tr><th>" . BML::ml('entryform.music') . "</th><td>";
            $out .= LJ::html_text({ 'name' => 'prop_current_music', 'value' => $opts->{'prop_current_music'},
                                    'size' => '35', 'maxlength' => '60', 'tabindex' => $tabindex->() }) . "</td></tr>\n";
            
            # Current Mood
            {
                my @moodlist = ('', BML::ml('entryform.noneother'));
                my $sel;
                
                my $moods = LJ::get_moods();
                
                foreach (sort { $moods->{$a}->{'name'} cmp $moods->{$b}->{'name'} } keys %$moods) {
                    push @moodlist, ($_, $moods->{$_}->{'name'});
                    
                    if ($opts->{'prop_current_mood'} eq $moods->{$_}->{'name'} ||
                        $opts->{'prop_current_moodid'} == $_) {
                        $sel = $_;
                    }
                }
                
                if ($remote) {
                    LJ::load_mood_theme($remote->{'moodthemeid'});
                      foreach my $mood (keys %$moods) {
                          if (LJ::get_mood_picture($remote->{'moodthemeid'}, $moods->{$mood}->{id}, \ my %pic)) {
                              $moodlist .= "    moods[" . $moods->{$mood}->{id} . "] = \"" . $moods->{$mood}->{name} . "\";\n";
                              $moodpics .= "    moodpics[" . $moods->{$mood}->{id} . "] = \"" . $pic{pic} . "\";\n";
                          }
                      }
                      $$onload .= " mood_preview();";
                $$head .= <<MOODS;
<script type="text/javascript" language="JavaScript"><!--
if (document.getElementById) {
    var moodpics = new Array();
    $moodpics
    var moods    = new Array();
    $moodlist
    function mood_preview() {
        if (! document.getElementById) return false;
        var mood_preview = document.getElementById('mood_preview');
        
        var mood_list  = document.getElementById('prop_current_moodid');
        var moodid = mood_list[mood_list.selectedIndex].value;
        if (moodid == "") {
            mood_preview.style.display = "none";
        } else {
            mood_preview.style.display = "block";
            var mood_image_preview = document.getElementById('mood_image_preview');
            mood_image_preview.src = moodpics[moodid];

            var mood_text_preview = document.getElementById('mood_text_preview');
            var mood_custom_text  = document.getElementById('prop_current_mood').value;
            mood_text_preview.innerHTML = mood_custom_text == "" ? moods[moodid] : mood_custom_text;
        }
    }
}
//--></script>
MOODS
                }
                
                $out .= "<tr valign='top'><th>" . BML::ml('entryform.mood') . "</th><td>";
                $out .= LJ::html_select({ 'name' => 'prop_current_moodid', 'id' => 'prop_current_moodid',
                                          'selected' => $sel, 'onchange' => "mood_preview()", 
                                          'tabindex' => $tabindex->() }, @moodlist);
                $out .= " " . LJ::html_text({ 'name' => 'prop_current_mood', 'id' => 'prop_current_mood',
                                              'value' => $opts->{'prop_current_mood'}, 'onchange' => "mood_preview()",
                                              'size' => '15', 'maxlength' => '30',
                                              'tabindex' => $tabindex->() });
                my $mood_preview = LJ::ejs("<p id='mood_preview'><img src='javascript:true' alt='' id='mood_image_preview' /> <span id='mood_text_preview'></span></p>");
                $out .= "<script type='text/javascript' language='JavaScript'>\n<!--\ndocument.write(\"$mood_preview\");\n//-->\n</script>" if $remote;
                $out .= "</td></tr>";
            }

            # Tag labeling
            unless ($LJ::DISABLED{tags}) {
                $out .= "<tr><th>" . BML::ml('entryform.tags') . "</th><td>";
                $out .= LJ::html_text(
                    {
                        'name'      => 'prop_taglist',
                        'size'      => '35',
                        'value'     => $opts->{'prop_taglist'},
                        'maxlength' => '255',
                        'tabindex'  => $tabindex->()
                    }
                );
                $out .= LJ::help_icon('addtags');
                $out .= "</td></tr>";
            }

            $out .= "</table></td>";
        }
        ### Options Column 2
        {
            $out .= "<td style='text-align: center' id='column_two_td'>";
            $out .= "<table style='text-align: left;' id='column_two_table'>";
            
            # Backdate Entry
            $out .= "<tr id='backdate_row'><th><label for='prop_opt_backdated'>" . BML::ml('entryform.backdated') . "</label></th><td>";
            $out .= LJ::html_check({ 'type' => "check", 'id' => "prop_opt_backdated", 
                                     'name' => "prop_opt_backdated", "value" => 1, 
                                     'selected' => $opts->{'prop_opt_backdated'},
                                     'tabindex' => $tabindex->() });
            $out .= "</td></tr>";
            
            # Comment Settings
            my $comment_settings_selected = $opts->{'prop_opt_noemail'} ? "noemail" : 
                $opts->{'prop_opt_nocomments'} ? "nocomments" : "";
            $comment_settings_selected  ||= $opts->{'comment_settings'};
            
            $out .= "<tr valign='top' id='comment_settings_row'><th style='white-space: nowrap'>" . BML::ml('entryform.comment.settings') . "</th><td>";
        $out .= LJ::html_select({ 'name' => "comment_settings", 'selected' => $comment_settings_selected,
                                  'tabindex' => $tabindex->() },
                                "", BML::ml('entryform.comment.settings.default'), "noemail", BML::ml('entryform.comment.settings.noemail'), "nocomments", BML::ml('entryform.comment.settings.nocomments'));
            $out .= "</td></tr>";
            
            # Comment Screening settings
            $out .= "<tr id='comment_screen_settings_row'><th>" . LJ::help_icon("screening", "", " ") . BML::ml('entryform.comment.screening') . "</th><td>";
            my @levels = ('', BML::ml('label.screening.default'), 'N', BML::ml('label.screening.none'),
                          'R', BML::ml('label.screening.anonymous'), 'F', BML::ml('label.screening.nonfriends'),
                          'A', BML::ml('label.screening.all'));
            $out .= LJ::html_select({ 'name' => 'prop_opt_screening', 'selected' => $opts->{'prop_opt_screening'},
                                      'tabindex' => $tabindex->() }, @levels);
            $out .= "</td></tr>";
            
            my $userpic_preview = "";
            # User Picture
            if ($res && ref $res->{'pickws'} eq 'ARRAY' && scalar @{$res->{'pickws'}} > 0) {
                my @pickws = map { ($_, $_) } @{$res->{'pickws'}};
                my $num = 0;
                $userpics .= "    userpics[$num] = \"$res->{'defaultpicurl'}\";\n";
                foreach (@{$res->{'pickwurls'}}) {
                    $num++; 
                    $userpics .= "    userpics[$num] = \"$_\";\n";
                }
                $$onload .= " userpic_preview();";
                $$head .= <<USERPICS;
<script type="text/javascript" language="JavaScript"><!--
if (document.getElementById) {
    var userpics = new Array();
    $userpics
    function userpic_preview() {
        if (! document.getElementById) return false;
        var userpic_select          = document.getElementById('prop_picture_keyword');
        var userpic_preview         = document.getElementById('userpic_preview');
        var userpic_preview_image   = document.getElementById('userpic_preview_image');

        if (userpics[userpic_select.selectedIndex] != "") {
            userpic_preview.style.display = "block";
            userpic_preview_image.src = userpics[userpic_select.selectedIndex];
        }
    }
}
//--></script>
USERPICS
                $out .= "<tr id='userpic_list_row' valign='top'>";
                $out .= "<th>" . LJ::help_icon("userpics", "", " ") . BML::ml('entryform.userpics') . "</th><td>";
                $out .= LJ::html_select({'name' => 'prop_picture_keyword', 'id' => 'prop_picture_keyword',
                                         'selected' => $opts->{'prop_picture_keyword'}, 'onchange' => "userpic_preview()",
                                         'tabindex' => $tabindex->() },
                                        "", BML::ml('entryform.opt.defpic'),
                                        @pickws);
                $out .= "</td></tr>\n";
                
                $userpic_preview = "<script type='text/javascript' language='JavaScript'>\n<!--\ndocument.write(\"" . 
                    LJ::ejs("<p id='userpic_preview' style='display: none'>" .
                            "<img src='' alt='selected userpic' id='userpic_preview_image' /></p>") .
                            "\");\n//-->\n</script>" if $remote;
            }
            $out .= "</table></td>";
            if ($userpic_preview ne "") { $out .= "<td style='width: 104px; text-align: left'>$userpic_preview</td>"; }
        }
        
        $out .= "</tr></table>";
    }
    ### Submit Bar
    {
        $out .= "<p style='text-align: center'><div id='SubmitBar'>";
        if ($opts->{'mode'} eq "update") {
            # communities the user can post in
            my $usejournal = $opts->{'usejournal'};
            if ($usejournal) {
                $out .= "<b>" . BML::ml('entryform.postto') . "</b> ";
                $out .= LJ::ljuser($usejournal);
                $out .= LJ::html_hidden('usejournal' => $usejournal, 'usejournal_set' => 'true');
            } elsif ($res && ref $res->{'usejournals'} eq 'ARRAY') {
                $out .= "<span id='usejournal_list'><b>" . BML::ml('entryform.postto') . "</b> ";
                $out .= LJ::html_select({ 'name' => 'usejournal', 'selected' => $usejournal,
                                          'tabindex' => $tabindex->() },
                                        "", $remote->{'user'},
                                        map { $_, $_ } @{$res->{'usejournals'}}) . "</span>\n";
            }
        }

        if ($opts->{'mode'} eq "update") {
            my $onclick = "";
            if ($opts->{'richtext_on'} || ! $LJ::IS_SSL) {
                $onclick .= "updateRTE('rte'); " if $opts->{'richtext_on'};
                $onclick .= "return sendForm('updateForm');" if ! $LJ::IS_SSL;
            }
            $out .= LJ::html_submit('action:update', BML::ml('entryform.update'), { 'onclick' => $onclick, 
                                                                                    'tabindex' => $tabindex->() }) . "&nbsp;";
        }

        if ($opts->{'mode'} eq "edit") {
            $out .= LJ::html_submit('action:save', BML::ml('entryform.save'),
                                    { 'disabled' => $opts->{'disabled_save'},
                                      'tabindex' => $tabindex->() }) . "&nbsp;";
            $out .= LJ::html_submit('action:delete', BML::ml('entryform.delete'), {
                'disabled' => $opts->{'disabled_delete'},
                'tabindex' => $tabindex->(),
                'onclick' => "return confirm('" . LJ::ejs(BML::ml('entryform.delete.confirm')) . "')" }) . "&nbsp;";
            

            if (!$opts->{'disabled_spamdelete'}) {
                $out .= LJ::html_submit('action:deletespam', BML::ml('entryform.deletespam'), {
                    'onclick' => "return confirm('" . LJ::ejs(BML::ml('entryform.deletespam.confirm')) . "')",
                    'tabindex' => $tabindex->() });
            }
        }
        if ($LJ::SPELLER && !$opts->{'disabled_save'}) {
            my $onclick = "updateRTE('rte');" if $opts->{'richtext_on'};
            $out .= LJ::html_submit('action:spellcheck', BML::ml('entryform.spellcheck'), { 'onclick' => $onclick,
                                                                                            'tabindex' => $tabindex->() }) . "&nbsp;";
        }

        my $preview = "var f=this.form; var action=f.action; f.action='/preview/entry.bml'; f.target='preview'; ";
        $preview   .= "window.open('','preview','width=760,height=600,resizable=yes,status=yes,toolbar=no,location=no,menubar=no,scrollbars=yes'); ";
        $preview   .= "updateRTE('rte'); " if $opts->{'richtext_on'};
        $preview   .= "f.submit(); f.action=action; f.target='_self'; return false; ";
        $preview    = LJ::ejs(LJ::html_submit('action:preview', BML::ml('entryform.preview'), { 'onclick' => $preview,
                                                                                                'tabindex' => $tabindex->() }));
        if(!$opts->{'disabled_save'}) {
            $out .= <<PREVIEW;
<script type="text/javascript" language="JavaScript">
<!--
if (document.getElementById) {
    document.write("$preview ");
}
//-->
</script>
PREVIEW
        }
        $out .= "</div></p>";
    }
    $out .= "</div>";
    return $out;
}

# <LJFUNC>
# name: LJ::entry_form_decode
# class: web
# des: Decodes an entry_form into a protocol compatible hash
# info: Generate form with [func[entry_form]].
# args: req, post
# des-req: protocol request hash to build
# des-post: entry_form POST contents
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
    $req->{'year'} = $year; $req->{'mon'} = $mon; $req->{'day'} = $day;

    foreach ( "year", "mon", "day" ) {
        $req->{$_} = $POST->{$_} if $POST->{$_} ne "";
    }

    # copy some things from %POST
    foreach (qw(subject hour min
                prop_picture_keyword prop_current_moodid
                prop_current_mood prop_current_music
                prop_opt_screening prop_opt_noemail
                prop_opt_preformatted prop_opt_nocomments
                prop_taglist)) {
        $req->{$_} = $POST->{$_};
    }

    $req->{"prop_opt_preformatted"} ||= $POST->{'event_format'} eq "preformatted" ? 1 : 0;
    $req->{"prop_opt_nocomments"}   ||= $POST->{'comment_settings'} eq "nocomments" ? 1 : 0;
    $req->{"prop_opt_noemail"}      ||= $POST->{'comment_settings'} eq "noemail" ? 1 : 0;
    $req->{'prop_opt_backdated'}      = $POST->{'prop_opt_backdated'} ? 1 : 0;
    
    # Convert the rich text editor output back to parsable lj tags.
    my $event = $POST->{'event'};
    if ($POST->{'richtext'}) {
        # check for blank entry
        (my $event_tmp = $event) =~ s!(?:<br>|<P>(?:&nbsp;|\s)+</P>|&nbsp;)\s*?!!gm;
        if ($event_tmp =~ /\w/) { # ok, we still have content
            $event =~ s/&lt;(\/)?lj-cut(.*?)(?: \/)?&gt;/<$1lj-cut$2>/ig;
            $event =~ s/&lt;lj user=['"]?(\w{1,15})['"]?\s?\/?&gt;/<lj user="$1" \/>/ig; # manually typed tags
            $event =~ s/<span class="?ljuser"?.*?userinfo\.bml\?user=(.+?)".*?<\/b><\/a>(?:<\/span>)?/<lj user="$1" \/>/ig;
        } else { # RTE blanks (just <br>, newlines, &nbsp; - no real content)
            $event = undef; # force protocol error
        }
    }
    $req->{'event'} = $event;

    ## see if an "other" mood they typed in has an equivalent moodid
    if ($POST->{'prop_current_mood'}) {
        if (my $id = LJ::mood_id($POST->{'prop_current_mood'})) {
            $req->{'prop_current_moodid'} = $id;
            delete $req->{'prop_current_mood'};
        }
    }
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
    if (ref $obj eq "HASH") {
        my $ret = "{";
        foreach my $k (keys %$obj) {
            $ret .= "$k: " . js_dumper($obj->{$k}) . ",";
        }
        chop $ret;
        $ret .= "}";
        return $ret;
    } elsif (ref $obj eq "ARRAY") {
        my $ret = "[" . join(", ", map { js_dumper($_) } @$obj) . "]";
        return $ret;
    } else {
        return $obj if $obj =~ /^\d+$/;
        return "\"" . LJ::ejs($obj) . "\"";
    }
}

# Common challenge/response javascript, needed by both login pages and comment pages alike.
# Forms that use this should onclick='return sendForm()' in the submit button.
# Returns true to let the submit continue.
$LJ::COMMON_CODE{'chalresp_js'} = qq{
<script type="text/javascript" src="$LJ::JSPREFIX/md5.js"></script>
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

# Common Javascript function for auto-checking radio buttons on form
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

# Common Javascript functions for Quick Reply
$LJ::COMMON_CODE{'quickreply'} = q{
    <script language="JavaScript" type="text/javascript" src="/js/x_core.js"></script>
    <script language='Javascript' type='text/javascript'>
    <!--
    var lastDiv;
    lastDiv = 'qrdiv';

    function quickreply(dtid, pid, newsubject) {
        var ev = window.event;

        // on IE, cancel the bubble of the event up to the page. other
        // browsers don't seem to bubble events up registered this way.
        if (ev) {
            if (ev.stopPropagation)
               ev.stopPropagation();
            if ("cancelBubble" in ev)
                ev.cancelBubble = true;
        }

        // Mac IE 5.x does not like dealing with
        // nextSibling since it does not support it
        if (xIE4Up && xMac) { return true;}

        var ptalkid = xGetElementById('parenttalkid');
        ptalkid.value = pid;

        var rto = xGetElementById('replyto');
        rto.value = pid;

        var dtid_field = xGetElementById('dtid');
        dtid_field.value = dtid;

        var qr_div = xGetElementById('qrdiv');
        var cur_div = xGetElementById(dtid);

        if (lastDiv == 'qrdiv') {
            if (! showQRdiv(qr_div)) {
               return true;
            }

            // Only one swap
            if (! swapnodes(qr_div, cur_div)) {
                return true;
            }
        } else if (lastDiv != dtid) {
            var last_div = xGetElementById(lastDiv);

            // Two swaps
            if (! (swapnodes(last_div, cur_div) && swapnodes(qr_div, last_div))) {
                return true;
            }
        }

        lastDiv = dtid;

        var subject = xGetElementById('subject');
        subject.value = newsubject;

        var multi_form = xGetElementById('multiform');
        multi_form.action = '/talkpost_do.bml';

        // So it does not follow the link
        return false;
    }

    function moreopts()
    {
        var multi_form = xGetElementById('multiform');
        var basepath = xGetElementById('basepath');
        var dtid = xGetElementById('dtid');

        multi_form.action = basepath.value + dtid.value;
        return true;
    }

   function submitform()
   {
        var submit = xGetElementById('submitpost');
        submit.disabled = true;

        var submitmore = xGetElementById('submitmoreopts');
        submitmore.disabled = true;

        // New top-level comments
        var dtid = xGetElementById('dtid');
        if (dtid.value == 'top' || dtid.value == 'bottom') {
            dtid.value = 0;
        }

        var multi_form = xGetElementById('multiform');
        multi_form.submit();
   }

   function swapnodes (orig, to_swap) {
        var orig_pn = xParent(orig, true);
        var next_sibling = orig.nextSibling;
        var to_swap_pn = xParent(to_swap, true);
        if (! to_swap_pn) {
            return false;
        }

        to_swap_pn.replaceChild(orig, to_swap);
        orig_pn.insertBefore(to_swap, next_sibling);
        return true;
   }

   function checkLength() {
        var textbox = xGetElementById('body');
        if (!textbox) return true;
        if (textbox.value.length > 4300) {
             alert('Sorry, but your comment of ' + textbox.value.length + ' characters exceeds the maximum character length of 4300.  Please try shortening it and then post again.');
             return false;
        }
        return true;
   }

    // Maintain entry through browser navigations.
    function save_entry() {
        var qr_body = xGetElementById('body');
        var qr_subject = xGetElementById('subject');
        var do_spellcheck = xGetElementById('do_spellcheck');
        var qr_dtid = xGetElementById('dtid');
        var qr_ptid = xGetElementById('parenttalkid');
        var qr_upic = xGetElementById('prop_picture_keyword');

        document.multiform.saved_body.value = qr_body.value;
        document.multiform.saved_subject.value = qr_subject.value;
        document.multiform.saved_spell.value = do_spellcheck.checked;
        document.multiform.saved_dtid.value = qr_dtid.value;
        document.multiform.saved_ptid.value = qr_ptid.value;

        if (qr_upic) { // if it was in the form
            document.multiform.saved_upic.value = qr_upic.selectedIndex;
        }

        return false;
    }

    // Restore saved_entry text across platforms.
    function restore_entry() {
        var saved_body = xGetElementById('saved_body');
        if (saved_body.value == "") return false;

        setTimeout(
            function () {

                var dtid = xGetElementById('saved_dtid');
                if (! dtid) return false;
                var ptid = xGetElementById('saved_ptid');
                if (! ptid) return false;

                quickreply(dtid.value, ptid.value, document.multiform.saved_subject.value);

                var body = xGetElementById('body');
                if (! body) return false;
                body.value = saved_body.value;

                // Some browsers require we explicitly set this after the div has moved
                // and is now no longer hidden
                var subject = xGetElementById('subject');
                if (! subject) return false;
                subject.value = document.multiform.saved_subject.value

                var prop_picture_keyword = xGetElementById('prop_picture_keyword');
                if (prop_picture_keyword) { // if it was in the form
                    prop_picture_keyword.selectedIndex = document.multiform.saved_upic.value;
                }

                var spell_check = xGetElementById('do_spellcheck');
                if (! spell_check) return false;
                if (document.multiform.saved_spell.value == 'true') {
                    spell_check.checked = true;
                } else {
                    spell_check.checked = false;
                }

            }, 100);
        return false;
    }

    function showQRdiv(qr_div) {
        if (! qr_div) {
            qr_div = xGetElementById('qr_div');
            if (! qr_div) {
                return false;
            }
        } else if (qr_div.style && xDef(qr_div.style.display)) {
            qr_div.style.display='inline';
            return true;
        } else {
            return false;
        }
    }

    //  -->
    </script>
};

1;
