#!/usr/bin/perl
#
# Directory search code.
#
############################################################
#
# Misc Notes...
#
# directory handle can only touch:
#   community
#   friends
#   payments
#   userinterests
#   userprop
#   userusage
#

use strict;
package LJ::Dir;
use Digest::MD5 qw(md5_hex);

my $MAX_RETURN_RESULT = 1000;

my %filters = (
            'int' => { 'searcher' => \&search_int,
                       'validate' => \&validate_int, },
            'fr' => { 'searcher' => \&search_fr,
                      'validate' => \&validate_fr, },
            'fro' => { 'searcher' => \&search_fro,
                      'validate' => \&validate_fro, },
            'loc' => { 'validate' => \&validate_loc,
                       'searcher' => \&search_loc, },
            #'gen' => { 'validate' => \&validate_gen,
            #           'searcher' => \&search_gen, },
            'age' => { 'validate' => \&validate_age,
                       'searcher' => \&search_age, },
            'ut' => { 'validate' => \&validate_ut,
                      'searcher' => \&search_ut, },
            'com' => { 'searcher' => \&search_com,
                       'validate' => \&validate_com, },
            );

# validate all filter options
#
sub validate
{
    my ($req, $errors) = @_;
    my @filters;
    foreach my $f (sort keys %filters) {
        next unless $filters{$f}->{'validate'};
        if ($filters{$f}->{'validate'}->($req, $errors)) {
            push @filters, $f;
        }
    }
    return sort @filters;
}

# entry point to do a search: give it
#    a db-read handle
#    directory master (must be able to write to dirsearchres2)
#    hashref of the request,
#    a listref of where to put the user hashrefs returned,
#    hashref of where to return results of the query
sub do_search
{
    my ($dbr, $dbdir, $req, $users, $info) = @_;
    my $sth;

    # clear return buffers
    @{$users} = ();
    %{$info} = ();

    my @crits;
    foreach my $f (sort keys %filters)
    {
        next unless $filters{$f}->{'validate'}->($req, []);

        my @criteria = $filters{$f}->{'searcher'}->($dbr, $req, $info);
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

    my $orderby;
    my %only_one_copy = qw(community c user u userusage uu);

    ## keep track of what table aliases we've used
    my %alias_used;
    $alias_used{'u'} = "?";     # only used by dbr, not dbdir
    $alias_used{'c'} = "?";     # might be used later, if opt_format eq "com"
    $alias_used{'uu'} = "?";    # might be used later, if opt_sort is by time

    my %conds;      # where condition -> 1
    my %useridcol;  # all keys here equal each other (up.userid == uu.userid == ..)

    ## foreach each critera, build up the query
    foreach my $crit (@crits)
    {
        ### each search criteria has its own table aliases.  make those unique.
        my %map_alias = ();  # keep track of local -> global table alias mapping

        foreach my $localalias (keys %{$crit->{'tables'}})
        {
            my $table = $crit->{'tables'}->{$localalias};
            my $newalias;

            # some tables might be used multiple times but they're
            # setup such that opening them multiple times is useless.
            if ($only_one_copy{$table}) {
                $newalias = $only_one_copy{$table};
                $alias_used{$newalias} = $table;
            } else {
                my $ct = 1;
                $newalias = $localalias;
                while ($alias_used{$newalias}) {
                    $ct++;
                    $newalias = "$localalias$ct";
                }
                $alias_used{$newalias} = $table;
            }

            $map_alias{$localalias} = $newalias;
        }

        ## add each condition to the where clause, after fixing up aliases
        foreach my $cond (@{$crit->{'conds'}}) {
            $cond =~ s/\{(\w+?)\}/$map_alias{$1}/g;
            $conds{$cond} = 1;
        }

        ## add join to u.userid table
        my $cond = $crit->{'userid'};
        if ($cond) {
            $cond =~ s/\{(\w+?)\}/$map_alias{$1}/g;
            $useridcol{$cond} = 1;
        }
    }

    my $pagesize = $req->{'opt_pagesize'}+0 || 100;
    if ($pagesize > 200) { $pagesize = 200; }
    if ($pagesize < 5) { $pagesize = 5; }

    $req->{'opt_format'} ||= "pics";
    if ($req->{'opt_format'} eq "com") {
        $alias_used{'c'} = "community";
        $useridcol{"c.userid"} = 1;
    }

    $req->{'opt_sort'} ||= "ut";
    if ($req->{'opt_sort'} eq "ut") {
        $alias_used{'uu'} = 'userusage';
        $useridcol{"uu.userid"} = 1;
        $orderby = "ORDER BY uu.timeupdate DESC";
    } elsif ($req->{'opt_sort'} eq "user") {
        $alias_used{'u'} = 'user';
        $useridcol{"u.userid"} = 1;
        $orderby = "ORDER BY u.user";
    } elsif ($req->{'opt_sort'} eq "name") {
        $alias_used{'u'} = 'user';
        $useridcol{"u.userid"} = 1;
        $orderby = "ORDER BY u.name";
    }

    # delete reserved table aliases the didn't end up being used
    foreach (keys %alias_used) {
        delete $alias_used{$_} if $alias_used{$_} eq "?";
    }

    # add clauses to make all userid cols equal each other
    my $useridcol;  # any one
    foreach my $ca (keys %useridcol) {
        foreach my $cb (keys %useridcol) {
            next if $ca eq $cb;
            $conds{"$ca=$cb"} = 1;
        }
        $useridcol = $ca;
    }

    my $fromwhat = join(", ", map { "$alias_used{$_} $_" } keys %alias_used);
    my $conds = join(" AND ", keys %conds);

    my $sql = "SELECT $useridcol FROM $fromwhat WHERE $conds $orderby LIMIT $MAX_RETURN_RESULT";

    if ($req->{'sql'}) {
        $info->{'errmsg'} = "SQL: $sql";
        return 0;
    }

    my $qdig = $dbr->quote(md5_hex($sql));
    my $hit_cache = 0;
    my $count = 0;
    my @ids;

    # delete any stale results
    $dbdir->do("DELETE FROM dirsearchres2 WHERE qdigest=$qdig AND ".
               "dateins < DATE_SUB(NOW(), INTERVAL 15 MINUTE)");
    # mark query as in progress.
    $dbdir->do("INSERT INTO dirsearchres2 (qdigest, dateins, userids) ".
               "VALUES ($qdig, NOW(), '[searching]')");
    if ($dbdir->err)
    {
        # if there's an error inserting that, we know something's there.
        # let's see what!
        my $ids = $dbdir->selectrow_array("SELECT userids FROM dirsearchres2 ".
                                          "WHERE qdigest=$qdig");
        if (defined $ids) {
            if ($ids eq "[searching]") {
                # somebody else (or same user before) is still searching
                $info->{'searching'} = 1;
                return 1;
            }
            @ids = split(/,/, $ids);
            $count = scalar(@ids);
            $hit_cache = 1;
        }
    }

    ## guess we'll have to query it.
    if (! $hit_cache)
    {
        BML::do_later(sub {
            $sth = $dbdir->prepare($sql);
            $sth->execute;
            while (my ($id) = $sth->fetchrow_array) {
                push @ids, $id;
            }
            my $ids = $dbdir->quote(join(",", @ids));
            $dbdir->do("REPLACE INTO dirsearchres2 (qdigest, dateins, userids) ".
                       "VALUES ($qdig, NOW(), $ids)");
        });
        $info->{'searching'} = 1;
        return 1;
    }

    my $page = $req->{'page'} || 1;
    my $skip = ($page-1)*$pagesize;
    my $pages = int($count / $pagesize) + (($count % $pagesize) ? 1 : 0);
    $pages ||= 1;
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
    @ids = grep{ $_+0 } @ids[($info->{'first'}-1)..($info->{'last'}-1)];
    return 1 unless @ids;

    my %u;
    LJ::load_userids_multiple([ map { $_ => \$u{$_} } @ids ]);
    my $tu = LJ::get_timeupdate_multi(@ids);
    my $now = time();

    # need to get community info
    if ($req->{'opt_format'} eq "com") {
        my $in = join(',', @ids);
        my $sth = $dbr->prepare("SELECT userid, membership, postlevel ".
                                "FROM community ".
                                "WHERE userid IN ($in)");
        $sth->execute;
        while (my ($uid, $mem, $postlev) = $sth->fetchrow_array) {
            next unless $u{$uid};
            $u{$uid}->{'membership'} = $mem;
            $u{$uid}->{'postlevel'} = $postlev;
        }
        foreach (@ids) {
            delete $u{$_} unless $u{$_}->{'membership'};
        }
    }

    foreach my $id (@ids) {
        next unless $u{$id} && $u{$id}->{'statusvis'} eq "V";
        $u{$id}->{'secondsold'} = $tu->{$id} ? $now - $tu->{$id} : undef;
        push @$users, $u{$id} if $u{$id};
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
    $int =~ s/^\s+//;
    $int =~ s/\s+$//;
    return 0 unless $int;

    $req->{'int_like'} = $int;
    return 1;
}

sub search_int
{
    my ($dbr, $req, $info) = @_;
    my $arg = $req->{'int_like'};
    push @{$info->{'english'}}, "are interested in \"$arg\"";

    ## find interest id, if one doth exist.
    my $qint = $dbr->quote($req->{'int_like'});
    my $intid = $dbr->selectrow_array("SELECT intid FROM interests ".
                                      "WHERE interest=$qint");
    unless ($intid) {
        $info->{'errmsg'} = "The interest you have entered is not valid.";
        return;
    }

    my $UI_TABLE = $req->{'com_do'} ? "comminterests" : "userinterests";

    return {
        'tables' => {
            'ui' => $UI_TABLE,
        },
        'conds' => [ "{ui}.intid=$intid" ],
        'userid' => "{ui}.userid",
    };
}

######## HAS FRIEND ##############

sub validate_fr
{
    my ($req, $errors) = @_;
    return 0 unless $req->{'fr_user'} =~ /\S/;
    return 1;
}

sub search_fr
{
    my ($dbr, $req, $info) = @_;

    my $user = lc($req->{'fr_user'});
    my $arg = $user;

    push @{$info->{'english'}}, "consider \"$arg\" a friend";

    my $friendid = LJ::get_userid($user);

    return {
        'tables' => {
            'f' => 'friends',
        },
        'conds' => [ "{f}.friendid=$friendid" ],
        'userid' => "{f}.userid",
    };
}


######## FRIEND OF ##############

sub validate_fro
{
    my ($req, $errors) = @_;
    return 0 unless $req->{'fro_user'} =~ /\S/;
    return 1;
}

sub search_fro
{
    my ($dbr, $req, $info) = @_;

    my $user = lc($req->{'fro_user'});
    my $arg = $user;

    push @{$info->{'english'}}, "are considered a friend by \"$arg\"";

    my $userid = LJ::get_userid($user);

    return {
        'tables' => {
            'f' => 'friends',
        },
        'conds' => [ "{f}.userid=$userid" ],
        'userid' => "{f}.friendid",
    };
}


########### LOCATION ###############

sub validate_loc
{
    my ($req, $errors) = @_;
    return 0 unless $req->{'loc_cn'} || $req->{'loc_st'} || $req->{'loc_ci'};

    if (!$req->{'loc_cn'} && ($req->{'loc_st'} || $req->{'loc_ci'})) {
        push @$errors, "You must define a country for your search.";
        return 0;
    }

    unless ($req->{'loc_cn'} =~ /^[A-Z]{2}$/ ||  # ISO code
            $req->{'loc_cn'} =~ /^LJ/)           # site-local country/region code
    {
        push @$errors, "Invalid country for location search.";
        return 0;
    }
    return 1;
}

sub search_loc
{
    my ($dbr, $req, $info) = @_;
    my ($sth);

    my ($longcountry, $longstate, $longcity);
    my $qcode = $dbr->quote(uc($req->{'loc_cn'}));
    $sth = $dbr->prepare("SELECT item FROM codes WHERE type='country' AND code=$qcode");
    $sth->execute;
    ($longcountry) = $sth->fetchrow_array;

    $longstate = lc($req->{'loc_st'});
    $longstate =~ s/(\w+)/\u$1/g;
    $longcity = lc($req->{'loc_ci'});
    $longcity =~ s/(\w+)/\u$1/g;

    $req->{'loc_st'} = lc($req->{'loc_st'});
    $req->{'loc_ci'} = lc($req->{'loc_ci'});
    
    if ($req->{'loc_cn'} eq "US") {
        my $qstate = $dbr->quote($req->{'loc_st'});
        if (length($req->{'loc_st'}) > 2) {
            ## convert long state name into state code
            $sth = $dbr->prepare("SELECT code FROM codes WHERE type='state' AND item=$qstate");
            $sth->execute;
            my ($code) = $sth->fetchrow_array;
            if ($code) {
                $req->{'loc_st'} = lc($code);
            }
        } else {
            $sth = $dbr->prepare("SELECT item FROM codes WHERE type='state' AND code=$qstate");
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
    return 0 unless $req->{'gen_sel'};
    unless ($req->{'gen_sel'} eq "M" ||
            $req->{'gen_sel'} eq "F")
    {
        push @$errors, "You must select either Male or Female when searching by gender.\n";
        return 0;
    }
    return 1;
}

sub search_gen
{
    my ($dbr, $req, $info) = @_;
    my $args = $req->{'gen_sel'};

    push @{$info->{'english'}}, "are " . ($args eq "M" ? "male" : "female");
    my $qgen = $dbr->quote($args);

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
    return 0 if $req->{'age_min'} eq "" && $req->{'age_max'} eq "";

    for (qw(age_min age_max)) {
        unless ($req->{$_} =~ /^\d+$/) {
            push @$errors, "Both min and max age must be specified for an age query.";
            return 0;
        }
    }
    if ($req->{'age_min'} > $req->{'age_max'}) {
        push @$errors, "Minimum age must be less than maximum age.";
        return 0;
    }
    if ($req->{'age_min'} < 14) {
        push @$errors, "You cannot search for users under 14 years of age.";
        return 0;
    }
    return 1;
}

sub search_age
{
    my ($dbr, $req, $info) = @_;
    my $qagemin = $dbr->quote($req->{'age_min'});
    my $qagemax = $dbr->quote($req->{'age_max'});
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
        'userid' => "{up}.userid",
    };
}

########### UPDATE TIME ###################

sub validate_ut
{
    my ($req, $errors) = @_;
    return 0 unless $req->{'ut_days'};
    unless ($req->{'ut_days'} =~ /^\d+$/) {
        push @$errors, "Days since last updated must be a postive, whole number.";
        return;
    }
    return 1;
}

sub search_ut
{
    my ($dbr, $req, $info) = @_;
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

sub validate_com
{
    my ($req, $errors) = @_;
    return 0 unless $req->{'com_do'};
    return 1;
}

sub search_com
{
    my ($dbr, $req, $info) = @_;
    $info->{'allwhat'} = "communities";

    return {
        'tables' => {
            'c' => 'community',
        },
        'userid' => "{c}.userid",
    };
}

1;
