package LJ::Schools::Log;
use strict;

=comment

LJ::Schools::Log: a logger module for Schools Directory actions

It logs pretty much what is passed to it: school data before the change, school
data after the change, timestamp for the change, and who performed it.

It can also log when a state or a city is renamed by doing complex-but-efficient
INSERT SELECT queries. Some notes on efficiency are available in the sub that
performs these queries.

Unless it is specifically said not to do so, this module passes data to
LJ::Schools::Stats for synchronous statistics collection.

$LJ::DISABLED{'schools-logs'} disables this module from functioning. After that,
it writes data to /dev/null and pretends that all tables are empty when reading.

Related modules:

 * LJ::Schools (schoollib.pl)
 * LJ::Schools::Stats

Related user-facing pages:

 * /admin/schools/*
 * specifically, /admin/schools/history.bml for viewing logs
 * /schools/

Related privileges:

 * siteadmin:schools-logs: allows for viewing logs/stats

=cut

use LJ::Schools::Stats;

# LJ::Schools::Log->log: add a row to the logs table
#
# signature:
# LJ::Schools::Log->log(%hash);
#
# in the hash, the following keys are interpreted:
# schoolid[12], name[12], country[12], state[12], city[12], url[12]: school data
#    before and after the change; 1 stands for "before" and 2 for "after"
# userid [optional]: initiator of the change. LJ::get_remote() if unspecified.
# nostats: do not send information to stats
sub log {
    my ($class, %data) = @_;

    return if $LJ::DISABLED{'schools-logs'};

    my $userid = $data{'userid'} || LJ::get_remote()->id;

    $data{$_} ||= '' foreach qw(
        schoolid1 name1 country1 state1 city1 url1
        schoolid2 name2 country2 state2 city2 url2
    );

    my $dbh = LJ::get_db_writer();
    $dbh->{'RaiseError'} = 1 if $LJ::IS_DEV_SERVER;
    $dbh->do(
        qq{
            INSERT INTO schools_log (
                action, userid, time, schoolid1, name1, country1, state1,
                city1, url1, schoolid2, name2, country2, state2, city2, url2
            ) VALUES (
                ?, ?, UNIX_TIMESTAMP(), ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
            );
        }, undef, $data{'action'}, $userid,
        $data{'schoolid1'}, $data{'name1'}, $data{'country1'}, $data{'state1'},
        $data{'city1'}, $data{'url1'}, $data{'schoolid2'}, $data{'name2'},
        $data{'country2'}, $data{'state2'}, $data{'city2'}, $data{'url2'}
    );

    LJ::Schools::Stats->record_touch($data{'action'}, $userid)
        unless $data{'nostats'};
}

# LJ::Schools::Log->log_mass_action: add several rows corresponding to a mass
# action performed on the Schools directory; "mass action" here can mean
# renaming a city or renaming a state.
#
# signature:
# LJ::Schools::Log->log_mass_action(%hash);
#
# in the hash, the "movetype" key indicates which of the mass actions is
# performed:
#
#  * "city" corresponds to renaming a city; in this case, hash must contain
#    "country", "state", "city1", and "city2" keys
#  * "state" corresponds to renaming a state; in this case, hash must contain
#    "country", "state1", and "state2" keys
#
# regardless of the movetype, there are two optional hash keys that are
# interpreted as well:
# userid: initiator of the change. LJ::get_remote() if unspecified.
# nostats: do not send information to stats
#
# Note that for each call to this function, only one touch is reported to
# Stats, provided that "nostats" is not enabled.
#
# Regarding the SQL queries, they are supposed to be efficient, though to be
# honest, I didn't test it. They are most likely more efficient than selecting
# and then looping over results, but seriously, I didn't aim for them working
# in a nanosecond. Mass actions like these aren't performed too often, so
# $remote can wait another second or two until logging is completed as well.
#
# (Also, Mark Smith used similar queries in LJ::Schools without hesitation, so
# I only added comparably complex queries in here. :P)
#
# Regarding the logic, "ahh, SQL". The select here works on the schools table
# left-joined with itself. t1 here is the school that is being changed by the
# move, and for a given t1, it tries to find t2, a school in the target
# city/state that has exactly the same name. If that school exists, it's a
# merge; otherwise, it's a move.
sub log_mass_action {
    my ($class, %data) = @_;

    return if $LJ::DISABLED{'schools-logs'};

    my $userid = $data{'userid'} || LJ::get_remote()->id;

    my $dbh = LJ::get_db_writer();
    $dbh->{'RaiseError'} = 1 if $LJ::IS_DEV_SERVER;
    if ($data{'movetype'} eq 'city') {
        $dbh->do(
            qq{
                INSERT INTO schools_log (
                    action, userid, time, schoolid1, name1, country1, state1,
                    city1, url1, schoolid2, name2, country2, state2, city2,
                    url2
                )
                SELECT
                    IF(s2.schoolid IS NULL, "mass-move", "mass-merge"),
                    ?, UNIX_TIMESTAMP(), s1.schoolid, s1.name,
                    s1.country, s1.state, s1.city, s1.url,
                    COALESCE(s2.schoolid, s1.schoolid), s1.name, s1.country,
                    s1.state, ?, COALESCE(s2.url, s1.url)
                FROM
                    schools s1 LEFT JOIN
                    schools s2 ON
                        s1.name = s2.name AND
                        s2.country = ? AND s2.state = ? AND s2.city = ?
                WHERE
                    s1.country = ? AND s1.state = ? AND s1.city = ?
            }, undef, $userid, $data{'city2'}, $data{'country'}, $data{'state'},
            $data{'city2'}, $data{'country'}, $data{'state'}, $data{'city1'}
        );
    } elsif ($data{'movetype'} eq 'state') {
        $dbh->do(
            qq{
                INSERT INTO schools_log (
                    action, userid, time, schoolid1, name1, country1, state1,
                    city1, url1, schoolid2, name2, country2, state2, city2,
                    url2
                )
                SELECT
                    IF(s2.schoolid IS NULL, "mass-move", "mass-merge"),
                    ?, UNIX_TIMESTAMP(), s1.schoolid, s1.name,
                    s1.country, s1.state, s1.city, s1.url,
                    COALESCE(s2.schoolid, s1.schoolid), s1.name, s1.country,
                    ?, s1.city, COALESCE(s2.url, s1.url)
                FROM
                    schools s1 LEFT JOIN
                    schools s2 ON
                        s1.name = s2.name AND s1.city = s2.city
                        s2.country = ? AND s2.state = ?
                WHERE
                    s1.country = ? AND s1.state = ?
            }, undef, $userid, $data{'state2'}, $data{'country'},
            $data{'state1'}, $data{'country'}, $data{'state1'}
        );
    }

    LJ::Schools::Stats->record_touch("mass-move", $userid)
        unless $data{'nostats'};
}

# LJ::Schools::Log->get_last_edit: get information about who and when last
# changed the given school entry.
#
# signature:
# my ($userid, $time) = LJ::Schools::Log->get_last_edit($schoolid);
#
# The UNIONs here are deliberately chosen over using one query with OR; tests
# showed that one query with OR doesn't utilize indices on schoolid[12] at all,
# so that would be a full scan.
sub get_last_edit {
    my ($class, $schoolid) = @_;

    return undef if $LJ::DISABLED{'schools-logs'};

    my $dbr = LJ::get_db_reader();

    return $dbr->selectrow_array(
        qq{
            (SELECT userid, time FROM schools_log WHERE schoolid1=?)
            UNION ALL
            (SELECT userid, time FROM schools_log WHERE schoolid2=?)
            ORDER BY time DESC
            LIMIT 1
        }, undef, $schoolid, $schoolid
    );
}

# LJ::Schools::Log->quert: get log entries matching the given criteria
#
# signature:
# my $arrayref = LJ::Schools::Log->query(%args);
# returns:
# [
#   { logid => 1, schoolid1 => 43, ... },
#   { logid => 2, schoolid1 => 43, ... },
#   ...
# ];
#
# %args can include:
#  * skipto: return log entries with the ID less than the given one
#  * schoolid: only show log entries in which the given school is affected
#  * userid: the user who made the change
#
# Note that this function returns no more than 100 rows; you can manipulate
# with the "skipto" argument for pagination.
#
# The UNIONs here are deliberately chosen over using one query with OR; tests
# showed that one query with OR doesn't utilize indices on schoolid[12] at all,
# so that would be a full scan.
sub query {
    my ($class, %args) = @_;

    return [] if $LJ::DISABLED{'schools-logs'};

    my @query_params;
    my @query_conditions = (1);

    if ($args{'skipto'}) {
        push @query_conditions, 'logid < ?';
        push @query_params, $args{'skipto'} + 0;
    }

    if ($args{'userid'}) {
        push @query_conditions, 'userid=?';
        push @query_params, int $args{'userid'};
    }

    my $cond = join ' AND ', @query_conditions;

    # we need to do one query if schoolid is not specified and two queries
    # in a union if it is specified

    my $dbr = LJ::get_db_reader();
    $dbr->{'RaiseError'} = 1 if $LJ::IS_DEV_SERVER;
    if ($args{'schoolid'}) {
        my $sid = $args{'schoolid'};
        return $dbr->selectall_arrayref(
            qq{
                (SELECT * FROM schools_log WHERE schoolid1=? AND $cond)
                UNION
                (SELECT * FROM schools_log WHERE schoolid2=? AND $cond)
                ORDER BY time DESC
                LIMIT 100
            }, { Slice => {} }, $sid, @query_params, $sid, @query_params
        );
    } else {
        return $dbr->selectall_arrayref(
            qq{
                SELECT * FROM schools_log WHERE $cond
                ORDER BY time DESC
                LIMIT 100
            }, { Slice => {} }, @query_params
        );
    }
}

1;
