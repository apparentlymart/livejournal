#!/usr/bin/perl
#

require "$ENV{'LJHOME'}/cgi-bin/ljconfig.pl";
require "$ENV{'LJHOME'}/cgi-bin/ljlang.pl";
require "$ENV{'LJHOME'}/cgi-bin/ljprotocol.pl";

use strict;

package LJ::Portal;
use vars qw(%box %colname
            );

%colname = ("left" => "Left Sidebar",
            "main" => "Main Area",
            "right" => "Right Sidebar",
            "moz" => "Mozilla Sidebar",
            );

# was using "use constant" here but the error logs filled up with
# warnings about redefinitions of subroutines. (constants are subs... great, perl.)
my $BOX_NAME  = 0;
my $BOX_ARGS  = 1;
my $BOX_POS   = 2;
my $BOX_DIRTY = 3;

sub get_box_size
{
    my $loc = shift;
    return $loc eq "main" ? "large" : "small";
}

sub get_box_types
{
    my $loc = shift;
    my $size = get_box_size($loc);
    return map { $_, $box{$_}->{'name'} } grep { $box{$_}->{$size} } sort keys %box;    
}

sub construct_page
{
    my $opts = shift;
    my $dbs = $opts->{'dbs'};
    my $dbh = $dbs->{'dbh'};
    my $dbr = $dbs->{'reader'};
    my $body = $opts->{'body'};
    my $remote = $opts->{'remote'};
    my $puri = $opts->{'puri'};
    $opts->{'border'} += 0;

    my %tdopts = ('main' => "",
                  'right' => "width=180",
                  'left' => "width=180",
                  );

    my $portopts = load_portopts($dbs, $remote);

    $$body .= "<table border=$opts->{'border'} cellpadding=3 width=100% height=500>\n";
    $$body .= "<tr valign=top>\n";
    foreach my $loc (@LJ::PORTAL_COLS)
    {
        next if ($loc eq "moz");

        $$body .= "<td $tdopts{$loc}>\n";

        $portopts->{$loc} ||= [];
        foreach my $pbox (@{$portopts->{$loc}})
        {
            my $bname = $pbox->[$BOX_NAME];
            my $bargs = $pbox->[$BOX_ARGS];
            next unless (ref $box{$bname}->{'handler'} eq "CODE");

            my $args = {};
            LJ::decode_url_string(\$bargs, $args);

            my $box = $box{$bname};
            $box->{'key'} = $bname;  # so we don't have to set it explicitly
            $box->{'args'} = $args;
            $box->{'loc'} = $loc;
            $box->{'pos'} = "$pbox->[$BOX_POS]";
            $box->{'uniq'} = "$loc$pbox->[$BOX_POS]";

            $box{$bname}->{'handler'}->($dbs, $remote, $opts, $box);
        }

        $$body .= "</td>\n";
    }
    $$body .= "</tr>\n";
    $$body .= "</table>\n";

    if ($opts->{'onload'}) {
        ${$opts->{'bodyopts'}} .= "onLoad=\"" . join('', keys %{$opts->{'onload'}}) . "\"";
    }

}

sub load_portopts
{
    my $dbs = shift;
    my $remote = shift;
    my $dbr = $dbs->{'reader'};

    my $portopts;

    # if user is logged in, see if they've defined their portal box settings:
    if ($remote) 
    {
        my $sth = $dbr->prepare("SELECT loc, pos, boxname, boxargs FROM portal WHERE userid=$remote->{'userid'} ORDER BY loc, pos");
        $sth->execute;
        while (my $row = $sth->fetchrow_hashref)
        {
            push @{$portopts->{$row->{'loc'}}}, [ $row->{'boxname'}, $row->{'boxargs'}, $row->{'pos'} ];
        }
    } 
   
    # if the user isn't logged in, or they haven't defined their portal boxes,
    # then give them the defaults:
    unless ($portopts) 
    {
        if ($remote) {
            $portopts = $LJ::PORTAL_LOGGED_IN;
        } else {
            $portopts = $LJ::PORTAL_LOGGED_OUT;
        }

        ## set the 'pos' argument on each box arrayref
        ## so it doesn't have to be set explicitly in ljconfig.pl, which would be tedious.
        ## also, set the dirty flag to true, so a subsequent save will change it
        foreach my $loc (keys %$portopts) {
            for (my $i=0; $i < scalar(@{$portopts->{$loc}}); $i++) {
                $portopts->{$loc}->[$i]->[$BOX_POS] = $i+1;
                $portopts->{$loc}->[$i]->[$BOX_DIRTY] = 1;
            }
        }

    }

    return $portopts;
}

sub count_boxes
{
    my $portopts = shift;
    my $count = 0;
    foreach my $loc (keys %$portopts) {
        for (my $i=0; $i < scalar(@{$portopts->{$loc}}); $i++) {
            my $box = $portopts->{$loc}->[$i];
            if ($box->[$BOX_NAME]) { $count++; }
        }
    }
    return $count;
}

sub save_portopts
{
    my $dbs = shift;
    my $dbh = $dbs->{'dbh'};
    my $remote = shift;
    my $portopts = shift;

    my $userid = $remote->{'userid'}+0;
    return unless ($userid);

    my @delsql;

    my $sql;
    foreach my $loc (keys %$portopts) {
        for (my $i=0; $i < scalar(@{$portopts->{$loc}}); $i++) {
            my $box = $portopts->{$loc}->[$i];
            next unless ($box->[$BOX_DIRTY]);

            my $qloc = $dbh->quote($loc);
            my $qpos = $box->[2] + 0;
            if ($box->[$BOX_NAME]) {
                # modifying
                my $qboxname = $dbh->quote($box->[$BOX_NAME]);
                my $qboxargs = $dbh->quote($box->[$BOX_ARGS]);
                $sql ||= "REPLACE INTO portal (userid, loc, pos, boxname, boxargs) VALUES ";
                $sql .= "($userid, $qloc, $qpos, $qboxname, $qboxargs),";
            } else {
                # deleting
                push @delsql, "DELETE FROM portal WHERE userid=$userid AND loc=$qloc AND pos=$qpos";
            }
            $box->[$BOX_DIRTY] = 0;
        }
    }

    if ($sql) {
        chop $sql;
        $dbh->do($sql);
    }
    foreach (@delsql) {
        $dbh->do($_);
    }
}

sub delete_box
{
    my $portopts = shift;
    my $loc = shift;
    my $pos = shift;
    my $bname = shift;

    return unless (defined $portopts->{$loc}->[$pos-1]);
    my $box = $portopts->{$loc}->[$pos-1];
    return unless ($box->[$BOX_NAME] eq $bname);
    
    # time to delete it... move everything else up.
    my $locsize = scalar(@{$portopts->{$loc}});

    # else, move everything else up, and mark the file one dirty;
    for (my $i=$pos; $i < $locsize; $i++) {
        $portopts->{$loc}->[$i-1] = $portopts->{$loc}->[$i];
        $portopts->{$loc}->[$i-1]->[$BOX_POS] = $i;
        $portopts->{$loc}->[$i-1]->[$BOX_DIRTY] = 1;
    }

    # final one is dirty and marked for deletion
    $portopts->{$loc}->[$locsize-1] = [ "", "", $locsize, 1];

}

sub move_box
{
    my $portopts = shift;
    my $loc = shift;
    my $pos = shift;
    my $bname = shift;
    my $op = shift;

    return unless (defined $portopts->{$loc}->[$pos-1]);
    my $box = $portopts->{$loc}->[$pos-1];
    return unless ($box->[$BOX_NAME] eq $bname);

    # how many are in that column?
    my $locsize = scalar(@{$portopts->{$loc}});

    # can't move top up or bottom down.
    return if ($op eq "u" && $pos == 1);
    return if ($op eq "d" && $pos == $locsize);
    
    # destination position
    my $dpos = $pos + ($op eq "u" ? -1 : 1);

    # does that location exist to swap with?
    return unless (defined $portopts->{$loc}->[$dpos-1]);

    # swap locations!
    ($portopts->{$loc}->[$dpos-1], $portopts->{$loc}->[$pos-1]) = 
        ($portopts->{$loc}->[$pos-1], $portopts->{$loc}->[$dpos-1]);

    # set their locations and dirty flags
    foreach my $p ($pos, $dpos)
    {
        $portopts->{$loc}->[$p-1]->[$BOX_POS] = $p;
        $portopts->{$loc}->[$p-1]->[$BOX_DIRTY] = 1;
    }
}

sub make_box_modify_form
{
    my $portopts = shift;
    my $loc = shift;
    my $pos = shift;

    return "" unless (defined $portopts->{$loc}->[$pos-1]);
    my $box = $portopts->{$loc}->[$pos-1];

    my $curargs = {};
    LJ::decode_url_string(\$box->[$BOX_ARGS], $curargs);
    
    my $ret = "";

    foreach my $opt (@{$box{$box->[$BOX_NAME]}->{'opts'}})
    {
        unless ($ret) {
            $ret .= "<form method=post action=\"/portal/alter.bml\"><input type=hidden name=op value=modbox><input type=hidden name=loc value=$loc><input type=hidden name=pos value=$pos>";
        }
        
        $ret .= "<p><b>$opt->{'name'}:</b> ";
        my $key = $opt->{'key'};
        if ($opt->{'type'} eq "select") {
            $ret .= LJ::html_select({ 'name' => "arg_$key",
                                       'selected' => $curargs->{$key}, },
                                     @{$opt->{'values'}});
        }
        if ($opt->{'type'} eq "check") {
            $ret .= LJ::html_check({ 'name' => "arg_$key",
                                      'selected' => $curargs->{$key}, 
                                      'value' => 1 });
        }
        if ($opt->{'type'} eq "text") {
            $ret .= LJ::html_text({ 'name' => "arg_$key",
                                     'maxlength' => $opt->{'maxlength'}, 
                                     'size' => $opt->{'size'}, 
                                     'value' => $curargs->{$key} });
        }
        if ($opt->{'des'}) {
            $ret .= "<br>$opt->{'des'}";
        }
        
    }
    if ($ret) {
        $ret .= "<p><input type=submit value=\"Save box settings\">";
        $ret .= "</form>";
    }
    
    return $ret;

}

sub modify_box
{
    my $dbs = shift;
    my $remote = shift;
    my $portopts = shift;
    my $loc = shift;
    my $pos = shift;
    my $form = shift;

    return "" unless (defined $portopts->{$loc}->[$pos-1]);
    my $box = $portopts->{$loc}->[$pos-1];

    my $newargs;
    
    foreach my $opt (@{$box{$box->[$BOX_NAME]}->{'opts'}})
    {
        if ($newargs) { $newargs .= "&"; }
        $newargs .= LJ::eurl($opt->{'key'}) . "=" . LJ::eurl($form->{"arg_$opt->{'key'}"});
        $box->[$BOX_ARGS] = $newargs;
        $box->[$BOX_DIRTY] = 1;
    }

    save_portopts($dbs, $remote, $portopts);
    return $newargs;
}

sub create_new_box
{
    my ($portopts, $bname, $loc) = @_;
    my $defargs;
    foreach my $opt (@{$box{$bname}->{'opts'}})
    {
        # if non-zero or non-blank default, remember it
        if ($opt->{'default'}) {
            $defargs .= "&" if ($defargs);
            $defargs .= LJ::eurl($opt->{'key'}) . "=" .  LJ::eurl($opt->{'default'});
        }
    }
    
    $portopts->{$loc} ||= [];
    my $size = scalar(@{$portopts->{$loc}});
    
    push @{$portopts->{$loc}}, [ $bname, $defargs, $size+1, 1 ];
}

sub make_box_link
{
    my $form = shift;
    my $bname = $form->{'bname'};

    my $args = "";
    foreach my $arg (@{$box{$bname}->{'args'}})
    {
        my $key = $arg->{'key'};
        my $val = $form->{"arg_$key"};
        if ($val) {
            $args .= "&$key=$val";
        }
    }
    my $title = $box{$bname}->{'name'} . " ($LJ::SITENAME)";
    
    return "$LJ::SITEROOT/portal/box.bml?bname=$bname$args";
}

# XXXXXXXX DEAD / OLD
sub make_mozilla_box
{
    my $dbs = shift;
    my $remote = shift;
    my $form = shift;
    my $opts = shift;

    my $bname = $form->{'bname'};
    return "" unless (ref $box{$bname}->{'handler'} eq "CODE");

    my $box = $box{$bname};
    $box->{'key'} = $bname;
    $box->{'args'} = $form;
    $box->{'pos'} = "moz";
    $box->{'loc'} = 1;
    $box->{'uniq'} = "moz1";
    $box{$bname}->{'handler'}->($dbs, $remote, $opts, $box);
}

sub make_mozilla_bar
{
    my $dbs = shift;
    my $remote = shift;
    my $form = shift;
    my $opts = shift;

    my $portopts = load_portopts($dbs, $remote);
    my $loc = "moz";
    
    foreach my $pbox (@{$portopts->{$loc}})
    {
        my $bname = $pbox->[$BOX_NAME];
        my $bargs = $pbox->[$BOX_ARGS];
        next unless (ref $box{$bname}->{'handler'} eq "CODE");
        
        my $args = {};
        LJ::decode_url_string(\$bargs, $args);
        
        my $box = $box{$bname};
        $box->{'key'} = $bname;  # so we don't have to set it explicitly
        $box->{'args'} = $args;
        $box->{'loc'} = $loc;
        $box->{'pos'} = "$pbox->[$BOX_POS]";
        $box->{'uniq'} = "$loc$pbox->[$BOX_POS]";
        
        $box{$bname}->{'handler'}->($dbs, $remote, $opts, $box);
    }
    
    
    if ($opts->{'onload'}) {
        ${$opts->{'bodyopts'}} .= "onLoad=\"" . join('', keys %{$opts->{'onload'}}) . "\"";
    }
}

sub box_start
{
    my ($b, $box, $opts) = @_;
    my $title = $opts->{'title'} || $box->{'name'};
    my $mapname = $box->{'uniq'};
    my $align = $opts->{'align'} || "left";
    my $t = join("-", $box->{'key'}, $box->{'loc'}, $box->{'pos'});

    $$b .= "<MAP name=$mapname>\n";
    $$b .= "<area shape=rect target=_self coords=0,0,16,16 href=/portal/alter.bml?op=d&amp;t=$t alt=Down>\n";
    $$b .= "<area shape=rect target=_self coords=16,0,32,16 href=/portal/alter.bml?op=u&amp;t=$t alt=Up>\n";
    $$b .= "<area shape=rect coords=32,0,48,16 href=/portal/alter.bml?op=a&amp;t=$t alt=\"Add/Modify\">\n";
    $$b .= "<area shape=rect target=_self coords=48,0,64,16 href=/portal/alter.bml?op=x&amp;t=$t alt=Kill>\n";
    $$b .= "</MAP>\n";

    if ($box->{'pos'} > 1) { $$b .= "<p>"; }
    $$b .= "<table width=100% bgcolor=<?emcolor?> border=0 cellpadding=1 cellspacing=0>";
    $$b .= "<tr bgcolor=<?emcolor?>><td bgcolor=<?emcolor?>>";
    $$b .= "<img align=right width=64 height=16 border=0 src=\"$LJ::IMGPREFIX/knobs.gif\" usemap=\"\#$mapname\"><b>";

    $$b .= "&nbsp;";
    if ($opts->{'url'}) { $$b .= "<a href=\"$opts->{'url'}\">"; }
    $$b .= $title;
    if ($opts->{'url'}) { $$b .= "</a>"; }
    $$b .= "</b></td></tr>\n";

    if ($box->{'loc'} eq "main") {
        $$b .="</table>\n";
    } else {
        $$b .= "<tr><td><table bgcolor=#ffffff width=100%><tr><td valign=top align=$align>";
    }
}

sub box_end
{
    my ($b, $box) = @_;
    unless ($box->{'loc'} eq "main")
    {
        $$b .= "</td></tr></table>\n";
        $$b .= "</td></tr></table>\n";
    }
}

############################################################################

$box{'login'} =
{
    'name' => 'Login Box',
    'small' => 1,
    'large' => 0,
    'handler' => sub {
        my ($dbs, $remote, $opts, $box) = @_;
        my $b = $opts->{'body'};

        box_start($b, $box, { 'title' => "Login", 
                              'align' => "center",
                              'url' => '/login.bml', });

        $$b .= "<form method='post' action='/login.bml'>";
        $$b .= "<input type='hidden' name='mode' value='login'>";
        $$b .= "<table><tr><td align=left>";
        $$b .= "<b>Username:</b><br><input name=user size=14 maxlength=15><br> ";
        $$b .= "<b>Password:</b><br><input name=password type=password size=14><br>";
        $$b .= "<input type=checkbox name=expire value=never> Remember me";
        $$b .= "<input type=hidden name=ref value=\"$LJ::SITEROOT$LJ::PORTAL_URI\">";
        $$b .= "</td></tr><tr><td align=right>";
        $$b .= "<input type=submit value=\"Login\">";
        $$b .= "</td></tr></table>";

        box_end($b, $box);
        $$b .= "</form>\n";
    },
};

############################################################################

$box{'newtolj'} =
{
    'name' => "Site Links",
    'small' => 1,
    'large' => 0,
    'handler' => sub {
        my ($dbs, $remote, $opts, $box) = @_;
        my $b = $opts->{'body'};

        box_start($b, $box, { 'title' => "About $LJ::SITENAME",
                              'align' => "left",
                              'url' => '/site/about.bml', });

        $$b .= "New to $LJ::SITENAME?";
        my @links = ("What is $LJ::SITENAME?", "/site/about.bml",
                     "Create an account!", "/create.bml");
        while (@links) {
            my $link = shift @links;
            my $url = shift @links;
            $$b .= "<li><a href=\"$url\"><b>$link</b></a>\n";
        }

        box_end($b, $box);
        $$b .= "</form>\n";
    },
};

############################################################################

$box{'stats'} =
{
    'name' => 'Site Statistics',
    'small' => 1,
    'large' => 0,
    'handler' => sub {
        my ($dbs, $remote, $opts, $box) = @_;
        my $dbr = $dbs->{'reader'};
        my $b = $opts->{'body'};
        my $sth;
        my @stats;
        my ($k, $v);

        box_start($b, $box, { 'title' => "Statistics",
                              'url' => '/stats.bml' });

        my %stat;
        $sth = $dbr->prepare("SELECT statkey, statval FROM stats WHERE statcat='statbox'");
        $sth->execute;
        while (my ($k, $v) = $sth->fetchrow_array) {
            $stat{$k} = $v;
        }

        push @stats, "Total users", $stat{'totusers'};
        push @stats, "Journal entries yesterday", $stat{'postyester'};
        
        $$b .= "<table>";
        while (@stats) {
            $k = shift @stats;
            $v = shift @stats;
            $$b .= "<tr><td><b>$k</b></td></tr>";
            $$b .= "<tr><td align=right>$v</td></tr>";
        }
        $$b .= "</table>";

        box_end($b, $box);
    },
};

############################################################################

$box{'bdays'} =
{
    'name' => "Friends' Birthdays",
    'small' => 1,
    'large' => 0,
    'opts' => [ { 'key' => 'count',
                  'name' => 'Birthdays to Display',
                  'des' => 'By default, the 5 friends with the soonest birthdays are shown.',
                  'type' => 'text',
                  'maxlength' => 3,
                  'size' => 3,		      
                  'default' => 5 },
                ],
    'handler' => sub {
        my ($dbs, $remote, $opts, $box) = @_;
        my $dbr = $dbs->{'reader'};
        my $bd = $opts->{'body'};
        my $sth;

        box_start($bd, $box, { 'title' => "Friends' Birthdays",
                              'url' => '/birthdays.bml' });

        $sth = $dbr->prepare("SELECT u.user, u.name, MONTH(bdate) AS 'month', DAYOFMONTH(bdate) AS 'day' FROM friends f, user u WHERE f.userid=$remote->{'userid'} AND f.friendid=u.userid AND u.journaltype='P' AND u.statusvis='V' AND u.allow_infoshow='Y' AND MONTH(bdate) != 0 AND DAYOFMONTH(bdate) != 0");
        $sth->execute;

        # what day is it now?  server time... suck, yeah.
        my @time = localtime();
        my ($mnow, $dnow) = ($time[4]+1, $time[3]);

        my @bdays;
        while (my ($user, $name, $m, $d) = $sth->fetchrow_array) {
            my $ref = [ $user, $name, $m, $d ];
            if ($m < $mnow || ($m == $mnow && $d < ($dnow-1))) {
                # birthday passed this year already
                $ref->[4] = 1;
            }
            push @bdays, $ref;
        }	    

        # sort birthdays that have passed this year after ones that haven't,
        # otherwise sort by month, otherwise by day.
        @bdays = sort {
            
            # passed sort
            ($a->[4] <=> $b->[4]) ||
                
            # month sort
                ($a->[2] <=> $b->[2]) ||
                        

            # day sort
                    ($a->[3] <=> $b->[3])

        } @bdays;

        # cut the list down
        my $show = ($box->{'args'}->{'count'} + 0) || 10;
        if ($show > 100) { $show = 100; }
        if (@bdays > $show) { @bdays = @bdays[0..$show-1]; }

        $$bd .= "<table width=100%>";
        my $lang = "EN";
        foreach my $bi (@bdays) 
        {
            my $mon = LJ::Lang::month_short($lang, $bi->[2]);
            my $day = $bi->[3] . LJ::Lang::day_ord($lang, $bi->[3]);
            $$bd .= "<tr><td nowrap><b><?ljuser $bi->[0] ljuser?></b></td><td align=right nowrap>$mon $day</td></tr>";
        }
        $$bd .= "</table>";

        box_end($bd, $box);
    },
};
############################################################################

$box{'lastnview'} =
{
    'name' => "Recent Entry View",
    'small' => 1,
    'large' => 1,
    'opts' => [ { 'key' => 'journal',
                  'name' => 'Journal',
                  'des' => 'What journal do you want to see the recent items from?',
                  'type' => 'text',
                  'maxlength' => 15,
                  'size' => 15,		      
                  'default' => '' },
                { 'key' => 'items',
                  'name' => 'Items to display',
                  'des' => 'By default, only the most interest entry is shown.',
                  'type' => 'text',
                  'maxlength' => 2,
                  'size' => 2,		      
                  'default' => 1 },
                { 'key' => 'mode',
                  'name' => 'Include text',
                  'type' => 'check',
                  'value' => 1,
                  'default' => 0,
                  'des' => 'By default only subjects will be shown.', },
                
                ],
    'handler' => sub {
        my ($dbs, $remote, $opts, $box) = @_;
        my $bd = $opts->{'body'};
        my $sth;

        my $user = LJ::canonical_username($box->{'args'}->{'journal'});
        my $items = $box->{'args'}->{'items'}+0 || 1;
        if ($items > 50) { $items = 50; }

        unless ($user)
        {
            box_start($bd, $box, { 'title' => "Recent Entry Box", });
            $$bd .= "You have to configure this box.  Click the plus symbol to setup the journal you'd like to watch here.";
            box_end($bd, $box);
            return;
        }

        my $u = LJ::load_user($dbs, $user);

        box_start($bd, $box, { 'title' => "$u->{'name'}",
                              'url' => "$LJ::SITEROOT/users/$user" });

        my @itemids;
        my @items = LJ::get_recent_items($dbs, {
            'userid' => $u->{'userid'},
            'skip' => 0,
            'itemshow' => $items,
            'itemids' => \@itemids,
            'order' => 	($u->{'journaltype'} eq "C") ? "logtime" : "",
        });

        unless (@itemids) {
            $$bd .= "No entries.";
            box_end($bd, $box);
            return;
        }

        # FIXME: need an LJ::get_logsubject 
        if ($box->{'args'}->{'showtext'}) {
        } else {
        }

        foreach my $item (@items)
        {
            my $subject = "(subject)"; # FIXME; see above
            $$bd .= "<a href=\"/talkread.bml?itemid=$item->{'itemid'}\">$subject</a>, ";
        }
        
        box_end($bd, $box);
    },
};

############################################################################

$box{'goat'} =
{
    'name' => 'Site Mascot',
    'small' => 1,
    'large' => 0,
    'opts' => [ { 'key' => 'misbehaved',
                  'name' => 'Mishaved Goat',
                  'des' => "You really wanted to leave this unchecked.  Goats that aren't housetrained are nothing but trouble.",
                  'type' => 'check',
                  'value' => 1,
                  'default' => 0, },
                { 'key' => 'goattext',
                  'name' => 'Goat Text',
                  'des' => "What do you want your goat to say?  The only true thing goats can say is 'Baaaaah', but you can pretend your goat can say something else if you really want.",
                  'type' => 'text',
                  'default' => "Baaaaah",
                  'size' => 40,
                  'maxlength' => 40, },
                ],
    'handler' => sub {
        my ($dbs, $remote, $opts, $box) = @_;
        my $b = $opts->{'body'};
        my $bo = $opts->{'bodyopts'};
        my $h = $opts->{'head'};
        my $pic;

        if ($opts->{'form'}->{'frank'} eq "urinate" || $box->{'args'}->{'misbehaved'}) {
            $pic = "pee";
        } else {
            $pic = "hover";
        }

        box_start($b, $box, { 'title' => "Frank",
                              'align' => "center",
                              'url' => "/site/goat.bml", });

        my $imgname = "frankani" . $box->{'uniq'};
        my $goattext = $box->{'args'}->{'goattext'} || "Baaaah";

        $$b .= <<"GOAT_STUFF";
<A onMouseOut="MM_swapImgRestore()" onMouseOver="MM_swapImage('$imgname','','$LJ::IMGPREFIX/goat-$pic.gif',1)" HREF="/site/goat.bml"><IMG NAME="$imgname" SRC="$LJ::IMGPREFIX/goat-normal.gif" WIDTH=110 HEIGHT=101 HSPACE=2 VSPACE=2 BORDER=0 ALT="Frank, the LiveJournal mascot goat."></A><BR>
<!--
<A HREF="/site/goat.bml"><IMG SRC="$LJ::IMGPREFIX/goat-irish.gif" WIDTH=110 HEIGHT=101 HSPACE=2 VSPACE=2 BORDER=0 ALT="Frank, the LiveJournal mascot goat."></A> 
-->
<B><I>"$goattext"</I> says Frank.
GOAT_STUFF
    
    box_end($b, $box);

        $opts->{'onload'}->{"MM_preloadImages('$LJ::IMGPREFIX/goat-$pic.gif');"} = 1;

        unless ($opts->{'did'}->{'image_javascript'}) 
        {
            $opts->{'did'}->{'image_javascript'} = 1;

        $$h .= <<'JAVASCRIPT';
<script language="JavaScript">
<!--
function MM_swapImgRestore() { //v3.0
  var i,x,a=document.MM_sr; for(i=0;a&&i<a.length&&(x=a[i])&&x.oSrc;i++) x.src=x.oSrc;
}

function MM_preloadImages() { //v3.0
  var d=document; if(d.images){ if(!d.MM_p) d.MM_p=new Array();
    var i,j=d.MM_p.length,a=MM_preloadImages.arguments; for(i=0; i<a.length; i++)
    if (a[i].indexOf("#")!=0){ d.MM_p[j]=new Image; d.MM_p[j++].src=a[i];}}
}

function MM_findObj(n, d) { //v3.0
  var p,i,x;  if(!d) d=document; if((p=n.indexOf("?"))>0&&parent.frames.length) {
    d=parent.frames[n.substring(p+1)].document; n=n.substring(0,p);}
  if(!(x=d[n])&&d.all) x=d.all[n]; for (i=0;!x&&i<d.forms.length;i++) x=d.forms[i][n];
  for(i=0;!x&&d.layers&&i<d.layers.length;i++) x=MM_findObj(n,d.layers[i].document); return x;
}

function MM_swapImage() { //v3.0
  var i,j=0,x,a=MM_swapImage.arguments; document.MM_sr=new Array; for(i=0;i<(a.length-2);i+=3)
   if ((x=MM_findObj(a[i]))!=null){document.MM_sr[j++]=x; if(!x.oSrc) x.oSrc=x.src; x.src=a[i+2];}
}
//-->
</script>
JAVASCRIPT

        }  # end unless


    },  # end handler
    
};

############################################################################

$box{'update'} =
{
    'name' => 'Journal Update',
    'small' => 0,
    'large' => 1,
    'opts' => [ { 'key' => 'mode',
                  'name' => 'Mode',
                  'type' => 'select',
                  'des' => 'Full mode gives you a ton of extra posting options ... including posting in communities and setting your current mood, music, and picture.  Simple mode is nicer if you hardly use those features and would prefer not to see it all.',
                  'values' => [ "", "Simple",
                                "full", "Full" ],
                  'default' => "" },
                ],
    'handler' => sub 
    {
        my ($dbs, $remote, $opts, $box) = @_;
        my $bd = $opts->{'body'};
        my $h = $opts->{'head'};

        $opts->{'onload'}->{"settime(updateForm$box->{'uniq'});"} = 1;
        
        box_start($bd, $box, {'title' => "Update Your Journal",
                             'url' => "$LJ::SITEROOT/update.bml",
                         });

        my $mode = $opts->{'form'}->{'mode'} || $box->{'args'}->{'mode'};

        $$bd .= "<FORM METHOD=POST ACTION=\"/update.bml\" NAME=updateForm$box->{'uniq'}>";
        $$bd .= "<INPUT TYPE=HIDDEN NAME=mode VALUE=update>";
        $$bd .= "<INPUT TYPE=HIDDEN NAME=oldmode VALUE=$mode>";

        my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
        $year+=1900;
        $mon=sprintf("%02d", $mon+1);
        $mday=sprintf("%02d", $mday);
        $min=sprintf("%02d", $min);

        $$bd .= "<table>";
        if ($remote) {
            $$bd .= "<input type=hidden name=usertype value=remote>";
            $$bd .= "<tr><td><b>Logged in user:</b> $remote->{'user'} (<a href=\"/update.bml?altlogin=1\">other user?</a>)</td></tr>\n";
        } else {
            $$bd .= "<input type=hidden name=usertype value=explicit>";
            $$bd .= "<tr><td><b>User:</b> <input name=user size=10 maxlength=15> ";
            $$bd .= "Password: <input type=password name=password size=10> ";
            $$bd .= "</td></tr>";
        }
        $$bd .= "</table>";

        $$bd .= "<table><tr><td><b>Date:</b> <tt>yyyy-mm-dd</tt></td><td><b>Local time:</b> <tt>hh:mm</tt> (24 hour time)</td></tr>\n";
        $$bd .= "<tr><td><INPUT NAME=year SIZE=4 MAXLENGTH=4 VALUE=$year>-";
        $$bd .= "<INPUT NAME=mon SIZE=2 MAXLENGTH=2 VALUE=$mon>-";
        $$bd .= "<INPUT NAME=day SIZE=2 MAXLENGTH=2 VALUE=$mday>&nbsp;&nbsp;&nbsp;</td>";

        $$bd .= "<td><INPUT NAME=hour SIZE=3 MAXLENGTH=2 VALUE=$hour>:";
        $$bd .= "<INPUT NAME=min SIZE=3 MAXLENGTH=2 VALUE=$min></td></tr></table>\n";


        $$bd .= "<noscript><p style=\"font-size: 0.85em;\"><b>Note:</b> The time/date above is from our server.  Correct them for your timezone before posting.</p></noscript>";
        
        $$bd .= "<TABLE><TR><TD><B>Subject:</B> <I>(optional)</I><BR>";
        $$bd .= "<INPUT NAME=\"subject\" SIZE=50 MAXLENGTH=100 VALUE=\"" . LJ::ehtml($opts->{'form'}->{'subject'}) . "\"><br>";
        
        $$bd .= "<B>Event:</B><BR>";
        $$bd .= "<TEXTAREA NAME=\"event\" COLS=50 ROWS=10 WRAP=VIRTUAL>";
        $$bd .= LJ::ehtml($opts->{'form'}->{'event'});
        $$bd .= "</TEXTAREA>";
        $$bd .= "<BR><?de (HTML okay; by default, newlines will be auto-formatted to <TT>&lt;BR&gt;</TT>) de?><BR>";
        $$bd .= "<input type=checkbox name=do_spellcheck value=1 id=\"spellcheck\"> <label for=\"spellcheck\">Spell check entry before posting</label>";
        $$bd .= "</TD></TR><TR><TD ALIGN=CENTER><INPUT TYPE=SUBMIT VALUE=\"Update Journal\"></TD></TR>";
        
        if ($mode eq "full") 
        {
            my %res;
            
            if (! $opts->{'form'}->{'altlogin'} && $remote)
            {
                LJ::do_request($dbs, { "mode" => "login",
                                       "ver" => $LJ::PROTOCOL_VER,
                                        "user" => $remote->{'user'},
                                        "getpickws" => 1,
                                    }, \%res, { "noauth" => 1, "userid" => $remote->{'userid'} });
            }
            
            $$bd .= "<TR><TD NOWRAP><INPUT TYPE=hidden NAME=webversion VALUE=full><?h2 Optional Settings h2?>";
            
            if ($res{'access_count'}) {
                $$bd .= "<P><B>Journal to post in: </B> ";
                my @access;
                for (my $i=1; $i<=$res{'access_count'}; $i++) {
                    push @access, $res{"access_$i"};
                }
                $$bd .= LJ::html_select({ 'name' => 'usejournal', 'selected' => $opts->{'form'}->{'usejournal'}, },
                                    "", "($remote->{'user'}) -- default", map { $_, $_ } @access);
            }
            
            $$bd .= "<P><B>Security Level:</B> ";
            $$bd .= LJ::html_select({ 'name' => 'security', 'selected' => $opts->{'form'}->{'security'}, },
                                "public", "Public",
                                "private", "Private",
                                "friends", "Friends");
            $$bd .= LJ::help_icon("security", " ");
            my $checked;
            $checked = $opts->{'form'}->{'prop_opt_preformatted'} ? "CHECKED" : "";
            $$bd .= "<P> <B>Don't auto-format:</B><INPUT TYPE=CHECKBOX NAME=\"prop_opt_preformatted\" VALUE=1 $checked>";
            $$bd .= LJ::help_icon("noautoformat", " ");
            $$bd .= " &nbsp; ";
            $checked = $opts->{'form'}->{'prop_opt_nocomments'} ? "CHECKED" : "";
            $$bd .= "<B>Disallow Comments:</B><INPUT TYPE=CHECKBOX NAME=\"prop_opt_nocomments\" VALUE=1 $checked>";
            
            $checked = $opts->{'form'}->{'prop_opt_backdated'} ? "CHECKED" : "";
            $$bd .= "<P><b>Backdate Entry:</b><INPUT TYPE=CHECKBOX NAME=\"prop_opt_backdated\" VALUE=1 $checked> (will only show on calendar)";
            
            if ($res{'pickw_count'}) {
                $$bd .= "<P><B>Picture to use:</B> ";
                my @pics;
                for (my $i=1; $i<=$res{'pickw_count'}; $i++) {
                    push @pics, $res{"pickw_$i"};
                }
                @pics = sort { lc($a) cmp lc($b) } @pics;
                $$bd .= LJ::html_select({'name' => 'prop_picture_keyword', 
                                     'selected' => $opts->{'form'}->{'prop_picture_keyword'}, },
                                    ("", "(default)", map { ($_, $_) } @pics));
                $$bd .= LJ::help_icon("userpics", " ");
            } else {
                $$bd .= "<P><B>$res{'errmsg'}</B>";
            }
            
            $$bd .= "<P><B>Current <A HREF=\"/moodlist.bml\">Mood</A>:</B>";
            
            LJ::load_moods($dbs);
            my @sel;
            foreach my $moodid (sort { $LJ::CACHE_MOODS{$a}->{'name'} cmp  
                                           $LJ::CACHE_MOODS{$b}->{'name'} } keys %LJ::CACHE_MOODS)
            {
                push @sel, $moodid, $LJ::CACHE_MOODS{$moodid}->{'name'};
            }
            
            $$bd .= LJ::html_select({'name' => 'prop_current_moodid',
                                     'selected' => $opts->{'form'}->{'prop_current_moodid'}, },
                                    ("", "None, or other:", @sel));
            
            $$bd .= "Other: <INPUT NAME=\"prop_current_mood\" SIZE=15 MAXLENGTH=30 VALUE=\"" . LJ::ehtml($opts->{'form'}->{'prop_current_mood'}) . "\">";
            $$bd .= "<P><B>Current Music:</B> <INPUT NAME=\"prop_current_music\" SIZE=40 MAXLENGTH=60 VALUE=\"" . LJ::ehtml($opts->{'form'}->{'prop_current_music'}) . "\">";
            $$bd .= "</TD></TR><TR><TD ALIGN=CENTER><INPUT TYPE=SUBMIT VALUE=\"Update Journal\"></td></tr>";
            
        }
        else 
        {
            $$bd .= "<TR><TD><?de For more options, modify this portal box or <A HREF=\"/update.bml\">go here</A>. de?></TD></TR>\n";
        }
        
        $$bd .= "</TABLE></FORM>";

        $$h .= <<'JAVASCRIPT_STUFF';
<SCRIPT LANGUAGE="JavaScript"><!--
        // for those of you reading the source.... the server will
        // automatically fill in the form with the time values for
        // the west coast, but what this does is if the client can
        // use JavaScript (nearly 99% of the time nowadays), we'll
        // prefill the time in from their computer's clock
function settime(f) {
        function twodigit (n) {
                if (n < 10) { return "0" + n; }
                else { return n; }
        }

        now = new Date();
        // javascript getYear method is really fucked up:
        f.year.value = now.getYear() < 1900 ? now.getYear() + 1900 : now.getYear();
        f.mon.value = twodigit(now.getMonth()+1);
        f.day.value = twodigit(now.getDate());
        f.hour.value = twodigit(now.getHours());
        f.min.value = twodigit(now.getMinutes());
}

// --></SCRIPT>
JAVASCRIPT_STUFF

box_end($bd, $box);

        
    },
};

####################################

## TODO: let user specify number of random people, and have them 
## go horizontally or vertically.
$box{'randuser'} =
{
    'name' => 'Random User',
    'small' => 1,
    'large' => 1,
    'opts' => [ { 'key' => 'hidepic',
                  'name' => 'Hide User Picture',
                  'type' => 'check',
                  'des' => "By default, the random user picture is shown, if available.  Check this to remove it.",
                  'default' => 0 },
                { 'key' => 'hidename',
                  'name' => 'Hide Name',
                  'type' => 'check',
                  'des' => "By default, the random user name is shown.  Check this to remove it.",
                  'default' => 0 },
                { 'key' => 'count',
                  'name' => 'Number of random users to show',
                  'des' => "By default, 1 random user is shown, but you can have up to 10 vertically in the narrow columns, or 5 horizontally in a wide column",
                  'type' => 'text',
                  'maxlength' => 2,
                  'size' => 2,
                  'default' => 1 },
                ],
    'handler' => sub 
    {
        my ($dbs, $remote, $opts, $box) = @_;
        my $dbr = $dbs->{'reader'};
        my $b = $opts->{'body'};
        my $h = $opts->{'head'};

        my $size = get_box_size($box->{'loc'});
        my $count = int($box->{'args'}->{'count'});
        if ($count < 1) { $count = 1; }
        if ($size eq "small" && $count > 5) { $count = 5; }
        if ($size eq "large" && $count > 10) { $count = 10; }

        my $max = $dbr->selectrow_array("SELECT statval FROM stats WHERE statcat='userinfo' AND statkey='randomcount'");
        $count = $max if ($count > $max);
        my %ruserid;
        while (keys %ruserid < $count) {
            $ruserid{int(rand($max))+1} = 1;
        }

        unless ($count) {
            box_start($b, $box, {'title' => "Random User",
                                 'align' => "center",
                             });
            $$b .= "Table randomuserset is empty.";
            box_end($b, $box);
            return;
        }

        box_start($b, $box, {'title' => "Random User" . (keys %ruserid > 1 ? "s" : ""),
                             'align' => "center",
                         });

        my @ruser;
        my $sth = $dbr->prepare(qq{
            SELECT user, name, defaultpicid FROM user WHERE userid IN
        } . "(" . join(",", keys %ruserid) . ")");
        $sth->execute;
        push @ruser, $_ while $_ = $sth->fetchrow_hashref;
        
        my %pic;
        unless ($box->{'args'}->{'hidepic'}) {
            LJ::load_userpics($dbs, \%pic, [ map { $_->{'defaultpicid'} } @ruser ]);
        }

        if ($size eq "large") {  $$b .= "<table width=100%><tr valign=bottom>"; }

        my $rct = 1;
        foreach my $r (@ruser)
        {
            if ($size eq "large") {  $$b .= "<td align=center>"; }
            elsif ($size eq "small" && $rct > 1) {  $$b .= "<p>"; }

            my $picid = $r->{'defaultpicid'};
            if ($picid && ! $box->{'args'}->{'hidepic'}) {
                $$b .= "<img src=\"$LJ::SITEROOT/userpic/$picid\" width=$pic{$picid}->{'width'} height=$pic{$picid}->{'height'}><br>";
            }
            $$b .= "<?ljuser $r->{'user'} ljuser?>";
            unless ($box->{'args'}->{'hidename'}) {
                $$b .= "<br>" . LJ::eall($r->{'name'});
            }

            if ($size eq "large") {  $$b .= "</td>"; }
            $rct++;
        }
        if ($size eq "large") {  $$b .= "</tr></table>"; }

        box_end($b, $box);
    }
};

1;
