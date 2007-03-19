#!/usr/bin/perl
#
#   This library is used by Support Stats.
#
#   In particular, it's used by the following pages:
#   - htdocs/admin/support/dept.bml
#   - htdocs/admin/support/individual.bml
#
#   This library doesn't have any DB access routines.
#   All DB access routines are in supportlib.pl
#

use strict;
package LJ::Support::Stats;
use vars qw($ALL_CATEGORIES_ID);

use Carp qw(croak);
use DateTime;

# Constants
$ALL_CATEGORIES_ID = -1;

#
# Name:   filter_support_by_category
# Desc:   Filter Support by Category ID
# Parm:   support = HashRef of Support Rows indexed by Support ID
# Return: Filtered HashRef of Support Rows
#
sub filter_support_by_category {
    my($support_hashref, $category_id_parm) = @_;

    return $support_hashref if $category_id_parm == $ALL_CATEGORIES_ID;

    my %filtered_support = ();
    while (my($support_id, $support) = each %{$support_hashref}) {
        $filtered_support{$support_id} = $support
            if $support->{spcatid} == $category_id_parm;
    }

    return \%filtered_support;
}

#
# Name:   date_formatter
# Desc:   Format a date
# Parms:  year  = Four digit year (e.g. 2001)
#         month = One-based numeric month: 1-12
#         day   = One-based numeric day: 1-31
# Return: Date formatted as follows: YYYY-MM-DD
#
sub date_formatter {
    croak('Not enough parameters') if @_ < 3;
    my($year, $month, $day) = @_;
    my $date = sprintf("%04d-%02d-%02d", $year, $month, $day);
    return $date;
}

#
# Name:   comma_formatter
# Desc:   Format a number with commas
# Parm:   number to commafy
# Return: Number with commas inserte
#
sub comma_formatter {
    my $number = shift or croak('No parameter for comma_formatter');
    1 while ($number =~ s/([-+]?\d+)(\d\d\d\.?)(?!\d)/$1,$2/);
    return $number;
};


#
# Name:   percent_formatter
# Desc:   Format a percentage: Take integer portion and append percent sign
# Parm:   percent: Number to format as a percentage
# Return: Formatted percentage
#
sub percent_formatter {
    my $percent = shift;
    $percent = int($percent) . '%';
    return $percent;
};

#
# Name:   get_grains_from_seconds
# Desc:   Determine the grains (day/week/month/year) of given a date
# Parm:   seconds = Seconds since epoch
# Return: HashRef of Grains
#
sub get_grains_from_seconds {
    my $seconds_since_epoch = shift or croak('No parameter specified');

    my $date = LJ::mysql_time($seconds_since_epoch);

    my %grain;
    $grain{grand} = 'Grand';
    $grain{day}   = substr($date, 0, 10);
    $grain{month} = substr($date, 0,  7);
    $grain{year}  = substr($date, 0,  4);

    # Get week of Support Ticket
    my $dt = DateTime->from_epoch( epoch => $seconds_since_epoch );
    my($week_year, $week_number) = $dt->week;
    $grain{week} = $week_year . ' - Week #' . sprintf('%02d', $week_number);

    return \%grain;
}


1;
