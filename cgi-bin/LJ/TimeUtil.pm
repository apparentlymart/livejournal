package LJ::TimeUtil;
use strict;

use DateTime;
use HTTP::Date;

# <LJFUNC>
# name: LJ::TimeUtil->days_in_month
# class: time
# des: Figures out the number of days in a month.
# args: month, year?
# des-month: Month
# des-year: Year.  Necessary for February.  If undefined or zero, function
#           will return 29.
# returns: Number of days in that month in that year.
# </LJFUNC>
sub days_in_month {
    my ($class, $month, $year) = @_;
    if ($month == 2)
    {
        return 29 unless $year;  # assume largest
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

sub day_of_week {
    my ($class, $year, $month, $day) = @_;

    require Time::Local;
    my $time = eval { Time::Local::timelocal(0,0,0,$day,$month-1,$year) };
    return undef if $@;
    return (localtime($time))[6];
}

# <LJFUNC>
# class: time
# name: LJ::TimeUtil->http_to_time
# des: Converts HTTP date to Unix time.
# info: Wrapper around HTTP::Date::str2time.
#       See also [func[LJ::TimeUtil->time_to_http]].
# args: string
# des-string: HTTP Date.  See RFC 2616 for format.
# returns: integer; Unix time.
# </LJFUNC>
sub http_to_time {
    my ($class, $string) = @_;
    return HTTP::Date::str2time($string);
}

sub mysqldate_to_ljtime {
    my ($class, $string) = @_;
    return undef unless $string =~ /^(\d\d\d\d)-(\d\d)-(\d\d)(?: (\d\d):(\d\d)(?::(\d\d))?)?$/;

    my ($y, $mon, $d, $h, $min, $s) = ($1, $2, $3, $4, $5, $6);
    return undef unless ($d + 0) and ($mon + 0); # '00' is string and is true value

    $mon -= 1;
    return undef if $mon < 0;

    return "$d " . LJ::Lang::ml( LJ::Lang::month_long_genitive_langcode( $mon )) . ' ' . LJ::Lang::ml('time.preposition') . " $h:$min";
}

sub mysqldate_to_time {
    my ($class, $string, $gmt) = @_;
    return undef unless $string =~ /^(\d\d\d\d)-(\d\d)-(\d\d)(?: (\d\d):(\d\d)(?::(\d\d))?)?$/;
    my ($y, $mon, $d, $h, $min, $s) = ($1, $2, $3, $4, $5, $6);
    return undef unless ($d + 0) and ($mon + 0); # '00' is string and is true value
    my $calc = sub {
        $gmt ?
            Time::Local::timegm($s, $min, $h, $d, $mon-1, $y) :
            Time::Local::timelocal($s, $min, $h, $d, $mon-1, $y);
    };

    # try to do it.  it'll die if the day is bogus
    my $ret = eval { $calc->(); };
    return $ret unless $@;

    # then fix the day up, if so.
    my $max_day = LJ::TimeUtil->days_in_month($mon, $y);
    return undef unless defined $max_day;
    $d = $max_day if $d > $max_day;
    return $calc->();
}

# <LJFUNC>
# class: time
# name: LJ::TimeUtil->time_to_http
# des: Converts a Unix time to a HTTP date.
# info: Wrapper around HTTP::Date::time2str to make an
#       HTTP date (RFC 1123 format)  See also [func[LJ::TimeUtil->http_to_time]].
# args: time
# des-time: Integer; Unix time.
# returns: String; RFC 1123 date.
# </LJFUNC>
sub time_to_http {
    my ($class, $time) = @_;
    return HTTP::Date::time2str($time);
}

# <LJFUNC>
# name: LJ::TimeUtil->time_to_cookie
# des: Converts Unix time to format expected in a Set-Cookie header.
# args: time
# des-time: unix time
# returns: string; Date/Time in format expected by cookie.
# </LJFUNC>
sub time_to_cookie {
    my ($class, $time) = @_;
    $time = time() unless defined $time;

    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime($time);
    $year+=1900;

    my @day = qw{Sunday Monday Tuesday Wednesday Thursday Friday Saturday};
    my @month = qw{Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec};

    return sprintf("$day[$wday], %02d-$month[$mon]-%04d %02d:%02d:%02d GMT",
                   $mday, $year, $hour, $min, $sec);
}

# http://www.w3.org/TR/NOTE-datetime
# http://www.w3.org/TR/xmlschema-2/#dateTime
sub time_to_w3c {
    my ($class, $time, $ofs) = @_;
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime($time);

    $mon++;
    $year += 1900;

    $ofs =~ s/([\-+]\d\d)(\d\d)/$1:$2/;
    $ofs = 'Z' if $ofs =~ /0000$/;
    return sprintf("%04d-%02d-%02dT%02d:%02d:%02d$ofs",
                   $year, $mon, $mday,
                   $hour, $min, $sec);
}

# <LJFUNC>
# name: LJ::TimeUtil->mysql_time
# des:
# class: time
# info:
# args:
# des-:
# returns:
# </LJFUNC>
sub mysql_time {
    my ($class, $time, $gmt) = @_;
    $time ||= time();
    my @ltime = $gmt ? gmtime($time) : localtime($time);
    return sprintf("%04d-%02d-%02d %02d:%02d:%02d",
                   $ltime[5]+1900,
                   $ltime[4]+1,
                   $ltime[3],
                   $ltime[2],
                   $ltime[1],
                   $ltime[0]);
}

# <LJFUNC>
# name: LJ::TimeUtil->alldatepart_s1
# des: Gets date in MySQL format, produces s1dateformat.
# class: time
# args:
# des-:
# info: s1 dateformat is: "%a %W %b %M %y %Y %c %m %e %d %D %p %i %l %h %k %H"
#       Sample string: Tue Tuesday Sep September 03 2003 9 09 30 30 30th AM 22 9 09 9 09.
#       Thu Thursday Oct October 03 2003 10 10 2 02 2nd AM 33 9 09 9 09
# returns:
# </LJFUNC>
sub alldatepart_s1 {
    my ($class, $time) = @_;
    my ($sec,$min,$hour,$mday,$mon,$year,$wday) =
        gmtime(LJ::TimeUtil->mysqldate_to_time($time, 1));
    my $ret = "";

    $ret .= LJ::Lang::day_short($wday+1) . " " .
      LJ::Lang::day_long($wday+1) . " " .
      LJ::Lang::month_short($mon+1) . " " .
      LJ::Lang::month_long($mon+1) . " " .
      sprintf("%02d %04d %d %02d %d %02d %d%s ",
              $year % 100, $year + 1900, $mon+1, $mon+1,
              $mday, $mday, $mday, LJ::Lang::day_ord($mday));
    $ret .= $hour < 12 ? "AM " : "PM ";
    $ret .= sprintf("%02d %d %02d %d %02d", $min,
                    ($hour+11)%12 + 1,
                    ($hour+ 11)%12 +1,
                    $hour,
                    $hour);

    return $ret;
}


# <LJFUNC>
# name: LJ::TimeUtil->alldatepart_s2
# des: Gets date in MySQL format, produces s2dateformat.
# class: time
# args:
# des-:
# info: s2 dateformat is: yyyy mm dd hh mm ss day_of_week
# returns:
# </LJFUNC>
sub alldatepart_s2 {
    my ($class, $time) = @_;
    my ($sec,$min,$hour,$mday,$mon,$year,$wday) =
        gmtime(LJ::TimeUtil->mysqldate_to_time($time, 1));
    return
        sprintf("%04d %02d %02d %02d %02d %02d %01d",
                $year+1900,
                $mon+1,
                $mday,
                $hour,
                $min,
                $sec,
                $wday);
}

# <LJFUNC>
# name: LJ::TimeUtil->statushistory_time
# des: Convert a time like "20070401120323" to "2007-04-01 12:03:23".
# class: time
# args:
# des-:
# info: Only [dbtable[statushistory]] currently formats dates like this.
# returns:
# </LJFUNC>
sub statushistory_time {
    my ($class, $time) = @_;
    $time =~ s/(\d{4})(\d\d)(\d\d)(\d\d)(\d\d)(\d\d)/$1-$2-$3 $4:$5:$6/;
    return $time;
}

# <LJFUNC>
# class: time
# name: LJ::TimeUtil->ago_text
# des: Converts integer seconds to English time span
# info: Turns a number of seconds into the largest possible unit of
#       time. "2 weeks", "4 days", or "20 hours".
# returns: A string with the number of largest units found
# args: secondsold
# des-secondsold: The number of seconds from now something was made.
# </LJFUNC>
# Time formatting rules explained here: LJSUP-11003
sub ago_text {
    my ($class, $secondsold) = @_;
    return LJ::Lang::ml('time.ago.never') unless $secondsold >= 0;

    my ($num, $unit);

    my $mlcache = $LJ::REQ_GLOBAL{'ago_text_ml_cache'} ||= {
        map { $_ => [] } qw{ year month week day hour minute }
    };

    use integer;

    # Year
    if ( $secondsold >= 60 * 60 * 24 * 365 ) {

        $secondsold /= (60 * 60 * 24 * 365 );
        # Array $mlcache->{'time.ago.year'}[] is autovivified on first pass
        # same trick below
        return $mlcache->{'year'}[$secondsold] ||= LJ::Lang::ml('time.ago.year', { num => $secondsold });

    # Month
    } elsif ( $secondsold >= 60 * 60 * 24 * 30 ) {

        $secondsold /= (60 * 60 * 24 * 30);
        return $mlcache->{'month'}[$secondsold] ||= LJ::Lang::ml('time.ago.month', { num => $secondsold });

    # Week
    } elsif ( $secondsold >= 60 * 60 * 24 * 7 ) {

        $secondsold /= (60 * 60 * 24 * 7);
        return $mlcache->{'week'}[$secondsold] ||= LJ::Lang::ml('time.ago.week', { num => $secondsold });

    # Day
    } elsif ( $secondsold >= 60 * 60 * 24 ) {

        $secondsold /= (60 * 60 * 24);
        return $mlcache->{'day'}[$secondsold] ||= LJ::Lang::ml('time.ago.day', { num => $secondsold });

    # Hour
    } elsif ( $secondsold >= 60 * 60 ) {

        $secondsold /= (60 * 60);
        return $mlcache->{'hour'}[$secondsold] ||= LJ::Lang::ml('time.ago.hour', { num => $secondsold });

    # Half hour
    } elsif ( $secondsold >= 60 * 30 ) {

        return $mlcache->{'halfhour'} ||= LJ::Lang::ml('time.ago.halfhour');

    # Minute
    } elsif ( $secondsold >= 60 ) {

        $secondsold /= 60;
        return $mlcache->{'minute'}[$secondsold] ||= LJ::Lang::ml('time.ago.minute', { num => $secondsold });

    } else {
        return $mlcache->{'rightnow'} ||= LJ::Lang::ml('time.ago.rightnow');
    }
}

# Given a year, month, and day; calculate the age in years compared to now. May return a negative number or
# zero if called in such a way as would cause those.

sub calc_age {
    my ($class, $year, $mon, $day) = @_;

    $year += 0; # Force all the numeric context, so 0s become false.
    $mon  += 0;
    $day  += 0;

    my ($cday, $cmon, $cyear) = (gmtime)[3,4,5];
    $cmon  += 1;    # Normalize the month to 1-12
    $cyear += 1900; # Normalize the year

    return unless $year;
    my $age = $cyear - $year;

    return $age unless $mon;

    # Sometime this year they will be $age, subtract one if we haven't hit their birthdate yet.
    $age -= 1 if $cmon < $mon;
    return $age unless $day;

    # Sometime this month they will be $age, subtract one if we haven't hit their birthdate yet.
    $age -= 1 if ($cday < $day && $cmon == $mon);

    return $age;
}

=head2 fancy_time_format

Format a UNIX timestamp so that it can be displayed to the user, taking care
of i18n.

 my $timestamp = 1273215570;
 
 print LJ::TimeUtil->fancy_time_format($timestamp, 'day');
    # => April 7 2010
 
 print LJ::TimeUtil->fancy_time_format($timestamp, 'min');
    # => April 7 2010, 10:59
 
 print LJ::TimeUtil->fancy_time_format($timestamp, 'sec');
    # or
 print LJ::TimeUtil->fancy_time_format($timestamp);
    # => April 7 2010, 10:59:30

Related ML variables are: C<esn.month.day_*>.

=cut

sub fancy_time_format {
    my ( $class, $timestamp, $precision, $timezone ) = @_;
    $precision ||= 'sec';
    $timezone ||= 'UTC';

    # DateTime heavily uses Params::Validate to validate incoming parameters,
    # but it gives significant overhead
    local $Params::Validate::NO_VALIDATION = 1;

    my $dt = DateTime->from_epoch(
        'epoch'     => int $timestamp,
        'time_zone' => $timezone,
    );

    my $month_code = lc LJ::Lang::month_short( $dt->month );
    my $day_month  = LJ::Lang::ml( 'esn.month.day_' . $month_code,
        { 'day' => $dt->day } );

    my $ret = $day_month . ' ' . $dt->year;
    return $ret if $precision eq 'day';

    $ret .= sprintf( ', %02d:%02d', $dt->hour, $dt->minute );
    return $ret if $precision eq 'min';

    $ret .= sprintf( ':%02d', $dt->second );
    return $ret if $precision eq 'sec';

    die "unknown precision $precision";
}

sub next_afternoon {
    my ($class, $tz, $after) = @_;

    $after ||= time;

    my $dt = DateTime->from_epoch('epoch' => $after, 'time_zone' => $tz);
    $dt->set( 'hour'    => 12,
              'minute'  => 0,
              'second'  => 0 );

    my $epoch = $dt->epoch;

    return ($epoch > $after ? $epoch : $epoch + 86400);
}

1;
