#!/usr/bin/perl
#

$maint{'bdaymail'} = sub
{
    &connect_db();
    $sth = $dbh->prepare("SELECT userid, user, name, email, allow_contactshow, timeupdate FROM user WHERE bdate IS NOT NULL AND status='A' AND statusvis='V' AND bdate <> '0000-00-00' AND MONTH(NOW())=MONTH(bdate) AND DAYOFMONTH(NOW())=DAYOFMONTH(bdate) AND timeupdate > DATE_SUB(NOW(), INTERVAL 1 MONTH)");
    $sth->execute;
    
    %bday = ();
    my $bdayppl = "";
    while (my ($userid, $user, $name, $email, $allow_contactshow) = $sth->fetchrow_array)
    {
	print "$user ($userid) .. $name .. $email\n";
	open (MAIL, "|$LJ::SENDMAIL");
	print MAIL "From: webmaster\@livejournal.com (LiveJournal.com)\n";
	print MAIL "To: $email ($name)\n";
	print MAIL "Subject: Happy Birthday!\n\n";
	print MAIL "Happy Birthday $name!!\n\n";
	print MAIL "According to our records, today is your birthday... everybody here at LiveJournal.com would like to wish you a happy birthday!\n\n";
	print MAIL "If you got any interesting birthday stories to share, do let us know!  Or better, email them to us and also update your LiveJournal with them.  :)  And if you have any questions/comments about the LiveJournal service in general, let us know too... we're real people, not a huge corporation, so we read and reply to all email.\n\n";
	print MAIL "Anyway... the point of this email was originally just HAPPY BIRTHDAY!\n\n";
	print MAIL "\nSincerely,\nLiveJournal.com Team\n\n--\nLiveJournal\nhttp://www.livejournal.com/\n";
	close MAIL;
	$bday{$user} = { 'user' => $user, 
			 'name' => $name, 
			 'email' => $email, 
			 'contactshow' => $allow_contactshow };
	$bdayppl .= "$userid,";
    }

    chop $bdayppl;
    my %friends = ();
    print $bdayppl, "\n";
    $sth = $dbh->prepare("SELECT uu.user AS 'user', uf.user AS 'friend' FROM friends f, user uu, user uf WHERE f.userid=uu.userid AND uf.userid=f.friendid AND f.friendid IN ($bdayppl)");
    $sth->execute;
    while (($user, $friend) = $sth->fetchrow_array)
    {
	print "$user -> $friend\n";
	push @{$friends{$user}}, $friend;
    }

    $friendppl = join(", ", map { $dbh->quote($_) } keys %friends);
    $sth = $dbh->prepare("SELECT user, name, email FROM user WHERE status='A' and statusvis='V' AND user IN ($friendppl)");
    $sth->execute;
    while (($user, $name, $email) = $sth->fetchrow_array)
    {
	foreach $friend (grep { $user ne $_  } @{$friends{$user}})
	{
	    print "Mail $user about $friend...\n";
	    open (MAIL, "|$LJ::SENDMAIL");
	    print MAIL "From: webmaster\@livejournal.com (LiveJournal.com)\n";
	    print MAIL "To: $email ($name)\n";
	    print MAIL "Subject: Birthday Reminder!\n\n";
	    print MAIL "$name,\n\n";
	    $s = $bday{$friend}->{'name'} =~ /s$/i ? "'" : "'s";
	    print MAIL "This is a reminder that today is $bday{$friend}->{'name'}$s birthday (LiveJournal user: $friend).  You have $bday{$friend}->{'name'} listed as a friend in your LiveJournal, so we thought this reminder would be useful.\n";
	    if ($bday{$friend}->{'contactshow'} eq "Y") {
		print MAIL "\nIf you'd like to mail this person and wish them a happy birthday, their email address is:\n\n       $bday{$friend}->{'email'}\n\n";
	    }
	    print MAIL "\nSincerely,\nLiveJournal.com Team\n\n--\nLiveJournal\nhttp://www.livejournal.com/\n";
	    close MAIL;
	}
    }

};

1;
