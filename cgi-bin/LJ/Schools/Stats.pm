package LJ::Schools::Stats;
use strict;

=comment

LJ::Schools::Stats: LJ::Schools::Log entries statistics.

For efficiency, the table here contains four fields:

 * day, stored as a UNIX epoch time for the midnight of that day
 * userid of the user who touched the directory;
   lack of userid indicates that this row reflects activity of all volunteers
   on a given day
 * action that that user has taken;
   lack of action indicates that this row reflects all actions volunteer(s)
   have taken on a given day
 * count of log entries corresponding to that day, userid, and action

Please note that LJ::Schools::Log is up to decide whether to count the given
action in statistics; its insert functions have the "nostats" parameter that
disables passing data to here.

$LJ::DISABLED{'schools-logs'} disables this module from functioning. After that,
it writes data to /dev/null and pretends that all tables are empty when reading.

Related modules:

 * LJ::Schools (schoollib.pl)
 * LJ::Schools::Logs

Related user-facing pages:

 * /admin/schools/*
 * specifically, /admin/schools/logstats.bml for viewing stats
 * /schools/

Related privileges:

 * siteadmin:schools-logs: allows for viewing logs/stats

=cut

use DateTime;

# LJ::Schools::Stats->record_touch: count the touch in statistics
#
# Signature: LJ::Schools::Stats->record_touch($action, $userid)
#
# For each call, it inserts or updates four rows, namely:
#
#  * today, the given action, the given userid
#  * today, the given action, all userids
#  * today, all actions, the given userid
#  * today, all actions, all userids
sub record_touch {
    my ($class, $action, $userid) = @_;

    return if $LJ::DISABLED{'schools-logs'};

    my $dbh = LJ::get_db_writer();
    $dbh->{'RaiseError'} = 1 if $LJ::IS_DEV_SERVER;

    my $handle_row = sub {
        my ($time, $userid, $action) = @_;

        my $affected_rows = $dbh->do(
            qq{
                UPDATE schools_stats
                SET count_touches = count_touches + 1
                WHERE
                    time=? AND userid=? AND action=?
            }, undef, $time, $userid, $action
        );

        return unless $affected_rows == 0;

        $dbh->do(
            qq{
                INSERT INTO schools_stats (
                    time, userid, action, count_touches
                ) VALUES (
                    ?, ?, ?, 1
                );
            }, undef, $time, $userid, $action
        );
    };

    my $date = DateTime->today;

    $handle_row->($date->epoch, $userid, $action);
    $handle_row->($date->epoch, 0, $action);
    $handle_row->($date->epoch, $userid, "");
    $handle_row->($date->epoch, 0, "");
}

# LJ::Schools::Stats->query: generate a report about touches in the given
# time interval
#
# Signature: LJ::Schools::Stats->query(%args)
#
# For each call, it inserts or updates four rows, namely:
#
# %args must include the following:
#
#  * mintime: the lower bound of the time interval
#  * maxtime: the higher bound of the time interval
#  * group: type of report (types are explained below)
#
# Let me note one more time that "mintime" and "maxtime" are mandatory; making
# them optional would make it less efficient.
#
# There is also an optional "userid" argument that makes "day" and "day-action"
# reports filter touches by the passed user.
#
# Types of Reports:
#  * userid: return all users who touched the directory and how many touches
#    they performed.
#  * day: return all days in the given interval, indicating how many touches
#    were performed.
#  * userid-day: for each user and day, return the number of touches
#  * userid-action: for each user and action type, return the number of touches
#  * day-action: for each user and day, return the number of touches
#
# The sub returns an arrayref containing hashrefs with table rows, so it's up
# to the calling side how to parse these data.
sub query {
    my ($class, %params) = @_;

    return [] if $LJ::DISABLED{'schools-logs'};

    my ($min, $max, $group) =
        ($params{'mintime'}, $params{'maxtime'}, $params{'group'});

    my $to_epoch = sub {
        my ($time) = @_;
        my ($year, $month, $day) = split /\D+/, $time;

        my $dt = DateTime->new(
            'year' => $year,
            'month' => $month,
            'day' => $day,
        );

        return $dt->epoch;
    };

    ($min, $max) = map { $to_epoch->($_); } ($min, $max);

    die "No time interval specified for LJ::Schools::Stats->get_in_timerange"
        unless $min and $max;

    my $dbr = LJ::get_db_reader();
    $dbr->{'RaiseError'} = 1 if $LJ::IS_DEV_SERVER;

    if ($group eq 'userid') {
        return $dbr->selectall_arrayref(
            qq{
                SELECT userid, SUM(count_touches) AS count_touches
                FROM schools_stats
                WHERE (time BETWEEN ? AND ?) AND userid!=0 AND action=""
                GROUP BY userid
            }, { Slice => {} }, $min, $max
        );
    } elsif ($group eq 'day') {
        my ($param, @subst) = $params{'userid'} ?
            ('userid=?', $params{'userid'}) :
            ('userid=0');

        return $dbr->selectall_arrayref(
            qq{
                SELECT time, count_touches
                FROM schools_stats
                WHERE (time BETWEEN ? AND ?) AND $param AND action=""
                ORDER BY time
            }, { Slice => {} }, $min, $max, @subst
        );
    } elsif ($group eq 'userid-day') {
        return $dbr->selectall_arrayref(
            qq{
                SELECT userid, time, count_touches AS count_touches
                FROM schools_stats
                WHERE (time BETWEEN ? AND ?) AND userid!=0 AND action=""
            }, { Slice => {} }, $min, $max
        );
    } elsif ($group eq 'userid-action') {
        return $dbr->selectall_arrayref(
            qq{
                SELECT userid, action, SUM(count_touches) AS count_touches
                FROM schools_stats
                WHERE (time BETWEEN ? AND ?) AND userid!=0 AND action!=""
                GROUP BY userid, action
            }, { Slice => {} }, $min, $max
        );
    } elsif ($group eq 'day-action') {
        my ($param, @subst) = $params{'userid'} ?
            ('userid=?', $params{'userid'}) :
            ('userid=0');

        return $dbr->selectall_arrayref(
            qq{
                SELECT time, action, count_touches
                FROM schools_stats
                WHERE (time BETWEEN ? AND ?) AND $param AND action!=""
                ORDER BY time
            }, { Slice => {} }, $min, $max, @subst
        );
    }
}

1;
