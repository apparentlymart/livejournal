#!/usr/bin/perl
#

use strict;
package LJ::S2;

sub ArchiveYearPage
{
    my ($u, $remote, $opts) = @_;

    my $p = Page($u, $opts->{'vhost'});
    $p->{'_type'} = "ArchiveYearPage";
    $p->{'view'} = "archive";
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
        push @{$p->{'years'}}, ArchiveYearYear($_, "$p->{'base_url'}/calendar/$_", $_ == $p->{'year'});
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
                '_type' => 'ArchiveYearWeek',
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

        $calmon = ArchiveYearMonth({
            'month' => $month,
            'year' => $year, 
            'url' => "$LJ::SITEROOT/view/?type=month&user=$p->{'journal'}->{'username'}&y=$year&m=$month",
            'weeks' => [],
            'has_entries' => $has_entries,
        });

        for my $day (1..$daysinmonth) {
            my $d = ArchiveYearDay($u, $year, $month, $day, 
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

sub ArchiveYearMonth {
    my $opts = shift;
    $opts->{'_type'} = 'ArchiveYearMonth';
    return $opts;
}

sub ArchiveYearYear {
    my ($year, $url, $displayed) = @_;
    return { '_type' => "ArchiveYearYear",
             'year' => $year, 'url' => $url, 'displayed' => $displayed };
}

1;

sub ArchiveYearDay {
    my ($u, $year, $month, $day, $count, $dow) = @_;
    my $d = {
        '_type' => 'ArchiveYearDay',
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



