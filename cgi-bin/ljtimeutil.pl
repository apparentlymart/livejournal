package LJ;
use strict;

### THIS MODULE IS DEPRECATED. USE LJ::TimeUtil INSTEAD. ###

use LJ::TimeUtil;
use Carp qw();

sub days_in_month {
    Carp::confess("the LJ::days_in_month subroutine is deprecated. Use LJ::TimeUtil->days_in_month instead.")
        if $LJ::IS_DEV_SERVER;

    return LJ::TimeUtil->days_in_month(@_);
}

sub day_of_week {
    Carp::confess("the LJ::day_of_week subroutine is deprecated. Use LJ::TimeUtil->day_of_week instead.")
        if $LJ::IS_DEV_SERVER;

    return LJ::TimeUtil->day_of_week(@_);
}

sub http_to_time {
    Carp::confess("the LJ::http_to_time subroutine is deprecated. Use LJ::TimeUtil->http_to_time instead.")
        if $LJ::IS_DEV_SERVER;

    return LJ::TimeUtil->http_to_time(@_);
}

sub mysqldate_to_time {
    Carp::confess("the LJ::mysqldate_to_time subroutine is deprecated. Use LJ::TimeUtil->mysqldate_to_time instead.")
        if $LJ::IS_DEV_SERVER;

    return LJ::TimeUtil->mysqldate_to_time(@_);
}

sub time_to_http {
    Carp::confess("the LJ::time_to_http subroutine is deprecated. Use LJ::TimeUtil->time_to_http instead.")
        if $LJ::IS_DEV_SERVER;

    return LJ::TimeUtil->time_to_http(@_);
}

sub time_to_cookie {
    Carp::confess("the LJ::time_to_cookie subroutine is deprecated. Use LJ::TimeUtil->time_to_cookie instead.")
        if $LJ::IS_DEV_SERVER;

    return LJ::TimeUtil->time_to_cookie(@_);
}

sub time_to_w3c {
    Carp::confess("the LJ::time_to_w3c subroutine is deprecated. Use LJ::TimeUtil->time_to_w3c instead.")
        if $LJ::IS_DEV_SERVER;

    return LJ::TimeUtil->time_to_w3c(@_);
}

sub mysql_time {
    Carp::confess("the LJ::mysql_time subroutine is deprecated. Use LJ::TimeUtil->mysql_time instead.")
        if $LJ::IS_DEV_SERVER;

    return LJ::TimeUtil->mysql_time(@_);
}

sub alldatepart_s1 {
    Carp::confess("the LJ::alldatepart_s1 subroutine is deprecated. Use LJ::TimeUtil->alldatepart_s1 instead.")
        if $LJ::IS_DEV_SERVER;

    return LJ::TimeUtil->alldatepart_s1(@_);
}

sub alldatepart_s2 {
    Carp::confess("the LJ::alldatepart_s2 subroutine is deprecated. Use LJ::TimeUtil->alldatepart_s2 instead.")
        if $LJ::IS_DEV_SERVER;

    return LJ::TimeUtil->alldatepart_s2(@_);
}

sub statushistory_time {
    Carp::confess("the LJ::statushistory_time subroutine is deprecated. Use LJ::TimeUtil->statushistory_time instead.")
        if $LJ::IS_DEV_SERVER;

    return LJ::TimeUtil->statushistory_time(@_);
}

sub ago_text {
    Carp::confess("the LJ::ago_text subroutine is deprecated. Use LJ::TimeUtil->ago_text instead.")
        if $LJ::IS_DEV_SERVER;

    return LJ::TimeUtil->ago_text(@_);
}

sub calc_age {
    Carp::confess("the LJ::calc_age subroutine is deprecated. Use LJ::TimeUtil->calc_age instead.")
        if $LJ::IS_DEV_SERVER;

    return LJ::TimeUtil->calc_age(@_);
}

1;
