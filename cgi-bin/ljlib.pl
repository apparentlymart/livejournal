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
	&LJ::clear_caches;
    };
} else {
    $SIG{'HUP'} = \&LJ::clear_caches;    
}

sub send_mail
{
    my $opt = shift;
    &LJ::send_mail($opt);
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
sub get_remote { &connect_db(); return LJ::get_remote($dbh, @_); }
sub get_remote_noauth { return LJ::get_remote_noauth(); }
sub remote_has_priv { return &LJ::remote_has_priv($dbh, @_); }

sub register_authaction
{
    &connect_db();
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
    my $remote = &get_remote_noauth();
    my $ret = "";
    if (!$FORM{'altlogin'} && !$opts->{'user'} && $remote->{'user'}) {
	my $hpass;
	if ($BMLClient::COOKIE{"ljhpass"} =~ /^$remote->{'user'}:(.+)/) {
	    $hpass = $1;
	}
	my $alturl = $ENV{'REQUEST_URI'};
	$alturl .= ($alturl =~ /\?/) ? "&" : "?";
	$alturl .= "altlogin=1";

	$ret .= "<TR><TD COLSPAN=2>You are currently logged in as <B>$remote->{'user'}</B>.<BR>If this is not you, <A HREF=\"$alturl\">click here</A>.\n";
	$ret .= "<INPUT TYPE=HIDDEN NAME=user VALUE=\"$remote->{'user'}\">\n";
	$ret .= "<INPUT TYPE=HIDDEN NAME=hpassword VALUE=\"$hpass\"><BR>&nbsp;\n";
	$ret .= "</TD></TR>\n";
    } else {
	$ret .= "<TR><TD>Username:</TD><TD><INPUT TYPE=TEXT NAME=user SIZE=15 MAXLENGTH=15 VALUE=\"";
	my $user = $opts->{'user'};
	unless ($user || $ENV{'QUERY_STRING'} =~ /=/) { $user=$ENV{'QUERY_STRING'}; }
	$ret .= &BMLUtil::escapeall($user) unless ($FORM{'altlogin'});
	$ret .= "\"></TD></TR>\n";
	$ret .= "<TR><TD>Password:</TD><TD>\n";
	$ret .= "<INPUT TYPE=password NAME=password SIZE=15 MAXLENGTH=30 VALUE=\"" . &ehtml($opts->{'password'}) . "\">";
	$ret .= "</TD></TR>\n";
    }
    return $ret;
}


sub valid_password { return &LJ::valid_password(@_); }
sub hash_password { return md5_hex($_[0]); }


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

# deprecated.  use LJ::load_user_props
sub load_user_props
{
    &connect_db();
    LJ::load_user_props($dbh, @_);
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


sub load_moods
{
    return if ($LJ::CACHED_MOODS);
    &connect_db();
    my $sth = $dbh->prepare("SELECT moodid, mood, parentmood FROM moods");
    $sth->execute;
    while (my ($id, $mood, $parent) = $sth->fetchrow_array) {
	$LJ::CACHE_MOODS{$id} = { 'name' => $mood, 'parent' => $parent };
	if ($id > $LJ::CACHED_MOOD_MAX) { $LJ::CACHED_MOOD_MAX = $id; }
    }
    $LJ::CACHED_MOODS = 1;
}

sub load_mood_theme
{
    my $themeid = shift;
    return if ($LJ::CACHE_MOOD_THEME{$themeid});

    &connect_db();
    $themeid += 0;
    my $sth = $dbh->prepare("SELECT moodid, picurl, width, height FROM moodthemedata WHERE moodthemeid=$themeid");
    $sth->execute;
    while (my ($id, $pic, $w, $h) = $sth->fetchrow_array) {
	$LJ::CACHE_MOOD_THEME{$themeid}->{$id} = { 'pic' => $pic, 'w' => $w, 'h' => $h };
    }
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


sub server_down_html
{
    return LJ::server_down_html();
}

sub make_journal
{
    connect_db();
    return LJ::make_journal($dbh, @_);
}

## DEPRECATED:
sub load_codes {  &connect_db(); LJ::load_codes($dbh, @_); }
sub get_userid { return &LJ::get_userid($dbh, @_); }
sub get_username { return &LJ::get_username($dbh, @_); }
sub load_userpics { return &LJ::load_userpics($dbh, @_); }

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

# XXX DEPRECATED
sub strip_bad_code
{
    return &LJ::strip_bad_code(@_);
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


#### UTILITY 

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

sub can_use_journal {
    &connect_db();
    return &LJ::can_use_journal($dbh, @_);
}
sub get_recent_itemids {
    &connect_db();
    return &LJ::get_recent_itemids($dbh, @_);
}
sub load_log_props {
    &connect_db();
    return &LJ::load_log_props($dbh, @_);
}
sub days_in_month {
    return &LJ::days_in_month(@_);
}

sub html_select
{
    return LJ::html_select(@_);
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
    $ret .= &html_select({ 'name' => "${name}_mm", 'selected' => $mm, 'disabled' => $opts->{'disabled'} },
			 map { $_, &LJ::Lang::month_long($lang, $_) } (0..12));
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

# this is here only for upwards compatability.  the good function to use is
# LJ::get_dbh, which this function now calls.
sub connect_db
{
    $dbh = ($BMLPersist::dbh = LJ::get_dbh("master"));
}

sub parse_vars
{
    return &LJ::parse_vars(@_);
}

sub load_user_theme
{
    &connect_db();
    return &LJ::load_user_theme(@_);
}

sub make_text_link { return LJ::make_text_link(@_); }
sub get_friend_itemids { return LJ::get_friend_itemids($dbh, @_); }

package LJ;

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

sub get_limit
{
    my $lname = shift;
    my $accttype = shift;
    my $default = shift;
    
    foreach my $k ($accttype, "") {
	if (defined $LJ::LIMIT{$lname}->{$k}) {
	    return $LJ::LIMIT{$lname}->{$k};
	}
    }
    return $default;
}

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

sub debug 
{
    return 1 unless ($LJ::DEBUG);
    open (L, ">>$LJ::VAR/debug.log") or return 0;
    print L scalar(time), ": $_[0]\n";
    close L;
    return 1;
}

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

# the caller is responsible for making sure the username isn't reserved.  this
# function only ensures that it's a valid username.
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
    return $userid;
}

# returns true if user B is a friend of user A (or if A == B)
sub is_friend
{
    my $dbarg = shift;
    my $ua = shift;
    my $ub = shift;
    
    my $dbs = make_dbs_from_arg($dbarg);
    my $dbh = $dbs->{'dbh'};
    my $dbr = $dbs->{'reader'};
		
    return 0 unless ($ua->{'userid'});
    return 0 unless ($ub->{'userid'});
    return 1 if ($ua->{'userid'} == $ub->{'userid'});

    my $sth = $dbr->prepare("SELECT COUNT(*) FROM friends WHERE userid=$ua->{'userid'} AND friendid=$ub->{'userid'}");
    $sth->execute;
    my ($is_friend) = $sth->fetchrow_array;
    $sth->finish;
    return $is_friend;
}

# args: ($dbs, @talkids)
# return: hashref with keys being talkids, values being [ $subject, $body ]
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

# args: ($dbs, @itemids)
# return: hashref with keys being itemids, values being [ $subject, $text ]
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

sub make_auth_code
{
    my $length = shift;
    my $vchars = "abcdefghijklmnopqrstuvwxyz0123456789";
    srand();
    my $authcode = "";
    for (1..$length) {
	$authcode .= substr($vchars, int(rand()*36), 1);
    }
    return $authcode;
}

## for stupid AOL mail client, wraps a plain-text URL in an anchor tag since AOL
## incorrectly renders regular text as HTML.  fucking AOL.  die.
sub make_text_link
{
    my ($url, $email) = @_;
    if ($email =~ /\@aol\.com$/i) {
	return "<A HREF=\"$url\">$url</A>";
    }
    return $url;
}

## authenticates the user at the remote end and returns a hashref containing:
##    user, userid
## or returns undef if no logged-in remote or errors.
## optional argument is arrayref to push errors
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

# this is like get_remote, but it only returns who they say they are,
# not who they really are.  so if they're faking out their cookies,
# they'll fake this out.  but this is fast.
#
sub get_remote_noauth
{
    ### are they logged in?
    my $remuser = $BMLClient::COOKIE{"ljuser"};
    return undef unless ($remuser =~ /^\w{1,15}$/);

    ### does their login password match their login?
    return undef unless ($BMLClient::COOKIE{"ljhpass"} =~ /^$remuser:(.+)/);
    return { 'user' => $remuser, };
}


sub did_post
{
    return ($ENV{'REQUEST_METHOD'} eq "POST");
}

# called from a HUP signal handler, so intentionally very very simple
# so we don't core dump on a system without reentrant libraries.
sub clear_caches
{
    $LJ::CLEAR_CACHES = 1;
}

# handle_caches
# clears caches, if the CLEAR_CACHES flag is set from an earlier HUP signal.
# always returns trues, so you can use it in a conjunction of statements
# in a while loop around the application like:
#        while (LJ::handle_caches() && FCGI::accept())
sub handle_caches
{
    return 1 unless ($LJ::CLEAR_CACHES);
    $LJ::CLEAR_CACHES = 0;

    %LJ::CACHE_STYLE = ();
    %LJ::CACHE_PROPS = ();
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

### hashref, arrayref
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

#sub strip_bad_code
#{
#    my $data = shift;
#    require "$ENV{'LJHOME'}/cgi-bin/cleanhtml.pl";
#    &LJ::CleanHTML::clean($data, {
#	'mode' => 'allow',
#	'keepcomments' => 1,
#    });
#}

# FIXME: this belongs in a site-specific config file
%LJ::acct_name = ("paid" => "Paid Account",
		  "off" => "Free Account",
		  "early" => "Early Adopter",
		  "on" => "Permanent Account");

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
    return "<B>$LJ::SERVER_DOWN_SUBJECT</B><BR>$LJ::SERVER_DOWN_MESSAGE";
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
	return &server_down_html();
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

    if ($LJ::USER_VHOSTS && $opts->{'vhost'} eq "users" && $u->{'paidfeatures'} eq "off")
    {
	return "<B>Notice</B><BR>Addresses like <TT>http://<I>username</I>.$LJ::USER_DOMAIN</TT> only work for users with <A HREF=\"$LJ::SITEROOT/paidaccounts/\">paid accounts</A>.  The journal you're trying to view is available here:<UL><FONT FACE=\"Verdana,Arial\"><B><A HREF=\"$LJ::SITEROOT/users/$user/\">$LJ::SITEROOT/users/$user/</A></B></FONT></UL>";
    }
    if ($opts->{'vhost'} eq "customview" && $u->{'paidfeatures'} eq "off")
    {
	return "<B>Notice</B><BR>Only users with <A HREF=\"$LJ::SITEROOT/paidaccounts/\">paid accounts</A> can create and embed styles.";
    }
    if ($opts->{'vhost'} eq "community" && $u->{'journaltype'} ne "C") {
	return "<B>Notice</B><BR>This account isn't a community journal.";
    }

    return "<H1>Error</H1>Journal has been deleted.  If you are <B>$user</B>, you have a period of 30 days to decide to undelete your journal." if ($u->{'statusvis'} eq "D");
    return "<H1>Error</H1>This journal has been suspended." if ($u->{'statusvis'} eq "S");

    my %vars = ();
    # load the base style
    my $basevars = "";
    &load_style_fast($dbh, $styleid, \$basevars, \$view);

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
    &load_user_theme($dbh, $user, $u, \%vars);
    
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
	$ret .= "<input type=radio ";
    } else {
	$ret .= "<input type=checkbox ";
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
    $ret .= "<input type=text";
    if ($opts->{'size'}) { $ret .= " size=\"$opts->{'size'}\""; }
    if ($opts->{'maxlength'}) { $ret .= " maxlength=\"$opts->{'maxlength'}\""; }
    if ($opts->{'name'}) { $ret .= " name=\"" . &ehtml($opts->{'name'}) . "\""; }
    if ($opts->{'value'}) { $ret .= " value=\"" . &ehtml($opts->{'value'}) . "\""; }
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

# takes nothing, returns db set (dbset = master and perhaps a slave)
# gets master and slave by connecting.
sub get_dbs
{
    my $dbh = LJ::get_dbh("master");
    my $dbr = LJ::get_dbh("slave!");
    return make_dbs($dbh, $dbr);
}

# take a master handle and optionally a slave handle and turns it
# into a dbs
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
    $ret .= "<a href=\"$LJ::SITEROOT/view/?type=month&user=$user&y=$y&m=$nm\">$m</a>-";
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
    &LJ::Poll::show_polls($dbh, $itemid, $remote, $eventref);
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

sub populate_web_menu {
    my ($res, $menu, $numref) = @_;
    my $mn = $$numref;  # menu number
    my $mi = 0;         # menu item
    foreach my $it (@$menu) {
	$mi++;
	$res->{"menu_${mn}_${mi}_text"} = $it->{'text'};
	if ($it->{'text'} eq "-") { next; }
	if ($it->{'sub'}) { 
	    $$numref++; 
	    $res->{"menu_${mn}_${mi}_sub"} = $$numref;
	    &populate_web_menu($res, $it->{'sub'}, $numref); 
	    next;
	    
	}
	$res->{"menu_${mn}_${mi}_url"} = $it->{'url'};
    }
    $res->{"menu_${mn}_count"} = $mi;
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
