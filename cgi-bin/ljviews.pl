#!/usr/bin/perl
#
# <LJDEP>
# lib: cgi-bin/ljlib.pl, cgi-bin/ljconfig.pl, cgi-bin/ljlang.pl, cgi-bin/cleanhtml.pl
# </LJDEP>

use strict;

package LJ::S1;

use vars qw(@themecoltypes);

# this used to be in a table, but that was kinda useless
@themecoltypes = (
                  [ 'page_back', 'Page background' ],
                  [ 'page_text', 'Page text' ],
                  [ 'page_link', 'Page link' ],
                  [ 'page_vlink', 'Page visited link' ],
                  [ 'page_alink', 'Page active link' ],
                  [ 'page_text_em', 'Page emphasized text' ],
                  [ 'page_text_title', 'Page title' ],
                  [ 'weak_back', 'Weak accent' ],
                  [ 'weak_text', 'Text on weak accent' ],
                  [ 'strong_back', 'Strong accent' ],
                  [ 'strong_text', 'Text on strong accent' ],
                  [ 'stronger_back', 'Stronger accent' ],
                  [ 'stronger_text', 'Text on stronger accent' ],                  
                  );

# updated everytime new S1 style cleaning rules are added,
# so cached cleaned versions are invalidated.
$LJ::S1::CLEANER_VERSION = 4;

# PROPERTY Flags:

# /a/:
#    safe in styles as sole attributes, without any cleaning.  for
#    example: <a href="%%urlread%%"> is okay, # if we're in
#    LASTN_TALK_READLINK, because the system generates # %%urlread%%.
#    by default, if we don't declare things trusted here, # we'll
#    double-check all attributes at the end for potential XSS #
#    problems.
#
# /u/:
#    is a URL.  implies /a/.
#
#
# /d/:
#    is a number.  implies /a/.
#
# /t/:
#    tainted!  User controls via other some other variable.
#
# /s/:
#    some system string... probably safe.  but maybe possible to coerce it
#    alongside something else.

my $commonprop = {
    'dateformat' => {
        'yy' => 'd', 'yyyy' => 'd',
        'm' => 'd', 'mm' => 'd',
        'd' => 'd', 'dd' => 'd',
        'min' => 'd',
        '12h' => 'd', '12hh' => 'd',
        '24h' => 'd', '24hh' => 'd',
    },
    'talklinks' => {
        'messagecount' => 'd',
        'urlread' => 'u',
        'urlpost' => 'u',
        'itemid' => 'd',
    },
    'talkreadlink' => {
        'messagecount' => 'd',
        'urlread' => 'u',
    },
    'event' => {
        'itemid' => 'd',
    },
    'pic' => {
        'src' => 'u',
        'width' => 'd',
        'height' => 'd',
    },
    'newday' => {
        yy => 'd', yyyy => 'd', m => 'd', mm => 'd',
        d => 'd', dd => 'd',
    },
    'skip' => {
        'numitems' => 'd',
        'url' => 'u',
    },

};

$LJ::S1::PROPS = {
    'CALENDAR_DAY' => {
        'd' => 'd',
        'eventcount' => 'd',
        'dayevent' => 't',
        'daynoevent' => 't',
    },
    'CALENDAR_DAY_EVENT' => {
        'eventcount' => 'd',
        'dayurl' => 'u',
    },
    'CALENDAR_DAY_NOEVENT' => {
    },
    'CALENDAR_EMPTY_DAYS' => {
        'numempty' => 'd',
    },
    'CALENDAR_MONTH' => {
        'monlong' => 's',
        'monshort' => 's',
        'yy' => 'd',
        'yyyy' => 'd',
        'weeks' => 't',
        'urlmonthview' => 'u',
    },
    'CALENDAR_NEW_YEAR' => {
        'yy' => 'd',
        'yyyy' => 'd',
    },
    'CALENDAR_PAGE' => {
        'name' => 't',
        "name-'s" => 's',
        'yearlinks' => 't',
        'months' => 't',
        'username' => 's',
        'website' => 't',
        'head' => 't',
        'urlfriends' => 'u',
        'urllastn' => 'u',
    },
    'CALENDAR_WEBSITE' => {
        'url' => 't',
        'name' => 't',
    },
    'CALENDAR_WEEK' => {
        'days' => 't',
        'emptydays_beg' => 't',
        'emptydays_end' => 't',
    },
    'CALENDAR_YEAR_DISPLAYED' => {
        'yyyy' => 'd',
        'yy' => 'd',
    },
    'CALENDAR_YEAR_LINK' => {
        'yyyy' => 'd',
        'yy' => 'd',
        'url' => 'u',
    },
    'CALENDAR_YEAR_LINKS' => {
        'years' => 't',
    },

    # day
    'DAY_DATE_FORMAT' => $commonprop->{'dateformat'},
    'DAY_EVENT' => $commonprop->{'event'},
    'DAY_EVENT_PRIVATE' => $commonprop->{'event'},
    'DAY_EVENT_PROTECTED' => $commonprop->{'event'},
    'DAY_PAGE' => {
        'prevday_url' => 'u',
        'nextday_url' => 'u',
        'yy' => 'd', 'yyyy' => 'd',
        'm' => 'd', 'mm' => 'd',
        'd' => 'd', 'dd' => 'd',
        'urllastn' => 'u',
        'urlcalendar' => 'u',
        'urlfriends' => 'u',
    },
    'DAY_TALK_LINKS' => $commonprop->{'talklinks'},
    'DAY_TALK_READLINK' => $commonprop->{'talkreadlink'},

    # friends
    'FRIENDS_DATE_FORMAT' => $commonprop->{'dateformat'},
    'FRIENDS_EVENT' => $commonprop->{'event'},
    'FRIENDS_EVENT_PRIVATE' => $commonprop->{'event'},
    'FRIENDS_EVENT_PROTECTED' => $commonprop->{'event'},
    'FRIENDS_FRIENDPIC' => $commonprop->{'pic'},
    'FRIENDS_NEW_DAY' => $commonprop->{'newday'},
    'FRIENDS_RANGE_HISTORY' => {
        'numitems' => 'd',
        'skip' => 'd',
    },
    'FRIENDS_RANGE_MOSTRECENT' => {
        'numitems' => 'd',
    },
    'FRIENDS_SKIP_BACKWARD' => $commonprop->{'skip'},
    'FRIENDS_SKIP_FORWARD' => $commonprop->{'skip'},
    'FRIENDS_TALK_LINKS' => $commonprop->{'talklinks'},
    'FRIENDS_TALK_READLINK' => $commonprop->{'talkreadlink'},

    # lastn
    'LASTN_ALTPOSTER' => {
        'poster' => 's',
        'owner' => 's',
        'pic' => 't',
    },
    'LASTN_ALTPOSTER_PIC' => $commonprop->{'pic'},
    'LASTN_CURRENT' => {
        'what' => 's',
        'value' => 't',
    },
    'LASTN_CURRENTS' => {
        'currents' => 't',
    },
    'LASTN_DATEFORMAT' => $commonprop->{'dateformat'},
    'LASTN_EVENT' => $commonprop->{'event'},
    'LASTN_EVENT_PRIVATE' => $commonprop->{'event'},
    'LASTN_EVENT_PROTECTED' => $commonprop->{'event'},
    'LASTN_NEW_DAY' => $commonprop->{'newday'},
    'LASTN_PAGE' => {
        'urlfriends' => 'u',
        'urlcalendar' => 'u',
    },
    'LASTN_RANGE_HISTORY' => {
        'numitems' => 'd',
        'skip' => 'd',
    },
    'LASTN_RANGE_MOSTRECENT' => {
        'numitems' => 'd',
    },
    'LASTN_SKIP_BACKWARD' => $commonprop->{'skip'},
    'LASTN_SKIP_FORWARD' => $commonprop->{'skip'},
    'LASTN_TALK_LINKS' => $commonprop->{'talklinks'},
    'LASTN_TALK_READLINK' => $commonprop->{'talkreadlink'},
    'LASTN_USERPIC' => {
        'src' => 'u',
        'width' => 'd',
        'height' => 'd',
    },
    
};

# <LJFUNC>
# name: LJ::S1::get_themeid
# des: Loads or returns cached version of given color theme data.
# returns: Hashref with color names as keys
# args: dbarg?, themeid
# des-themeid: S1 themeid.
# </LJFUNC>
sub get_themeid
{
    &LJ::nodb;
    my $themeid = shift;
    return $LJ::S1::CACHE_THEMEID{$themeid} if $LJ::S1::CACHE_THEMEID{$themeid};
    my $dbr = LJ::get_db_reader();
    my $ret = {};
    my $sth = $dbr->prepare("SELECT coltype, color FROM themedata WHERE themeid=?");
    $sth->execute($themeid);
    $ret->{$_->{'coltype'}} = $_->{'color'} while $_ = $sth->fetchrow_hashref;
    return $LJ::S1::CACHE_THEMEID{$themeid} = $ret;
}

# returns: hashref of vars (cleaned)
sub load_style
{
    &LJ::nodb;
    my ($styleid, $viewref) = @_;
    
    my $cch = $LJ::S1::CACHE_STYLE{$styleid};
    if ($cch && $cch->{'cachetime'} > time() - 300) {
        $$viewref = $cch->{'type'} if ref $viewref eq "SCALAR";
        return $cch->{'style'};
    }

    my $memkey = [$styleid, "s1styc:$styleid"];
    my $styc = LJ::MemCache::get($memkey);

    unless ($styc) {
        my $dbr = @LJ::MEMCACHE_SERVERS ? LJ::get_db_writer() : LJ::get_db_reader();
        $styc = $dbr->selectrow_hashref("SELECT * FROM s1stylecache WHERE styleid=?",
                                        undef, $styleid);
        LJ::MemCache::set($memkey, $styc, time()+60*30) if $styc;
    }

    if (! $styc || $styc->{'vars_cleanver'} < $LJ::S1::CLEANER_VERSION) {
        my $dbh = LJ::get_db_writer();
        my ($type, $data, $opt_cache) = 
            $dbh->selectrow_array("SELECT type, formatdata, opt_cache FROM style WHERE styleid=?",
                                  undef, $styleid);
        return {} unless $type;

        $styc = {
            'type' => $type,
            'opt_cache' => $opt_cache,
            'vars_stor' => LJ::CleanHTML::clean_s1_style($data),
            'vars_cleanver' => $LJ::S1::CLEANER_VERSION,
        };
        
        $dbh->do("REPLACE INTO s1stylecache (styleid, cleandate, type, opt_cache, vars_stor, vars_cleanver) ".
                 "VALUES (?,NOW(),?,?,?,?)", undef, $styleid, 
                 map { $styc->{$_} } qw(type opt_cache vars_stor vars_cleanver));
    }
    
    my $ret = Storable::thaw($styc->{'vars_stor'});
    $$viewref = $styc->{'type'} if ref $viewref eq "SCALAR";

    if ($styc->{'opt_cache'} eq "Y") {
        $LJ::S1::CACHE_STYLE{$styleid} = {
            'style' => $ret,
            'cachetime' => time(),
            'type' => $styc->{'type'},
        };
    }

    return $ret;
}

package LJ;

# <LJFUNC>
# name: LJ::alldateparts_to_hash
# class: s1
# des: Given a date/time format from MySQL, breaks it into a hash.
# info: This is used by S1.
# args: alldatepart
# des-alldatepart: The output of the MySQL function
#                  DATE_FORMAT(sometime, "%a %W %b %M %y %Y %c %m %e %d
#                  %D %p %i %l %h %k %H")
# returns: Hash (whole, not reference), with keys: dayshort, daylong,
#          monshort, monlong, yy, yyyy, m, mm, d, dd, dth, ap, AP,
#          ampm, AMPM, min, 12h, 12hh, 24h, 24hh

# </LJFUNC>
sub alldateparts_to_hash
{
    my $alldatepart = shift;
    my @dateparts = split(/ /, $alldatepart);
    return (
            'dayshort' => $dateparts[0],
            'daylong' => $dateparts[1],
            'monshort' => $dateparts[2],
            'monlong' => $dateparts[3],
            'yy' => $dateparts[4],
            'yyyy' => $dateparts[5],
            'm' => $dateparts[6],
            'mm' => $dateparts[7],
            'd' => $dateparts[8],
            'dd' => $dateparts[9],
            'dth' => $dateparts[10],
            'ap' => substr(lc($dateparts[11]),0,1),
            'AP' => substr(uc($dateparts[11]),0,1),
            'ampm' => lc($dateparts[11]),
            'AMPM' => $dateparts[11],
            'min' => $dateparts[12],
            '12h' => $dateparts[13],
            '12hh' => $dateparts[14],
            '24h' => $dateparts[15],
            '24hh' => $dateparts[16],
            );
}

# <LJFUNC>
# class: s1
# name: LJ::fill_var_props
# args: vars, key, hashref
# des: S1 utility function to interpolate %%variables%% in a variable.  If
#      a modifier is given like %%foo:var%%, then [func[LJ::fvp_transform]]
#      is called.
# des-vars: hashref with keys being S1 vars
# des-key: the variable in the vars hashref we're expanding
# des-hashref: hashref of values that could interpolate.
# returns: Expanded string.
# </LJFUNC>
sub fill_var_props
{
    my ($vars, $key, $hashref) = @_;
    $_ = $vars->{$key};
    s/%%([\w:]+:)?([\w\-\']+)%%/$1 ? LJ::fvp_transform(lc($1), $vars, $hashref, $2) : $hashref->{$2}/eg;
    return $_;
}

# <LJFUNC>
# class: s1
# name: LJ::fvp_transform
# des: Called from [func[LJ::fill_var_props]] to do trasformations.
# args: transform, vars, hashref, attr
# des-transform: The transformation type.
# des-vars: hashref with keys being S1 vars
# des-hashref: hashref of values that could interpolate. (see
#              [func[LJ::fill_var_props]])
# des-attr: the attribute name that's being interpolated.
# returns: Transformed interpolated variable.
# </LJFUNC>
sub fvp_transform
{
    my ($transform, $vars, $hashref, $attr) = @_;
    my $ret = $hashref->{$attr};
    while ($transform =~ s/(\w+):$//) {
        my $trans = $1;
        if ($trans eq "color") {
            return $vars->{"color-$attr"};
        }
        elsif ($trans eq "ue") {
            $ret = LJ::eurl($ret);
        }
        elsif ($trans eq "cons") {
            if ($attr eq "img") { return $LJ::IMGPREFIX; }
            if ($attr eq "siteroot") { return $LJ::SITEROOT; }
            if ($attr eq "sitename") { return $LJ::SITENAME; }
        }
        elsif ($trans eq "attr") {
            $ret =~ s/\"/&quot;/g;
            $ret =~ s/\'/&\#39;/g;
            $ret =~ s/</&lt;/g;
            $ret =~ s/>/&gt;/g;
            $ret =~ s/\]\]//g;  # so they can't end the parent's [attr[..]] wrapper
        }
        elsif ($trans eq "lc") {
            $ret = lc($ret);
        }
        elsif ($trans eq "uc") {
            $ret = uc($ret);
        }
        elsif ($trans eq "xe") {
            $ret = LJ::exml($ret);
        }
        elsif ($trans eq "ljuser") {
            $ret = LJ::ljuser(LJ::canonical_username($ret));
        }
        elsif ($trans eq "ljcomm") {
            $ret = LJ::ljuser(LJ::canonical_username($ret), {'type'=>'C'});
        }

    }
    return $ret;
}

# <LJFUNC>
# class: s1
# name: LJ::parse_vars
# des: Parses S1 style data into hashref.
# returns: Nothing.  Modifies a hashref.
# args: dataref, hashref
# des-dataref: Reference to scalar with data to parse. Format is
#              a BML-style full block, as used in the S1 style system.
# des-hashref: Hashref to populate with data.
# </LJFUNC>
sub parse_vars
{
    my ($dataref, $hashref) = @_;
    my @data = split(/\n/, $$dataref);
    my $curitem = "";

    foreach (@data)
    {
        $_ .= "\n";
        s/\r//g;
        if ($curitem eq "" && /^([A-Z0-9\_]+)=>([^\n\r]*)/)
        {
            $hashref->{$1} = $2;
        }
        elsif ($curitem eq "" && /^([A-Z0-9\_]+)<=\s*$/)
        {
            $curitem = $1;
            $hashref->{$curitem} = "";
        }
        elsif ($curitem && /^<=$curitem\s*$/)
        {
            chop $hashref->{$curitem};  # remove the false newline
            $curitem = "";
        }
        else
        {
            $hashref->{$curitem} .= $_ if ($curitem =~ /\S/);
        }
    }
}

# <LJFUNC>
# class: s1
# name: LJ::prepare_currents
# des: do all the current music/mood/weather/whatever stuff.  only used by ljviews.pl.
# args: dbarg, args
# des-args: hashref with keys: 'props' (a hashref with itemid keys), 'vars' hashref with
#           keys being S1 variables.
# </LJFUNC>
sub prepare_currents
{
    my $args = shift;

    my $datakey = $args->{'datakey'} || $args->{'itemid'}; # new || old

    my %currents = ();
    my $val;
    if ($val = $args->{'props'}->{$datakey}->{'current_music'}) {
        LJ::CleanHTML::clean_subject(\$val);
        $currents{'Music'} = $val;
    }
    if ($val = $args->{'props'}->{$datakey}->{'current_mood'}) {
        LJ::CleanHTML::clean_subject(\$val);
        $currents{'Mood'} = $val;
    }
    if ($val = $args->{'props'}->{$datakey}->{'current_moodid'}) {
        my $theme = $args->{'user'}->{'moodthemeid'};
        my %pic;
        my $name = LJ::mood_name($val);
        if (LJ::get_mood_picture($theme, $val, \%pic)) {
            $currents{'Mood'} = "<img src=\"$pic{'pic'}\" align='absmiddle' width='$pic{'w'}' ".
                "height='$pic{'h'}' vspace='1' alt='' /> $name";
        } else {
            $currents{'Mood'} = $name;
        }
    }
    if (%currents) {
        if ($args->{'vars'}->{$args->{'prefix'}.'_CURRENTS'})
        {
            ### PREFIX_CURRENTS is defined, so use the correct style vars

            my $fvp = { 'currents' => "" };
            foreach (sort keys %currents) {
                $fvp->{'currents'} .= LJ::fill_var_props($args->{'vars'}, $args->{'prefix'}.'_CURRENT', {
                    'what' => $_,
                    'value' => $currents{$_},
                });
            }
            $args->{'event'}->{'currents'} =
                LJ::fill_var_props($args->{'vars'}, $args->{'prefix'}.'_CURRENTS', $fvp);
        } else
        {
            ### PREFIX_CURRENTS is not defined, so just add to %%events%%
            $args->{'event'}->{'event'} .= "<br />&nbsp;";
            foreach (sort keys %currents) {
                $args->{'event'}->{'event'} .= "<br /><b>Current $_</b>: " . $currents{$_} . "\n";
            }
        }
    }
}


package LJ::S1;
use strict;
require "$ENV{'LJHOME'}/cgi-bin/ljconfig.pl";
require "$ENV{'LJHOME'}/cgi-bin/ljlang.pl";
require "$ENV{'LJHOME'}/cgi-bin/cleanhtml.pl";

# the creator for the 'lastn' view:
sub create_view_lastn
{
    my ($ret, $u, $vars, $remote, $opts) = @_;
    my $dbr = LJ::get_db_reader();
    my $dbcr = LJ::get_cluster_reader($u);

    my $user = $u->{'user'};

    if ($u->{'journaltype'} eq "R" && $u->{'renamedto'} ne "") {
        $opts->{'redir'} = LJ::journal_base($u->{'renamedto'}, $opts->{'vhost'});
        return 1;
    }

    foreach ("name", "url", "urlname", "journaltitle") { LJ::text_out(\$u->{$_}); }

    my $get = $opts->{'getargs'};

    if ($opts->{'pathextra'}) {
        $opts->{'badargs'} = 1;
        return 1;
    }

    my %lastn_page = ();
    $lastn_page{'name'} = LJ::ehtml($u->{'name'});
    $lastn_page{'name-\'s'} = ($u->{'name'} =~ /s$/i) ? "'" : "'s";
    $lastn_page{'username'} = $user;
    $lastn_page{'title'} = LJ::ehtml($u->{'journaltitle'} ||
                                     $u->{'name'} . $lastn_page{'name-\'s'} . " Journal");
    $lastn_page{'numitems'} = $vars->{'LASTN_OPT_ITEMS'} || 20;

    my $journalbase = LJ::journal_base($user, $opts->{'vhost'});
    $lastn_page{'urlfriends'} = "$journalbase/friends";
    $lastn_page{'urlcalendar'} = "$journalbase/calendar";

    if ($u->{'url'} =~ m!^https?://!) {
        $lastn_page{'website'} =
            LJ::fill_var_props($vars, 'LASTN_WEBSITE', {
                "url" => LJ::ehtml($u->{'url'}),
                "name" => LJ::ehtml($u->{'urlname'} || "My Website"),
            });
    }

    $lastn_page{'events'} = "";

    # if user has requested, or a skip back link has been followed, don't index or follow
    if ($u->{'opt_blockrobots'} || $get->{'skip'}) {
        $lastn_page{'head'} = LJ::robot_meta_tags()
    }
    if ($LJ::UNICODE) {
        $lastn_page{'head'} .= '<meta http-equiv="Content-Type" content="text/html; charset='.$opts->{'saycharset'}."\" />\n";
    }

    # "Automatic Discovery of RSS feeds"
    $lastn_page{'head'} .= qq{<link rel="alternate" type="application/rss+xml" title="RSS" href="$journalbase/rss" />\n};

    $lastn_page{'head'} .= 
        $vars->{'GLOBAL_HEAD'} . "\n" . $vars->{'LASTN_HEAD'};

    my $events = \$lastn_page{'events'};
    
    # to show
    my $itemshow = $vars->{'LASTN_OPT_ITEMS'} + 0;
    if ($itemshow < 1) { $itemshow = 20; }
    if ($itemshow > 50) { $itemshow = 50; }

    my $skip = $get->{'skip'}+0;
    my $maxskip = $LJ::MAX_HINTS_LASTN-$itemshow;
    if ($skip < 0) { $skip = 0; }
    if ($skip > $maxskip) { $skip = $maxskip; }

    # do they want to 
    my $viewall = 0;
    if ($get->{'viewall'} && LJ::check_priv($remote, "viewall")) {
        LJ::statushistory_add($u->{'userid'}, $remote->{'userid'}, 
                              "viewall", "lastn: $user");
        $viewall = 1;
    }

    ## load the itemids
    my @itemids;
    my $err;
    my @items = LJ::get_recent_items({
        'clusterid' => $u->{'clusterid'},
        'clustersource' => 'slave',
        'viewall' => $viewall,
        'userid' => $u->{'userid'},
        'remote' => $remote,
        'itemshow' => $itemshow,
        'skip' => $skip,
        'itemids' => \@itemids,
        'order' => ($u->{'journaltype'} eq "C" || $u->{'journaltype'} eq "Y")  # community or syndicated
            ? "logtime" : "",
        'err' => \$err,
    });

    if ($err) {
        $opts->{'errcode'} = $err;
        $$ret = "";
        return 0;
    }
    
    ### load the log properties
    my %logprops = ();
    my $logtext;
    LJ::load_log_props2($dbcr, $u->{'userid'}, \@itemids, \%logprops);
    $logtext = LJ::get_logtext2($u, @itemids);

    my $lastday = -1;
    my $lastmonth = -1;
    my $lastyear = -1;
    my $eventnum = 0;

    my %posteru = ();  # map posterids to u objects
    LJ::load_userids_multiple([map { $_->{'posterid'}, \$posteru{$_->{'posterid'}} } 
                               @items], [$u]);

    # pre load things in a batch (like userpics) to minimize db calls
    my %userpics;
    my @userpic_load;
    push @userpic_load, $u->{'defaultpicid'} if $u->{'defaultpicid'};
    foreach my $item (@items) {
        next if $item->{'posterid'} == $u->{'userid'};
        my $itemid = $item->{'itemid'};
        my $pu = $posteru{$item->{'posterid'}};

        my $picid;
        if ($logprops{$itemid}->{'picture_keyword'}) {
            $picid = $dbr->selectrow_array("SELECT m.picid FROM userpicmap m, keywords k ".
                                           "WHERE m.userid=? AND m.kwid=k.kwid AND k.keyword=?",
                                           undef, $item->{'posterid'}, $logprops{$itemid}->{'picture_keyword'});
        }
        $picid ||= $pu->{'defaultpicid'};
        $item->{'_picid'} = $picid;
        push @userpic_load, $picid if ($picid && ! grep { $_ eq $picid } @userpic_load);
    }
    LJ::load_userpics(\%userpics, \@userpic_load);

    if (my $picid = $u->{'defaultpicid'}) {
        $lastn_page{'userpic'} = 
            LJ::fill_var_props($vars, 'LASTN_USERPIC', {
                "src" => "$LJ::USERPIC_ROOT/$picid/$u->{'userid'}",
                "width" => $userpics{$picid}->{'width'},
                "height" => $userpics{$picid}->{'height'},
            });
    }

    # spit out the S1

  ENTRY:
    foreach my $item (@items) 
    {
        my ($posterid, $itemid, $security, $alldatepart, $replycount) = 
            map { $item->{$_} } qw(posterid itemid security alldatepart replycount);

        my $pu = $posteru{$posterid};
        next ENTRY if $pu && $pu->{'statusvis'} eq 'S';

        my $subject = $logtext->{$itemid}->[0];
        my $event = $logtext->{$itemid}->[1];
        if ($get->{'nohtml'}) {
            # quote all non-LJ tags
            $subject =~ s{<(?!/?lj)(.*?)>} {&lt;$1&gt;}gi;
            $event   =~ s{<(?!/?lj)(.*?)>} {&lt;$1&gt;}gi;
        }

        if ($LJ::UNICODE && $logprops{$itemid}->{'unknown8bit'}) {
            LJ::item_toutf8($u, \$subject, \$event, $logprops{$itemid});
        }

        my %lastn_date_format = LJ::alldateparts_to_hash($alldatepart);

        if ($lastday != $lastn_date_format{'d'} ||
            $lastmonth != $lastn_date_format{'m'} ||
            $lastyear != $lastn_date_format{'yyyy'})
        {
          my %lastn_new_day = ();
          foreach (qw(dayshort daylong monshort monlong m mm yy yyyy d dd dth))
          {
              $lastn_new_day{$_} = $lastn_date_format{$_};
          }
          unless ($lastday==-1) {
              $$events .= LJ::fill_var_props($vars, 'LASTN_END_DAY', {});
          }
          $$events .= LJ::fill_var_props($vars, 'LASTN_NEW_DAY', \%lastn_new_day);

          $lastday = $lastn_date_format{'d'};
          $lastmonth = $lastn_date_format{'m'};
          $lastyear = $lastn_date_format{'yyyy'};
        }

        my %lastn_event = ();
        $eventnum++;
        $lastn_event{'eventnum'} = $eventnum;
        $lastn_event{'itemid'} = $itemid;
        $lastn_event{'datetime'} = LJ::fill_var_props($vars, 'LASTN_DATE_FORMAT', \%lastn_date_format);
        if ($subject) {
            LJ::CleanHTML::clean_subject(\$subject);
            $lastn_event{'subject'} = LJ::fill_var_props($vars, 'LASTN_SUBJECT', { 
                "subject" => $subject,
            });
        }

        my $ditemid = $itemid * 256 + $item->{'anum'};
        my $itemargs = "journal=$user&amp;itemid=$ditemid";
        $lastn_event{'itemargs'} = $itemargs;

        LJ::CleanHTML::clean_event(\$event, { 'preformatted' => $logprops{$itemid}->{'opt_preformatted'},
                                               'cuturl' => LJ::item_link($u, $itemid, $item->{'anum'}), });
        LJ::expand_embedded($ditemid, $remote, \$event);
        $lastn_event{'event'} = $event;

        if ($u->{'opt_showtalklinks'} eq "Y" && 
            ! $logprops{$itemid}->{'opt_nocomments'}
            ) 
        {
            my $readurl = "$journalbase/$ditemid.html";
            my $posturl = "$journalbase/$ditemid.html?mode=reply";
            if ($replycount && $remote && $remote->{'opt_nctalklinks'}) {
                $readurl .= "?nc=$replycount";
            }

            my $dispreadlink = $replycount || 
                ($logprops{$itemid}->{'hasscreened'} &&
                 ($remote->{'user'} eq $user
                  || LJ::check_rel($u, $remote, 'A')));

            $lastn_event{'talklinks'} = LJ::fill_var_props($vars, 'LASTN_TALK_LINKS', {
                'itemid' => $ditemid,
                'itemargs' => $itemargs,
                'urlpost' => $posturl,
                'urlread' => $readurl,
                'messagecount' => $replycount,
                'readlink' => $dispreadlink ? LJ::fill_var_props($vars, 'LASTN_TALK_READLINK', {
                    'urlread' => $readurl,
                    'messagecount' => $replycount,
                    'mc-plural-s' => $replycount == 1 ? "" : "s",
                    'mc-plural-es' => $replycount == 1 ? "" : "es",
                    'mc-plural-ies' => $replycount == 1 ? "y" : "ies",
                }) : "",
            });
        }

        ## current stuff
        LJ::prepare_currents({
            'props' => \%logprops, 
            'itemid' => $itemid, 
            'vars' => $vars, 
            'prefix' => "LASTN",
            'event' => \%lastn_event,
            'user' => $u,
        });

        if ($u->{'userid'} != $posterid) 
        {
            my %lastn_altposter = ();

            my $poster = $pu->{'user'};
            $lastn_altposter{'poster'} = $poster;
            $lastn_altposter{'owner'} = $user;
            
            if (my $picid = $item->{'_picid'}) {
                my $pic = $userpics{$picid};
                $lastn_altposter{'pic'} = LJ::fill_var_props($vars, 'LASTN_ALTPOSTER_PIC', {
                    "src" => "$LJ::USERPIC_ROOT/$picid/$pic->{'userid'}",
                    "width" => $pic->{'width'},
                    "height" => $pic->{'height'},
                });
            }
            $lastn_event{'altposter'} = 
                LJ::fill_var_props($vars, 'LASTN_ALTPOSTER', \%lastn_altposter);
        }

        my $var = 'LASTN_EVENT';
        if ($security eq "private" && 
            $vars->{'LASTN_EVENT_PRIVATE'}) { $var = 'LASTN_EVENT_PRIVATE'; }
        if ($security eq "usemask" && 
            $vars->{'LASTN_EVENT_PROTECTED'}) { $var = 'LASTN_EVENT_PROTECTED'; }
        $$events .= LJ::fill_var_props($vars, $var, \%lastn_event);
    } # end huge while loop

    $$events .= LJ::fill_var_props($vars, 'LASTN_END_DAY', {});

    my $item_shown = $eventnum;
    my $item_total = @items;
    my $item_hidden = $item_total - $item_shown;

    if ($skip) {
        $lastn_page{'range'} = 
            LJ::fill_var_props($vars, 'LASTN_RANGE_HISTORY', {
                "numitems" => $item_shown,
                "skip" => $skip,
            });
    } else {
        $lastn_page{'range'} = 
            LJ::fill_var_props($vars, 'LASTN_RANGE_MOSTRECENT', {
                "numitems" => $item_shown,
            });
    }

    #### make the skip links
    my ($skip_f, $skip_b) = (0, 0);
    my %skiplinks;

    ### if we've skipped down, then we can skip back up

    if ($skip) {
        $skip_f = 1;
        my $newskip = $skip - $itemshow;
        if ($newskip <= 0) { $newskip = ""; }
        else { $newskip = "?skip=$newskip"; }

        $skiplinks{'skipforward'} = 
            LJ::fill_var_props($vars, 'LASTN_SKIP_FORWARD', {
                "numitems" => $itemshow,
                "url" => "$journalbase/$newskip",
            });
    }

    ## unless we didn't even load as many as we were expecting on this
    ## page, then there are more (unless there are exactly the number shown 
    ## on the page, but who cares about that)

    unless ($item_total != $itemshow) {
        $skip_b = 1;

        if ($skip==$maxskip) {
            $skiplinks{'skipbackward'} = 
                LJ::fill_var_props($vars, 'LASTN_SKIP_BACKWARD', {
                    "numitems" => "Day",
                    "url" => "$journalbase/" . sprintf("%04d/%02d/%02d/", $lastyear, $lastmonth, $lastday),
                });
        } else {
            my $newskip = $skip + $itemshow;
            $newskip = "?skip=$newskip";
            $skiplinks{'skipbackward'} = 
                LJ::fill_var_props($vars, 'LASTN_SKIP_BACKWARD', {
                    "numitems" => $itemshow,
                    "url" => "$journalbase/$newskip",
                });
        }
    }

    ### if they're both on, show a spacer
    if ($skip_b && $skip_f) {
        $skiplinks{'skipspacer'} = $vars->{'LASTN_SKIP_SPACER'};
    }

    ### if either are on, put skiplinks into lastn_page
    if ($skip_b || $skip_f) {
        $lastn_page{'skiplinks'} = 
            LJ::fill_var_props($vars, 'LASTN_SKIP_LINKS', \%skiplinks);
    }

    $$ret = LJ::fill_var_props($vars, 'LASTN_PAGE', \%lastn_page);

    return 1;
}

# the creator for the 'friends' view:
sub create_view_friends
{
    my ($ret, $u, $vars, $remote, $opts) = @_;
    my $dbr = LJ::get_db_reader();
    my $sth;
    my $user = $u->{'user'};

    # see how often the remote user can reload this page.  
    # "friendsviewupdate" time determines what granularity time
    # increments by for checking for new updates
    my $nowtime = time();

    # update delay specified by "friendsviewupdate"
    my $newinterval = LJ::get_cap_min($remote, "friendsviewupdate") || 1;

    # when are we going to say page was last modified?  back up to the 
    # most recent time in the past where $time % $interval == 0
    my $lastmod = $nowtime;
    $lastmod -= $lastmod % $newinterval;

    # see if they have a previously cached copy of this page they
    # might be able to still use.
    if ($opts->{'header'}->{'If-Modified-Since'}) {
        my $theirtime = LJ::http_to_time($opts->{'header'}->{'If-Modified-Since'});

        # send back a 304 Not Modified if they say they've reloaded this 
        # document in the last $newinterval seconds:
        unless ($theirtime < $lastmod) {
            $opts->{'status'} = "304 Not Modified";
            $opts->{'nocontent'} = 1;
            return 1;
        }
    }
    $opts->{'headers'}->{'Last-Modified'} = LJ::time_to_http($lastmod);

    $$ret = "";

    my $get = $opts->{'getargs'};

    if ($get->{'mode'} eq "live") {
        $$ret .= "<html><head><title>${user}'s friends: live!</title></head>\n";
        $$ret .= "<frameset rows=\"100%,0%\" border=0>\n";
        $$ret .= "  <frame name=livetop src=\"friends?mode=framed\">\n";
        $$ret .= "  <frame name=livebottom src=\"friends?mode=livecond&amp;lastitemid=0\">\n";
        $$ret .= "</frameset></html>\n";
        return 1;
    }

    if ($u->{'journaltype'} eq "R" && $u->{'renamedto'} ne "") {
        $opts->{'redir'} = LJ::journal_base($u->{'renamedto'}, $opts->{'vhost'}) . "/friends";
        return 1;
    }

    foreach ("name", "url", "urlname", "friendspagetitle") { LJ::text_out(\$u->{$_}); }

    my %friends_page = ();
    $friends_page{'name'} = LJ::ehtml($u->{'name'});
    $friends_page{'name-\'s'} = ($u->{'name'} =~ /s$/i) ? "'" : "'s";
    $friends_page{'username'} = $user;
    $friends_page{'title'} = LJ::ehtml($u->{'friendspagetitle'} ||
                                       $u->{'name'} . $friends_page{'name-\'s'} . " Friends");
    $friends_page{'numitems'} = $vars->{'FRIENDS_OPT_ITEMS'} || 20;

    ## never have spiders index friends pages (change too much, and some 
    ## people might not want to be indexed)
    $friends_page{'head'} = LJ::robot_meta_tags();
    if ($LJ::UNICODE) {
        $friends_page{'head'} .= '<meta http-equiv="Content-Type" content="text/html; charset='.$opts->{'saycharset'}.'" />';
    }
    $friends_page{'head'} .= 
        $vars->{'GLOBAL_HEAD'} . "\n" . $vars->{'FRIENDS_HEAD'};

    if ($u->{'url'} =~ m!^https?://!) {
        $friends_page{'website'} =
            LJ::fill_var_props($vars, 'FRIENDS_WEBSITE', {
                "url" => LJ::ehtml($u->{'url'}),
                "name" => LJ::ehtml($u->{'urlname'} || "My Website"),
            });
    }

    my $journalbase = LJ::journal_base($user, $opts->{'vhost'});

    $friends_page{'urlcalendar'} = "$journalbase/calendar";
    $friends_page{'urllastn'} = "$journalbase/";

    $friends_page{'events'} = "";

    my $itemshow = $vars->{'FRIENDS_OPT_ITEMS'} + 0;
    if ($itemshow < 1) { $itemshow = 20; }
    if ($itemshow > 50) { $itemshow = 50; }

    my $skip = $get->{'skip'}+0;
    my $maxskip = ($LJ::MAX_SCROLLBACK_FRIENDS || 1000) - $itemshow;
    if ($skip > $maxskip) { $skip = $maxskip; }
    if ($skip < 0) { $skip = 0; }
    my $itemload = $itemshow+$skip;

    my %owners;
    my $filter;
    my $group;
    my $common_filter = 1;

    if (defined $get->{'filter'} && $remote && $remote->{'user'} eq $user) {
        $filter = $get->{'filter'}; 
        $common_filter = 0;
    } else {
        if ($opts->{'pathextra'}) {
            $group = $opts->{'pathextra'};
            $group =~ s!^/!!;
            $group =~ s!/$!!;
            if ($group) { $group = LJ::durl($group); $common_filter = 0;}
        }
        my $qgroup = $dbr->quote($group || "Default View");
        my ($bit, $public) = $dbr->selectrow_array("SELECT groupnum, is_public " .
            "FROM friendgroup WHERE userid=$u->{'userid'} AND groupname=$qgroup");
        if ($bit && ($public || ($remote && $remote->{'user'} eq $user))) { 
            $filter = (1 << $bit); 
        }
    }


    if ($get->{'mode'} eq "livecond") 
    {
        ## load the itemids
        my @items = LJ::get_friend_items({
            'u' => $u,
            'userid' => $u->{'userid'},
            'remote' => $remote,
            'itemshow' => 1,
            'skip' => 0,
            'filter' => $filter,
            'common_filter' => $common_filter,
        });
        my $first = @items ? $items[0]->{'itemid'} : 0;

        $$ret .= "time = " . scalar(time()) . "<br />";
        $opts->{'headers'}->{'Refresh'} = "30;URL=$LJ::SITEROOT/users/$user/friends?mode=livecond&lastitemid=$first";
        if ($get->{'lastitemid'} == $first) {
            $$ret .= "nothing new!";
        } else {
            if ($get->{'lastitemid'}) {
                $$ret .= "<b>New stuff!</b>\n";
                $$ret .= "<script language=\"JavaScript\">\n";
                $$ret .= "window.parent.livetop.location.reload(true);\n";	    
                $$ret .= "</script>\n";
                $opts->{'trusted_html'} = 1;
            } else {
                $$ret .= "Friends Live! started.";
            }
        }
        return 1;
    }
    
    ## load the itemids 
    my %idsbycluster;
    my @items = LJ::get_friend_items({
        'u' => $u,
        'userid' => $u->{'userid'},
        'remote' => $remote,
        'itemshow' => $itemshow,
        'skip' => $skip,
        'filter' => $filter,
        'common_filter' => $common_filter,
        'owners' => \%owners,
        'idsbycluster' => \%idsbycluster,
        'showtypes' => $get->{'show'},
        'friendsoffriends' => $opts->{'view'} eq "friendsfriends",
    });

    my $ownersin = join(",", keys %owners);

    my %friends = ();
    unless ($opts->{'view'} eq "friendsfriends") {
        $sth = $dbr->prepare("SELECT u.user, u.userid, u.clusterid, f.fgcolor, f.bgcolor, u.name, u.defaultpicid, u.opt_showtalklinks, u.moodthemeid, u.statusvis, u.oldenc, u.journaltype FROM friends f, user u WHERE u.userid=f.friendid AND f.userid=$u->{'userid'} AND f.friendid IN ($ownersin)");
    } else {
        $sth = $dbr->prepare("SELECT u.user, u.userid, u.clusterid, '#000000' as 'fgcolor', '#ffffff' as 'bgcolor', u.name, u.defaultpicid, u.opt_showtalklinks, u.moodthemeid, u.statusvis, u.oldenc, u.journaltype FROM user u WHERE u.userid IN ($ownersin)");
    }

    $sth->execute;
    while ($_ = $sth->fetchrow_hashref) {
        next unless $_->{'statusvis'} eq 'V';  # ignore suspended/deleted users.
        $_->{'fgcolor'} = LJ::color_fromdb($_->{'fgcolor'});
        $_->{'bgcolor'} = LJ::color_fromdb($_->{'bgcolor'});
        $friends{$_->{'userid'}} = $_;
    }

    unless (%friends)
    {
        $friends_page{'events'} = LJ::fill_var_props($vars, 'FRIENDS_NOFRIENDS', {
          "name" => LJ::ehtml($u->{'name'}),
          "name-\'s" => ($u->{'name'} =~ /s$/i) ? "'" : "'s",
          "username" => $user,
        });

        $$ret .= "<base target='_top'>" if ($get->{'mode'} eq "framed");
        $$ret .= LJ::fill_var_props($vars, 'FRIENDS_PAGE', \%friends_page);
        return 1;
    }

    my %aposter;  # alt-posterid -> u object (if not in friends already)
    LJ::load_userids_multiple([map { $_->{'posterid'}, \$aposter{$_->{'posterid'}} }
                               grep { $friends{$_->{'ownerid'}} &&
                                          ! $friends{$_->{'posterid'}} } @items],
                              [ $u, $remote ]);

    ### load the log properties
    my %logprops = ();  # key is "$owneridOrZero $[j]itemid"
    LJ::load_log_props2multi(\%idsbycluster, \%logprops);

    # load the pictures for the user
    my %userpics;
    my @picids = map { $friends{$_}->{'defaultpicid'} } keys %friends;
    LJ::load_userpics(\%userpics, [ @picids, map { $_->{'defaultpicid'} } values %aposter ]);

    # load the text of the entries
    my $logtext = LJ::get_logtext2multi(\%idsbycluster);
  
    my %friends_events = ();
    my $events = \$friends_events{'events'};
    
    my $lastday = -1;
    my $eventnum = 0;

  ENTRY:
    foreach my $item (@items) 
    {
        my ($friendid, $posterid, $itemid, $security, $alldatepart, $replycount) = 
            map { $item->{$_} } qw(ownerid posterid itemid security alldatepart replycount);

        my $pu = $friends{$posterid} || $aposter{$posterid};
        next ENTRY if $pu && $pu->{'statusvis'} eq 'S';

        # counting excludes skipped entries
        $eventnum++;

        my $clusterid = $item->{'clusterid'}+0;
        
        my $datakey = "$friendid $itemid";
            
        my $subject = $logtext->{$datakey}->[0];
        my $event = $logtext->{$datakey}->[1];
        if ($get->{'nohtml'}) {
            # quote all non-LJ tags
            $subject =~ s{<(?!/?lj)(.*?)>} {&lt;$1&gt;}gi;
            $event   =~ s{<(?!/?lj)(.*?)>} {&lt;$1&gt;}gi;
        }

        if ($LJ::UNICODE && $logprops{$datakey}->{'unknown8bit'}) {
            LJ::item_toutf8($friends{$friendid}, \$subject, \$event, $logprops{$datakey});
        }

        my ($friend, $poster);
        $friend = $poster = $friends{$friendid}->{'user'};
        $poster = $pu->{'user'};
        
        my %friends_date_format = LJ::alldateparts_to_hash($alldatepart);

        if ($lastday != $friends_date_format{'d'})
        {
            my %friends_new_day = ();
            foreach (qw(dayshort daylong monshort monlong m mm yy yyyy d dd dth))
            {
                $friends_new_day{$_} = $friends_date_format{$_};
            }
            unless ($lastday==-1) {
                $$events .= LJ::fill_var_props($vars, 'FRIENDS_END_DAY', {});
            }
            $$events .= LJ::fill_var_props($vars, 'FRIENDS_NEW_DAY', \%friends_new_day);
            $lastday = $friends_date_format{'d'};
        }
        
        my %friends_event = ();
        $friends_event{'itemid'} = $itemid;
        $friends_event{'datetime'} = LJ::fill_var_props($vars, 'FRIENDS_DATE_FORMAT', \%friends_date_format);
        if ($subject) {
            LJ::CleanHTML::clean_subject(\$subject);
            $friends_event{'subject'} = LJ::fill_var_props($vars, 'FRIENDS_SUBJECT', { 
                "subject" => $subject,
            });
        } else {
            $friends_event{'subject'} = LJ::fill_var_props($vars, 'FRIENDS_NO_SUBJECT', { 
                "friend" => $friend,
                "name" => $friends{$friendid}->{'name'},
            });
        }

        my $ditemid = $itemid * 256 + $item->{'anum'};
        my $itemargs = "journal=$friend&amp;itemid=$ditemid";
        $friends_event{'itemargs'} = $itemargs;

        LJ::CleanHTML::clean_event(\$event, { 'preformatted' => $logprops{$datakey}->{'opt_preformatted'},
                                               'cuturl' => LJ::item_link($friends{$friendid}, $itemid, $item->{'anum'}), });
        LJ::expand_embedded($ditemid, $remote, \$event);
        $friends_event{'event'} = $event;
        
        # do the picture
        {
            my $picid = $friends{$friendid}->{'defaultpicid'};  # this could be the shared journal pic
            my $picuserid = $friendid;
            if ($friendid != $posterid && ! $u->{'opt_usesharedpic'}) {
                if ($pu->{'defaultpicid'}) {
                    $picid = $pu->{'defaultpicid'};
                    $picuserid = $posterid;
                }
            }
            if ($logprops{$datakey}->{'picture_keyword'} && 
                (! $u->{'opt_usesharedpic'} || ($posterid == $friendid))) 
            {
                my $qkw = $dbr->quote($logprops{$datakey}->{'picture_keyword'});
                my $sth = $dbr->prepare("SELECT m.picid FROM userpicmap m, keywords k ".
                                        "WHERE m.userid=$posterid AND m.kwid=k.kwid AND k.keyword=$qkw");
                $sth->execute;
                my $alt_picid = $sth->fetchrow_array;
                if ($alt_picid) {
                    LJ::load_userpics(\%userpics, [ $alt_picid ]);
                    $picid = $alt_picid;
                    $picuserid = $posterid;
                }
            }
            if ($picid) {
                $friends_event{'friendpic'} = 
                    LJ::fill_var_props($vars, 'FRIENDS_FRIENDPIC', {
                        "src" => "$LJ::USERPIC_ROOT/$picid/$picuserid",
                        "width" => $userpics{$picid}->{'width'},
                        "height" => $userpics{$picid}->{'height'},
                    });
            }
        }
        
        if ($friend ne $poster) {
            $friends_event{'altposter'} = 
                LJ::fill_var_props($vars, 'FRIENDS_ALTPOSTER', {
                    "poster" => $poster,
                    "owner" => $friend,
                    "fgcolor" => $friends{$friendid}->{'fgcolor'} || "#000000",
                    "bgcolor" => $friends{$friendid}->{'bgcolor'} || "#ffffff",
                });
        }

        # friends view specific:
        $friends_event{'user'} = $friend;
        $friends_event{'fgcolor'} = $friends{$friendid}->{'fgcolor'} || "#000000";
        $friends_event{'bgcolor'} = $friends{$friendid}->{'bgcolor'} || "#ffffff";
        
        if ($friends{$friendid}->{'opt_showtalklinks'} eq "Y" &&
            ! $logprops{$datakey}->{'opt_nocomments'}
            ) 
        {
            my $dispreadlink = $replycount || 
                ($logprops{$datakey}->{'hasscreened'} &&
                 ($remote->{'user'} eq $friend
                  || LJ::check_rel($friendid, $remote, 'A')));

            my ($readurl, $posturl);
            my $journalbase = LJ::journal_base($friends{$friendid});

            $posturl = "$journalbase/$ditemid.html?mode=reply";
            $readurl = "$journalbase/$ditemid.html";
            $readurl .= "?nc=$replycount" if $replycount && $remote && $remote->{'opt_nctalklinks'};
            
            $friends_event{'talklinks'} = LJ::fill_var_props($vars, 'FRIENDS_TALK_LINKS', {
                'itemid' => $ditemid,
                'itemargs' => $itemargs,
                'urlpost' => $posturl,
                'urlread' => $readurl,
                'messagecount' => $replycount,
                'readlink' => $dispreadlink ? LJ::fill_var_props($vars, 'FRIENDS_TALK_READLINK', {
                    'urlread' => $readurl,
                    'messagecount' => $replycount,
                    'mc-plural-s' => $replycount == 1 ? "" : "s",
                    'mc-plural-es' => $replycount == 1 ? "" : "es",
                    'mc-plural-ies' => $replycount == 1 ? "y" : "ies",
                }) : "",
            });
        }

        ## current stuff
        LJ::prepare_currents({
            'props' => \%logprops, 
            'datakey' => $datakey, 
            'vars' => $vars, 
            'prefix' => "FRIENDS",
            'event' => \%friends_event,
            'user' => ($u->{'opt_forcemoodtheme'} eq "Y" ? $u :
                       $friends{$friendid}),
        });

        my $var = 'FRIENDS_EVENT';
        if ($security eq "private" && 
            $vars->{'FRIENDS_EVENT_PRIVATE'}) { $var = 'FRIENDS_EVENT_PRIVATE'; }
        if ($security eq "usemask" && 
            $vars->{'FRIENDS_EVENT_PROTECTED'}) { $var = 'FRIENDS_EVENT_PROTECTED'; }
        
        $$events .= LJ::fill_var_props($vars, $var, \%friends_event);
    } # end while

    $$events .= LJ::fill_var_props($vars, 'FRIENDS_END_DAY', {});
    $friends_page{'events'} = LJ::fill_var_props($vars, 'FRIENDS_EVENTS', \%friends_events);

    my $item_shown = $eventnum;
    my $item_total = @items;
    my $item_hidden = $item_total - $item_shown;
    
    ### set the range property (what entries are we looking at)

    if ($skip) {
        $friends_page{'range'} = 
            LJ::fill_var_props($vars, 'FRIENDS_RANGE_HISTORY', {
                "numitems" => $item_shown,
                "skip" => $skip,
            });
    } else {
        $friends_page{'range'} = 
            LJ::fill_var_props($vars, 'FRIENDS_RANGE_MOSTRECENT', {
                "numitems" => $item_shown,
            });
    }

    my ($skip_f, $skip_b) = (0, 0);
    my %skiplinks;
    my $base = "$journalbase/$opts->{'view'}";
    if ($group) {
        $base .= "/" . LJ::eurl($group);
    }

    # $linkfilter is distinct from $filter: if user has a default view,
    # $filter is now set according to it but we don't want it to show in the links.
    # $incfilter may be true even if $filter is 0: user may use filter=0 to turn
    # off the default group
    my $linkfilter = $get->{'filter'} + 0;
    my $incfilter = defined $get->{'filter'};

    # if we've skipped down, then we can skip back up
    if ($skip) {
        $skip_f = 1;
        my %linkvars;

        $linkvars{'filter'} = $linkfilter if $incfilter;
        $linkvars{'show'} = $get->{'show'} if $get->{'show'} =~ /^\w+$/;

        my $newskip = $skip - $itemshow;
        if ($newskip > 0) { $linkvars{'skip'} = $newskip; }

        $skiplinks{'skipforward'} = 
            LJ::fill_var_props($vars, 'FRIENDS_SKIP_FORWARD', {
                "numitems" => $itemshow,
                "url" => LJ::make_link($base, \%linkvars),
            });
    }

    ## unless we didn't even load as many as we were expecting on this
    ## page, then there are more (unless there are exactly the number shown 
    ## on the page, but who cares about that)

    unless ($item_total != $itemshow || $skip == $maxskip) {
        $skip_b = 1;
        my %linkvars;

        $linkvars{'filter'} = $linkfilter if $incfilter;
        $linkvars{'show'} = $get->{'show'} if $get->{'show'} =~ /^\w+$/;

        my $newskip = $skip + $itemshow;
        $linkvars{'skip'} = $newskip;

        $skiplinks{'skipbackward'} = 
            LJ::fill_var_props($vars, 'FRIENDS_SKIP_BACKWARD', {
                "numitems" => $itemshow,
                "url" => LJ::make_link($base, \%linkvars),
            });
    }

    ### if they're both on, show a spacer
    if ($skip_f && $skip_b) {
        $skiplinks{'skipspacer'} = $vars->{'FRIENDS_SKIP_SPACER'};
    }

    ### if either are on, put skiplinks into lastn_page
    if ($skip_b || $skip_f) {
        $friends_page{'skiplinks'} = 
            LJ::fill_var_props($vars, 'FRIENDS_SKIP_LINKS', \%skiplinks);
    }
    
    $$ret .= "<base target='_top' />" if ($get->{'mode'} eq "framed");
    $$ret .= LJ::fill_var_props($vars, 'FRIENDS_PAGE', \%friends_page);

    return 1;
}

# the creator for the 'calendar' view:
sub create_view_calendar
{
    my ($ret, $u, $vars, $remote, $opts) = @_;
    
    my $user = $u->{'user'};

    if ($u->{'journaltype'} eq "R" && $u->{'renamedto'} ne "") {
        $opts->{'redir'} = LJ::journal_base($u->{'renamedto'}, $opts->{'vhost'}) .
            "/calendar" . $opts->{'pathextra'};
        return 1;
    }

    foreach ("name", "url", "urlname", "journaltitle") { LJ::text_out(\$u->{$_}); }

    my $get = $opts->{'getargs'};

    my %calendar_page = ();
    $calendar_page{'name'} = LJ::ehtml($u->{'name'});
    $calendar_page{'name-\'s'} = ($u->{'name'} =~ /s$/i) ? "'" : "'s";
    $calendar_page{'username'} = $user;
    $calendar_page{'title'} = LJ::ehtml($u->{'journaltitle'} ||
                                        $u->{'name'} . $calendar_page{'name-\'s'} . " Journal");
    if ($u->{'opt_blockrobots'}) {
        $calendar_page{'head'} = LJ::robot_meta_tags();
    }
    if ($LJ::UNICODE) {
        $calendar_page{'head'} .= '<meta http-equiv="Content-Type" content="text/html; charset='.$opts->{'saycharset'}.'" />';
    }
    $calendar_page{'head'} .=
        $vars->{'GLOBAL_HEAD'} . "\n" . $vars->{'CALENDAR_HEAD'};
    
    $calendar_page{'months'} = "";

    if ($u->{'url'} =~ m!^https?://!) {
        $calendar_page{'website'} =
            LJ::fill_var_props($vars, 'CALENDAR_WEBSITE', {
                "url" => LJ::ehtml($u->{'url'}),
                "name" => LJ::ehtml($u->{'urlname'} || "My Website"),
            });
    }

    my $journalbase = LJ::journal_base($user, $opts->{'vhost'});
    
    $calendar_page{'urlfriends'} = "$journalbase/friends";
    $calendar_page{'urllastn'} = "$journalbase/";

    my $months = \$calendar_page{'months'};

    my $quserid = int($u->{'userid'});
    my $maxyear = 0;

    my $db = LJ::get_cluster_reader($u);
    my $sql = "SELECT year, month, day, DAYOFWEEK(CONCAT(year, \"-\", month, \"-\", day)) AS 'dayweek', COUNT(*) AS 'count' FROM log2 WHERE journalid=$quserid GROUP BY year, month, day, dayweek";

    unless ($db) {
        $opts->{'errcode'} = "nodb";
        $$ret = "";
        return 0;
    }

    my $sth = $db->prepare($sql);
    $sth->execute;

    my (%count, %dayweek, $year, $month, $day, $dayweek, $count);
    while (($year, $month, $day, $dayweek, $count) = $sth->fetchrow_array)
    {
        $count{$year}->{$month}->{$day} = $count;
        $dayweek{$year}->{$month}->{$day} = $dayweek;
        if ($year > $maxyear) { $maxyear = $year; }
    }

    my @allyears = sort { $b <=> $a } keys %count;
    if ($vars->{'CALENDAR_SORT_MODE'} eq "forward") { @allyears = reverse @allyears; }

    my @years = ();
    my $dispyear = $get->{'year'};  # old form was /users/<user>/calendar?year=1999

    # but the new form is purtier:  */calendar/2001
    # but the NEWER form is purtier:  */2001
    unless ($dispyear) {
        if ($opts->{'pathextra'} =~ m!^/(\d\d\d\d)/?\b!) {
            $dispyear = $1;
        }
    }

    # else... default to the year they last posted.
    $dispyear ||= $maxyear;  

    # we used to show multiple years.  now we only show one at a time:  (hence the @years confusion)
    if ($dispyear) { push @years, $dispyear; }  

    if (scalar(@allyears) > 1) {
        my $yearlinks = "";
        foreach my $year (@allyears) {
            my $yy = sprintf("%02d", $year % 100);
            my $url = "$journalbase/$year";
            if ($year != $dispyear) { 
                $yearlinks .= LJ::fill_var_props($vars, 'CALENDAR_YEAR_LINK', {
                    "url" => $url, "yyyy" => $year, "yy" => $yy });
            } else {
                $yearlinks .= LJ::fill_var_props($vars, 'CALENDAR_YEAR_DISPLAYED', {
                    "yyyy" => $year, "yy" => $yy });
            }
        }
        $calendar_page{'yearlinks'} = 
            LJ::fill_var_props($vars, 'CALENDAR_YEAR_LINKS', { "years" => $yearlinks });
    }

    foreach $year (@years)
    {
        $$months .= LJ::fill_var_props($vars, 'CALENDAR_NEW_YEAR', {
          'yyyy' => $year,
          'yy' => substr($year, 2, 2),
        });

        my @months = sort { $b <=> $a } keys %{$count{$year}};
        if ($vars->{'CALENDAR_SORT_MODE'} eq "forward") { @months = reverse @months; }
        foreach $month (@months)
        {
          my $daysinmonth = LJ::days_in_month($month, $year);
          
          # this picks a random day there were journal entries (thus, we know
          # the %dayweek from above)  from that we go backwards and forwards
          # to find the rest of the days of week
          my $firstday = (%{$count{$year}->{$month}})[0];

          # go backwards from first day
          my $dayweek = $dayweek{$year}->{$month}->{$firstday};
          for (my $i=$firstday-1; $i>0; $i--)
          {
              if (--$dayweek < 1) { $dayweek = 7; }
              $dayweek{$year}->{$month}->{$i} = $dayweek;
          }
          # go forwards from first day
          $dayweek = $dayweek{$year}->{$month}->{$firstday};
          for (my $i=$firstday+1; $i<=$daysinmonth; $i++)
          {
              if (++$dayweek > 7) { $dayweek = 1; }
              $dayweek{$year}->{$month}->{$i} = $dayweek;
          }

          my %calendar_month = ();
          $calendar_month{'monlong'} = LJ::Lang::month_long($month);
          $calendar_month{'monshort'} = LJ::Lang::month_short($month);
          $calendar_month{'yyyy'} = $year;
          $calendar_month{'yy'} = substr($year, 2, 2);
          $calendar_month{'weeks'} = "";
          $calendar_month{'urlmonthview'} = sprintf("$journalbase/%04d/%02d/", $year, $month);
          my $weeks = \$calendar_month{'weeks'};

          my %calendar_week = ();
          $calendar_week{'emptydays_beg'} = "";
          $calendar_week{'emptydays_end'} = "";
          $calendar_week{'days'} = "";

          # start the first row and check for its empty spaces
          my $rowopen = 1;
          if ($dayweek{$year}->{$month}->{1} != 1)
          {
              my $spaces = $dayweek{$year}->{$month}->{1} - 1;
              $calendar_week{'emptydays_beg'} = 
                  LJ::fill_var_props($vars, 'CALENDAR_EMPTY_DAYS', 
                                  { 'numempty' => $spaces });
          }

          # make the days!
          my $days = \$calendar_week{'days'};

          for (my $i=1; $i<=$daysinmonth; $i++)
          {
              $count{$year}->{$month}->{$i} += 0;
              if (! $rowopen) { $rowopen = 1; }

              my %calendar_day = ();
              $calendar_day{'d'} = $i;
              $calendar_day{'eventcount'} = $count{$year}->{$month}->{$i};
              if ($count{$year}->{$month}->{$i})
              {
                $calendar_day{'dayevent'} = LJ::fill_var_props($vars, 'CALENDAR_DAY_EVENT', {
                    'eventcount' => $count{$year}->{$month}->{$i},
                    'dayurl' => "$journalbase/" . sprintf("%04d/%02d/%02d/", $year, $month, $i),
                });
              }
              else
              {
                $calendar_day{'daynoevent'} = $vars->{'CALENDAR_DAY_NOEVENT'};
              }

              $$days .= LJ::fill_var_props($vars, 'CALENDAR_DAY', \%calendar_day);

              if ($dayweek{$year}->{$month}->{$i} == 7)
              {
                $$weeks .= LJ::fill_var_props($vars, 'CALENDAR_WEEK', \%calendar_week);
                $rowopen = 0;
                $calendar_week{'emptydays_beg'} = "";
                $calendar_week{'emptydays_end'} = "";
                $calendar_week{'days'} = "";
              }
          }

          # if rows is still open, we have empty spaces
          if ($rowopen)
          {
              if ($dayweek{$year}->{$month}->{$daysinmonth} != 7)
              {
                  my $spaces = 7 - $dayweek{$year}->{$month}->{$daysinmonth};
                  $calendar_week{'emptydays_end'} = 
                      LJ::fill_var_props($vars, 'CALENDAR_EMPTY_DAYS', 
                                         { 'numempty' => $spaces });
              }
              $$weeks .= LJ::fill_var_props($vars, 'CALENDAR_WEEK', \%calendar_week);
          }

          $$months .= LJ::fill_var_props($vars, 'CALENDAR_MONTH', \%calendar_month);
        } # end foreach months

    } # end foreach years

    ######## new code

    $$ret .= LJ::fill_var_props($vars, 'CALENDAR_PAGE', \%calendar_page);

    return 1;  
}

# the creator for the 'day' view:
sub create_view_day
{
    my ($ret, $u, $vars, $remote, $opts) = @_;
    my $dbr = LJ::get_db_reader();
    my $sth;

    my $user = $u->{'user'};

    if ($u->{'journaltype'} eq "R" && $u->{'renamedto'} ne "") {
        $opts->{'redir'} = LJ::journal_base($u->{'renamedto'}, $opts->{'vhost'}) .
            "/day" . $opts->{'pathextra'};
        return 1;
    }

    foreach ("name", "url", "urlname", "journaltitle") { LJ::text_out(\$u->{$_}); }

    my %day_page = ();
    $day_page{'username'} = $user;
    if ($u->{'opt_blockrobots'}) {
        $day_page{'head'} = LJ::robot_meta_tags();
    }
    if ($LJ::UNICODE) {
        $day_page{'head'} .= '<meta http-equiv="Content-Type" content="text/html; charset='.$opts->{'saycharset'}.'" />';
    }
    $day_page{'head'} .= 
        $vars->{'GLOBAL_HEAD'} . "\n" . $vars->{'DAY_HEAD'};
    $day_page{'name'} = LJ::ehtml($u->{'name'});
    $day_page{'name-\'s'} = ($u->{'name'} =~ /s$/i) ? "'" : "'s";
    $day_page{'title'} = LJ::ehtml($u->{'journaltitle'} ||
                                   $u->{'name'} . $day_page{'name-\'s'} . " Journal");

    if ($u->{'url'} =~ m!^https?://!) {
        $day_page{'website'} =
            LJ::fill_var_props($vars, 'DAY_WEBSITE', {
                "url" => LJ::ehtml($u->{'url'}),
                "name" => LJ::ehtml($u->{'urlname'} || "My Website"),
            });
    }

    my $journalbase = LJ::journal_base($user, $opts->{'vhost'});
    $day_page{'urlfriends'} = "$journalbase/friends";
    $day_page{'urlcalendar'} = "$journalbase/calendar";
    $day_page{'urllastn'} = "$journalbase/";

    my $initpagedates = 0;

    my $get = $opts->{'getargs'};

    my $month = $get->{'month'};
    my $day = $get->{'day'};
    my $year = $get->{'year'};
    my @errors = ();

    if ($opts->{'pathextra'} =~ m!^(?:/day)?/(\d\d\d\d)/(\d\d)/(\d\d)\b!) {
        ($month, $day, $year) = ($2, $3, $1);
    }

    if ($year !~ /^\d+$/) { push @errors, "Corrupt or non-existant year."; }
    if ($month !~ /^\d+$/) { push @errors, "Corrupt or non-existant month."; }
    if ($day !~ /^\d+$/) { push @errors, "Corrupt or non-existant day."; }
    if ($month < 1 || $month > 12 || int($month) != $month) { push @errors, "Invalid month."; }
    if ($year < 1970 || $year > 2038 || int($year) != $year) { push @errors, "Invalid year: $year"; }
    if ($day < 1 || $day > 31 || int($day) != $day) { push @errors, "Invalid day."; }
    if (scalar(@errors)==0 && $day > LJ::days_in_month($month, $year)) { push @errors, "That month doesn't have that many days."; }

    if (@errors) {
        $$ret .= "Errors occurred processing this page:\n<ul>\n";		
        foreach (@errors) {
          $$ret .= "<li>$_</li>\n";
        }
        $$ret .= "</ul>\n";
        return 0;
    }

    my $logdb = LJ::get_cluster_reader($u);
    unless ($logdb) {
        $opts->{'errcode'} = "nodb";
        $$ret = "";
        return 0;
    }

    my $optDESC = $vars->{'DAY_SORT_MODE'} eq "reverse" ? "DESC" : "";

    my $secwhere = "AND security='public'";
    if ($remote) {
        if ($remote->{'userid'} == $u->{'userid'}) {
            $secwhere = "";   # see everything
        } elsif ($remote->{'journaltype'} eq 'P') {
            my $gmask = $dbr->selectrow_array("SELECT groupmask FROM friends ".
                                              "WHERE userid=? AND friendid=?", undef, 
                                              $u->{'userid'}, $remote->{'userid'});
            $secwhere = "AND (security='public' OR (security='usemask' AND allowmask & $gmask))"
                if $gmask;
        }
    }

    # load the log items
    my $dateformat = "%a %W %b %M %y %Y %c %m %e %d %D %p %i %l %h %k %H";
    $sth = $logdb->prepare("SELECT jitemid AS itemid, posterid, security, replycount, ".
                           "       DATE_FORMAT(eventtime, \"$dateformat\") AS 'alldatepart', anum " .
                           "FROM log2 " .
                           "WHERE journalid=? AND year=? AND month=? AND day=? $secwhere " .
                           "ORDER BY eventtime $optDESC, logtime $optDESC LIMIT 200");
    $sth->execute($u->{'userid'}, $year, $month, $day);
    my @items;
    push @items, $_ while $_ = $sth->fetchrow_hashref;
    my @itemids = map { $_->{'itemid'} } @items;

    ### load the log properties
    my %logprops = ();
    LJ::load_log_props2($logdb, $u->{'userid'}, \@itemids, \%logprops);
    my $logtext = LJ::get_logtext2($u, @itemids);

    my %posteru = ();  # map posterids to u objects
    LJ::load_userids_multiple([map { $_->{'posterid'}, \$posteru{$_->{'posterid'}} } @items], [$u]);

    my $events = "";

  ENTRY:
    foreach my $item (@items)
    {
        my ($itemid, $posterid, $security, $replycount, $alldatepart, $anum) = 
            map { $item->{$_} } qw(itemid posterid security replycount alldatepart anum);

        next ENTRY if $posteru{$posterid} && $posteru{$posterid}->{'statusvis'} eq 'S';

        my $subject = $logtext->{$itemid}->[0];
        my $event = $logtext->{$itemid}->[1];

	if ($LJ::UNICODE && $logprops{$itemid}->{'unknown8bit'}) {
	    LJ::item_toutf8($u, \$subject, \$event, $logprops{$itemid});
	}

        my %day_date_format = LJ::alldateparts_to_hash($alldatepart);

        unless ($initpagedates)
        {
          foreach (qw(dayshort daylong monshort monlong yy yyyy m mm d dd dth))
          {
              $day_page{$_} = $day_date_format{$_};
          }
          $initpagedates = 1;
        }

        my %day_event = ();
        $day_event{'itemid'} = $itemid;
        $day_event{'datetime'} = LJ::fill_var_props($vars, 'DAY_DATE_FORMAT', \%day_date_format);
        if ($subject) {
            LJ::CleanHTML::clean_subject(\$subject);
            $day_event{'subject'} = LJ::fill_var_props($vars, 'DAY_SUBJECT', { 
                "subject" => $subject,
            });
        }

        my $ditemid = $itemid*256 + $anum;
        my $itemargs = "journal=$user&amp;itemid=$ditemid";
        $day_event{'itemargs'} = $itemargs;

        LJ::CleanHTML::clean_event(\$event, { 'preformatted' => $logprops{$itemid}->{'opt_preformatted'},
                                               'cuturl' => LJ::item_link($u, $itemid, $anum), });
        LJ::expand_embedded($ditemid, $remote, \$event);
        $day_event{'event'} = $event;

        if ($u->{'opt_showtalklinks'} eq "Y" &&
            ! $logprops{$itemid}->{'opt_nocomments'}
            ) 
        {
            my $posturl = "$journalbase/$ditemid.html?mode=reply";
            my $readurl = "$journalbase/$ditemid.html";
            if ($replycount && $remote && $remote->{'opt_nctalklinks'}) {
                $readurl .= "?nc=$replycount";
            }
            my $dispreadlink = $replycount || 
                ($logprops{$itemid}->{'hasscreened'} &&
                 ($remote->{'user'} eq $user
                  || LJ::check_rel($u, $remote, 'A')));
            $day_event{'talklinks'} = LJ::fill_var_props($vars, 'DAY_TALK_LINKS', {
                'itemid' => $ditemid,
                'itemargs' => $itemargs,
                'urlpost' => $posturl,
                'urlread' => $readurl,
                'messagecount' => $replycount,
                'readlink' => $dispreadlink ? LJ::fill_var_props($vars, 'DAY_TALK_READLINK', {
                    'urlread' => $readurl,
                    'messagecount' => $replycount,
                    'mc-plural-s' => $replycount == 1 ? "" : "s",
                    'mc-plural-es' => $replycount == 1 ? "" : "es",
                    'mc-plural-ies' => $replycount == 1 ? "y" : "ies",
                }) : "",
            });
        }

        ## current stuff
        LJ::prepare_currents({
            'props' => \%logprops, 
            'itemid' => $itemid, 
            'vars' => $vars, 
            'prefix' => "DAY",
            'event' => \%day_event,
            'user' => $u,
        });

        my $var = 'DAY_EVENT';
        if ($security eq "private" && 
            $vars->{'DAY_EVENT_PRIVATE'}) { $var = 'DAY_EVENT_PRIVATE'; }
        if ($security eq "usemask" && 
            $vars->{'DAY_EVENT_PROTECTED'}) { $var = 'DAY_EVENT_PROTECTED'; }
            
        $events .= LJ::fill_var_props($vars, $var, \%day_event);
    }

    if (! $initpagedates)
    {
        # if no entries were on that day, we haven't populated the time shit!
        $sth = $dbr->prepare("SELECT DATE_FORMAT('$year-$month-$day', '%a %W %b %M %y %Y %c %m %e %d %D') AS 'alldatepart'");
        $sth->execute;
        my @dateparts = split(/ /, $sth->fetchrow_arrayref->[0]);
        foreach (qw(dayshort daylong monshort monlong yy yyyy m mm d dd dth))
        {
          $day_page{$_} = shift @dateparts;
        }

        $day_page{'events'} = LJ::fill_var_props($vars, 'DAY_NOEVENTS', {});
    }
    else
    {
        $day_page{'events'} = LJ::fill_var_props($vars, 'DAY_EVENTS', { 'events' => $events });
        $events = "";  # free some memory maybe
    }

    # calculate previous day
    my $pdyear = $year;
    my $pdmonth = $month;
    my $pdday = $day-1;
    if ($pdday < 1)
    {
        if (--$pdmonth < 1)
        {
          $pdmonth = 12;
          $pdyear--;
        }
        $pdday = LJ::days_in_month($pdmonth, $pdyear);
    }

    # calculate next day
    my $nxyear = $year;
    my $nxmonth = $month;
    my $nxday = $day+1;
    if ($nxday > LJ::days_in_month($nxmonth, $nxyear))
    {
        $nxday = 1;
        if (++$nxmonth > 12) { ++$nxyear; $nxmonth=1; }
    }
    
    $day_page{'prevday_url'} = "$journalbase/" . sprintf("%04d/%02d/%02d/", $pdyear, $pdmonth, $pdday); 
    $day_page{'nextday_url'} = "$journalbase/" . sprintf("%04d/%02d/%02d/", $nxyear, $nxmonth, $nxday); 

    $$ret .= LJ::fill_var_props($vars, 'DAY_PAGE', \%day_page);
    return 1;
}

# the creator for the RSS XML syndication view
sub create_view_rss
{
    my ($ret, $u, $vars, $remote, $opts) = @_;
    my $dbr = LJ::get_db_reader();

    # for syndicated accounts, redirect to the syndication URL
    if ($u->{'journaltype'} eq 'Y') {
        my $synurl = $dbr->selectrow_array("SELECT synurl FROM syndicated WHERE userid=$u->{'userid'}");
        unless ($synurl) {
            $opts->{'errcode'} = "nosyn";
            return 0;
        }
        $opts->{'redir'} = $synurl;
        return 1;
    }

    my $user = $u->{'user'};
    foreach ("name", "url", "urlname") { LJ::text_out(\$u->{$_}); }

    ## load the itemids
    my @itemids;
    my @items = LJ::get_recent_items({
        'clusterid' => $u->{'clusterid'},
        'clustersource' => 'slave',
        'remote' => $remote,
        'userid' => $u->{'userid'},
        'itemshow' => 25,
        'order' => "logtime",
        'itemids' => \@itemids,
        'friendsview' => 1,           # this makes rlogtimes return
    });

    $opts->{'contenttype'} = 'text/xml; charset='.$opts->{'saycharset'};

    ### load the log properties
    my %logprops = ();
    my $logtext;
    my $logdb = LJ::get_cluster_reader($u);
    LJ::load_log_props2($logdb, $u->{'userid'}, \@itemids, \%logprops);
    $logtext = LJ::get_logtext2($u, @itemids);

    # some data used throughout the channel
    my $clink = LJ::journal_base($u) . "/";
    my $ctitle = LJ::exml($u->{'name'});
    my $cbuilddate = LJ::time_to_http($LJ::EndOfTime - $items[0]->{'rlogtime'});

    # email address of journal owner, but respect their privacy settings
    my $ceditor;
    if ($u->{'allow_contactshow'} eq "Y" && $u->{'opt_whatemailshow'} ne "N" && $u->{'opt_mangleemail'} ne "Y") {
        
        # default to their actual email
        $ceditor = $u->{'email'};
        
        # use their livejournal email if they have one
        if ($LJ::USER_EMAIL && $u->{'opt_whatemailshow'} eq "L" &&
            LJ::get_cap($u, "useremail") && ! $u->{'no_mail_alias'}) {

            $ceditor = "$u->{'user'}\@$LJ::USER_DOMAIN";
        } 

        # clean it up since we know we have one now
        $ceditor = LJ::exml($ceditor);
    }
    

    # header
    $$ret .= "<?xml version='1.0' encoding='$opts->{'saycharset'}' ?>\n";
    $$ret .= "<rss version='2.0'>\n";

    # channel attributes
    $$ret .= "<channel>\n";
    $$ret .= "  <title>$ctitle</title>\n";
    $$ret .= "  <link>$clink</link>\n";
    $$ret .= "  <description>$ctitle - $LJ::SITENAME</description>\n";
    $$ret .= "  <managingEditor>$ceditor</managingEditor>\n" if $ceditor;
    $$ret .= "  <lastBuildDate>$cbuilddate</lastBuildDate>\n";
    $$ret .= "  <generator>LiveJournal / $LJ::SITENAME</generator>\n";
    # TODO: add 'language' field when user.lang has more useful information

    ### image block, returns info for their current userpic
    if ($u->{'defaultpicid'}) {
        my $pic = {};
        LJ::load_userpics($pic, [$u->{'defaultpicid'}]);
        $pic = $pic->{$u->{'defaultpicid'}}; # flatten
        
        $$ret .= "  <image>\n";
        $$ret .= "    <url>$LJ::USERPIC_ROOT/$u->{'defaultpicid'}/$u->{'userid'}</url>\n";
        $$ret .= "    <title>$ctitle</title>\n";
        $$ret .= "    <link>$clink</link>\n";
        $$ret .= "    <width>$pic->{'width'}</width>\n";
        $$ret .= "    <height>$pic->{'height'}</height>\n";
        $$ret .= "  </image>\n\n";
    }

    my %posteru = ();  # map posterids to u objects
    LJ::load_userids_multiple([map { $_->{'posterid'}, \$posteru{$_->{'posterid'}} } @items], [$u]);

    # output individual item blocks

  ENTRY:
    foreach my $it (@items) 
    {
        # load required data
        my $itemid = $it->{'itemid'};

        next ENTRY if $posteru{$it->{'posterid'}} && $posteru{$it->{'posterid'}}->{'statusvis'} eq 'S';

        if ($LJ::UNICODE && $logprops{$itemid}->{'unknown8bit'}) {
            LJ::item_toutf8($u, \$logtext->{$itemid}->[0],
                            \$logtext->{$itemid}->[1], $logprops{$itemid});
        }

        # see if we have a subject and clean it
        my $subject = $logtext->{$itemid}->[0];
        LJ::CleanHTML::clean_subject_all(\$subject);
        $subject = LJ::exml($subject);

        # if no subject, use logtext with all HTML stripped
        my $event = $logtext->{$itemid}->[1];

        # users without 'full_rss' get their logtext bodies truncated
        # do this now so that the html cleaner will hopefully fix html we break
        unless (LJ::get_cap($u, 'full_rss')) {
            my $trunc = LJ::text_trim($event, 0, 80);
            $event = "$trunc..." if $trunc ne $event;
        }

        # clean the event
        LJ::CleanHTML::clean_event(\$event, 
                                   { 'preformatted' => $logprops{$itemid}->{'opt_preformatted'} });
        $event = LJ::exml($event);

        my $ditemid = $itemid*256 + $it->{'anum'};

        $$ret .= "<item>\n";
        $$ret .= "  <guid isPermaLink='true'>$clink$ditemid.html</guid>\n";
        $$ret .= "  <pubDate>" . LJ::time_to_http($LJ::EndOfTime - $it->{'rlogtime'}) . "</pubDate>\n";
        $$ret .= "  <title>$subject</title>\n" if $subject;
        $$ret .= "  <author>$ceditor</author>" if $ceditor;
        $$ret .= "  <link>$clink$ditemid.html</link>\n";
        $$ret .= "  <description>$event</description>\n";
        unless ($logprops{$itemid}->{'opt_nocomments'}) {
            $$ret .= "  <comments>$clink$ditemid.html</comments>\n";
        }
        # TODO: add author field with posterid's email address, respect communities
        $$ret .= "</item>\n";

    } # end huge while loop

    $$ret .= "</channel>\n";
    $$ret .= "</rss>\n";

    return 1;
}

1;
