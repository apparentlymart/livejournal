#!/usr/bin/perl
#
# <LJDEP>
# lib: DBI::, Digest::MD5, URI::URL, HTML::TokeParser
# lib: cgi-bin/ljconfig.pl, cgi-bin/ljlang.pl, cgi-bin/ljpoll.pl
# link: htdocs/paidaccounts/index.bml, htdocs/users, htdocs/view/index.bml
# </LJDEP>

use strict;
use vars qw($dbh %FORM);  # FIXME: in process of removing global $dbh usage.
use DBI;
use Digest::MD5 qw(md5_hex);
use Text::Wrap;
use MIME::Lite;
use HTML::LinkExtor;

########################
# CONSTANTS
#

require "$ENV{'LJHOME'}/cgi-bin/ljconfig.pl";
require "$ENV{'LJHOME'}/cgi-bin/ljlang.pl";
require "$ENV{'LJHOME'}/cgi-bin/ljpoll.pl";

@LJ::views = qw(lastn friends calendar day);
%LJ::viewinfo = (
		 "lastn" => {
		     "creator" => \&create_view_lastn,
		     "des" => "Most Recent Events",
		 },
		 "calendar" => {
		     "creator" => \&create_view_calendar,
		     "des" => "Calendar",
		 },
		 "day" => { 
		     "creator" => \&create_view_day,
		     "des" => "Day View",
		 },
		 "friends" => { 
		     "creator" => \&create_view_friends,
		     "des" => "Friends View",
		 },
		 );

## for use in style system's %%cons:.+%% mapping
%LJ::constant_map = ('siteroot' => $LJ::SITEROOT,
		     'sitename' => $LJ::SITENAME,
		     'img' => $LJ::IMGPREFIX,
		     );

## we want to set this right away, so when we get a HUP signal later
## and our signal handler sets it to true, perl doesn't need to malloc,
## since malloc may not be thread-safe and we could core dump.
## see LJ::clear_caches and LJ::handle_caches
$LJ::CLEAR_CACHES = 0;

## if this library is used in a BML page, we don't want to destroy BML's
## HUP signal handler.
if ($SIG{'HUP'}) {
    my $oldsig = $SIG{'HUP'};
    $SIG{'HUP'} = sub {
	&{$oldsig};
        LJ::clear_caches();
    };
} else {
    $SIG{'HUP'} = \&LJ::clear_caches;    
}

sub is_valid_authaction
{
    &connect_db();
    my ($aaid, $auth) = map { $dbh->quote($_) } @_;
    my $sth = $dbh->prepare("SELECT aaid, userid, datecreate, authcode, action, arg1 FROM authactions WHERE aaid=$aaid AND authcode=$auth");
    $sth->execute;
    return $sth->fetchrow_hashref;
}

#  DEPRECATED.  use LJ:: versions.
sub can_use_journal { &connect_db(); return LJ::can_use_journal($dbh, @_); }
sub connect_db { $dbh = ($BMLPersist::dbh = LJ::get_dbh("master")); }
sub days_in_month { return LJ::days_in_month(@_); }
sub get_friend_itemids { return LJ::get_friend_itemids($dbh, @_); }
sub get_recent_itemids { &connect_db(); return LJ::get_recent_itemids($dbh, @_); }
sub get_remote { &connect_db(); return LJ::get_remote($dbh, @_); }
sub get_remote_noauth { return LJ::get_remote_noauth(); }
sub get_userid { return LJ::get_userid($dbh, @_); }
sub get_username { return LJ::get_username($dbh, @_); }
sub hash_password { return md5_hex($_[0]); }
sub html_select { return LJ::html_select(@_); }
sub load_codes {  &connect_db(); LJ::load_codes($dbh, @_); }
sub load_log_props { &connect_db(); return LJ::load_log_props($dbh, @_); }
sub load_mood_theme { &connect_db(); return LJ::load_mood_theme($dbh, @_); }
sub load_moods { &connect_db(); return LJ::load_moods($dbh); }
sub load_user_props { &connect_db(); LJ::load_user_props($dbh, @_); }
sub load_user_theme { &connect_db(); return LJ::load_user_theme(@_); }
sub load_userpics { return LJ::load_userpics($dbh, @_); }
sub make_journal { connect_db(); return LJ::make_journal($dbh, @_); }
sub make_text_link { return LJ::make_text_link(@_); }
sub parse_vars { return LJ::parse_vars(@_); }
sub remote_has_priv { return LJ::remote_has_priv($dbh, @_); }
sub send_mail { return LJ::send_mail(@_); }
sub server_down_html { return LJ::server_down_html(); }
sub strip_bad_code { return LJ::strip_bad_code(@_); }
sub valid_password { return LJ::valid_password(@_); }

sub register_authaction
{
    my $dbs = LJ::get_dbs();
    my $dbh = $dbs->{'dbh'};

    my $userid = shift;  $userid += 0;
    my $action = $dbh->quote(shift);
    my $arg1 = $dbh->quote(shift);
    
    # make the authcode
    my $authcode = "";
    my $vchars = "abcdefghijklmnopqrstuvwxyz0123456789";
    srand();
    for (1..15) {
	$authcode .= substr($vchars, int(rand()*36), 1);
    }
    my $qauthcode = $dbh->quote($authcode);

    my $sth = $dbh->prepare("INSERT INTO authactions (aaid, userid, datecreate, authcode, action, arg1) VALUES (NULL, $userid, NOW(), $qauthcode, $action, $arg1)");
    $sth->execute;

    if ($dbh->err) {
	return 0;
    } else {
	return { 'aaid' => $dbh->{'mysql_insertid'},
		 'authcode' => $authcode,
	     };
    }
}

sub auth_fields
{
    my $opts = shift;
    my $remote = LJ::get_remote_noauth();
    my $ret = "";
    if (!$FORM{'altlogin'} && !$opts->{'user'} && $remote->{'user'}) {
	my $hpass;
	if ($BMLClient::COOKIE{"ljhpass"} =~ /^$remote->{'user'}:(.+)/) {
	    $hpass = $1;
	}
	my $alturl = $ENV{'REQUEST_URI'};
	$alturl .= ($alturl =~ /\?/) ? "&amp;" : "?";
	$alturl .= "altlogin=1";

	$ret .= "<TR><TD COLSPAN=2>You are currently logged in as <B>$remote->{'user'}</B>.<BR>If this is not you, <A HREF=\"$alturl\">click here</A>.\n";
	$ret .= "<INPUT TYPE=HIDDEN NAME=user VALUE=\"$remote->{'user'}\">\n";
	$ret .= "<INPUT TYPE=HIDDEN NAME=hpassword VALUE=\"$hpass\"><BR>&nbsp;\n";
	$ret .= "</TD></TR>\n";
    } else {
	$ret .= "<TR><TD>Username:</TD><TD><INPUT TYPE=TEXT NAME=user SIZE=15 MAXLENGTH=15 VALUE=\"";
	my $user = $opts->{'user'};
	unless ($user || $ENV{'QUERY_STRING'} =~ /=/) { $user=$ENV{'QUERY_STRING'}; }
	$ret .= BMLUtil::escapeall($user) unless ($FORM{'altlogin'});
	$ret .= "\"></TD></TR>\n";
	$ret .= "<TR><TD>Password:</TD><TD>\n";
	$ret .= "<INPUT TYPE=password NAME=password SIZE=15 MAXLENGTH=30 VALUE=\"" . LJ::ehtml($opts->{'password'}) . "\">";
	$ret .= "</TD></TR>\n";
    }
    return $ret;
}


sub remap_event_links
{
    my ($eventref, $baseurl) = @_;
    return unless $baseurl;
    $$eventref =~ s/(<IMG\s+[^>]*SRC=)(("(.+?)")|([^\s>]+))/"$1\"" . &abs_url($2, $baseurl). '"'/ieg;
    $$eventref =~ s/(<A\s+[^>]*HREF=)(("(.+?)")|([^\s>]+))/"$1\"" . &abs_url($2, $baseurl). '"'/ieg;
}

sub abs_url
{
    use URI::URL;
    my ($uri, $base) = @_;
    $uri =~ s/^"//;
	$uri =~ s/"$//;
    return url($uri)->abs($base)->as_string;
}

sub set_userprop
{
    my ($dbh, $userid, $propname, $value) = @_;
    my $p;

    if ($LJ::CACHE_USERPROP{$propname}) {
	$p = $LJ::CACHE_USERPROP{$propname};
    } else {
	my $qpropname = $dbh->quote($propname);
	$userid += 0;
	my $propid;
	my $sth;
	
	$sth = $dbh->prepare("SELECT upropid, indexed FROM userproplist WHERE name=$qpropname");
	$sth->execute;
	$p = $sth->fetchrow_hashref;
	return unless ($p);
	$LJ::CACHE_USERPROP{$propname} = $p;
    }

    my $table = $p->{'indexed'} ? "userprop" : "userproplite";
    $value = $dbh->quote($value);

    $dbh->do("REPLACE INTO $table (userid, upropid, value) VALUES ($userid, $p->{'upropid'}, $value)");
}

##
## returns 1 and populates %$retref if successful, else returns 0
##
sub get_mood_picture
{
    my ($themeid, $moodid, $ref) = @_;
    do 
    {
	if ($LJ::CACHE_MOOD_THEME{$themeid}->{$moodid}) {
	    %{$ref} = %{$LJ::CACHE_MOOD_THEME{$themeid}->{$moodid}};
	    if ($ref->{'pic'} =~ m!^/!) {
		$ref->{'pic'} =~ s!^/img!!;
		$ref->{'pic'} = $LJ::IMGPREFIX . $ref->{'pic'};
	    }
	    $ref->{'moodid'} = $moodid;
	    return 1;
	} else {
	    $moodid = $LJ::CACHE_MOODS{$moodid}->{'parent'};
	}
    } 
    while ($moodid);
    return 0;
}

sub ago_text
{
    my $secondsold = shift;
    return "Never." unless ($secondsold);
    my $num;
    my $unit;
    if ($secondsold > 60*60*24*7) {
	$num = int($secondsold / (60*60*24*7));
	$unit = "week";
    } elsif ($secondsold > 60*60*24) {
	$num = int($secondsold / (60*60*24));
	$unit = "day";
    } elsif ($secondsold > 60*60) {
	$num = int($secondsold / (60*60));
	$unit = "hour";
    } elsif ($secondsold > 60) {
	$num = int($secondsold / (60));
	$unit = "minute";
    } else {
	$num = $secondsold;
	$unit = "second";
    }
    return "$num $unit" . ($num==1?"":"s") . " ago";
}


# do all the current music/mood/weather/whatever stuff
sub prepare_currents
{
    my $args = shift;

    my %currents = ();
    my $val;
    if ($val = $args->{'props'}->{$args->{'itemid'}}->{'current_music'}) {
	$currents{'Music'} = $val;
    }
    if ($val = $args->{'props'}->{$args->{'itemid'}}->{'current_mood'}) {
	$currents{'Mood'} = $val;
    }
    if ($val = $args->{'props'}->{$args->{'itemid'}}->{'current_moodid'}) {
	my $theme = $args->{'user'}->{'moodthemeid'};
	&load_mood_theme($theme);
	my %pic;
	if (&get_mood_picture($theme, $val, \%pic)) {
	    $currents{'Mood'} = "<IMG SRC=\"$pic{'pic'}\" ALIGN=ABSMIDDLE WIDTH=$pic{'w'} HEIGHT=$pic{'h'} VSPACE=1> $LJ::CACHE_MOODS{$val}->{'name'}";
	} else {
	    $currents{'Mood'} = $LJ::CACHE_MOODS{$val}->{'name'};
	}
    }
    if (%currents) {
	if ($args->{'vars'}->{$args->{'prefix'}.'_CURRENTS'}) 
	{
	    ### PREFIX_CURRENTS is defined, so use the correct style vars

	    my $fvp = { 'currents' => "" };
	    foreach (sort keys %currents) {
		$fvp->{'currents'} .= &fill_var_props($args->{'vars'}, $args->{'prefix'}.'_CURRENT', {
		    'what' => $_,
		    'value' => $currents{$_},
		});
	    }
	    $args->{'event'}->{'currents'} = 
		&fill_var_props($args->{'vars'}, $args->{'prefix'}.'_CURRENTS', $fvp);
	} else 
	{
	    ### PREFIX_CURRENTS is not defined, so just add to %%events%%
	    $args->{'event'}->{'event'} .= "<BR>&nbsp;";
	    foreach (sort keys %currents) {
		$args->{'event'}->{'event'} .= "<BR><B>Current $_</B>: " . $currents{$_} . "\n";
	    }
	}
    }
}

sub fill_var_props
{
    my ($vars, $key, $hashref) = @_;
    my $data = $vars->{$key};
    $data =~ s/%%(?:([\w:]+:))?(\S+?)%%/$1 ? &fvp_transform(lc($1), $vars, $hashref, $2) : $hashref->{$2}/eg;
    return $data;
}

sub fvp_transform
{
    my ($transform, $vars, $hashref, $attr) = @_;
    my $ret = $hashref->{$attr};
    while ($transform =~ s/(\w+):$//) {
	my $trans = $1;
	if ($trans eq "ue") {
	    $ret = &eurl($ret);
	}
	elsif ($trans eq "xe") {
	    $ret = &exml($ret);
	}
	elsif ($trans eq "lc") {
	    $ret = lc($ret);
	}
	elsif ($trans eq "uc") {
	    $ret = uc($ret);
	}  
	elsif ($trans eq "color") {
	    $ret = $vars->{"color-$attr"};
	}
	elsif ($trans eq "cons") {
	    $ret = $LJ::constant_map{$attr};
	}
	elsif ($trans eq "ad") {
	    $ret = "<LJAD $attr>";
	}
    }
    return $ret;
}

sub eurl
{
    my $a = $_[0];
    $a =~ s/([^a-zA-Z0-9_\,\-.\/\\\: ])/uc sprintf("%%%02x",ord($1))/eg;
    $a =~ tr/ /+/;
    return $a;
}

### escape stuff so it can be used in XML attributes or elements
sub exml
{
    my $a = shift;
    $a =~ s/\&/&amp;/g;
    $a =~ s/\"/&quot;/g;
    $a =~ s/\'/&apos;/g;
    $a =~ s/</&lt;/g;
    $a =~ s/>/&gt;/g;
    return $a;
}

sub ehtml
{
    my $a = $_[0];
    $a =~ s/\&/&amp;/g;
    $a =~ s/\"/&quot;/g;
    $a =~ s/</&lt;/g;
    $a =~ s/>/&gt;/g;
    return $a;	
}

# pass this a hashref, and it'll populate it.
sub get_form_data 
{
    my ($hashref) = shift;
    my $buffer = shift;

    if ($ENV{'REQUEST_METHOD'} eq 'POST') {
        read(STDIN, $buffer, $ENV{'CONTENT_LENGTH'});
    } else {
        $buffer = $ENV{'QUERY_STRING'} || $ENV{'REDIRECT_QUERY_STRING'};
	if ($buffer eq "" && $ENV{'REQUEST_URI'} =~ /\?(.+)/) {
	    $buffer = $1;
	}
    }
    
    # Split the name-value pairs
    my $pair;
    my @pairs = split(/&/, $buffer);
    my ($name, $value);
    foreach $pair (@pairs)
    {
        ($name, $value) = split(/=/, $pair);
        $value =~ tr/+/ /;
        $value =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/eg;
        $name =~ tr/+/ /;
        $name =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/eg;
        $hashref->{$name} .= $hashref->{$name} ? "\0$value" : $value;
    }
}

sub bullet_errors
{
    my ($errorref) = @_;
    my $ret = "(=BADCONTENT=)\n<UL>\n";
    foreach (@{$errorref})
    {
	$ret .= "<LI>$_\n";
    }
    $ret .= "</UL>\n";
    return $ret;
}

sub icq_send
{
    my ($uin, $msg) = @_;
    if (length($msg) > 450) { $msg = substr($msg, 0, 447) . "..."; }
    return unless ($uin eq "489151" || $uin eq "19639663");
    my $time = time();
    my $rand = "0000";
    my $file;
    $file = "$LJ::ICQSPOOL/$time.$rand";
    while (-e $file) {
	$rand = sprintf("%04d", int(rand()*10000));
	$file = "$LJ::ICQSPOOL/$time.$rand";
    }
    open (FIL, ">$file");
    print FIL "send $uin $msg";
    close FIL;
}

sub create_password
{
    my @c = split(/ */, "bcdfghjklmnprstvwxyz");
    my @v = split(/ */, "aeiou");
    my $l = int(rand(2)) + 4;
    my $password = "";
    for(my $i = 1; $i <= $l; $i++)
    {
        $password .= "$c[int(rand(20))]$v[int(rand(5))]";
    }
    return $password;
}

sub age
{
    my ($age) = $_[0];   # seconds
    my $sec = $age; 
    my $unit;
    if ($age < 60) 
    { 
        $unit="sec"; 
    } 
    elsif ($age < 3600) 
    { 
        $age = int($age/60); 
        $unit=" min";
    } 
    elsif ($age < 3600*24)
    {
        $age = (int($age/3600)); 
        $unit="hr"; 
    } 
    else
    {
        $age = (int($age/(3600*24))); 
        $unit = "day";
    }
    if ($age != 1) 
    {
        $unit .= "s"; 
    } 
    return "$age $unit";
}



sub self_link
{
    my $newvars = shift;
    my $link = $ENV{'REQUEST_URI'};
    $link =~ s/\?.+//;
    $link .= "?";
    foreach (keys %$newvars) {
	if (! exists $FORM{$_}) { $FORM{$_} = ""; }
    }
    foreach (sort keys %FORM) {
	if (defined $newvars->{$_} && ! $newvars->{$_}) { next; }
	my $val = $newvars->{$_} || $FORM{$_};
	next unless $val;
	$link .= &BMLUtil::eurl($_) . "=" . &BMLUtil::eurl($val) . "&";
    }
    chop $link;
    return $link;
}

sub make_link
{
    my $url = shift;
    my $vars = shift;
    my $append = "?";
    foreach (keys %$vars) {
	next if ($vars->{$_} eq "");
	$url .= "${append}${_}=$vars->{$_}";
	$append = "&";
    }
    return $url;
}

sub trim
{
    my $a = $_[0];
    $a =~ s/^\s+//;
    $a =~ s/\s+$//;
    return $a;	
}

sub durl
{
    my ($a) = @_;
    $a =~ tr/+/ /;
    $a =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/eg;
    return $a;
}

sub html_datetime_decode
{
    my $opts = shift;
    my $hash = shift;
    my $name = $opts->{'name'};
    return sprintf("%04d-%02d-%02d %02d:%02d:%02d", 
		   $hash->{"${name}_yyyy"},
		   $hash->{"${name}_mm"},
		   $hash->{"${name}_dd"},
		   $hash->{"${name}_hh"},
		   $hash->{"${name}_nn"},
		   $hash->{"${name}_ss"});
}

sub html_datetime
{
    my $opts = shift;
    my $lang = $opts->{'lang'} || "EN";
    my ($yyyy, $mm, $dd, $hh, $nn, $ss);
    my $ret;
    my $name = $opts->{'name'};
    my $disabled = $opts->{'disabled'} ? "DISABLED" : "";
    if ($opts->{'default'} =~ /^(\d\d\d\d)-(\d\d)-(\d\d)(?: (\d\d):(\d\d):(\d\d))/) {
	($yyyy, $mm, $dd, $hh, $nn, $ss) = ($1 > 0 ? $1 : "",
					    $2+0, 
					    $3 > 0 ? $3+0 : "",
					    $4 > 0 ? $4 : "", 
					    $5 > 0 ? $5 : "", 
					    $6 > 0 ? $6 : "");
    }
    $ret .= LJ::html_select({ 'name' => "${name}_mm", 'selected' => $mm, 'disabled' => $opts->{'disabled'} },
			 map { $_, LJ::Lang::month_long($lang, $_) } (0..12));
    $ret .= "<INPUT SIZE=2 MAXLENGTH=2 NAME=${name}_dd VALUE=\"$dd\" $disabled>, <INPUT SIZE=4 MAXLENGTH=4 NAME=${name}_yyyy VALUE=\"$yyyy\" $disabled>";
    unless ($opts->{'notime'}) {
	$ret.= " <INPUT SIZE=2 MAXLENGTH=2 NAME=${name}_hh VALUE=\"$hh\" $disabled>:<INPUT SIZE=2 MAXLENGTH=2 NAME=${name}_nn VALUE=\"$nn\" $disabled>";
	if ($opts->{'seconds'}) {
	    $ret .= "<INPUT SIZE=2 MAXLENGTH=2 NAME=${name}_ss VALUE=\"$ss\" $disabled>";
	}
    }

    return $ret;
}

sub get_query_string
{
    my $q = $ENV{'QUERY_STRING'} || $ENV{'REDIRECT_QUERY_STRING'};
    if ($q eq "" && $ENV{'REQUEST_URI'} =~ /\?(.+)/) {
	$q = $1;
    }
    return $q;
}


package LJ;

# <LJFUNC>
# name: LJ::get_urls
# des: Returns a list of all referenced URLs from a string
# args: text
# des-text: Text to extra URLs from
# returns: list of URLs
# </LJFUNC>
sub get_urls
{
    my $text = shift;
    my @urls;
    my $p = HTML::LinkExtor->new(sub { 
	my ($tag, %attr) = @_;
	return if ($tag eq "img");
	push @urls, values %attr;
    });
    $p->parse($text);
    return @urls;
}

# <LJFUNC>
# name: LJ::record_meme
# des: Records a URL reference from a journal entry to the meme table.
# args: dbarg, url, posterid, itemid
# des-url: URL to log
# des-posterid: Userid of person posting
# des-itemid: Itemid URL appears in
# </LJFUNC>
sub record_meme
{
    my ($dbarg, $url, $posterid, $itemid) = @_;
    my $dbs = LJ::make_dbs_from_arg($dbarg);
    my $dbh = $dbs->{'dbh'};

    $url =~ s!/$!!;  # strip / at end
    LJ::run_hooks("canonicalize_url", \$url);
    
    my $qurl = $dbh->quote($url);
    $posterid += 0;
    $itemid += 0;
    LJ::query_buffer_add($dbs, "meme",
			 "REPLACE INTO meme (url, posterid, itemid) " .
			 "VALUES ($qurl, $posterid, $itemid)");
}

# <LJFUNC>
# name: LJ::name_caps
# des: Given a user's capability class bit mask, returns a
#      site-specific string representing the capability class name.
# args: caps
# des-caps: 16 bit capability bitmask
# </LJFUNC>
sub name_caps
{
    return undef unless LJ::are_hooks("name_caps");
    my $caps = shift;
    my @r = LJ::run_hooks("name_caps", $caps);
    return $r[0]->[0];
}

# <LJFUNC>
# name: LJ::get_cap
# des: Given a user object or capability class bit mask and a capability/limit name,
#      returns the maximum value allowed for given user or class, considering 
#      all the limits in each class the user is a part of.
# args: u_cap, capname
# des-u_cap: 16 bit capability bitmask or a user object from which the
#            bitmask could be obtained
# des-capname: the name of a limit, defined in doc/capabilities.txt
# </LJFUNC>
sub get_cap
{
    my $caps = shift;   # capability bitmask (16 bits), or user object
    my $cname = shift;  # capability limit name
    if (ref $caps eq "HASH") { $caps = $caps->{'caps'}; }
    my $max = undef;
    foreach my $bit (keys %LJ::CAP) {
	next unless ($caps & (1 << $bit));
	my $v = $LJ::CAP{$bit}->{$cname};
	next unless (defined $v);
	$max = $v if ($v > $max);
    }
    return $max;
}

# <LJFUNC>
# name: LJ::get_cap_min
# des: Just like [func[LJ::get_cap]], but returns the minimum value.
#      Although it might not make sense at first, some things are 
#      better when they're low, like the minimum amount of time
#      a user might have to wait between getting updates or being
#      allowed to refresh a page.
# args: u_cap, capname
# des-u_cap: 16 bit capability bitmask or a user object from which the
#            bitmask could be obtained
# des-capname: the name of a limit, defined in doc/capabilities.txt
# </LJFUNC>
sub get_cap_min
{
    my $caps = shift;   # capability bitmask (16 bits), or user object
    my $cname = shift;  # capability name
    if (ref $caps eq "HASH") { $caps = $caps->{'caps'}; }
    my $min = undef;
    foreach my $bit (keys %LJ::CAP) {
	next unless ($caps & (1 << $bit));
	my $v = $LJ::CAP{$bit}->{$cname};
	next unless (defined $v);
	$min = $v if ($v > $min);
    }
    return $min;
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
    return "$pre(=HELP $LJ::HELPURL{$topic} HELP=)$post";
}

# <LJFUNC>
# name: LJ::are_hooks
# des: Returns true if the site has one or more hooks installed for
#      the given hookname.
# args: hookname
# </LJFUNC>
sub are_hooks
{
    my $hookname = shift;
    return defined $LJ::HOOKS{$hookname};
}

# <LJFUNC>
# name: LJ::run_hooks
# des: Runs all the site-specific hooks of the given name.
# returns: list of arrayrefs, one for each hook ran, their
#          contents being their own return values.
# args: hookname, args*
# des-args: Arguments to be passed to hook.
# </LJFUNC>
sub run_hooks
{
    my $hookname = shift;
    my @args = shift;
    my @ret;
    foreach my $hook (@{$LJ::HOOKS{$hookname}}) {
	push @ret, [ $hook->(@args) ];
    }
    return @ret;
}

# <LJFUNC>
# name: LJ::register_hook
# des: Installs a site-specific hook.  Installing multiple hooks per hookname
#      is valid.  They're run later in the order they're registered.
# args: hookname, subref
# des-subref: Subroutine reference to run later.
# </LJFUNC>
sub register_hook
{
    my $hookname = shift;
    my $subref = shift;
    push @{$LJ::HOOKS{$hookname}}, $subref;
}

# <LJFUNC>
# name: LJ::make_auth_code
# des: Makes a random string of characters of a given length.
# returns: string of random characters, from an alphabet of 30
#          letters & numbers which aren't easily confused.
# args: length
# des-length: length of auth code to return
# </LJFUNC>
sub make_auth_code
{
    my $length = shift;
    my $digits = "abcdefghjkmnpqrstvwxyz23456789";
    my $auth;
    for (1..$length) { $auth .= substr($digits, int(rand(30)), 1); }
    return $auth;
}

# <LJFUNC>
# name: LJ::acid_encode
# des: Given a decimal number, returns base 30 encoding
#      using an alphabet of letters & numbers that are
#      not easily mistaken for each other.
# returns: Base 30 encoding, alwyas 7 characters long.
# args: number
# des-number: Number to encode in base 30.
# </LJFUNC>
sub acid_encode
{
    my $num = shift;
    my $acid = "";
    my $digits = "abcdefghjkmnpqrstvwxyz23456789";
    while ($num) {
	my $dig = $num % 30;
	$acid = substr($digits, $dig, 1) . $acid;
	$num = ($num - $dig) / 30;
    }
    return ("a"x(7-length($acid)) . $acid);
}

# <LJFUNC>
# name: LJ::acid_decode
# des: Given an acid encoding from [func[LJ::acid_encode]], 
#      returns the original decimal number.
# returns: Integer.
# args: acid
# des-acid: base 30 number from [func[LJ::acid_encode]].
# </LJFUNC>
sub acid_decode
{
    my $acid = shift;
    $acid = lc($acid);
    my %val;
    my $digits = "abcdefghjkmnpqrstvwxyz23456789";
    for (0..30) { $val{substr($digits,$_,1)} = $_; }
    my $num = 0;
    my $place = 0;
    while ($acid) {
	return 0 unless ($acid =~ s/[$digits]$//o);
	$num += $val{$&} * (30 ** $place++);	
    }
    return $num;    
}

# <LJFUNC>
# name: LJ::acct_code_generate
# des: Creates an invitation code from an optional userid
#      for use by anybody.
# returns: Account/Invite code.
# args: dbarg, userid?
# des-userid: Userid to make the invitation code from,
#             else the code will be from userid 0 (system)
# </LJFUNC>
sub acct_code_generate
{
    my $dbarg = shift;
    my $userid = shift;

    my $dbs = LJ::make_dbs_from_arg($dbarg);
    my $dbh = $dbs->{'dbh'};
    my $auth = LJ::make_auth_code(5);
    $userid = int($userid);
    $dbh->do("INSERT INTO acctcode (acid, userid, rcptid, auth) ".
	     "VALUES (NULL, $userid, 0, \"$auth\")");
    my $acid = $dbh->{'mysql_insertid'};
    return undef unless $acid;
    return acct_code_encode($acid, $auth);
}

# <LJFUNC>
# name: LJ::acct_code_encode
# des: Given an account ID integer and a 5 digit auth code, returns
#      a 12 digit account code.
# returns: 12 digit account code.
# args: acid, auth
# des-acid: account ID, a 4 byte unsigned integer
# des-auth: 5 random characters from base 30 alphabet.
# </LJFUNC>
sub acct_code_encode
{
    my $acid = shift;
    my $auth = shift;
    return lc($auth) . acid_encode($acid);
}

# <LJFUNC>
# name: LJ::acct_code_decode
# des: Breaks an account code down into its two parts
# returns: list of (account ID, auth code)
# args: code
# des-code: 12 digit account code
# </LJFUNC>
sub acct_code_decode
{
    my $code = shift;
    return (acid_decode(substr($code, 5, 7)), lc(substr($code, 0, 5)));
}

# <LJFUNC>
# name: LJ::acct_code_check
# des: Checks the validity of a given account code
# returns: boolean; 0 on failure, 1 on validity. sets $$err on failure.
# args: dbarg, code, err?, userid?
# des-code: account code to check
# des-err: optional scalar ref to put error message into on failure
# des-userid: optional userid which is allowed in the rcptid field,
#             to allow for htdocs/create.bml case when people double
#             click the submit button.
# </LJFUNC>
sub acct_code_check
{
    my $dbarg = shift;
    my $code = shift;
    my $err = shift;     # optional; scalar ref
    my $userid = shift;  # optional; acceptable userid (double-click proof)
    
    my $dbs = LJ::make_dbs_from_arg($dbarg);
    my $dbr = $dbs->{'reader'};
    
    unless (length($code) == 12) {
	$$err = "Malformed code; not 12 characters.";
	return 0;	 
    }
    
    my ($acid, $auth) = acct_code_decode($code);
    my $sth = $dbr->prepare("SELECT userid, rcptid, auth FROM acctcode WHERE acid=$acid");
    $sth->execute;
    my $ac = $sth->fetchrow_hashref;
    
    unless ($ac && $ac->{'auth'} eq $auth) {
	$$err = "Invalid account code.";
	return 0;
    }
    
    if ($ac->{'rcptid'} && $ac->{'rcptid'} != $userid) {
	$$err = "This code has already been used.";
	return 0;
    }
    
    return 1;
}

# <LJFUNC>
# name: LJ::load_mood_theme
# des: Loads and caches a mood theme, or returns immediately if already loaded.
# args: dbarg, themeid
# des-themeid: the mood theme ID to load
# </LJFUNC>
sub load_mood_theme
{
    my $dbarg = shift;
    my $themeid = shift;
    return if ($LJ::CACHE_MOOD_THEME{$themeid});

    my $dbs = make_dbs_from_arg($dbarg);
    my $dbr = $dbs->{'reader'};

    $themeid += 0;
    my $sth = $dbr->prepare("SELECT moodid, picurl, width, height FROM moodthemedata WHERE moodthemeid=$themeid");
    $sth->execute;
    while (my ($id, $pic, $w, $h) = $sth->fetchrow_array) {
	$LJ::CACHE_MOOD_THEME{$themeid}->{$id} = { 'pic' => $pic, 'w' => $w, 'h' => $h };
    }
    $sth->finish;
}

# <LJFUNC>
# name: LJ::load_props
# des: Loads and caches one or more of the various *proplist tables:
#      logproplist, talkproplist, and userproplist, which describe
#      the various meta-data that can be stored on log (journal) items,
#      comments, and users, respectively.
# args: dbarg, table*
# des-table: a list of tables' proplists to load.  can be one of
#            "log", "talk", or "user".
# </LJFUNC>
sub load_props
{
    my $dbarg = shift;
    my @tables = @_;

    my $dbs = make_dbs_from_arg($dbarg);
    my $dbr = $dbs->{'reader'};

    my %keyname = qw(log  propid
		     talk tpropid
		     user upropid);

    foreach my $t (@tables) {
	next unless defined $keyname{$t};
	next if (defined $LJ::CACHE_PROP{$t});
	my $sth = $dbr->prepare("SELECT * FROM ${t}proplist");
	$sth->execute;
	while (my $p = $sth->fetchrow_hashref) {
	    $p->{'id'} = $p->{$keyname{$t}};
	    $LJ::CACHE_PROP{$t}->{$p->{'name'}} = $p;
	}
	$sth->finish;
    }
}

# <LJFUNC>
# name: LJ::get_prop
# des: This is used after [func[LJ::load_props]] is called to retrieve
#      a hashref of a row from the given tablename's proplist table.
#      One difference from getting it straight from the database is
#      that the 'id' key is always present, as a copy of the real
#      proplist unique id for that table.
# args: table, name
# returns: hashref of proplist row from db
# des-table: the tables to get a proplist hashref from.  can be one of
#            "log", "talk", or "user".
# des-name: the name of the prop to get the hashref of.
# </LJFUNC>
sub get_prop
{
    my $table = shift;
    my $name = shift;
    return 0 unless defined $LJ::CACHE_PROP{$table};
    return $LJ::CACHE_PROP{$table}->{$name};
}

# <LJFUNC>
# name: LJ::load_codes
# des: Populates hashrefs with lookup data from the database or from memory,
#      if already loaded in the past.  Examples of such lookup data include
#      state codes, country codes, color name/value mappings, etc.
# args: dbarg, whatwhere
# des-whatwhere: a hashref with keys being the code types you want to load
#                and their associated values being hashrefs to where you
#                want that data to be populated.
# </LJFUNC>
sub load_codes
{
    my $dbarg = shift;
    my $req = shift;

    my $dbs = make_dbs_from_arg($dbarg);
    my $dbh = $dbs->{'dbh'};
    my $dbr = $dbs->{'reader'};

    foreach my $type (keys %{$req})
    {
	unless ($LJ::CACHE_CODES{$type})
	{
	    $LJ::CACHE_CODES{$type} = [];
	    my $qtype = $dbr->quote($type);
	    my $sth = $dbr->prepare("SELECT code, item FROM codes WHERE type=$qtype ORDER BY sortorder");
	    $sth->execute;
	    while (my ($code, $item) = $sth->fetchrow_array)
	    {
		push @{$LJ::CACHE_CODES{$type}}, [ $code, $item ];
	    }
	}

	foreach my $it (@{$LJ::CACHE_CODES{$type}})
	{
	    if (ref $req->{$type} eq "HASH") {
		$req->{$type}->{$it->[0]} = $it->[1];
	    } elsif (ref $req->{$type} eq "ARRAY") {
		push @{$req->{$type}}, { 'code' => $it->[0], 'item' => $it->[1] };
	    }
	}
    }
}

# <LJFUNC>
# name: LJ::img
# des: Returns an HTML &lt;img&gt; or &lt;input&gt; tag to an named image
#      code, which each site may define with a different image file with 
#      its own dimensions.  This prevents hard-coding filenames & sizes
#      into the source.  The real image data is stored in LJ::Img, which
#      has default values provided in cgi-bin/imageconf.pl but can be 
#      overridden in cgi-bin/ljconfig.pl.
# args: imagecode, type?, name?
# des-imagecode: The unique string key to reference the image.  Not a filename,
#                but the purpose or location of the image.
# des-type: By default, the tag returned is an &lt;img&gt; tag, but if 'type'
#           is "input", then an input tag is returned.
# des-name: The name of the input element, if type == "input".
# </LJFUNC>
sub img
{
    my $ic = shift;
    my $type = shift;  # either "" or "input"
    my $name = shift;  # if input

    my $i = $LJ::Img::img{$ic};
    if ($type eq "") {
	return "<img src=\"$LJ::IMGPREFIX$i->{'src'}\" width=\"$i->{'width'}\" height=\"$i->{'height'}\" alt=\"$i->{'alt'}\" border=0>";
    }
    if ($type eq "input") {
	return "<input type=\"image\" src=\"$LJ::IMGPREFIX$i->{'src'}\" width=\"$i->{'width'}\" height=\"$i->{'height'}\" alt=\"$i->{'alt'}\" border=0 name=\"$name\">";
    }
    return "<b>XXX</b>";
}

# <LJFUNC>
# name: LJ::load_user_props
# des: Given a user hashref, loads the values of the given named properties
#      into that user hashref.
# args: dbarg, u, propname*
# des-propname: the name of a property from the userproplist table.
# </LJFUNC>
sub load_user_props
{
    my $dbarg = shift;

    my $dbs = make_dbs_from_arg($dbarg);
    my $dbh = $dbs->{'dbh'};
    my $dbr = $dbs->{'reader'};

    ## user reference
    my ($uref, @props) = @_;
    my $uid = $uref->{'userid'}+0;
    unless ($uid) {
	$uid = LJ::get_userid($dbarg, $uref->{'user'});
    }
    
    my $propname_where;
    if (@props) {
	$propname_where = "AND upl.name IN (" . join(",", map { $dbh->quote($_) } @props) . ")";
    }
    
    my ($sql, $sth);

    # FIXME: right now we read userprops from both tables (indexed and
    # lite).  we always have to do this for cases when we're loading
    # all props, but when loading a subset, we might be able to
    # eliminate one query or the other if we cache somewhere the
    # userproplist and which props are in which table.  For now,
    # though, this works:

    foreach my $table (qw(userprop userproplite))
    {
	$sql = "SELECT upl.name, up.value FROM $table up, userproplist upl WHERE up.userid=$uid AND up.upropid=upl.upropid $propname_where";
	$sth = $dbr->prepare($sql);
	$sth->execute;
	while ($_ = $sth->fetchrow_hashref) {
	    $uref->{$_->{'name'}} = $_->{'value'};
	}
	$sth->finish;
    }
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
    $ret .= "(=BADCONTENT=)\n<ul>\n";
    foreach (@errors) {
	$ret .= "<li>$_\n";
    }
    $ret .= "</ul>\n";
    return $ret;
}

# <LJFUNC>
# name: LJ::debug
# des: When $LJ::DEBUG is set, logs the given message to 
#      $LJ::VAR/debug.log.
# returns: 1 if logging disabled, 0 on failure to open log, 1 otherwise
# args: message
# des-message: Message to log.
# </LJFUNC>
sub debug 
{
    return 1 unless ($LJ::DEBUG);
    open (L, ">>$LJ::VAR/debug.log") or return 0;
    print L scalar(time), ": $_[0]\n";
    close L;
    return 1;
}

# <LJFUNC>
# name: LJ::auth_okay
# des: Validates a user's password.  The "clear" or "md5" argument
#      must be present, and either the "actual" argument (the correct
#      password) must be set, or the first argument must be a user
#      object ($u) with the 'password' key set.  Note that this is
#      the preferred way to validate a password (as opposed to doing
#      it by hand) since this function will use a pluggable authenticator
#      if one is defined, so LiveJournal installations can be based
#      off an LDAP server, for example.
# returns: boolean; 1 if authentication succeeded, 0 on failure
# args: user_u, clear, md5, actual?
# des-user_u: Either the user name or a user object.
# des-clear: Clear text password the client is sending. (need this or md5)
# des-md5: MD5 of the password the client is sending. (need this or clear).
#          If this value instead of clear, clear can be anything, as md5
#          validation will take precedence.
# des-actual: The actual password for the user.  Ignored if a pluggable
#             authenticator is being used.  Required unless the first
#             argument is a user object instead of a username scalar.
# </LJFUNC>
sub auth_okay
{
    my $user = shift;
    my $clear = shift;
    my $md5 = shift;
    my $actual = shift;

    # first argument can be a user object instead of a string, in
    # which case the actual password (last argument) is got from the
    # user object.
    if (ref $user eq "HASH") {
	$actual = $user->{'password'};
	$user = $user->{'user'};
    }

    LJ::debug("auth_okay(user=$user, clear=$clear, md5=$md5, act=$actual)");

    ## custom authorization:
    if (ref $LJ::AUTH_CHECK eq "CODE") {
	my $type = $md5 ? "md5" : "clear";
	my $try = $md5 || $clear;
	return $LJ::AUTH_CHECK->($user, $try, $type);
    }
    
    ## LJ default authorization:
    return 1 if ($md5 && $md5 eq LJ::hash_password($actual));
    return 1 if ($clear eq $actual);
    return 0;
}

# <LJFUNC>
# name: LJ::create_account
# des: Creates a new basic account.  <b>Note:</b> This function is
#      not really too useful but should be extended to be useful so
#      htdocs/create.bml can use it, rather than doing the work itself.
# returns: integer of userid created, or 0 on failure.
# args: dbarg, opts
# des-opts: hashref containing keys 'user', 'name', and 'password'
# </LJFUNC>
sub create_account
{
    my $dbarg = shift;
    my $o = shift;

    my $dbs = make_dbs_from_arg($dbarg);
    my $dbh = $dbs->{'dbh'};
    my $dbr = $dbs->{'reader'};
    
    my $user = LJ::canonical_username($o->{'user'});
    unless ($user)  {
	return 0;
    }
    
    my $quser = $dbr->quote($user);
    my $qpassword = $dbr->quote($o->{'password'});
    my $qname = $dbr->quote($o->{'name'});

    my $sth = $dbh->prepare("INSERT INTO user (user, name, password) VALUES ($quser, $qname, $qpassword)");
    $sth->execute;
    if ($dbh->err) { return 0; }

    my $userid = $sth->{'mysql_insertid'};
    $dbh->do("INSERT INTO useridmap (userid, user) VALUES ($userid, $quser)");
    $dbh->do("INSERT INTO userusage (userid, timecreate) VALUES ($userid, NOW())");

    LJ::run_hooks("post_create", {
	'dbs' => $dbs,
	'userid' => $userid,
	'user' => $user,
	'code' => undef,
    });
    return $userid;
}

# <LJFUNC>
# name: LJ::is_friend
# des: Checks to see if a user is a friend of another user.
# returns: boolean; 1 iff user B is a friend of user A (or if A == B)
# args: dbarg, usera, userb
# des-usera: Source user hashref or userid.
# des-userb: Destination user hashref or userid.
# </LJFUNC>
sub is_friend
{
    my $dbarg = shift;
    my $ua = shift;
    my $ub = shift;
    
    my $uaid = (ref $ua ? $ua->{'userid'} : $ua)+0;
    my $ubid = (ref $ub ? $ub->{'userid'} : $ub)+0;

    my $dbs = make_dbs_from_arg($dbarg);
    my $dbh = $dbs->{'dbh'};
    my $dbr = $dbs->{'reader'};
		
    return 0 unless $uaid;
    return 0 unless $ubid;
    return 1 if ($uaid == $ubid);

    my $sth = $dbr->prepare("SELECT COUNT(*) FROM friends WHERE ".
			    "userid=$uaid AND friendid=$ubid");
    $sth->execute;
    my ($is_friend) = $sth->fetchrow_array;
    $sth->finish;
    return $is_friend;
}

# <LJFUNC>
# name: LJ::can_view
# des: Checks to see if the remote user can view a given journal entry.
#      <b>Note:</b> This is meant for use on single entries at a time,
#      not for calling many times on every entry in a journal.
# returns: boolean; 1 if remote user can see item
# args: dbarg, remote, item
# des-item: Hashref from the 'log' table.
# </LJFUNC>
sub can_view
{
    my $dbarg = shift;
    my $remote = shift;
    my $item = shift;
    
    # public is okay
    return 1 if ($item->{'security'} eq "public");

    # must be logged in otherwise
    return 0 unless $remote;

    my $userid = int($item->{'ownerid'});
    my $remoteid = int($remote->{'userid'});

    # owners can always see their own.
    return 1 if ($userid == $remoteid);

    # other people can't read private
    return 0 if ($item->{'security'} eq "private");

    # should be 'usemask' security from here out, otherwise
    # assume it's something new and return 0
    return 0 unless ($item->{'security'} eq "usemask");

    # usemask
    my $dbs = make_dbs_from_arg($dbarg);
    my $dbr = $dbs->{'reader'};

    my $sth = $dbr->prepare("SELECT groupmask FROM friends WHERE ".
			    "userid=$userid AND friendid=$remoteid");
    $sth->execute;
    my ($gmask) = $sth->fetchrow_array;
    my $allowed = (int($gmask) & int($item->{'allowmask'}));
    return $allowed ? 1 : 0;  # no need to return matching mask
}

# <LJFUNC>
# name: LJ::get_talktext
# des: Efficiently retrieves a large number of comments, trying first
#      slave database servers for recent items, then the master in 
#      cases of old items the slaves have already disposed of.  See also:
#      [func[LJ::get_logtext]].
# args: dbs, talkid*
# returns: hashref with keys being talkids, values being [ $subject, $body ]
# des-talkid: List of talkids to retrieve the subject & text for.
# </LJFUNC>
sub get_talktext
{
    my $dbs = shift;

    # return structure.
    my $lt = {};

    # keep track of itemids we still need to load.
    my %need;
    foreach (@_) { $need{$_+0} = 1; }

    # always consider hitting the master database, but if a slave is 
    # available, hit that first.
    my @sources = ([$dbs->{'dbh'}, "talktext"]);
    if ($dbs->{'has_slave'}) {
        if ($LJ::USE_RECENT_TABLES) {
            unshift @sources, [ $dbs->{'dbr'}, "recent_talktext" ];
        } else {
            unshift @sources, [ $dbs->{'dbr'}, "talktext" ];
        }
    }

    while (@sources && %need)
    {
        my $s = shift @sources;
        my ($db, $table) = ($s->[0], $s->[1]);
        my $talkid_in = join(", ", keys %need);

        my $sth = $db->prepare("SELECT talkid, subject, body FROM $table ".
                               "WHERE talkid IN ($talkid_in)");
        $sth->execute;
        while (my ($id, $subject, $body) = $sth->fetchrow_array) {
            $lt->{$id} = [ $subject, $body ];
            delete $need{$id};
        }
    }
    return $lt;

}

# <LJFUNC>
# name: LJ::get_logtext
# des: Efficiently retrieves a large number of journal entry text, trying first
#      slave database servers for recent items, then the master in 
#      cases of old items the slaves have already disposed of.  See also:
#      [func[LJ::get_talktext]].
# args: dbs, itemid*
# returns: hashref with keys being itemids, values being [ $subject, $body ]
# des-itemid: List of itemids to retrieve the subject & text for.
# </LJFUNC>
sub get_logtext
{
    my $dbs = shift;

    # return structure.
    my $lt = {};

    # keep track of itemids we still need to load.
    my %need;
    foreach (@_) { $need{$_+0} = 1; }

    # always consider hitting the master database, but if a slave is 
    # available, hit that first.
    my @sources = ([$dbs->{'dbh'}, "logtext"]);
    if ($dbs->{'has_slave'}) { 
	if ($LJ::USE_RECENT_TABLES) {
	    unshift @sources, [ $dbs->{'dbr'}, "recent_logtext" ];
	} else {
	    unshift @sources, [ $dbs->{'dbr'}, "logtext" ];
	}
    }

    while (@sources && %need)
    {
	my $s = shift @sources;
	my ($db, $table) = ($s->[0], $s->[1]);
	my $itemid_in = join(", ", keys %need);

	my $sth = $db->prepare("SELECT itemid, subject, event FROM $table ".
			       "WHERE itemid IN ($itemid_in)");
	$sth->execute;
	while (my ($id, $subject, $event) = $sth->fetchrow_array) {
	    $lt->{$id} = [ $subject, $event ];
	    delete $need{$id};
	}
    }
    return $lt;
}

# <LJFUNC>
# name: LJ::make_text_link
# des: The most pathetic function of them all.  AOL's shitty mail
#      reader interprets all incoming mail as HTML formatted, even if
#      the content type says otherwise.  And AOL users are all too often
#      confused by a a URL that isn't clickable, so to make it easier on
#      them (*sigh*) this function takes a URL and an email address, and
#      if the address is @aol.com, then this function wraps the URL in
#      an anchor tag to its own address.  I'm sorry.
# returns: the same URL, or the URL wrapped in an anchor tag for AOLers
# args: url, email
# des-url: URL to return or wrap.
# des-email: Email address this is going to.  If it's @aol.com, the URL
#            will be wrapped.
# </LJFUNC>
sub make_text_link
{
    my ($url, $email) = @_;
    if ($email =~ /\@aol\.com$/i) {
	return "<a href=\"$url\">$url</a>";
    }
    return $url;
}

# <LJFUNC>
# name: LJ::get_remote
# des: authenticates the user at the remote end based on their cookies 
#      and returns a hashref representing them
# returns: hashref containing 'user' and 'userid' if valid user, else
#          undef.
# args: dbarg, errors?, cgi?
# des-errors: <b>FIXME:</b> no longer used. use undef or nothing.
# des-cgi: Optional CGI.pm reference if using in a script which
#          already uses CGI.pm.
# </LJFUNC>
sub get_remote
{
    my $dbarg = shift;	
    my $errors = shift;
    my $cgi = shift;   # optional CGI.pm reference

    my $dbs = make_dbs_from_arg($dbarg);
    my $dbh = $dbs->{'dbh'};
    my $dbr = $dbs->{'reader'};

    ### are they logged in?
    my $remuser = $cgi ? $cgi->cookie('ljuser') : $BMLClient::COOKIE{"ljuser"};
    return undef unless ($remuser);

    my $hpass = $cgi ? $cgi->cookie('ljhpass') : $BMLClient::COOKIE{"ljhpass"};

    ### does their login password match their login?
    return undef unless ($hpass =~ /^$remuser:(.+)/);
    my $remhpass = $1;

    ### do they exist?
    my $userid = get_userid($dbh, $remuser);
    $userid += 0;
    return undef unless ($userid);

    ### is their password correct?
    my $correctpass;
    unless (ref $LJ::AUTH_CHECK eq "CODE") {
	my $sth = $dbr->prepare("SELECT password FROM ".
				"user WHERE userid=$userid");
	$sth->execute;
	($correctpass) = $sth->fetchrow_array;
    }
    return undef unless
      LJ::auth_okay($remuser, undef, $remhpass, $correctpass);

    return { 'user' => $remuser,
	     'userid' => $userid, };
}

# <LJFUNC>
# name: LJ::get_remote_noauth
# des: returns who the remote user says they are, but doesn't check
#      their login token.  disadvantage: insecure, only use when
#      you're not doing anything critical.  advantage:  faster.
# returns: hashref containing only key 'user', not 'userid' like
#          [func[LJ::get_remote]].
# </LJFUNC>
sub get_remote_noauth
{
    ### are they logged in?
    my $remuser = $BMLClient::COOKIE{"ljuser"};
    return undef unless ($remuser =~ /^\w{1,15}$/);

    ### does their login password match their login?
    return undef unless ($BMLClient::COOKIE{"ljhpass"} =~ /^$remuser:(.+)/);
    return { 'user' => $remuser, };
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
    return ($ENV{'REQUEST_METHOD'} eq "POST");
}

# <LJFUNC>
# name: LJ::clear_caches
# des: This function is called from a HUP signal handler and is intentionally
#      very very simple (1 line) so we don't core dump on a system without
#      reentrant libraries.  It just sets a flag to clear the caches at the
#      beginning of the next request (see [func[LJ::handle_caches]]).  
#      There should be no need to ever call this function directly.
# </LJFUNC>
sub clear_caches
{
    $LJ::CLEAR_CACHES = 1;
}

# <LJFUNC>
# name: LJ::handle_caches
# des: clears caches if the CLEAR_CACHES flag is set from an earlier
#      HUP signal that called [func[LJ::clear_caches]], otherwise
#      does nothing.
# returns: true (always) so you can use it in a conjunction of
#          statements in a while loop around the application like:
#          while (LJ::handle_caches() && FCGI::accept())
# </LJFUNC>
sub handle_caches
{
    return 1 unless ($LJ::CLEAR_CACHES);
    $LJ::CLEAR_CACHES = 0;

    %LJ::CACHE_PROP = ();
    %LJ::CACHE_STYLE = ();
    $LJ::CACHED_MOODS = 0;
    $LJ::CACHED_MOOD_MAX = 0;
    %LJ::CACHE_MOODS = ();
    %LJ::CACHE_MOOD_THEME = ();
    %LJ::CACHE_USERID = ();
    %LJ::CACHE_USERNAME = ();
    %LJ::CACHE_USERPIC_SIZE = ();
    %LJ::CACHE_CODES = ();
    %LJ::CACHE_USERPROP = ();  # {$prop}->{ 'upropid' => ... , 'indexed' => 0|1 };
    return 1;
}

# <LJFUNC>
# name: LJ::load_userpics
# des: Loads a bunch of userpic at once.
# args: dbarg, upics, idlist
# des-upics: hashref to load pictures into, keys being the picids
# des-idlist: arrayref of picids to load
# </LJFUNC>
sub load_userpics
{
    my ($dbarg, $upics, $idlist) = @_;

    my $dbs = make_dbs_from_arg($dbarg);
    my $dbh = $dbs->{'dbh'};
    my $dbr = $dbs->{'reader'};

    my @load_list;
    foreach my $id (@{$idlist}) 
    {
	if ($LJ::CACHE_USERPIC_SIZE{$id}) {
	    $upics->{$id}->{'width'} = $LJ::CACHE_USERPIC_SIZE{$id}->{'width'};
	    $upics->{$id}->{'height'} = $LJ::CACHE_USERPIC_SIZE{$id}->{'height'};
	} elsif ($id+0) {
	    push @load_list, ($id+0);
	}
    }
    return unless (@load_list);
    my $picid_in = join(",", @load_list);
    my $sth = $dbr->prepare("SELECT picid, width, height FROM userpic WHERE picid IN ($picid_in)");
    $sth->execute;
    while ($_ = $sth->fetchrow_hashref) {
	my $id = $_->{'picid'};
	undef $_->{'picid'};	
	$upics->{$id} = $_;
	$LJ::CACHE_USERPIC_SIZE{$id}->{'width'} = $_->{'width'};
	$LJ::CACHE_USERPIC_SIZE{$id}->{'height'} = $_->{'height'};
    }
}

# <LJFUNC>
# name: LJ::send_mail
# des: Sends email.
# args: opt
# des-opt: Hashref of arguments.  <b>Required:</b> to, from, subject, body.
#          <b>Optional:</b> toname, fromname, cc, bcc
# </LJFUNC>
sub send_mail
{
    my $opt = shift;
    open (MAIL, "|$LJ::SENDMAIL");
    my $toname;
    if ($opt->{'toname'}) {
	$opt->{'toname'} =~ s/[\n\t\(\)]//g;
	$toname = " ($opt->{'toname'})";
    }
    print MAIL "To: $opt->{'to'}$toname\n";
    print MAIL "Cc: $opt->{'bcc'}\n" if ($opt->{'cc'});
    print MAIL "Bcc: $opt->{'bcc'}\n" if ($opt->{'bcc'});
    print MAIL "From: $opt->{'from'}";
    if ($opt->{'fromname'}) {
	print MAIL " ($opt->{'fromname'})";
    }
    print MAIL "\nSubject: $opt->{'subject'}\n\n";
    print MAIL $opt->{'body'};
    close MAIL;
}

# TODO: make this just call the HTML cleaner.
sub strip_bad_code
{
    my $data = shift;
    my $newdata;
    use HTML::TokeParser;
    my $p = HTML::TokeParser->new($data);

    while (my $token = $p->get_token)
    {
	my $type = $token->[0];
	if ($type eq "S") {
	    if ($token->[1] eq "script") {
		$p->unget_token($token);
		$p->get_tag("/script");
	    } else {
		my $tag = $token->[1];
		my $hash = $token->[2];
		delete $hash->{'onabort'};
		delete $hash->{'onblur'};
		delete $hash->{'onchange'};
		delete $hash->{'onclick'};
		delete $hash->{'onerror'};
		delete $hash->{'onfocus'};
		delete $hash->{'onload'};
		delete $hash->{'onmouseout'};
		delete $hash->{'onmouseover'};
		delete $hash->{'onreset'};
		delete $hash->{'onselect'};
		delete $hash->{'onsubmit'};
		delete $hash->{'onunload'};
		if ($tag eq "a") {
		    if ($hash->{'href'} =~ /^\s*javascript:/) { $hash->{'href'} = "about:"; }
		} elsif ($tag eq "meta") {
		    if ($hash->{'content'} =~ /javascript:/) { delete $hash->{'content'}; }
		} elsif ($tag eq "img") {
		    if ($hash->{'src'} =~ /javascript:/) { delete $hash->{'src'}; }
		    if ($hash->{'dynsrc'} =~ /javascript:/) { delete $hash->{'dynsrc'}; }
		    if ($hash->{'lowsrc'} =~ /javascript:/) { delete $hash->{'lowsrc'}; }
		}
		$newdata .= "<" . $tag;
		foreach (keys %$hash) {
		    $newdata .= " $_=\"$hash->{$_}\"";
		}
		$newdata .= ">";
	    }
	}
	elsif ($type eq "E") {
	    $newdata .= "</" . $token->[1] . ">";
	}
	elsif ($type eq "T" || $type eq "D") {
	    $newdata .= $token->[1];
	} 
	elsif ($type eq "C") {
	    # ignore comments
	}
	elsif ($type eq "PI") {
	    $newdata .= "<?$token->[1]>";
	}
	else {
	    $newdata .= "<!-- OTHER: " . $type . "-->\n";
	}
    } # end while
    $$data = $newdata;
}

sub load_user_theme
{
    # hashref, hashref
    my ($dbarg, $user, $u, $vars) = @_;

    my $dbs = make_dbs_from_arg($dbarg);
    my $dbh = $dbs->{'dbh'};
    my $dbr = $dbs->{'reader'};
		
    my $sth;
    my $quser = $dbh->quote($user);

    if ($u->{'themeid'} == 0) {
	$sth = $dbr->prepare("SELECT coltype, color FROM themecustom WHERE user=$quser");
    } else {
	my $qtid = $dbh->quote($u->{'themeid'});
	$sth = $dbr->prepare("SELECT coltype, color FROM themedata WHERE themeid=$qtid");
    }
    $sth->execute;
    $vars->{"color-$_->{'coltype'}"} = $_->{'color'} while ($_ = $sth->fetchrow_hashref);
}

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

sub server_down_html
{
    return "<b>$LJ::SERVER_DOWN_SUBJECT</b><br />$LJ::SERVER_DOWN_MESSAGE";
}

##
## loads a style and takes into account caching (don't reload a system style
## until 60 seconds)
##
sub load_style_fast
{
    ### styleid -- numeric, primary key
    ### dataref -- pointer where to store data
    ### typeref -- optional pointer where to store style type (undef for none)
    ### nocache -- flag to say don't cache

    my ($dbarg, $styleid, $dataref, $typeref, $nocache) = @_;

    my $dbs = make_dbs_from_arg($dbarg);
    my $dbh = $dbs->{'dbh'};
    my $dbr = $dbs->{'reader'};
    
    $styleid += 0;
    my $now = time();
    
    if ((defined $LJ::CACHE_STYLE{$styleid}) &&
	($LJ::CACHE_STYLE{$styleid}->{'lastpull'} > ($now-300)) &&
	(! $nocache)
	)
    {
	$$dataref = $LJ::CACHE_STYLE{$styleid}->{'data'};
	if (ref $typeref eq "SCALAR") { $$typeref = $LJ::CACHE_STYLE{$styleid}->{'type'}; }
    }
    else
    {
	my @h = ($dbh);
	if ($dbs->{'has_slave'}) {
	    unshift @h, $dbr;
	}
	my ($data, $type, $cache);
	my $sth;
	foreach my $db (@h) 
	{
	    $sth = $dbr->prepare("SELECT formatdata, type, opt_cache FROM style WHERE styleid=$styleid");
	    $sth->execute;
	    ($data, $type, $cache) = $sth->fetchrow_array;
	    $sth->finish;
	    last if ($data);
	}
	if ($cache eq "Y") {
	    $LJ::CACHE_STYLE{$styleid} = { 'lastpull' => $now,
				       'data' => $data,
				       'type' => $type,
				   };
	}

	$$dataref = $data;
	if (ref $typeref eq "SCALAR") { $$typeref = $type; }
    }
}

# $dbarg can be either a $dbh (master) or a $dbs (db set, master & slave hashref)
sub make_journal
{
    my ($dbarg, $user, $view, $remote, $opts) = @_;

    my $dbs = LJ::make_dbs_from_arg($dbarg);
    my $dbh = $dbs->{'dbh'};
    my $dbr = $dbs->{'reader'};

    if ($LJ::SERVER_DOWN) {
	if ($opts->{'vhost'} eq "customview") {
	    return "<!-- LJ down for maintenance -->";
	}
	return LJ::server_down_html();
    }
    
    my ($styleid);
    if ($opts->{'styleid'}) { 
	$styleid = $opts->{'styleid'}+0; 
    } else {
	$view ||= "lastn";    # default view when none specified explicitly in URLs
	if ($LJ::viewinfo{$view})  {
	    $styleid = -1;    # to get past the return, then checked later for -1 and fixed, once user is loaded.
	    $view = $view;
	} else {
	    $opts->{'badargs'} = 1;
	}
    }
    return "" unless ($styleid);

    my $quser = $dbh->quote($user);
    my $u;
    if ($opts->{'u'}) {
	$u = $opts->{'u'};
    } else {
	$u = LJ::load_user($dbs, $user);
    }

    unless ($u)
    {
	$opts->{'baduser'} = 1;
	return "<H1>Error</H1>No such user <B>$user</B>";
    }

    if ($styleid == -1) {
	$styleid = $u->{"${view}_style"};
    }

    if ($LJ::USER_VHOSTS && $opts->{'vhost'} eq "users" && ! LJ::get_cap($u, "userdomain")) {
	return "<b>Notice</b><br />Addresses like <tt>http://<i>username</i>.$LJ::USER_DOMAIN</tt> aren't enabled for this user's account type.  Instead, visit:<ul><font face=\"Verdana,Arial\"><b><a href=\"$LJ::SITEROOT/users/$user/\">$LJ::SITEROOT/users/$user/</a></b></font></ul>";
    }
    if ($opts->{'vhost'} eq "customview" && ! LJ::get_cap($u, "userdomain")) {
	return "<b>Notice</b><br />Only users with <A HREF=\"$LJ::SITEROOT/paidaccounts/\">paid accounts</A> can create and embed styles.";
    }
    if ($opts->{'vhost'} eq "community" && $u->{'journaltype'} ne "C") {
	return "<b>Notice</b><br />This account isn't a community journal.";
    }

    return "<h1>Error</h1>Journal has been deleted.  If you are <B>$user</B>, you have a period of 30 days to decide to undelete your journal." if ($u->{'statusvis'} eq "D");
    return "<h1>Error</h1>This journal has been suspended." if ($u->{'statusvis'} eq "S");

    my %vars = ();
    # load the base style
    my $basevars = "";
    LJ::load_style_fast($dbs, $styleid, \$basevars, \$view);

    # load the overrides
    my $overrides = "";
    if ($opts->{'nooverride'}==0 && $u->{'useoverrides'} eq "Y")
    {
        my $sth = $dbr->prepare("SELECT override FROM overrides WHERE user=$quser");
        $sth->execute;
        ($overrides) = $sth->fetchrow_array;
	$sth->finish;
    }

    # populate the variable hash
    &parse_vars(\$basevars, \%vars);
    &parse_vars(\$overrides, \%vars);
    LJ::load_user_theme($dbs, $user, $u, \%vars);
    
    # kinda free some memory
    $basevars = "";
    $overrides = "";

    # instruct some function to make this specific view type
    return "" unless (defined $LJ::viewinfo{$view}->{'creator'});
    my $ret = "";

    # call the view creator w/ the buffer to fill and the construction variables
    &{$LJ::viewinfo{$view}->{'creator'}}($dbs, \$ret, $u, \%vars, $remote, $opts);

    # remove bad stuff
    unless ($opts->{'trusted_html'}) {
	&strip_bad_code(\$ret);
    }

    # return it...
    return $ret;   
}


sub html_select
{
    my $opts = shift;
    my @items = @_;
    my $disabled = $opts->{'disabled'} ? " DISABLED" : "";
    my $ret;
    $ret .= "<select";
    if ($opts->{'name'}) { $ret .= " name=\"$opts->{'name'}\""; }
    $ret .= "$disabled>";
    while (my ($value, $text) = splice(@items, 0, 2)) {
	my $sel = "";
	if ($value eq $opts->{'selected'}) { $sel = " selected"; }
	$ret .= "<option value=\"$value\"$sel>$text";
    }
    $ret .= "</select>";
    return $ret;
}

sub html_check
{
    my $opts = shift;

    my $disabled = $opts->{'disabled'} ? " DISABLED" : "";
    my $ret;
    if ($opts->{'type'} eq "radio") {
	$ret .= "<input type=\"radio\" ";
    } else {
	$ret .= "<input type=\"checkbox\" ";
    }
    if ($opts->{'selected'}) { $ret .= " checked"; }
    if ($opts->{'name'}) { $ret .= " name=\"$opts->{'name'}\""; }
    if (defined $opts->{'value'}) { $ret .= " value=\"$opts->{'value'}\""; }
    $ret .= "$disabled>";
    return $ret;
}

sub html_text
{
    my $opts = shift;

    my $disabled = $opts->{'disabled'} ? " DISABLED" : "";
    my $ret;
    $ret .= "<input type=\"text\"";
    if ($opts->{'size'}) { $ret .= " size=\"$opts->{'size'}\""; }
    if ($opts->{'maxlength'}) { $ret .= " maxlength=\"$opts->{'maxlength'}\""; }
    if ($opts->{'name'}) { $ret .= " name=\"" . LJ::ehtml($opts->{'name'}) . "\""; }
    if ($opts->{'value'}) { $ret .= " value=\"" . LJ::ehtml($opts->{'value'}) . "\""; }
    $ret .= "$disabled>";
    return $ret;
}

#
# returns the canonical username given, or blank if the username is not well-formed
#
sub canonical_username
{
    my $user = shift;
    if ($user =~ /^\s*([\w\-]{1,15})\s*$/) {
	$user = lc($1);
	$user =~ s/-/_/g;
	return $user;
    }
    return "";  # not a good username.
}

sub decode_url_string
{
    my $buffer = shift;   # input scalarref
    my $hashref = shift;  # output hash

    my $pair;
    my @pairs = split(/&/, $$buffer);
    my ($name, $value);
    foreach $pair (@pairs)
    {
        ($name, $value) = split(/=/, $pair);
        $value =~ tr/+/ /;
        $value =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/eg;
        $name =~ tr/+/ /;
        $name =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/eg;
        $hashref->{$name} .= $hashref->{$name} ? "\0$value" : $value;
    }
}

# called by nearly all the other functions
sub get_dbh
{
    my $type = shift;  # 'master', 'slave', or 'slave!'. (the latter won't fall back to master)
    my $dbh;

    # with an exclamation mark, the caller only wants a slave, never
    # the master.  presumably, the caller already has a master handle
    # and only wants a slave for a performance gain and having two
    # masters would not only be silly, but slower, if it tries to use
    # both of them.

    if ($type eq "slave!") {
	if (! $LJ::DBINFO{'slavecount'}) {
	    return undef;
	}
	$type = "slave";
    }

    ## already have a dbh of this type open?

    if (ref $LJ::DBCACHE{$type}) {
        $dbh = $LJ::DBCACHE{$type};

	# make sure connection is still good.
	my $sth = $dbh->prepare("SELECT CONNECTION_ID()");  # mysql specific
	$sth->execute;
	my ($id) = $sth->fetchrow_array;
	if ($id) { return $dbh; }
	undef $dbh;
	undef $LJ::DBCACHE{$type};
    }

    ### if we don't have a dbh cached already, which one would we try to connect to?

    my $key;
    if ($type eq "slave") {
	my $ct = $LJ::DBINFO{'slavecount'};
	if ($ct) {
	    my $rand = rand(1);
	    my $i = 1;
	    while (! $key && $i <= $ct) {
		if ($rand < $LJ::DBINFO{"slave$i"}->{'ub'}) {
		    $key = "slave$i";
		} else {
		    $i++;
		}
	    }
	    unless ($key) {
		$key = "slave" . int(rand($ct)+1);
	    }
	} else {
	    $key = "master";
	}
    } else {
	$key = "master";
    }

    my $dsn = "DBI:mysql";
    my $db = $LJ::DBINFO{$key};
    $db->{'dbname'} ||= "livejournal";
    $dsn .= ":$db->{'dbname'}:";
    if ($db->{'host'}) {
	$dsn .= "host=$db->{'host'};";
    }
    if ($db->{'sock'}) {
	$dsn .= "mysql_socket=$db->{'sock'};";
    }

    $dbh = DBI->connect($dsn, $db->{'user'}, $db->{'pass'}, {
	PrintError => 0,
    });
    
    # save a reference to the database handle for later
    $LJ::DBCACHE{$type} = $dbh;

    return $dbh;
}

# <LJFUNC>
# name: LJ::get_dbs
# des: Returns a set of database handles to master and a slave,
#      if this site is using slave databases.  Only use this
#      once per connection and pass around the same $dbs, since
#      this function calls [func[LJ::get_dbh]] which uses cached
#      connections, but validates the connection is still live.
# returns: $dbs (see [func[LJ::make_dbs]])
# </LJFUNC>
sub get_dbs
{
    my $dbh = LJ::get_dbh("master");
    my $dbr = LJ::get_dbh("slave!");
    return make_dbs($dbh, $dbr);
}

# <LJFUNC>
# name: LJ::make_dbs
# des: Makes a $dbs structure from a master db
#      handle and optionally a slave.  This function
#      is called from [func[LJ::get_dbs]].  You shouldn't need
#      to call it yourself.
# returns: $dbs: hashref with 'dbh' (master), 'dbr' (slave or undef),
#          'has_slave' (boolean) and 'reader' (dbr if defined, else dbh)
# </LJFUNC>
sub make_dbs
{
    my ($dbh, $dbr) = @_;
    my $dbs = {};
    $dbs->{'dbh'} = $dbh;
    $dbs->{'dbr'} = $dbr;
    $dbs->{'has_slave'} = defined $dbr ? 1 : 0;
    $dbs->{'reader'} = defined $dbr ? $dbr : $dbh;
    return $dbs;
}

# converts a single argument to a dbs.  the argument is either a 
# dbset already, or it's a master handle, in which case we need
# to make it into a dbset with no slave.
sub make_dbs_from_arg
{
    my $dbarg = shift;
    my $dbs;
    if (ref($dbarg) eq "HASH") {
	$dbs = $dbarg;
    } else {
	$dbs = LJ::make_dbs($dbarg, undef);
    }
    return $dbs;    
}

 
## turns a date (yyyy-mm-dd) into links to year calendar, month view, and day view, given
## also a user object (hashref)
sub date_to_view_links
{
    my ($u, $date) = @_;
    
    return unless ($date =~ /(\d\d\d\d)-(\d\d)-(\d\d)/);
    my ($y, $m, $d) = ($1, $2, $3);
    my ($nm, $nd) = ($m+0, $d+0);   # numeric, without leading zeros
    my $user = $u->{'user'};

    my $ret;
    $ret .= "<a href=\"$LJ::SITEROOT/users/$user/calendar/$y\">$y</a>-";
    $ret .= "<a href=\"$LJ::SITEROOT/view/?type=month&amp;user=$user&amp;y=$y&amp;m=$nm\">$m</a>-";
    $ret .= "<a href=\"$LJ::SITEROOT/users/$user/day/$y/$m/$d\">$d</a>";
    return $ret;
}

sub item_link
{
    my ($u, $itemid) = @_;
    return "$LJ::SITEROOT/talkread.bml?itemid=$itemid";
}

sub make_graphviz_dot_file
{
    my $dbarg = shift;
    my $user = shift;

    my $dbs = make_dbs_from_arg($dbarg);
    my $dbh = $dbs->{'dbh'};
    my $dbr = $dbs->{'reader'};

    my $quser = $dbr->quote($user);
    my $sth;
    my $ret;
 
    $sth = $dbr->prepare("SELECT u.*, UNIX_TIMESTAMP()-UNIX_TIMESTAMP(uu.timeupdate) AS 'secondsold' FROM user u, userusage uu WHERE u.userid=uu.userid AND u.user=$quser");
    $sth->execute;
    my $u = $sth->fetchrow_hashref;
    
    unless ($u) {
	return "";	
    }
    
    $ret .= "digraph G {\n";
    $ret .= "  node [URL=\"$LJ::SITEROOT/userinfo.bml?user=\\N\"]\n";
    $ret .= "  node [fontsize=10, color=lightgray, style=filled]\n";
    $ret .= "  \"$user\" [color=yellow, style=filled]\n";
    
    my @friends = ();
    $sth = $dbr->prepare("SELECT friendid FROM friends WHERE userid=$u->{'userid'} AND userid<>friendid");
    $sth->execute;
    while ($_ = $sth->fetchrow_hashref) {
	push @friends, $_->{'friendid'};
    }
    
    my $friendsin = join(", ", map { $dbh->quote($_); } ($u->{'userid'}, @friends));
    my $sql = "SELECT uu.user, uf.user AS 'friend' FROM friends f, user uu, user uf WHERE f.userid=uu.userid AND f.friendid=uf.userid AND f.userid<>f.friendid AND uu.statusvis='V' AND uf.statusvis='V' AND (f.friendid=$u->{'userid'} OR (f.userid IN ($friendsin) AND f.friendid IN ($friendsin)))";
    $sth = $dbr->prepare($sql);
    $sth->execute;
    while ($_ = $sth->fetchrow_hashref) {
	$ret .= "  \"$_->{'user'}\"->\"$_->{'friend'}\"\n";
    }
    
    $ret .= "}\n";
    
    return $ret;
}

sub expand_embedded
{
    my $dbarg = shift;
    my $itemid = shift;
    my $remote = shift;
    my $eventref = shift;

    my $dbs = make_dbs_from_arg($dbarg);
    my $dbh = $dbs->{'dbh'};
    my $dbr = $dbs->{'reader'};
    
    # TODO: This should send $dbs instead of $dbh when that function
    # is converted. In addition, when that occurs the make_dbs_from_arg
    # code above can be removed.
    LJ::Poll::show_polls($dbh, $itemid, $remote, $eventref);
}

sub make_remote
{
    my $user = shift;
    my $userid = shift;
    if ($userid && $userid =~ /^\d+$/) {
	return { 'user' => $user,
		 'userid' => $userid, };
    }
    return undef;
}

sub escapeall
{
    my $a = $_[0];

    ### escape HTML
    $a =~ s/\&/&amp;/g;
    $a =~ s/\"/&quot;/g;
    $a =~ s/</&lt;/g;
    $a =~ s/>/&gt;/g;

    ### and escape BML
    $a =~ s/\(=/\(&#0061;/g;
    $a =~ s/=\)/&#0061;\)/g;
    return $a;
}

# $dbarg can be either a $dbh (master) or a $dbs (db set, master & slave hashref)
sub load_user
{
    my $dbarg = shift;
    my $user = shift;

    my $dbs = LJ::make_dbs_from_arg($dbarg);
    my $dbh = $dbs->{'dbh'};
    my $dbr = $dbs->{'reader'};

    $user = LJ::canonical_username($user);

    my $quser = $dbr->quote($user);
    my $sth = $dbr->prepare("SELECT * FROM user WHERE user=$quser");
    $sth->execute;
    my $u = $sth->fetchrow_hashref;
    $sth->finish;

    # if user doesn't exist in the LJ database, it's possible we're using
    # an external authentication source and we should create the account
    # implicitly.
    if (! $u && ref $LJ::AUTH_EXISTS eq "CODE") {
	if ($LJ::AUTH_EXISTS->($user)) {
	    if (LJ::create_account($dbh, {
		'user' => $user,
		'name' => $user,
		'password' => "",
	    }))
	    {
		# NOTE: this should pull from the master, since it was _just_
		# created and the elsif below won't catch.
		$sth = $dbh->prepare("SELECT * FROM user WHERE user=$quser");
		$sth->execute;
		$u = $sth->fetchrow_hashref;
		$sth->finish;
		return $u;		
	    } else {
		return undef;
	    }
	}
    } elsif (! $u && $dbs->{'has_slave'}) {
        # If the user still doesn't exist, and there isn't an alternate auth code
        # try grabbing it from the master.
        $sth = $dbh->prepare("SELECT * FROM user WHERE user=$quser");
        $sth->execute;
        $u = $sth->fetchrow_hashref;
        $sth->finish;
    }

    return $u;
}

sub load_userid
{
    my $dbarg = shift;
    my $userid = shift;

    my $dbs = make_dbs_from_arg($dbarg);
    my $dbh = $dbs->{'dbh'};
    my $dbr = $dbs->{'reader'};
		
    my $quserid = $dbr->quote($userid);
    my $sth = $dbr->prepare("SELECT * FROM user WHERE userid=$quserid");
    $sth->execute;
    my $u = $sth->fetchrow_hashref;
    $sth->finish;
    return $u;
}

sub load_moods
{
    return if ($LJ::CACHED_MOODS);
    my $dbarg = shift;

    my $dbs = make_dbs_from_arg($dbarg);
    my $dbh = $dbs->{'dbh'};
    my $dbr = $dbs->{'reader'};

    my $sth = $dbr->prepare("SELECT moodid, mood, parentmood FROM moods");
    $sth->execute;
    while (my ($id, $mood, $parent) = $sth->fetchrow_array) {
	$LJ::CACHE_MOODS{$id} = { 'name' => $mood, 'parent' => $parent };
	if ($id > $LJ::CACHED_MOOD_MAX) { $LJ::CACHED_MOOD_MAX = $id; }
    }
    $LJ::CACHED_MOODS = 1;
}

# <LJFUNC>
# name: LJ::query_buffer_add
# des: Schedules an insert/update query to be run on a certain table sometime 
#      in the near future in a batch with a lot of similar updates, or
#      immediately if the site doesn't provide query buffering.  Returns
#      nothing (no db error code) since there's the possibility it won't
#      run immediately anyway.
# args: dbarg, table, query
# des-table: Table to modify.
# des-query: Query that'll update table.  The query <b>must not</b> access
#            any table other than that one, since the update is done inside
#            an explicit table lock for performance.
# </LJFUNC>
sub query_buffer_add
{
    my ($dbarg, $table, $query) = @_;

    my $dbs = make_dbs_from_arg($dbarg);
    my $dbh = $dbs->{'dbh'};
    my $dbr = $dbs->{'reader'};
    
    if ($LJ::BUFFER_QUERIES) 
    {
	# if this is a high load site, you'll want to batch queries up and send them at once.

	my $table = $dbh->quote($table);
	my $query = $dbh->quote($query);
	$dbh->do("INSERT INTO querybuffer (qbid, tablename, instime, query) VALUES (NULL, $table, NOW(), $query)");
    }
    else 
    {
	# low load sites can skip this, and just have queries go through immediately.
	$dbh->do($query);
    }
}

sub query_buffer_flush
{
    my ($dbarg, $table) = @_;

    my $dbs = make_dbs_from_arg($dbarg);
    my $dbh = $dbs->{'dbh'};
    my $dbr = $dbs->{'reader'};

    return -1 unless ($table);
    return -1 if ($table =~ /[^\w]/);
    
    $dbh->do("LOCK TABLES $table WRITE, querybuffer WRITE");
    
    my $count = 0;
    my $max = 0;
    my $qtable = $dbh->quote($table);

    # We want to leave this pointed to the master to ensure we are
    # getting the most recent data!  (also, querybuffer doesn't even
    # replicate to slaves in the recommended configuration... it's
    # pointless to do so)
    my $sth = $dbh->prepare("SELECT qbid, query FROM querybuffer WHERE tablename=$qtable ORDER BY qbid");
    if ($dbh->err) { $dbh->do("UNLOCK TABLES"); die $dbh->errstr; }
    $sth->execute;
    if ($dbh->err) { $dbh->do("UNLOCK TABLES"); die $dbh->errstr; }	
    while (my ($id, $query) = $sth->fetchrow_array)
    {
	$dbh->do($query);
	$count++;
	$max = $id;
    }
    $sth->finish;
    
    $dbh->do("DELETE FROM querybuffer WHERE tablename=$qtable");
    if ($dbh->err) { $dbh->do("UNLOCK TABLES"); die $dbh->errstr; }		
    
    $dbh->do("UNLOCK TABLES");
    return $count;
}

sub journal_base
{
    my ($user, $vhost) = @_;
    if ($vhost eq "users") {
	my $he_user = $user;
	$he_user =~ s/_/-/g;
	return "http://$he_user.$LJ::USER_DOMAIN";
    } elsif ($vhost eq "tilde") {
	return "$LJ::SITEROOT/~$user";
    } elsif ($vhost eq "community") {
	return "$LJ::SITEROOT/community/$user";
    } else { 
	return "$LJ::SITEROOT/users/$user";
    }
}

# loads all of the given privs for a given user into a hashref
# inside the user record ($u->{_privs}->{$priv}->{$arg} = 1)
sub load_user_privs
{
    my $dbarg = shift;
    my $remote = shift;
    my @privs = @_;

    my $dbs = make_dbs_from_arg($dbarg);
    my $dbh = $dbs->{'dbh'};
    my $dbr = $dbs->{'reader'};
    
    return unless ($remote and @privs);

    # return if we've already loaded these privs for this user.
    @privs = map { $dbr->quote($_) } 
             grep { ! $remote->{'_privloaded'}->{$_}++ } @privs;
    
    return unless (@privs);

    my $sth = $dbr->prepare("SELECT pl.privcode, pm.arg ".
			    "FROM priv_map pm, priv_list pl ".
			    "WHERE pm.prlid=pl.prlid AND ".
			    "pl.privcode IN (" . join(',',@privs) . ") ".
			    "AND pm.userid=$remote->{'userid'}");
    $sth->execute;
    while (my ($priv, $arg) = $sth->fetchrow_array)
    {
	unless (defined $arg) { $arg = ""; }  # NULL -> ""
	$remote->{'_priv'}->{$priv}->{$arg} = 1;
    }
}

# arg is optional.  if arg not present, checks if remote has
# any privs at all of that type.
# also, $dbh can be undef, in which case privs must be pre-loaded
sub check_priv
{
    my ($dbarg, $remote, $priv, $arg) = @_;
    return 0 unless ($remote);

    my $dbs = make_dbs_from_arg($dbarg);
    my $dbh = $dbs->{'dbh'};
    my $dbr = $dbs->{'reader'};
    
    if (! $remote->{'_privloaded'}->{$priv}) {
	if ($dbr) {
	    load_user_privs($dbr, $remote, $priv);
	} else {
	    return 0;
	}
    }

    if (defined $arg) {
	return (defined $remote->{'_priv'}->{$priv} &&
		defined $remote->{'_priv'}->{$priv}->{$arg});
    } else {
	return (defined $remote->{'_priv'}->{$priv});
    }
}

# check to see if the given remote user has a certain privledge
# DEPRECATED.  should use load_user_privs + check_priv
sub remote_has_priv
{
    my $dbarg = shift;
    my $remote = shift;
    my $privcode = shift;     # required.  priv code to check for.
    my $ref = shift;  # optional, arrayref or hashref to populate

    my $dbs = make_dbs_from_arg($dbarg);
    my $dbh = $dbs->{'dbh'};
    my $dbr = $dbs->{'reader'};

    return 0 unless ($remote);

    ### authentication done.  time to authorize...

    my $qprivcode = $dbh->quote($privcode);
    my $sth = $dbr->prepare("SELECT pm.arg FROM priv_map pm, priv_list pl WHERE pm.prlid=pl.prlid AND pl.privcode=$qprivcode AND pm.userid=$remote->{'userid'}");
    $sth->execute;
    
    my $match = 0;
    if (ref $ref eq "ARRAY") { @$ref = (); }
    if (ref $ref eq "HASH") { %$ref = (); }
    while (my ($arg) = $sth->fetchrow_array) {
	$match++;
	if (ref $ref eq "ARRAY") { push @$ref, $arg; }
	if (ref $ref eq "HASH") { $ref->{$arg} = 1; }
    }
    return $match;
}

## get a userid from a username (returns 0 if invalid user)
sub get_userid
{
    my $dbarg = shift;
    my $user = shift;
		
    my $dbs = make_dbs_from_arg($dbarg);
    my $dbh = $dbs->{'dbh'};
    my $dbr = $dbs->{'reader'};
    
    $user = canonical_username($user);

    my $userid;
    if ($LJ::CACHE_USERID{$user}) { return $LJ::CACHE_USERID{$user}; }

    my $quser = $dbr->quote($user);
    my $sth = $dbr->prepare("SELECT userid FROM useridmap WHERE user=$quser");
    $sth->execute;
    ($userid) = $sth->fetchrow_array;
    if ($userid) { $LJ::CACHE_USERID{$user} = $userid; }

    # implictly create an account if we're using an external
    # auth mechanism
    if (! $userid && ref $LJ::AUTH_EXISTS eq "CODE")
    {
	# TODO: eventual $dbs conversion (even though create_account will ALWAYS
	# use the master)
	$userid = LJ::create_account($dbh, { 'user' => $user,
					     'name' => $user,
					     'password' => '', });
    }

    return ($userid+0);
}

## get a username from a userid (returns undef if invalid user)
# $dbarg can be either a $dbh (master) or a $dbs (db set, master & slave hashref)
sub get_username
{
    my $dbarg = shift;
    my $userid = shift;
    my $user;
    $userid += 0;

    # Checked the cache first. 
    if ($LJ::CACHE_USERNAME{$userid}) { return $LJ::CACHE_USERNAME{$userid}; }

    my $dbs = LJ::make_dbs_from_arg($dbarg);
    my $dbr = $dbs->{'reader'};

    my $sth = $dbr->prepare("SELECT user FROM useridmap WHERE userid=$userid");
    $sth->execute;
    $user = $sth->fetchrow_array;

    # Fall back to master if it doesn't exist.
    if (! defined($user) && $dbs->{'has_slave'}) {
        my $dbh = $dbs->{'dbh'};
        $sth = $dbh->prepare("SELECT user FROM useridmap WHERE userid=$userid");
        $sth->execute;
        $user = $sth->fetchrow_array;
    }
    if (defined($user)) { $LJ::CACHE_USERNAME{$userid} = $user; }
    return ($user);
}

sub get_itemid_near
{
    my $dbarg = shift;
    my $ownerid = shift;
    my $date = shift;
    my $after_before = shift;
		
    my $dbs = LJ::make_dbs_from_arg($dbarg);
    my $dbh = $dbs->{'dbh'};
    my $dbr = $dbs->{'reader'};
    
    return 0 unless ($date =~ /^(\d{4})-(\d{2})-\d{2} \d{2}:\d{2}:\d{2}$/);
    my ($year, $month) = ($1, $2);

    my ($op, $inc, $func);
    if ($after_before eq "after") {
	($op, $inc, $func) = (">",  1, "MIN");
    } elsif ($after_before eq "before") {
	($op, $inc, $func) = ("<", -1, "MAX");
    } else {
	return 0;
    }

    my $qeventtime = $dbh->quote($date);

    my $item = 0;
    my $tries = 0;
    while ($item==0 && $tries<2) 
    {
	my $sql = "SELECT $func(itemid) FROM log WHERE ownerid=$ownerid AND year=$year AND month=$month AND eventtime $op $qeventtime";
	my $sth = $dbr->prepare($sql);
	$sth->execute;
	($item) = $sth->fetchrow_array;

	unless ($item) {
	    $tries++;
	    $month += $inc;
	    if ($month == 13) { $month = 1;  $year++; }
	    if ($month == 0)  { $month = 12; $year--; }
	}
    }
    return ($item+0);
}

sub get_itemid_after  { return get_itemid_near(@_, "after");  }
sub get_itemid_before { return get_itemid_near(@_, "before"); }

sub mysql_time
{
    my $time = shift;
    $time ||= time();
    my @ltime = localtime($time);
    return sprintf("%04d-%02d-%02d %02d:%02d:%02d", 
		   $ltime[5]+1900,
		   $ltime[4]+1,
		   $ltime[3],
		   $ltime[2],
		   $ltime[1],
		   $ltime[0]);
}

sub get_keyword_id
{
    my $dbarg = shift;
    my $kw = shift;
    unless ($kw =~ /\S/) { return 0; }

    my $dbs = LJ::make_dbs_from_arg($dbarg);
    my $dbh = $dbs->{'dbh'};
    my $dbr = $dbs->{'reader'};
		
    my $qkw = $dbh->quote($kw);

    # Making this a $dbr could cause problems due to the insertion of
    # data based on the results of this query. Leave as a $dbh.
    my $sth = $dbh->prepare("SELECT kwid FROM keywords WHERE keyword=$qkw");
    $sth->execute;
    my ($kwid) = $sth->fetchrow_array;
    unless ($kwid) {
	$sth = $dbh->prepare("INSERT INTO keywords (kwid, keyword) VALUES (NULL, $qkw)");
	$sth->execute;
	$kwid = $dbh->{'mysql_insertid'};
    }
    return $kwid;
}

sub trim
{
    my $a = $_[0];
    $a =~ s/^\s+//;
    $a =~ s/\s+$//;
    return $a;	
}

# returns true if $formref->{'password'} matches cleartext password or if
# $formref->{'hpassword'} is the hash of the cleartext password
sub valid_password
{
    my ($clearpass, $formref) = @_;
    if ($formref->{'password'} && $formref->{'password'} eq $clearpass)
    {
        return 1;
    }
    if ($formref->{'hpassword'} && lc($formref->{'hpassword'}) eq &hash_password($clearpass))
    {
        return 1;
    }
    return 0;    
}

sub delete_user
{
		# TODO: Is this function even being called?
		# It doesn't look like it does anything useful
    my $dbh = shift;
    my $user = shift;
    my $quser = $dbh->quote($user);
    my $sth;
    $sth = $dbh->prepare("SELECT user, userid FROM useridmap WHERE user=$quser");
    my $u = $sth->fetchrow_hashref;
    unless ($u) { return; }
    
    ### so many issues.     
}

sub hash_password
{
    return Digest::MD5::md5_hex($_[0]);
}

# $dbarg can be either a $dbh (master) or a $dbs (db set, master & slave hashref)
sub can_use_journal
{
    my ($dbarg, $posterid, $reqownername, $res) = @_;

    my $dbs = LJ::make_dbs_from_arg($dbarg);
    my $dbh = $dbs->{'dbh'};
    my $dbr = $dbs->{'reader'};

    my $qreqownername = $dbh->quote($reqownername);
    my $qposterid = $posterid+0;

    ## find the journal owner's userid
    my $sth = $dbr->prepare("SELECT userid FROM useridmap WHERE user=$qreqownername");
    $sth->execute;
    my $ownerid = $sth->fetchrow_array;
    # First, fall back to the master.
    unless ($ownerid) {
        if ($dbs->{'has_slave'}) {
            $sth = $dbh->prepare("SELECT userid FROM useridmap WHERE user=$qreqownername");
            $sth->execute;
            $ownerid = $sth->fetchrow_array;
        }
        # If it still doesn't exist, it doesn't exist.
        unless ($ownerid) {
            $res->{'errmsg'} = "User \"$reqownername\" does not exist.";
            return 0;
        }
    }
    
    ## check if user has access
    $sth = $dbh->prepare("SELECT COUNT(*) AS 'count' FROM logaccess WHERE ownerid=$ownerid AND posterid=$qposterid");

    $sth->execute;
    my $row = $sth->fetchrow_hashref;
    if ($row && $row->{'count'}==1) {
	$res->{'ownerid'} = $ownerid;
	return 1;
    } else {
	$res->{'errmsg'} = "You do not have access to post to this journal.";
	return 0;
    }
}

## get the friends id
sub get_friend_itemids
{
    my $dbarg = shift;
    my $opts = shift;

    my $dbs = LJ::make_dbs_from_arg($dbarg);
    my $dbh = $dbs->{'dbh'};
    my $dbr = $dbs->{'reader'};

    my $userid = $opts->{'userid'}+0;
    my $remoteid = $opts->{'remoteid'}+0;
    my @items = ();
    my $itemshow = $opts->{'itemshow'}+0;
    my $skip = $opts->{'skip'}+0;
    my $getitems = $itemshow+$skip;
    my $owners_ref = (ref $opts->{'owners'} eq "HASH") ? $opts->{'owners'} : {};
    my $filter = $opts->{'filter'}+0;

    my $sth;

    # sanity check:
    $skip = 0 if ($skip < 0);

    ### what do your friends think of remote viewer?  what security level?
    my %usermask;
    if ($remoteid) 
    {
	$sth = $dbr->prepare("SELECT ff.userid, ff.groupmask FROM friends fu, friends ff WHERE fu.userid=$userid AND fu.friendid=ff.userid AND ff.friendid=$remoteid");
	$sth->execute;
	while (my ($friendid, $mask) = $sth->fetchrow_array) { 
	    $usermask{$friendid} = $mask; 
	}
	$sth->finish;
    }

    my $filtersql;
    if ($filter) {
	if ($remoteid == $userid) {
	    $filtersql = "AND f.groupmask & $filter";
	}
    }

    $sth = $dbr->prepare("SELECT u.userid, uu.timeupdate FROM friends f, userusage uu, user u WHERE f.userid=$userid AND f.friendid=uu.userid AND f.friendid=u.userid $filtersql AND u.statusvis='V'");
    $sth->execute;

    my @friends = ();
    while (my ($userid, $update) = $sth->fetchrow_array) {
	push @friends, [ $userid, $update ];
    }
    @friends = sort { $b->[1] cmp $a->[1] } @friends;

    my $loop = 1;
    my $queries = 0;
    my $oldest = "";
    while ($loop)
    {
	my @ids = ();
	while (scalar(@ids) < 20 && @friends) {
	    my $f = shift @friends;
	    if ($oldest && $f->[1] lt $oldest) { last; }
	    push @ids, $f->[0];
	}
	last unless (@ids);
	my $in = join(',', @ids);
	
	my $sql;
	if ($remoteid) {
	    $sql = "SELECT l.ownerid, h.itemid, l.logtime, l.security, l.allowmask FROM hintlastnview h, log l WHERE h.userid IN ($in) AND h.itemid=l.itemid";
	} else {
	    $sql = "SELECT l.ownerid, h.itemid, l.logtime FROM hintlastnview h, log l WHERE h.userid IN ($in) AND h.itemid=l.itemid AND l.security='public'";
	}
	if ($oldest) { $sql .= " AND l.logtime > '$oldest'";  }

	# this causes MySQL to do use a temporary table and do an extra pass also (use file sort).  so, we'll do it in memory here.  yay.
	# $sql .= " ORDER BY l.logtime DESC";
	
	$sth = $dbr->prepare($sql);
	$sth->execute;

	my $rows = $sth->rows;
	if ($rows == 0) { last; }

	## see comment above.  this is our "ORDER BY l.logtime DESC".  pathetic, huh?
	my @hintrows;	
	while (my ($owner, $itemid, $logtime, $sec, $allowmask) = $sth->fetchrow_array) 
	{
	    push @hintrows, [ $owner, $itemid, $logtime, $sec, $allowmask ];
	}
	$sth->finish;
	@hintrows = sort { $b->[2] cmp $a->[2] } @hintrows;
	
	my $count;
	while (@hintrows)
	{
	    my $rec = shift @hintrows;
	    my ($owner, $itemid, $logtime, $sec, $allowmask) = @{$rec};

	    if ($sec eq "private" && $owner != $remoteid) { next; }
	    if ($sec eq "usemask" && $owner != $remoteid && ! (($usermask{$owner}+0) & ($allowmask+0))) { next; }
	    push @items, [ $itemid, $logtime, $owner ];
	    $count++;
	    if ($count >= $getitems) { last; }
	}
	@items = sort { $b->[1] cmp $a->[1] } @items;
	my $size = scalar(@items);
	if ($size < $getitems) { next; }
	@items = @items[0..($getitems-1)];
	$oldest = $items[$getitems-1]->[1] if (@items);
    }

    my $size = scalar(@items);

    my @ret;
    my $max = $skip+$itemshow;
    if ($size < $max) { $max = $size; }
    foreach my $it (@items[$skip..($max-1)]) {
	push @ret, $it->[0];
	$owners_ref->{$it->[2]} = 1;
    }
    return @ret;
}

## internal function to most efficiently retrieve the last 'n' items
## for either the lastn or friends view
sub get_recent_itemids
{
    my $dbarg = shift;
    my ($opts) = shift;

    my $dbs = LJ::make_dbs_from_arg($dbarg);
    my $dbh = $dbs->{'dbh'};
    my $dbr = $dbs->{'reader'};

    my @itemids = ();
    my $userid = $opts->{'userid'}+0;
    my $view = $opts->{'view'};
    my $remid = $opts->{'remoteid'}+0;

    my $sth;

    my $max_hints = 0;
    my $sort_key = "eventtime";
    if ($view eq "lastn") { $max_hints = $LJ::MAX_HINTS_LASTN; }
    if ($view eq "friends") { 
	# THIS IS DEAD CODE!  this is never called with friends anymore.
	# TODO: Bring out your dead!! Should we put it in the wheel barrow 
	# and cart it off then?
	$max_hints = $LJ::MAX_HINTS_FRIENDS; 
	$sort_key = "logtime";
    }
    unless ($max_hints) { return @itemids; }

    my $skip = $opts->{'skip'}+0;
    my $itemshow = $opts->{'itemshow'}+0;
    if ($itemshow > $max_hints) { $itemshow = $max_hints; }
    my $maxskip = $max_hints - $itemshow;
    if ($skip < 0) { $skip = 0; }
    if ($skip > $maxskip) { $skip = $maxskip; }
    my $itemload = $itemshow+$skip;
    
    ### get all the known hints, right off the bat.

    $sth = $dbr->prepare("SELECT hintid, itemid FROM hint${view}view WHERE userid=$userid");
    $sth->execute;
    my %iteminf;
    my $numhints = 0;
    while ($_ = $sth->fetchrow_arrayref) {
	$numhints++;
	$iteminf{$_->[1]} = { 'hintid' => $_->[0] };
    }
    if ($numhints > $max_hints * 4) {
	my @extra = sort { $b->{'hintid'} <=> $a->{'hintid'} } values %iteminf;
	my $minextra = $extra[$max_hints]->{'hintid'};
	$dbh->do("DELETE FROM hint${view}view WHERE userid=$userid AND hintid<=$minextra");
	foreach my $itemid (keys %iteminf) {
	    if ($iteminf{$itemid}->{'hintid'} <= $minextra) {
		delete $iteminf{$itemid};
	    }
	}
	
    }

    if (%iteminf) 
    {
	my %gmask_from;  # group mask of remote user from context of userid in key
	my $itemid_in = join(",", keys %iteminf);

	if ($remid) {
	    if ($view eq "lastn")
	    {
		## then we need to load the group mask for this friend
		$sth = $dbh->prepare("SELECT groupmask FROM friends WHERE userid=$userid AND friendid=$remid");
		$sth->execute;
		my ($mask) = $sth->fetchrow_array;
		$gmask_from{$userid} = $mask;
	    }
	}

	$sth = $dbr->prepare("SELECT itemid, security, allowmask, $sort_key FROM log WHERE itemid IN ($itemid_in)");
	$sth->execute;
	while (my $li = $sth->fetchrow_hashref) 
	{
	    my $this_ownerid = $li->{'ownerid'} || $userid;
	    
	    if ($li->{'security'} eq "public" ||
		($li->{'security'} eq "usemask" && 
		 (($li->{'allowmask'} + 0) & $gmask_from{$this_ownerid})) ||
		($remid && $this_ownerid == $remid))
	    {
		push @itemids, { 'hintid' => $iteminf{$li->{'itemid'}}->{'hintid'},
				 'itemid' => $li->{'itemid'},
				 'ownerid' => $this_ownerid,
				 $sort_key => $li->{$sort_key}, 
			     };
	    }
	}
    }
    
    %iteminf = ();  # free some memory (like perl would care!)

    @itemids = sort { $b->{$sort_key} cmp $a->{$sort_key} } @itemids;
    
    my $hintcount = scalar(@itemids);

    if ($hintcount >= $itemload) 
    {
	# we can delete some items from the hints table.
	if ($hintcount > $max_hints) {
	    my @remove = splice (@itemids, $max_hints, ($hintcount-$max_hints));
	    $hintcount = scalar(@itemids);
	    if (@remove) {
		my $sql = "REPLACE INTO batchdelete (what, itsid) VALUES ";
		$sql .= join(",", map { "('hint${view}', $_->{'hintid'})" } @remove);
		$dbh->do($sql);

		# my $removein = join(",", map { $_->{'hintid'} } @remove);
		# $dbh->do("DELETE FROM hint${view}view WHERE hintid IN ($removein)");
	    }
	}
    } 
    elsif (! $opts->{'dont_add_hints'})
    {
	## this hints table was too small.  populate it again.

	#print "Not enough in hint table!  hintcount ($hintcount) < itemload ($itemload)\n";

	if ($view eq "lastn")
        {
	    my $sql = "
REPLACE INTO hintlastnview (hintid, userid, itemid)
SELECT NULL, $userid, l.itemid
FROM log l
WHERE l.ownerid=$userid
ORDER BY l.eventtime DESC, l.logtime DESC
LIMIT $max_hints
";

	    # FUCK IT!  This kills MySQL!  Maybe later.
	    # $dbh->do($sql);
	}

	## call ourselves recursively, now that we've populated the hints table
	## however, we set this flag so we don't recurse again.  this may be true
	## for new journals that don't yet have $max_hints entries in them

	$opts->{'dont_add_hints'} = 1;
	return get_recent_itemids($dbs, $opts);
    }

    ### remove the ones we're skipping
    if ($skip) {
	splice (@itemids, 0, $skip);
    }
    if (@itemids > $itemshow) {
	splice (@itemids, $itemshow, (scalar(@itemids)-$itemshow));
    }

    ## change the list of hashrefs to a list of integers (don't need other info now)
    if (ref $opts->{'owners'} eq "HASH") {
	grep { $opts->{'owners'}->{$_->{'ownerid'}}++ } @itemids;
    }

    @itemids = map { $_->{'itemid'} } @itemids;
    return @itemids;
}

sub load_log_props
{
    my ($dbarg, $listref, $hashref) = @_;

    my $dbs = make_dbs_from_arg($dbarg);
    my $dbh = $dbs->{'dbh'};
    my $dbr = $dbs->{'reader'};

    my $itemin = join(", ", map { $_+0; } @{$listref});
    unless ($itemin) { return ; }
    unless (ref $hashref eq "HASH") { return; }
    
    my $sth = $dbr->prepare("SELECT p.itemid, l.name, p.value FROM logprop p, logproplist l WHERE p.propid=l.propid AND p.itemid IN ($itemin)");
    $sth->execute;
    while ($_ = $sth->fetchrow_hashref) {
	$hashref->{$_->{'itemid'}}->{$_->{'name'}} = $_->{'value'};
    }
    $sth->finish;
}

sub load_talk_props
{
    my ($dbarg, $listref, $hashref) = @_;
    my $itemin = join(", ", map { $_+0; } @{$listref});
    unless ($itemin) { return ; }
    unless (ref $hashref eq "HASH") { return; }
    
    my $dbs = make_dbs_from_arg($dbarg);
    my $dbh = $dbs->{'dbh'};
    my $dbr = $dbs->{'reader'};
    
    my $sth = $dbr->prepare("SELECT tp.talkid, tpl.name, tp.value FROM talkproplist tpl, talkprop tp WHERE tp.tpropid=tpl.tpropid AND tp.talkid IN ($itemin)");
    $sth->execute;
    while (my ($id, $name, $val) = $sth->fetchrow_array) {
	$hashref->{$id}->{$name} = $val;
    }
    $sth->finish;
}

# <LJFUNC>
# name: LJ::eurl
# des: Escapes a value before it can be put in a URL.
# args: string
# des-string: string to be escaped
# returns: string escaped
# </LJFUNC>
sub eurl
{
    my $a = $_[0];
    $a =~ s/([^a-zA-Z0-9_\,\-.\/\\\: ])/uc sprintf("%%%02x",ord($1))/eg;
    $a =~ tr/ /+/;
    return $a;
}

# <LJFUNC>
# name: LJ::exml
# des: Escapes a value before it can be put in XML.
# args: string
# des-string: string to be escaped
# returns: string escaped.
# </LJFUNC>
sub exml
{
    my $a = shift;
    $a =~ s/\&/&amp;/g;
    $a =~ s/\"/&quot;/g;
    $a =~ s/\'/&apos;/g;
    $a =~ s/</&lt;/g;
    $a =~ s/>/&gt;/g;
    return $a;
}

# <LJFUNC>
# name: LJ::ehtml
# des: Escapes a value before it can be put in HTML.
# args: string
# des-string: string to be escaped
# returns: string escaped.
# </LJFUNC>
sub ehtml
{
    my $a = $_[0];
    $a =~ s/\&/&amp;/g;
    $a =~ s/\"/&quot;/g;
    $a =~ s/</&lt;/g;
    $a =~ s/>/&gt;/g;
    return $a;	
}

# <LJFUNC>
# name: LJ::days_in_month
# des: Figures out the number of days in a month.
# args: month, year
# des-month: Month
# des-year: Year
# returns: Number of days in that month in that year.
# </LJFUNC>
sub days_in_month
{
    my ($month, $year) = @_;
    if ($month == 2)
    {
        if ($year % 4 == 0)
        {
	  # years divisible by 400 are leap years
	  return 29 if ($year % 400 == 0);

	  # if they're divisible by 100, they aren't.
	  return 28 if ($year % 100 == 0);

	  # otherwise, if divisible by 4, they are.
	  return 29;
        }
    }
    return ((31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31)[$month-1]);
}

####
### delete an itemid.  if $quick is specified, that means items are being deleted en-masse
##  and the batch deleter will take care of some of the stuff, so this doesn't have to
#
sub delete_item
{
    my ($dbarg, $ownerid, $itemid, $quick) = @_;
    my $sth;
		
    my $dbs = make_dbs_from_arg($dbarg);
    my $dbh = $dbs->{'dbh'};
    my $dbr = $dbs->{'reader'};
    
    $ownerid += 0;
    $itemid += 0;

    $dbh->do("DELETE FROM hintlastnview WHERE itemid=$itemid") unless ($quick);
    $dbh->do("DELETE FROM memorable WHERE itemid=$itemid");
    $dbh->do("UPDATE userusage SET lastitemid=0 WHERE userid=$ownerid AND lastitemid=$itemid") unless ($quick);
    $dbh->do("DELETE FROM log WHERE itemid=$itemid");
    $dbh->do("DELETE FROM logtext WHERE itemid=$itemid");
    $dbh->do("DELETE FROM logsubject WHERE itemid=$itemid");
    $dbh->do("DELETE FROM logprop WHERE itemid=$itemid");
    $dbh->do("DELETE FROM logsec WHERE ownerid=$ownerid AND itemid=$itemid");

    my @talkids = ();
    $sth = $dbh->prepare("SELECT talkid FROM talk WHERE nodetype='L' AND nodeid=$itemid");
    $sth->execute;
    while (my ($tid) = $sth->fetchrow_array) {
	push @talkids, $tid;
    }
    if (@talkids) {
	my $in = join(",", @talkids);
	$dbh->do("DELETE FROM talk WHERE talkid IN ($in)");
	$dbh->do("DELETE FROM talktext WHERE talkid IN ($in)");
	$dbh->do("DELETE FROM talkprop WHERE talkid IN ($in)");
    }
}

1;
