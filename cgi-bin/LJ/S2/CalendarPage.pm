#!/usr/bin/perl
#

use strict;
package LJ::S2;

sub CalendarPage
{
    my ($u, $remote, $opts) = @_;

    my $p = Page($u, $opts->{'vhost'});
    $p->{'_type'} = "CalendarPage";
    $p->{'view'} = "calendar";
    $p->{'weekdays'} = [ 1..7 ];

    my $dbs = LJ::get_dbs();
    my $dbh = $dbs->{'dbh'};
    my $dbr = $dbs->{'reader'};
    my $dbcr;
    if ($u->{'clusterid'}) {
        $dbcr = LJ::get_cluster_reader($u);
    }
    my $user = $u->{'user'};

    if ($u->{'journaltype'} eq "R" && $u->{'renamedto'} ne "") {
        $opts->{'redir'} = LJ::journal_base($u->{'renamedto'}, $opts->{'vhost'}) .
            "/calendar" . $opts->{'pathextra'};
        return 1;
    }

    if ($u->{'opt_blockrobots'}) {
        $p->{'head_content'} = "<meta name=\"robots\" content=\"noindex\">\n";
    }
    if ($LJ::UNICODE) {
        $p->{'head_content'} .= '<meta http-equiv="Content-Type" content="text/html; charset='.$opts->{'saycharset'}."\">\n";
    }

    my %FORM = ();
    LJ::decode_url_string($opts->{'args'}, \%FORM);

    my ($db, $sql);
    if ($u->{'clusterid'}) {
        $db = LJ::get_cluster_reader($u);
        $sql = "SELECT year, month, day, COUNT(*) AS 'count' ".
            "FROM log2 WHERE journalid=? ".
            "GROUP BY year, month, day";
    } else {
        $db = $dbr;
        $sql = "SELECT year, month, day, COUNT(*) AS 'count' ".
            "FROM log WHERE ownerid=? ".
            "GROUP BY year, month, day";
    }
    
    my $sth = $db->prepare($sql);
    $sth->execute($u->{'userid'});

    my (%count, $maxyear);
    while (my ($year, $month, $day, $count) = $sth->fetchrow_array) {
        $count{$year}->{$month}->{$day} = $count;
        if ($year > $maxyear) { $maxyear = $year; }
    }

    my @years = sort { $a <=> $b } keys %count;
    my $year = $FORM{'year'};  # old form was /users/<user>/calendar?year=1999

    # but the new form is purtier:  */calendar/2001
    if (! $year && $opts->{'pathextra'} =~ m!^/(\d\d\d\d)/?\b!) {
        $year = $1;
    }

    # else... default to the year they last posted.
    $year ||= $maxyear;  

    my $start_monday = 0;  # FIXME: check some property to see if weeks start on monday

    $p->{'year'} = $year;
    $p->{'years'} = [];
    foreach (@years) {
        push @{$p->{'years'}}, CalendarPageYear($_, "$p->{'base_url'}/calendar/$_", $_ == $p->{'year'});
    }

    $p->{'months'} = [];

    my $calmon = undef;
    my $week = undef;

    my $flush_week = sub {
        my $end_month = shift;
        return unless $week;
        push @{$calmon->{'weeks'}}, $week;
        if ($end_month) {
            $week->{'post_empty'} = 
                7 - $week->{'pre_empty'} - @{$week->{'days'}};
        }
        $week = undef;
    };

    my $push_day = sub {
        my $d = shift;
        unless ($week) {
            my $leading = $d->{'date'}->{'_dayofweek'}-1;
            if ($start_monday) {
                $leading = 6 if --$leading < 0;
            }
            $week = {
                '_type' => 'CalendarPageWeek',
                'days' => [],
                'pre_empty' => $leading,
                'post_empty' => 0,
            };
        }
        push @{$week->{'days'}}, $d;
        if ($week->{'pre_empty'} + @{$week->{'days'}} == 7) {
            $flush_week->();
            my $size = scalar @{$calmon->{'weeks'}};
        }
    };

    my $day_of_week = LJ::day_of_week($year, 1, 1);

    for my $month (1..12) {
        my $has_entries = $count{$year}->{$month} ? 1 : 0;
        my $daysinmonth = LJ::days_in_month($month, $year);

        $calmon = CalendarPageMonth({
            'month' => $month,
            'year' => $year, 
            'url' => "$LJ::SITEROOT/view/?type=month&user=$p->{'journal'}->{'username'}&y=$year&m=$month",
            'weeks' => [],
            'has_entries' => $has_entries,
        });

        for my $day (1..$daysinmonth) {
            my $d = CalendarPageDay($u, $year, $month, $day, 
                                    $count{$year}->{$month}->{$day},
                                    $day_of_week+1);
            $push_day->($d);
            $day_of_week = ($day_of_week + 1) % 7;
        }
        $flush_week->(1); # end of month flag

        push @{$p->{'months'}}, $calmon;
    }

    return $p;
}

sub CalendarPageMonth {
    my $opts = shift;
    $opts->{'_type'} = 'CalendarPageMonth';
    return $opts;
}

sub CalendarPageYear {
    my ($year, $url, $displayed) = @_;
    return { '_type' => "CalendarPageYear",
             'year' => $year, 'url' => $url, 'displayed' => $displayed };
}

1;

sub CalendarPageDay {
    my ($u, $year, $month, $day, $count, $dow) = @_;
    my $d = {
        '_type' => 'CalendarPageDay',
        'day' => $day,
        'date' => Date($year, $month, $day, $dow),
        'num_entries' => $count
    };
    if ($count) {
        $d->{'url'} = sprintf("$u->{'_journalbase'}/day/$year/%02d/%02d",
                              $month, $day);
    }
    return $d;
}

__END__

sub create_view_calendar
{
    my ($dbs, $ret, $u, $vars, $remote, $opts) = @_;

    if ($u->{'opt_blockrobots'}) {
        $calendar_page{'head'} = "<meta name=\"robots\" content=\"noindex\">\n";
    }
    if ($LJ::UNICODE) {
        $calendar_page{'head'} .= '<meta http-equiv="Content-Type" content="text/html; charset='.$opts->{'saycharset'}.'">';
    }

    unless ($db) {
        $opts->{'errcode'} = "nodb";
        $$ret = "";
        return 0;
    }

    my $sth = $db->prepare($sql);
    $sth->execute;

    my (%count, %dayweek, $year, $month, $day, $dayweek, $count);
    while (($year, $month, $day, $dayweek, $count) = $sth->fetchrow_array)
    {
        $count{$year}->{$month}->{$day} = $count;
        $dayweek{$year}->{$month}->{$day} = $dayweek;
        if ($year > $maxyear) { $maxyear = $year; }
    }

    my @allyears = sort { $b <=> $a } keys %count;
    if ($vars->{'CALENDAR_SORT_MODE'} eq "forward") { @allyears = reverse @allyears; }

    my @years = ();
    my $dispyear = $FORM{'year'};  # old form was /users/<user>/calendar?year=1999

    # but the new form is purtier:  */calendar/2001
    unless ($dispyear) {
        if ($opts->{'pathextra'} =~ m!^/(\d\d\d\d)/?\b!) {
            $dispyear = $1;
        }
    }

    # else... default to the year they last posted.
    $dispyear ||= $maxyear;  

    # we used to show multiple years.  now we only show one at a time:  (hence the @years confusion)
    if ($dispyear) { push @years, $dispyear; }  

    if (scalar(@allyears) > 1) {
        my $yearlinks = "";
        foreach my $year (@allyears) {
            my $yy = sprintf("%02d", $year % 100);
            my $url = "$journalbase/calendar/$year";
            if ($year != $dispyear) { 
                $yearlinks .= LJ::fill_var_props($vars, 'CALENDAR_YEAR_LINK', {
                    "url" => $url, "yyyy" => $year, "yy" => $yy });
            } else {
                $yearlinks .= LJ::fill_var_props($vars, 'CALENDAR_YEAR_DISPLAYED', {
                    "yyyy" => $year, "yy" => $yy });
            }
        }
        $calendar_page{'yearlinks'} = 
            LJ::fill_var_props($vars, 'CALENDAR_YEAR_LINKS', { "years" => $yearlinks });
    }

    foreach $year (@years)
    {
        $$months .= LJ::fill_var_props($vars, 'CALENDAR_NEW_YEAR', {
          'yyyy' => $year,
          'yy' => substr($year, 2, 2),
        });

        my @months = sort { $b <=> $a } keys %{$count{$year}};
        if ($vars->{'CALENDAR_SORT_MODE'} eq "forward") { @months = reverse @months; }
        foreach $month (@months)
        {
          my $daysinmonth = LJ::days_in_month($month, $year);
          
          # TODO: wtf is this doing?  picking a random day that it knows day of week from?  ([0] from hash?)
          my $firstday = (%{$count{$year}->{$month}})[0];

          # go backwards from first day
          my $dayweek = $dayweek{$year}->{$month}->{$firstday};
          for (my $i=$firstday-1; $i>0; $i--)
          {
              if (--$dayweek < 1) { $dayweek = 7; }
              $dayweek{$year}->{$month}->{$i} = $dayweek;
          }
          # go forwards from first day
          $dayweek = $dayweek{$year}->{$month}->{$firstday};
          for (my $i=$firstday+1; $i<=$daysinmonth; $i++)
          {
              if (++$dayweek > 7) { $dayweek = 1; }
              $dayweek{$year}->{$month}->{$i} = $dayweek;
          }

          my %calendar_month = ();
          $calendar_month{'monlong'} = LJ::Lang::month_long($u->{'lang'}, $month);
          $calendar_month{'monshort'} = LJ::Lang::month_short($u->{'lang'}, $month);
          $calendar_month{'yyyy'} = $year;
          $calendar_month{'yy'} = substr($year, 2, 2);
          $calendar_month{'weeks'} = "";
          $calendar_month{'urlmonthview'} = "$LJ::SITEROOT/view/?type=month&user=$user&y=$year&m=$month";
          my $weeks = \$calendar_month{'weeks'};

          my %calendar_week = ();
          $calendar_week{'emptydays_beg'} = "";
          $calendar_week{'emptydays_end'} = "";
          $calendar_week{'days'} = "";

          # start the first row and check for its empty spaces
          my $rowopen = 1;
          if ($dayweek{$year}->{$month}->{1} != 1)
          {
              my $spaces = $dayweek{$year}->{$month}->{1} - 1;
              $calendar_week{'emptydays_beg'} = 
                  LJ::fill_var_props($vars, 'CALENDAR_EMPTY_DAYS', 
                                  { 'numempty' => $spaces });
          }

          # make the days!
          my $days = \$calendar_week{'days'};

          for (my $i=1; $i<=$daysinmonth; $i++)
          {
              $count{$year}->{$month}->{$i} += 0;
              if (! $rowopen) { $rowopen = 1; }

              my %calendar_day = ();
              $calendar_day{'d'} = $i;
              $calendar_day{'eventcount'} = $count{$year}->{$month}->{$i};
              if ($count{$year}->{$month}->{$i})
              {
                $calendar_day{'dayevent'} = LJ::fill_var_props($vars, 'CALENDAR_DAY_EVENT', {
                    'eventcount' => $count{$year}->{$month}->{$i},
                    'dayurl' => "$journalbase/day/" . sprintf("%04d/%02d/%02d", $year, $month, $i),
                });
              }
              else
              {
                $calendar_day{'daynoevent'} = $vars->{'CALENDAR_DAY_NOEVENT'};
              }

              $$days .= LJ::fill_var_props($vars, 'CALENDAR_DAY', \%calendar_day);

              if ($dayweek{$year}->{$month}->{$i} == 7)
              {
                $$weeks .= LJ::fill_var_props($vars, 'CALENDAR_WEEK', \%calendar_week);
                $rowopen = 0;
                $calendar_week{'emptydays_beg'} = "";
                $calendar_week{'emptydays_end'} = "";
                $calendar_week{'days'} = "";
              }
          }

          # if rows is still open, we have empty spaces
          if ($rowopen)
          {
              if ($dayweek{$year}->{$month}->{$daysinmonth} != 7)
              {
                  my $spaces = 7 - $dayweek{$year}->{$month}->{$daysinmonth};
                  $calendar_week{'emptydays_end'} = 
                      LJ::fill_var_props($vars, 'CALENDAR_EMPTY_DAYS', 
                                         { 'numempty' => $spaces });
              }
              $$weeks .= LJ::fill_var_props($vars, 'CALENDAR_WEEK', \%calendar_week);
          }

          $$months .= LJ::fill_var_props($vars, 'CALENDAR_MONTH', \%calendar_month);
        } # end foreach months

    } # end foreach years

    ######## new code

    $$ret .= LJ::fill_var_props($vars, 'CALENDAR_PAGE', \%calendar_page);

    return 1;  
}


