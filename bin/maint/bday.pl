#!/usr/bin/perl
#

use strict;
use vars qw(%maint);

$maint{'bdaymail'} = sub
{
    my $dbr = LJ::get_db_reader();
    my $sth;
    
    # get everybody whose birthday is today.
    $sth = $dbr->prepare("SELECT u.userid, u.user, u.name, u.email ".
                         "FROM user u, userusage uu WHERE u.userid=uu.userid AND ".
                         "u.bdate IS NOT NULL AND u.status='A' AND ".
                         "u.statusvis='V' AND u.bdate <> '0000-00-00' AND ".
                         "MONTH(NOW())=MONTH(u.bdate) AND DAYOFMONTH(NOW())=DAYOFMONTH(u.bdate) ".
                         "AND uu.timeupdate > DATE_SUB(NOW(), INTERVAL 1 MONTH) AND ".
                         "u.journaltype='P'");
    $sth->execute;
    my @bdays; push @bdays, $_ while ($_ = $sth->fetchrow_hashref);
    $sth->finish;

    # go through each birthday person and tell them happy birthday.
    foreach my $bu (@bdays)
    {
        my ($user, $userid, $name, $email) = map { $bu->{$_} } qw(user userid name email);
        print "$user ($userid) .. $name .. $email\n";

        LJ::send_mail({
            'to' => $email,
            'toname' => $name,
            'subject' => "Happy Birthday!",
            'from' => $LJ::ADMIN_EMAIL,
            'fromname' => $LJ::SITENAME,
            'body' => ("Happy Birthday $name!!\n\n".
                       "According to our records, today is your birthday... everybody here ".
                       "at $LJ::SITENAME would like to wish you a happy birthday!\n\n".
                       "If you have any interesting birthday stories to share, do let us know!  ".
                       "Or better, email them to us and also update your LiveJournal with them.  ".
                       ":)  And if you have any questions/comments about the service in general, ".
                       "let us know too... we're real people, not a huge corporation, so we read ".
                       "and try to reply to all email.\n\n".
                       "Anyway... the point of this email was originally just HAPPY BIRTHDAY!\n\n".
                       "--\n$LJ::SITENAME\n$LJ::SITEROOT/\n"),
        });

        # and now, tell people that list them as friends.
        $sth = $dbr->prepare("SELECT u.user, u.name, u.email ".
                             "FROM user u, friends f, userprop up, userproplist upl, userusage uu ".
                             "WHERE f.friendid=$userid AND f.userid=u.userid AND ".
                             "up.userid=u.userid AND upl.upropid=up.upropid AND uu.userid=u.userid AND ".
                             "upl.name='opt_bdaymail' AND up.value='1' AND ".
                             "u.journaltype='P' AND u.status='A' AND u.statusvis='V' AND ".
                             "uu.timeupdate>DATE_SUB(NOW(), INTERVAL 1 MONTH) AND ".
                             "u.userid <> $userid");
        $sth->execute;
        if ($dbr->err) { die $dbr->errstr; }
        my @friendof; push @friendof, $_ while ($_ = $sth->fetchrow_hashref);

        # possesive es
        my $s = ($name =~ /s$/i) ? "'" : "'s";

        foreach my $fu (@friendof)
        {
            my ($fuser, $fname, $femail) = map { $fu->{$_} } qw(user name email);	    
            print "  mail $fuser about $user...\n";

            LJ::send_mail({
                'to' => $femail,
                'toname' => $fname,
                'subject' => "Birthday Reminder!",
                'from' => $LJ::ADMIN_EMAIL,
                'fromname' => $LJ::SITENAME,
                'body' => ("This is a reminder that today is $name$s birthday ".
                           "(LiveJournal user: $user).  You have $name listed as ".
                           "a friend in your LiveJournal, so we thought this ".
                           "reminder would be useful.".
                           "\n\n--\n$LJ::SITENAME\n$LJ::SITEROOT/\n"),
            });
        }
    }

};

1;
