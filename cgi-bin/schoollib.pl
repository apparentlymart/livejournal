#!/usr/bin/perl

package LJ::Schools;

use strict;

# <LJFUNC>
# name: LJ::Schools:get_attended
# class: schools
# des: Gets a list of schools a user has attended.
# args: uobj
# des-uobj: User id or object of user to get schools attended.
# returns: Hashref; schoolid as key, value is hashref containing basic information
#          about the record: year_start, year_end.  Also: keys from get_school/get_school_multi.
# </LJFUNC>
sub get_attended {
    my $u = LJ::want_user(shift);
    return undef unless $u;

    # now load what schools they've been to from memcache
    # FIXME: memcache

    my $dbcr = LJ::get_cluster_reader($u);
    return undef unless $dbcr;

    my $rows = $dbcr->selectall_arrayref(qq{
            SELECT schoolid, year_start, year_end
            FROM user_schools
            WHERE userid = ?
        }, undef, $u->{userid});
    return undef if $dbcr->err || ! $rows;

    my $res = {};
    foreach my $row (@$rows) {
        $res->{$row->[0]} = {
            year_start => $row->[1],
            year_end => $row->[2],
        };
    }

    my @sids = keys %$res;
    my $schools = LJ::Schools::load_schools(@sids);
    foreach my $sid (@sids) {
        next unless $res->{$sid} && $schools->{$sid};

        $schools->{$sid}->{year_start} = $res->{$sid}->{year_start};
        $schools->{$sid}->{year_end} = $res->{$sid}->{year_end};
    }

    return $schools;
}

# <LJFUNC>
# name: LJ::Schools::load_schools
# class: schools
# des: Returns detailed information about schools.
# args: schoolids
# des-schoolids: List of school ids to return.
# returns: Hashref; key being schoolid, value being a hashref with keys name, url,
#          citycode, countrycode, statecode.
# </LJFUNC>
sub load_schools {
    my @ids = grep { defined $_ && $_ > 0 } @_;
    return {} unless @ids;

    # FIXME: memcache

    my $in = join(',', @ids);
    my $dbr = LJ::get_db_reader();
    return undef unless $dbr;
    my $rows = $dbr->selectall_arrayref(qq{
            SELECT schoolid, name, country, state, city, url
            FROM schools
            WHERE schoolid IN ($in)
        });
    return undef if $dbr->err || ! $rows;

    my $res;
    foreach my $row (@$rows) {
        $res->{$row->[0]} = {
            name => $row->[1],
            country => $row->[2],
            state => $row->[3],
            city => $row->[4],
            url => $row->[6],
        };
    }

    return $res;
}

# <LJFUNC>
# name: LJ::Schools:get_attendees
# class: schools
# des: Gets a list of users that attended a school.
# args: schoolid, year?
# des-schoolid: School id to get attendees for.
# des-year?: Optional; if provided, returns people that attended in this year.
# returns: List of userids that attended.
# </LJFUNC>
sub get_attendees {
    my $sid = shift() + 0;
    my $year = shift() + 0;
    return undef unless $sid;

    # see if it's in memcache first
    my $mkey = $year ? "saaly:$sid:$year" : "saal:$sid";
    my $list = LJ::MemCache::get([ $sid, $mkey ]);
    return @$list if $list;

    # hit database for info
    my $dbr = LJ::get_db_reader();
    return undef unless $dbr;

    # query changes based on what we're doing
    my $ids;
    if ($year) {
        # this works even if they're null! (the condition just returns null which evaluates
        # to false which means don't return the row)
        $ids = $dbr->selectcol_arrayref(qq{
                SELECT userid
                FROM schools_attended
                WHERE schoolid = ?
                  AND ? BETWEEN year_start AND year_end
                LIMIT 1000
            }, undef, $sid, $year);
    } else {
        $ids = $dbr->selectcol_arrayref('SELECT userid FROM schools_attended WHERE schoolid = ? LIMIT 1000',
                                        undef, $sid);
    }
    return undef if $dbr->err || ! $ids;

    # set and return
    LJ::MemCache::set([ $sid, $mkey ], $ids, 300);
    return @$ids;
}

# <LJFUNC>
# name: LJ::Schools::get_countries
# class: schools
# des: Get a list of countries that we have schools in.
# returns: Hashref; countrycode as key, countryname as the values.
# </LJFUNC>
sub get_countries {
    # see if we can get it from memcache
    my $data = LJ::MemCache::get('saccs');
    return $data if $data;

    # if not, pull from db
    my $dbh = LJ::get_db_writer();
    return undef unless $dbh;
    my $rows = $dbh->selectcol_arrayref('SELECT DISTINCT country FROM schools');
    return undef if $dbh->err || ! $rows;

    # now we want to dig out the country codes
    my %countries;
    LJ::load_codes({ country => \%countries });

    # and now combine them
    my $res = {};
    foreach my $cc (@$rows) {
        $res->{$cc} = $countries{$cc} || $cc;
    }

    # set to memcache and return
    LJ::MemCache::set('saccs', $res);
    return $res;
}

# <LJFUNC>
# name: LJ::Schools::get_states
# class: schools
# des: Gets information about what states have been populated with schools.  States
#      and provinces are considered the same thing.
# args: countrycode
# des-countrycode: The country code provided from LJ::Schools::get_countries.
# returns: Hashref; statecode as key, statename as the values.
# </LJFUNC>
sub get_states {
    my $ctc = shift;
    return undef unless $ctc;

    # see if we can get it from memcache
    my $data = LJ::MemCache::get("sascs:$ctc");
    return $data if $data;

    # if not, pull from db
    my $dbh = LJ::get_db_writer();
    return undef unless $dbh;
    my $rows = $dbh->selectcol_arrayref('SELECT DISTINCT state FROM schools WHERE country = ?',
                                        undef, $ctc);
    return undef if $dbh->err || ! $rows;

    # now we want to dig out the states, if this is the US
    my %states;
    if ($ctc eq 'US') {
        LJ::load_codes({ state => \%states });
    }

    # and now combine them
    my $res = {};
    foreach my $cc (@$rows) {
        $res->{$cc} = $states{$cc} || $cc;
    }

    # set to memcache and return
    LJ::MemCache::set("sascs:$ctc", $res);
    return $res;
}

# <LJFUNC>
# name: LJ::Schools::get_cities
# class: schools
# des: Gets information about what cities have been populated with schools.
# args: countrycode, statecode
# des-countrycode: The country code provided from LJ::Schools::get_countries.
# des-statecode: The state code provided from LJ::Schools::get_states.
# returns: Hashref; citycode as key, cityname as the values.
# </LJFUNC>
sub get_cities {
    my ($ctc, $sc) = @_;
    return undef unless $ctc && defined $sc;

    # FIXME: memcache
    # just dredge it up from the database (READER)
    my $dbr = LJ::get_db_reader();
    return undef unless $dbr;
    my $rows;
    if ($sc) {
        $rows = $dbr->selectcol_arrayref
            ('SELECT DISTINCT city FROM schools WHERE country = ? AND state = ?',
             undef, $ctc, $sc);
    } else {
        $rows = $dbr->selectcol_arrayref
            ('SELECT DISTINCT city FROM schools WHERE country = ? AND state IS NULL',
             undef, $ctc);
    }
    return undef if $dbr->err || ! $rows;

    # and now combine them
    my $res = {};
    foreach my $cc (@$rows) {
        $res->{$cc} = $cc;
    }
    return $res;
}

# <LJFUNC>
# name: LJ::Schools::get_schools
# class: schools
# des: Gets schools defined in an area.
# args: countrycode, statecode, citycode
# des-countrycode: The country code provided from LJ::Schools::get_countries.
# des-statecode: The state code provided from LJ::Schools::get_states.
# des-citycode: The city code provided from LJ::Schools::get_cities.
# returns: Hashref; schoolid as key, hashref of schools row as value with
#          keys: name, city, state, country, url.
# </LJFUNC>
sub get_schools {
    my ($ctc, $sc, $cc) = @_;
    return undef unless $ctc && defined $sc && defined $cc;

    # just dredge it up from the database (READER)
    my $dbr = LJ::get_db_reader();
    return undef unless $dbr;

    # might get some nulls
    my @args = grep { defined $_ && $_ } ($ctc, $sc, $cc);
    my $scs = $sc ? "state = ?" : "state IS NULL";
    my $ccs = $cc ? "city = ?"  : "city IS NULL";

    # do the query
    my $rows = $dbr->selectall_arrayref
        ("SELECT schoolid, name FROM schools WHERE country = ? AND $scs AND $ccs",
         undef, @args);
    return undef if $dbr->err || ! $rows;

    # and now combine them
    my $res = {};
    foreach my $row (@$rows) {
        $res->{$row->[0]} = $row->[1];
    }
    return $res;
}

# <LJFUNC>
# name: LJ::Schools::expand_codes
# class: schools
# des: Expands country, state, and city codes into actual names.
# args: countrycode, statecode?, citycode?
# des-countrycode: Code of the country.
# des-statecode?: Code of the state/province.
# des-citycode?: Code of the city.
# returns: Array of country, state, city.
# </LJFUNC>
sub expand_codes {
    my ($ctc, $sc, $cc, $sid) = @_;
    return undef unless $ctc;

    my (%countries, %states);
    if ($ctc eq 'US') {
        LJ::load_codes({ country => \%countries, state => \%states });
    } else {
        LJ::load_codes({ country => \%countries });
    }

    # countries are pretty easy, from the list
    my ($ct, $s, $c, $sn);
    $ct = $countries{$ctc};

    # state codes translate to US states, or are themselves
    if (defined $sc) {
        $s = $states{$sc} || $sc;
    }

    # for now, city codes = city names
    if (defined $cc) {
        $c = $cc;
    }

    # simple db query (FIXME: memcache)
    if (defined $sid && $sid > 0) {
        my $dbr = LJ::get_db_reader();
        my $name = $dbr->selectrow_array('SELECT name FROM schools WHERE schoolid = ?', undef, $sid);
        $sn = $name;
    }

    # la la la return
    return ($ct, $s, $c, $sn);
}

# <LJFUNC>
# name: LJ::Schools::determine_location_opts
# class: schools
# des: Internal; used to perform the logic to determine the location codes to use for
#      a record based on the inputs.
# args: opts
# des-opts: Hashref; should contain some combination of city, country, state, citycode,
#           countrycode, statecode.  The codes trump the non-code arguments.
# returns: list of: countrycode, statecode, citycode.  undef on error.
# </LJFUNC>
sub determine_location_opts {
    my $opts = shift;
    return undef unless $opts && ref $opts;

    my ($ctc, $sc, $cc);

    # get country code first
    $ctc = $opts->{countrycode};
    unless ($ctc) {
        my %countries;
        LJ::load_codes({ country => \%countries });
        %countries = reverse %countries;
        $ctc = $countries{$opts->{country}};
    }
    return () unless $ctc;
}

# <LJFUNC>
# name: LJ::Schools::add_pending_school
# class: schools
# des: Adds a school from a user to the pending list of schools.
# args: uobj, options
# des-uobj: User id or object of user that's adding the row.
# des-options: Hashref; Key=>value pairs that can include: name, city, state, country,
#              citycode, statecode, countrycode, url.
# returns: 1 on success, undef on error.
# </LJFUNC>
sub add_pending_school {
    my ($u, $opts) = @_;
    $u = LJ::want_user($u);
    return undef unless $u && $opts && ref $opts eq 'HASH';

    # verify we have minimum data
    return undef unless
        $opts->{name} && $opts->{city} && $opts->{country}
}

# <LJFUNC>
# name: LJ::Schools::set_attended
# class: schools
# des: Lists a school as being attended by a user or updates an existing edge.
# args: uobj, schoolid, options?
# des-uobj: User id or object of user doing the attending.
# des-schoolid: School id of school being attended.
# des-options?: Hashref; Key=>value pairs year_start and year_end, if desired.
# returns: 1 on success, undef on error.
# </LJFUNC>
sub set_attended {
    my ($u, $sid, $opts) = @_;
    $u = LJ::want_user($u);
    $sid = $sid + 0;
    $opts ||= {};
    return undef unless $u && $sid && $opts;

    # now, make sure the school is valid
    my $school = LJ::Schools::load_schools( $sid );
    return undef unless $school->{$sid};

    # validate our information
    my $ys = ($opts->{year_start} + 0) || undef;
    my $ye = ($opts->{year_end} + 0) || undef;

    # enforce convention that year end must be undef if year start is
    # undef; if it's not, it can be either
    $ye = undef unless $ys;

    # and now ensure they're in the right order
    ($ys, $ye) = ($ye, $ys)
        if defined $ys && defined $ye && $ye < $ys;

    # now do the insert, if that fails, do an update
    my $dbcm = LJ::get_cluster_master($u)
        or return undef;
    my $dbh = LJ::get_db_writer()
        or return undef;

    # see if we're adding a new row or updating
    my $ct = $dbh->do("INSERT IGNORE INTO schools_attended (schoolid, userid, year_start, year_end) VALUES (?, ?, ?, ?)",
                      undef, $sid, $u->{userid}, $ys, $ye);
    return undef if $dbh->err;

    # now, if we have a count, do the cluster insert and call it good
    if ($ct > 0) {
        $dbcm->do("INSERT INTO user_schools (userid, schoolid, year_start, year_end) VALUES (?, ?, ?, ?)",
                  undef, $u->{userid}, $sid, $ys, $ye);

        # if error there, attempt to roll back global change
        if ($dbcm->err) {
            $dbh->do("DELETE FROM schools_attended WHERE schoolid = ? AND userid = ?",
                     undef, $sid, $u->{userid});
            return undef;
        }

        # must have been successful!
        return 1;
    }

    # okay, so we're doing an update
    $dbh->do("UPDATE schools_attended SET year_start = ?, year_end = ? WHERE schoolid = ? AND userid = ?",
             undef, $ys, $ye, $sid, $u->{userid});
    return undef if $dbh->err;
    $dbcm->do("UPDATE user_schools SET year_start = ?, year_end = ? WHERE userid = ? AND schoolid = ?",
              undef, $ys, $ye, $u->{userid}, $sid);
    return undef if $dbcm->err;
    return 1;
}

# <LJFUNC>
# name: LJ::Schools::delete_attended
# class: schools
# des: Removes an attended edge from a user/school.
# args: uobj, schoolid
# des-uobj: User id or object of user doing the attending.
# des-schoolid: School id of school being un-attended.
# returns: 1 on success, undef on error.
# </LJFUNC>
sub delete_attended {
    my ($u, $sid) = @_;
    $u = LJ::want_user($u);
    $sid = $sid + 0;
    return undef unless $u && $sid;

    # get the dbs we need
    my $dbcm = LJ::get_cluster_master($u)
        or return undef;
    my $dbh = LJ::get_db_writer()
        or return undef;

    # now delete the data
    $dbh->do("DELETE FROM schools_attended WHERE schoolid = ? AND userid = ?",
             undef, $sid, $u->{userid});
    return undef if $dbh->err;
    $dbcm->do("DELETE FROM user_schools WHERE userid = ? AND schoolid = ?",
              undef, $u->{userid}, $sid);
    return undef if $dbcm->err;

    # now clear the user's memcache... note that we do not delete the school's
    # memcache rows, because then we'd have to load more information to get what
    # years this user attended, and it doesn't help us much.  we want the school
    # attendance lists to be loaded as little as possible.
    # FIXME: delete user's memcache row
    return 1;
}

# <LJFUNC>
# name: LJ::Schools::approve_pending
# class: schools
# des: Takes a bunch of pending rows and approves them as a new target school.
# args: pendids, options
# des-pendids: Arrayref of pendids from the schools_pending table.
# des-options: Hashref; Key=>value pairs that define the target school's information.  Keys
#              are one of: name, city, state, country, citycode, statecode, countrycode, url.
# returns: 1 on success, undef on error.
# </LJFUNC>
sub approve_pending {

}

# <LJFUNC>
# name: LJ::Schools::get_pending
# class: schools
# des: Returns the next "potentially good" set of records to be processed.
# returns: Arrayref of hashrefs of records; the hashrefs have keys of name,
#          city, state, country, citycode, statecode, countrycode,
#          url, userid.
# </LJFUNC>
sub get_pending {

}

1;
