#!/usr/bin/perl
#
# Tables hit:
#   user
#   community
#   userinterests
#   interests
#   payments
#   friends
#   logins
#   userprop
#   userproplist
#

use strict;

package LJ::Dir;
use Digest::MD5 qw(md5_hex);

my $MAX_RETURN_RESULT = 1000;

my %filters = (
	    'int' => { 'searcher' => \&search_int, 
		       'validate' => \&validate_int, },
	    'fr' => { 'searcher' => \&search_fr, },
	    'fro' => { 'searcher' => \&search_fro, },
#	    'client' => { 'searcher' => \&search_client, 
#			  'validate' => \&validate_client, 
#		      },
#	    'withpic' => { 'searcher' => \&search_withpic, },
	    'loc' => { 'validate' => \&validate_loc, 
		       'searcher' => \&search_loc, },
	    'gen' => { 'validate' => \&validate_gen,
		       'searcher' => \&search_gen, },
	    'age' => { 'validate' => \&validate_age,
		       'searcher' => \&search_age, },
	    'ut' => { 'validate' => \&validate_ut,
		      'searcher' => \&search_ut, },
	    'sup' => { 'searcher' => \&search_sup, },
	    'com' => { 'searcher' => \&search_com, },
	    );


# validate all filter options
#
sub validate
{
    my ($req, $errors) = @_;
    foreach my $f (sort keys %filters) {
	if ($req->{"s_$f"} && $filters{$f}->{'validate'}) {
	    $filters{$f}->{'validate'}->($req, $errors);
	}
    }
}

#
# entry point to do a search: give it 
#    a db-read handle
#    db-master handle, 
#    hashref of the request,
#    a listref of where to put the user hashrefs returned,
#    hashref of where to return results of the query

sub do_search
{
    my ($dbh, $dbmaster, $req, $users, $info) = @_;
    my $sth;

    # clear return buffers
    @{$users} = ();  
    %{$info} = ();  

    # load some stuff we'll need for searchers probably
    LJ::load_props($dbh, "user");

    my @crits;
    foreach my $f (sort keys %filters) 
    {
	next unless ($req->{"s_$f"} && $filters{$f}->{'searcher'});
	if ($filters{$f}->{'subrequest'}) {
	    $info->{'errmsg'} = "[Filter $f] cannot directly invoke sub-filter";
	    return 0;
	}

	my @criteria = $filters{$f}->{'searcher'}->($dbh, $req, $info);
	if (@criteria) {
	    push @crits, @criteria;
	} else {
	    # filters return nothing to signal an error, and should have set $info->{'errmsg'}
	    $info->{'errmsg'} = "[Filter $f failed] $info->{'errmsg'}";
	    return 0;
	}
    }

    unless (scalar(@crits)) {
	$info->{'errmsg'} = "You did not enter any search criteria.";
	return 0;
    }

    ########## time to build us some huge SQL statement.  yee haw.

    # what database to hit?
    my $pfx = $LJ::DIR_DB ? "$LJ::DIR_DB." : "";

    my $orderby;

    ## the ones with '2' at the end are always needed, even when cached.  the first ones are
    ## only needed when getting the data for the first time.
    my ($extrawhere, $extrawhere2);
    my ($extrafrom, $extrafrom2);

    my $distinct = "";

    ## keep track of what table aliases we've used
    my %alias_used;
    $alias_used{'u'} = 1;  # used later.
    $alias_used{'c'} = 1;  # might be used later, if opt_format eq "com"
    $alias_used{'uu'} = 1;  # might be used later, if opt_sort is by time

    ## foreach each critera, build up the query
    foreach my $crit (@crits)
    {
	### each search criteria has its own table aliases.  make those unique.
	my %map_alias = ();  # keep track of local -> global table alias mapping
	foreach my $localalias (keys %{$crit->{'tables'}}) {
	    my $ct = 1;
	    my $newalias = $localalias;
	    while ($alias_used{$newalias}) {
		$ct++;
		$newalias = "$localalias$ct";
	    }
	    $map_alias{$localalias} = $newalias;
	    $alias_used{$newalias} = 1;

	    my $tablename = $crit->{'tables'}->{$localalias};
	    $extrafrom .= ", $pfx$tablename $newalias";
	}
	
	## add each condition to the where clause, after fixing up aliases
	foreach my $cond (@{$crit->{'conds'}}) {
	    $cond =~ s/\{(\w+?)\}/$map_alias{$1}/g;
	    $extrawhere .= "AND $cond ";
	}

	## add join to u.userid table
	my $cond = $crit->{'userid'};
	if ($cond) {
	    $cond =~ s/\{(\w+?)\}/$map_alias{$1}/g;
	    $extrawhere .= "AND $cond=u.userid ";
	}

	## does this crit require a distinct select?
	if ($crit->{'distinct'}) {
	    $distinct = "DISTINCT";
	}
    }

    my $pagesize = $req->{'opt_pagesize'}+0 || 100;
    if ($pagesize > 200) { $pagesize = 200; }
    if ($pagesize < 5) { $pagesize = 5; }
    my $fields;

    $req->{'opt_format'} ||= "pics";
    if ($req->{'opt_format'} eq "pics") {
	$fields .= ", u.defaultpicid";
    } elsif ($req->{'opt_format'} eq "simple") {
	$fields .= ", u.name";
    } elsif ($req->{'opt_format'} eq "com") {
	$fields .= ", u.name, c.ownerid, c.membership, c.postlevel";
	$extrafrom2 .= ", ${pfx}community c";
	$extrawhere2 .= "AND c.userid=u.userid";
    }

    $req->{'opt_sort'} ||= "ut";
    if ($req->{'opt_sort'} eq "ut") {
	$extrafrom2 .= ", userusage uu";  # FIX: don't open two copies of table when already using
	$orderby = "ORDER BY uu.timeupdate DESC";
    } elsif ($req->{'opt_sort'} eq "user") {
	$orderby = "ORDER BY u.user";
    } elsif ($req->{'opt_sort'} eq "name") {
	$orderby = "ORDER BY u.name";
    } elsif ($req->{'opt_sort'} eq "loc") {
#	$orderby = "ORDER BY country, state, city";
#	$extrawhere = "AND country <> '' AND country IS NOT NULL";
#	$fields .= ", u.country, u.state, u.city";
    }

    my $all_fields = "u.userid, u.user, u.journaltype, UNIX_TIMESTAMP()-UNIX_TIMESTAMP(u.timeupdate) AS 'secondsold' $fields";
    my $sql = "SELECT $distinct u.userid FROM ${pfx}user u $extrafrom $extrafrom2 WHERE 1 $extrawhere $extrawhere2 $orderby LIMIT $MAX_RETURN_RESULT";

    if ($req->{'sql'}) {
	$info->{'errmsg'} = "SQL: $sql";
	return 0;
    }

    my $qdig = $dbh->quote(md5_hex($sql));
    my $hit_cache = 0;
    my $count = 0;
    my @ids;
    
    ## let's see if it's cached.
    {
	my $csql = "SELECT userids FROM ${pfx}dirsearchres2 WHERE qdigest=$qdig AND dateins > DATE_SUB(NOW(), INTERVAL 15 MINUTE)";
	my $sth = $dbmaster->prepare($csql);
	$sth->execute;
	if ($dbh->err) {  $info->{'errmsg'} = $dbh->errstr; return 0; }

	my ($ids) = $sth->fetchrow_array;
	if (defined $ids) {
	    @ids = split(/,/, $ids);
	    $count = scalar(@ids);
	    $hit_cache = 1;
	}
    }

    my $page = $req->{'page'} || 1;
    my $skip = ($page-1)*$pagesize;

    ## guess we'll have to query it.
    if (! $hit_cache)
    {
	$sth = $dbh->prepare($sql);
	$sth->execute;
	if ($dbh->err) { $info->{'errmsg'} = $dbh->errstr . "<p>SQL: $sql"; return 0; }

	while (my ($id) = $sth->fetchrow_array) {
	    push @ids, $id;
	}

	# insert it into the cache
	my $ids = $dbh->quote(join(",", @ids));
	$dbmaster->do("REPLACE INTO ${pfx}dirsearchres2 (qdigest, dateins, userids) VALUES ($qdig, NOW(), $ids)");
	$count = scalar(@ids);
    }

    my $pages = int($count / $pagesize) + (($count % $pagesize) ? 1 : 0);
    if ($page > $pages) { $page = $pages; }
    $info->{'pages'} = $pages;
    $info->{'page'} = $page;
    $info->{'first'} = ($page-1)*$pagesize+1;
    $info->{'last'} = $page * $pagesize;
    $info->{'count'} = $count;
    if ($count == $MAX_RETURN_RESULT) {
	$info->{'overflow'} = 1;
    }
    if ($page == $pages) { $info->{'last'} = $count; }

    ## now, get info on the ones we want.
    @ids = @ids[($info->{'first'}-1)..($info->{'last'}-1)];
   
    my $in = join(",", grep { $_+0; } @ids);
    my $fsql = "SELECT $all_fields FROM ${pfx}user u $extrafrom2 WHERE u.userid IN ($in) $extrawhere2";
    $sth = $dbh->prepare($fsql);
    $sth->execute;

    my %u;    
    while ($_ = $sth->fetchrow_hashref) {
	$u{$_->{'userid'}} = $_;
    }

    foreach my $id (@ids) {
	push @$users, $u{$id};
    }

    return 1;
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

########## INTEREST ############

sub validate_int
{
    my ($req, $errors) = @_;

    my $int = lc($req->{'int_like'});
    $int =~ s/^[^\w\s]+//;
    $int =~ s/[^\w\s]+$//;
    unless ($int) {
	push @$errors, "Blank or invalid interest.";
    }
    if ($int =~ / .+ .+ .+ /) {
	push @$errors, "Interest shouldn't be a whole sentence.";
    }
    if (length($int) > 35) {
	push @$errors, "Interest is too long.";
    }
    
    $req->{'int_like'} = $int;
}

sub search_int
{
    my ($dbh, $req, $info) = @_;
    my $arg = $req->{'int_like'};
    push @{$info->{'english'}}, "are interested in \"$arg\"";

    ## find interest id, if one doth exist.
    my $qint = $dbh->quote($req->{'int_like'});

    return {
	'tables' => {
	    'ui' => 'userinterests', 
	    'i' => 'interests',
	}, 
	'conds' => [ "{ui}.intid={i}.intid",
		     "{i}.interest=$qint",
		     ],
	'userid' => "{ui}.userid",
    };
   
}

######## HAVE A PICTURE? ##############3

### NO INDEX!
sub search_withpic
{
    my ($dbh, $req, $info) = @_;

    push @{$info->{'english'}}, "have pictures uploaded";

    return {
	'conds' => [ "u.defaultpicid <> 0", ],
    };
}

####### SUPPORTER?

sub search_sup
{
    my ($dbh, $req, $info) = @_;

    push @{$info->{'english'}}, "have supported $LJ::SITENAME by purchasing paid accounts";

    return {
	'tables' => {
	    'p' => 'payments', 
	}, 
	'conds' => [  ],
	'userid' => "{p}.userid",
    };

}

######## HAS FRIEND ##############

sub search_fr
{
    my ($dbh, $req, $info) = @_;

    my $user = lc($req->{'fr_user'});
    my $quser = $dbh->quote($user);
    my $arg = $user;

    push @{$info->{'english'}}, "consider \"$arg\" a friend";

    my $friendid = &LJ::get_userid($dbh, $user);
    
    return {
	'tables' => {
	    'f' => 'friends',
	},
	'conds' => [ "{f}.friendid=$friendid" ],
	'userid' => "{f}.userid",
    };
}


######## FRIEND OF ##############

sub search_fro
{
    my ($dbh, $req, $info) = @_;

    my $user = lc($req->{'fro_user'});
    my $quser = $dbh->quote($user);
    my $arg = $user;

    push @{$info->{'english'}}, "are considered a friend by \"$arg\"";

    my $userid = &LJ::get_userid($dbh, $user);

    return {
	'tables' => {
	    'f' => 'friends',
	},
	'conds' => [ "{f}.userid=$userid" ],
	'userid' => "{f}.friendid",
    };
}

######## CLIENT USAGE ##############

sub validate_client
{
    my ($req, $errors) = @_;
    unless (length($req->{'client_match'})) {
	push @$errors, "You must enter at least a substring of the client name to search for.";
    }
}

sub search_client
{
    my ($dbh, $req, $info) = @_;

    my $client = lc($req->{'client_match'});
    my $arg = $client;
    my $qlike = $dbh->quote("$client%");

    push @{$info->{'english'}}, "have used the \"$arg\" LiveJournal client";

    return {
	'distinct' => 1,
	'tables' => {
	    'l' => 'logins',
	    'u' => 'user',
	},
	'conds' => [ "{u}.user={l}.user",
		     "{l}.client LIKE $qlike" ],
	'userid' => "{u}.userid",
    };
}


########### LOCATION ###############

sub validate_loc
{
    my ($req, $errors) = @_;
    
    unless ($req->{'loc_cn'} =~ /^[A-Z]{2}$/) {
	push @$errors, "Invalid country for location search.";
	return;
    }
    
}

sub search_loc
{
    my ($dbh, $req, $info) = @_;
    my ($sth);

    my ($longcountry, $longstate, $longcity);
    my $qcode = $dbh->quote(uc($req->{'loc_cn'}));
    $sth = $dbh->prepare("SELECT item FROM codes WHERE type='country' AND code=$qcode");
    $sth->execute;
    ($longcountry) = $sth->fetchrow_array;

    $longstate = lc($req->{'loc_st'});
    $longstate =~ s/(\w+)/\u$1/g;
    $longcity = lc($req->{'loc_ci'});
    $longcity =~ s/(\w+)/\u$1/g;

    $req->{'loc_st'} = lc($req->{'loc_st'});
    $req->{'loc_ci'} = lc($req->{'loc_ci'});
    
    if ($req->{'loc_cn'} eq "US") {
	my $qstate = $dbh->quote($req->{'loc_st'});
	if (length($req->{'loc_st'}) > 2) {
	    ## convert long state name into state code
	    $sth = $dbh->prepare("SELECT code FROM codes WHERE type='state' AND item=$qstate");
	    $sth->execute;
	    my ($code) = $sth->fetchrow_array;
	    if ($code) {
		$req->{'loc_st'} = lc($code);
	    }
	} else {
	    $sth = $dbh->prepare("SELECT item FROM codes WHERE type='state' AND code=$qstate");
	    $sth->execute;
	    ($longstate) = $sth->fetchrow_array;
	}
    }

    push @{$info->{'english'}}, "live in " . join(", ", grep { $_; } ($longcity, $longstate, $longcountry));

    my $p = LJ::get_prop("user", "sidx_loc");
    unless ($p) {
	$info->{'errmsg'} = "Userprop sidx_loc doesn't exist. Run update-db.pl?";
	return;
    }

    my $prefix = join("-", $req->{'loc_cn'}, $req->{'loc_st'}, $req->{'loc_ci'});
    $prefix =~ s/\-+$//;  # remove trailing hyphens
    $prefix =~ s![\_\%\"\']!\\$&!g;
								  
    #### do the sub requests.

    return {
	'tables' => {
	    'up' => 'userprop', 
	}, 
	'conds' => [ "{up}.upropid=$p->{'id'}",
		     "{up}.value LIKE '$prefix%'",
		     ],
	'userid' => "{up}.userid",
    };

}

########### GENDER ###################

sub validate_gen
{
    my ($req, $errors) = @_;
    unless ($req->{'gen_sel'} eq "M" ||
	    $req->{'gen_sel'} eq "F")
    {
	push @$errors, "You must select either Male or Female when searching by gender.\n";
    }
}

sub search_gen
{
    my ($dbh, $req, $info) = @_;
    my $args = $req->{'gen_sel'};

    push @{$info->{'english'}}, "are " . ($args eq "M" ? "male" : "female");
    my $qgen = $dbh->quote($args);

    my $p = LJ::get_prop("user", "gender");
    unless ($p) {
	$info->{'errmsg'} = "Userprop gender doesn't exist. Run update-db.pl?";
	return;
    }

    return {
	'tables' => {
	    'up' => 'userprop', 
	}, 
	'conds' => [ "{up}.upropid=$p->{'id'}",
		     "{up}.value=$qgen",
		     ],
	'userid' => "{up}.userid",
    };
}

########### AGE ###################

sub validate_age
{
    my ($req, $errors) = @_;
    for (qw(age_min age_max)) {
	unless ($req->{$_} =~ /^\d+$/) {
	    push @$errors, "Both min and max age must be specified for an age query.";
	    return;	
	}
    }
    if ($req->{'age_min'} > $req->{'age_max'}) {
	push @$errors, "Minimum age must be less than maximum age.";
	return;	
    }
    if ($req->{'age_min'} < 14) {
	push @$errors, "You cannot search for users under 14 years of age.";
	return;
    }
}

sub search_age
{
    my ($dbh, $req, $info) = @_;
    my $qagemin = $dbh->quote($req->{'age_min'});
    my $qagemax = $dbh->quote($req->{'age_max'});
    my $args = "$req->{'age_min'}-$req->{'age_max'}";

    if ($req->{'age_min'} == $req->{'age_max'}) {
	push @{$info->{'english'}}, "are $req->{'age_min'} years old";
    } else {
	push @{$info->{'english'}}, "are between $req->{'age_min'} and $req->{'age_max'} years old";
    }
    
    my $p = LJ::get_prop("user", "sidx_bdate");
    unless ($p) {
	$info->{'errmsg'} = "Userprop sidx_bdate doesn't exist. Run update-db.pl?";
	return;
    }
    
    return {
	'tables' => {
	    'up' => 'userprop', 
	}, 
	'conds' => [ "{up}.upropid=$p->{'id'}",
		     "{up}.value BETWEEN DATE_SUB(NOW(), INTERVAL $qagemax YEAR) AND DATE_SUB(NOW(), INTERVAL $qagemin YEAR)",
		     ],
	'userid' => "{u}.userid",
    };
}

########### UPDATE TIME ###################

sub validate_ut
{
    my ($req, $errors) = @_;
    for (qw(ut_days)) {
	unless ($req->{$_} =~ /^\d+$/) {
	    push @$errors, "Days since last updated must be a postive, whole number.";
	    return;	
	}
    }
}

sub search_ut
{
    my ($dbh, $req, $info) = @_;
    my $qdays = $req->{'ut_days'}+0;

    if ($qdays == 1) {
	push @{$info->{'english'}}, "have updated their journal in the past day";
    } else {
	push @{$info->{'english'}}, "have updated their journal in the past $qdays days";
    }

    return {
	'tables' => {
	    'uu' => 'userusage',
	},
	'conds' => [ "{uu}.timeupdate > DATE_SUB(NOW(), INTERVAL $qdays DAY)", ],
	'userid' => "{uu}.userid",
    };
}

######### community

sub search_com
{
    my ($dbh, $req, $info) = @_;

    $info->{'allwhat'} = "communities";

    return {
	'tables' => {
	    'c' => 'community',
	},
	'userid' => "{c}.userid",
    };
}

1;
