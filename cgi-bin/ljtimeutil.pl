package LJ;
use strict;

### THIS MODULE IS DEPRECATED. USE LJ::TimeUtil INSTEAD. ###

use LJ::TimeUtil;

sub days_in_month { LJ::TimeUtil->days_in_month(@_); }
sub day_of_week { LJ::TimeUtil->day_of_week(@_); }
sub http_to_time { LJ::TimeUtil->http_to_time(@_); }
sub mysqldate_to_time { LJ::TimeUtil->mysqldate_to_time(@_); }
sub time_to_http { LJ::TimeUtil->time_to_http(@_); }
sub time_to_cookie { LJ::TimeUtil->time_to_cookie(@_); }
sub time_to_w3c { LJ::TimeUtil->time_to_w3c(@_); }
sub mysql_time { LJ::TimeUtil->mysql_time(@_); }
sub alldatepart_s1 { LJ::TimeUtil->alldatepart_s1(@_); }
sub alldatepart_s2 { LJ::TimeUtil->alldatepart_s2(@_); }
sub statushistory_time { LJ::TimeUtil->statushistory_time(@_); }
sub ago_text { LJ::TimeUtil->ago_text(@_); }
sub calc_age { LJ::TimeUtil->calc_age(@_); }

1;
