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
    my $res = LJ::MemCache::get([ $u->{userid}, "saui:$u->{userid}" ]);

    # if that failed, hit db
    unless ($res) {
        my $dbcr = LJ::get_cluster_def_reader($u);
        return undef unless $dbcr;

        my $rows = $dbcr->selectall_arrayref(qq{
            SELECT schoolid, year_start, year_end
            FROM user_schools
            WHERE userid = ?
        }, undef, $u->{userid});
        return undef if $dbcr->err || ! $rows;

        $res = {};
        foreach my $row (@$rows) {
            $res->{$row->[0]} = {
                year_start => $row->[1],
                year_end => $row->[2],
            };
        }

        LJ::MemCache::add([ $u->{userid}, "saui:$u->{userid}" ], $res);
    }

    # now populate with school information
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

    # check from memcache
    my $res;
    my %need = map { $_ => 1 } @ids;
    my @keys = map { [ $_, "sasi:$_" ] } @ids;
    my $mres = LJ::MemCache::get_multi(@keys);
    foreach my $key (keys %{$mres || {}}) {
        if ($key =~ /^sasi:(\d+)$/) {
            delete $need{$1};
            $res->{$1} = $mres->{$key};
        }
    }
    return $res unless %need;

    # now fallback to database
    my $in = join(',', keys %need);
    my $dbh = LJ::get_db_writer(); # writer to get data for memcache
    return undef unless $dbh;
    my $rows = $dbh->selectall_arrayref(qq{
            SELECT schoolid, name, country, state, city, url
            FROM schools
            WHERE schoolid IN ($in)
        });
    return undef if $dbh->err || ! $rows;

    foreach my $row (@$rows) {
        $res->{$row->[0]} = {
            name => $row->[1],
            country => $row->[2],
            state => $row->[3],
            city => $row->[4],
            url => $row->[6],
        };
        LJ::MemCache::set([ $row->[0], "sasi:$row->[0]" ], $res->{$row->[0]});
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
# returns: list of: countrycode, statecode, citycode.  empty list on error.
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
        if (exists $countries{$opts->{country}}) {
            # valid code, use it
            $ctc = $opts->{country};
        } else {
            # must be a name, back-convert it
            %countries = reverse %countries;
            $ctc = $countries{$opts->{country}};
        }
    }
    return () unless $ctc;

    # now get the state code
    $sc = $opts->{statecode};
    unless ($sc) {
        if ($ctc eq 'US') {
            my %states;
            LJ::load_codes({ state => \%states });
            if (exists $states{$opts->{state}}) {
                # valid code, use it
                $sc = $opts->{state};
            } else {
                # must be a name, back-convert it
                %states = reverse %states;
                $sc = $states{$opts->{state}};
            }
        } else {
            $sc = $opts->{state};
        }
    }

    # and finally the city
    $cc = $opts->{citycode} || $opts->{city};

    # and the list
    return ($ctc, $sc, $cc);
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

    # verify we have location data
    my ($ctc, $sc, $cc) = LJ::Schools::determine_location_opts($opts);
    return undef unless $ctc && defined $sc && defined $cc;

    # verify we have minimum data (name)
    return undef unless $opts->{name};

    # now undef things that need to be null if blank
    $sc ||= undef;
    $cc ||= undef;
    $opts->{url} ||= undef;

    # get db and insert
    my $dbh = LJ::get_db_writer();
    $dbh->do("INSERT INTO schools_pending (userid, name, country, state, city, url) VALUES (?, ?, ?, ?, ?, ?)",
             undef, $u->{userid}, $opts->{name}, $ctc, $sc, $cc, $opts->{url});
    return undef if $dbh->err;
    return 1;
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

    # delete a user's school attended info
    LJ::MemCache::delete([ $u->{userid}, "saui:$u->{userid}" ]);

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
    LJ::MemCache::delete([ $u->{userid}, "saui:$u->{userid}" ]);
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
# returns: Allocated school id on success, undef on error.
# </LJFUNC>
sub approve_pending {
    my ($pendids, $opts) = @_;
    return undef unless $pendids && ref $pendids eq 'ARRAY' && @$pendids &&
                        $opts && ref $opts eq 'HASH';

    # now verify our pendids are valid
    @$pendids = grep { $_ } map { $_+0 } @$pendids;
    return undef unless @$pendids;

    # verify we have location data
    my ($ctc, $sc, $cc) = LJ::Schools::determine_location_opts($opts);
    return undef unless $ctc && defined $sc && defined $cc;

    # and verify other options
    return undef unless $opts->{name};

    # get database handle
    my $dbh = LJ::get_db_writer();
    return undef unless $dbh;

    # load these pending rows
    my $in = join(',', @$pendids);
    my $rows = $dbh->selectall_hashref(qq{
            SELECT pendid, userid, name, country, state, city, url
            FROM schools_pending
            WHERE pendid IN ($in)
        }, 'pendid') || {};
    return undef if $dbh->err;

    # setup to add the new school
    $sc ||= undef;
    $cc ||= undef;
    $opts->{url} ||= undef;

    # actually add the school
    my $sid = LJ::alloc_global_counter('O');
    return undef unless $sid;
    $dbh->do("INSERT INTO schools (schoolid, name, country, state, city, url) VALUES (?, ?, ?, ?, ?, ?)",
             undef, $sid, $opts->{name}, $ctc, $sc, $cc, $opts->{url});
    return undef if $dbh->err;

    # now insert the user attendance lists
    my %userids;
    foreach my $row (values %$rows) {
        next if $userids{$row->{userid}}++;
        LJ::Schools::set_attended($row->{userid}, $sid);
    }

    # and delete their pending rows, but ignore errors
    $dbh->do("DELETE FROM schools_pending WHERE pendid IN ($in)");

    # and we're done
    return $sid;
}

# <LJFUNC>
# name: LJ::Schools::get_pending
# class: schools
# des: Returns the next "potentially good" set of records to be processed.
# args: uobj
# des-uobj: User id or object of user doing the admin work.
# returns: Hashref; keys being 'primary' with a value of a school hashref,
#          and 'secondary', 'tertiary' with values being a hashref of
#          { pendid => { ..school.. } }, where the school hashref contains
#          name, citycode, statecode, countrycode, url, userid.  Undef on error!
# </LJFUNC>
sub get_pending {
    my $u = LJ::want_user(shift);
    return undef unless $u;

    # need db
    my $dbh = LJ::get_db_writer();
    return undef unless $dbh;

    # step 1: select some rows, so we have a sample to choose from
    my $rows = $dbh->selectall_hashref(qq{
            SELECT pendid, userid, name, country, state, city, url
            FROM schools_pending
            LIMIT 20
        }, 'pendid');
    return undef if $dbh->err;

    # step 2: now, we want to find one that isn't being dealt with; I think we will
    # not run into too many "at the same time" issues, so we're doing the memcache
    # queries one at a time instead of implementing the multi logic
    my $pend;
    foreach my $pendid (keys %$rows) {
        my $userid = LJ::MemCache::get([ $pendid, "sapiu:$pendid" ]);
        next if $userid;

        # nobody's touching it, so mark it for us for 10 minutes
        $pend = $pendid;
        last;
    }
    my $school = $rows->{$pend};

    # step 3: find anything relating to this pending record, by name first
    my $sim_name = $dbh->selectall_hashref(qq{
            SELECT pendid, userid, name, country, state, city, url
            FROM schools_pending
            WHERE name = ? AND country = ?
            AND pendid <> ?
        }, 'pendid', undef, $school->{name}, $school->{country}, $pend) || {};
    return undef if $dbh->err;

    # step 4: now find anything in this location as 'possible' matches
    my @args = grep { $_ } ( $school->{state}, $school->{city} );
    my $state = $school->{state} ? "= ?" : "IS NULL";
    my $city  = $school->{city}  ? "= ?" : "IS NULL";
    my $in = join(',', $pend, map { $_+0 } keys %$sim_name);
    my $sim_loc = $dbh->selectall_hashref(qq{
            SELECT pendid, userid, name, country, state, city, url
            FROM schools_pending
            WHERE country = ? AND state $state AND city $city
            AND pendid NOT IN ($in)
        }, 'pendid', undef, $school->{country}, @args) || {};
    return undef if $dbh->err;

    # step 5: note all of these as being 'used'
    my %set;
    foreach my $id ($pend, keys %$sim_name, keys %$sim_loc) {
        next if $set{$id}++;
        LJ::MemCache::set([ $id, "sapiu:$id" ], $u->{userid}, 600);
    }

    # step 6: break things down into secondary and tertiary matches
    my ($second, $third) = ({}, {});
    foreach my $value (values %$sim_loc, values %$sim_name) {
        if (defined $value->{state} && defined $school->{state} &&
                $value->{state} eq $school->{state} &&
                defined $value->{city} && defined $school->{city} &&
                $value->{city} eq $school->{city}) {
            # state+city present & matches, this is a good match
            $second->{$value->{pendid}} = $value;
        } else {
            # tertiary match
            $third->{$value->{pendid}} = $value;
        }
    }

    # step 6: return the results
    return {
        primary   => $school,
        secondary => $second,
        tertiary  => $third,
    };
}

# <LJFUNC>
# name: LJ::Schools::canonical_school_name
# class: schools
# des: Canonicalizes a school name to a standard format.
# args: name, city
# des-name: Name of the school to canonicalize.
# des-city: Name of the city the school is located in.
# returns: Canonicalized name of the school.
# </LJFUNC>
sub canonical_school_name {
    my ($name, $city) = @_;

    # condense spaces and trim as our first act
    $name =~ s/^\s+//;
    $name =~ s/\s+$//;
    $name =~ s/\s+/ /g;

    # remove initial The
    $name =~ s/^The //i;

    # remove a city from the end?
    if ($city =~ /^[\w\s]+$/) {
        $name =~ s/\W$city$//i;
        $name =~ s/ at$//;
        $name =~ s/ -$//;

        # "Universidad de Buenos Aires" etc.
        if ($name =~ /\b(?:de|of)$/i) {
            $name .= " $city";
        }
    }

    # hash of do not capitalize these words
    my %nocaps = map { $_ => 1 }
        qw( de du la le of the and at for );

    # canonicalize it to lowercase with each word capitalized
    $name = lc $name;
    $name = join(' ', map { $nocaps{$_} ? $_ : ucfirst(lc($_)) } split(/\s+/, $name));

    # fix up "O'neill" to "O'Neill"
    $name =~ s/(O'\w)/uc $1/eg;

    # fix up "Mccarthy" to "McCarthy"
    $name =~ s/Mc(\w)/"Mc" . uc $1/eg;

    # fix up "H.c." into "H.C."
    $name =~ s/\b((?:\w\.)+ )/uc $1/eg;

    # fix up "A&m" to "A&M", effectively
    $name =~ s/\b(\w&\w)\b/uc $1/eg;

    # fix up "Foo-bar" into "Foo-Bar"
    $name =~ s/\b(\w)(\w+)-(\w)(\w+)\b/uc($1) . $2 . "-" . uc($3) . $4/eg;

    # fix up Ft.
    $name =~ s/^Ft\.? /Fort /;
 
    # convert Saint to St. at BEGINNING of name
    $name =~ s/^Saint /St. /;
    $name =~ s/^St /St. /;

    # convert St. to Saint INSIDE name
    $name =~ s/ St\.? / Saint /g;

    # fix "foo & bar" to "foo and bar"
    $name =~ s/ & / and /g;

    # now fix "A and M" ... mostly because "A & M" is expanded to such above
    $name =~ s/ A and M / A&M /;

    # fix things that are just "Foo High"
    $name =~ s/ High$/ High School/;

    # we don't call them Senior or Junior high schools
    $name =~ s/ (?:Senior|Junior) High / High /;

    # kill anybody putting ", State" or similar after the name?
    $name =~ s/\s*,\s*$//;

    # now ensure the FIRST LETTER is capitalized
    # fixes case where city names "la Porte" aren't
    $name = ucfirst($name);

    return $name;
}

# <LJFUNC>
# name: LJ::Schools::edit_school
# class: schools
# des: Edits the information for a school.
# args: sid, options
# des-sid: School id to edit.
# des-options: Hashref; Key=>value pairs that can include: name, city, state, country,
#              citycode, statecode, countrycode, url.
# returns: 1 on success, undef on error.
# </LJFUNC>
sub edit_school {
    my ($sid, $opts) = @_;
    $sid += 0;
    return undef unless $sid && $opts && ref $opts eq 'HASH';

    # verify we have location data
    my ($ctc, $sc, $cc) = LJ::Schools::determine_location_opts($opts);
    return undef unless $ctc && defined $sc && defined $cc;

    # verify we have minimum data (name)
    return undef unless $opts->{name};

    # now undef things that need to be null if blank
    $sc ||= undef;
    $cc ||= undef;
    $opts->{url} ||= undef;

    # get db and update
    my $dbh = LJ::get_db_writer();
    $dbh->do("UPDATE schools SET name = ?, city = ?, state = ?, country = ?, url = ? WHERE schoolid = ?",
             undef, $opts->{name}, $cc, $sc, $ctc, $opts->{url}, $sid);
    return undef if $dbh->err;

    # fix memcache
    LJ::MemCache::delete([ $sid, "sasi:$sid" ]);
    return 1;
}

# <LJFUNC>
# name: LJ::Schools::reject_pending
# class: schools
# des: Deletes pending schools.
# args: pendids
# des-pendids: Arrayref of pendids to delete
# returns: 1 on success, undef on error.
# </LJFUNC>
sub reject_pending {
    my ($pendids) = @_;
    return undef unless $pendids && ref $pendids eq 'ARRAY' && @$pendids;

    # now verify our pendids are valid
    @$pendids = grep { $_ } map { $_+0 } @$pendids;
    return undef unless @$pendids;

    # get database handle
    my $dbh = LJ::get_db_writer();
    return undef unless $dbh;

    my $in = join(',', @$pendids);
    # and delete their pending rows, but ignore errors
    $dbh->do("DELETE FROM schools_pending WHERE pendid IN ($in)");

    # and we're done
    return 1;
}

1;
