#!/usr/bin/perl
#

$maint{joinmail} = sub {
    my $dbr = LJ::get_db_reader();

    # get all information
    my $pending = $dbr->selectall_arrayref("SELECT userid, COUNT(arg1) FROM authactions " .
                                           "WHERE used = 'N' AND datecreate > DATE_SUB(NOW(), INTERVAL 1 DAY)" .
                                           "GROUP BY userid") || [];

    # get userids of communities
    my @commids;
    push @commids, $_->[0]+0 foreach @$pending;
    my $cus = LJ::load_userids(@commids);

    # now let's get the maintainers of these
    my $in = join ',', @commids;
    my $maintrows = $dbr->selectall_arrayref("SELECT userid, targetid FROM reluser WHERE userid IN ($in) AND type = 'A'") || [];
    my @maintids;
    my %maints;
    foreach (@$maintrows) {
        push @{$maints{$_->[0]}}, $_->[1];
        push @maintids, $_->[1];
    }
    my $mus = LJ::load_userids(@maintids);
 
    # tell the maintainers that they got new people.
    foreach my $row (@$pending) {
        my $cuser = $cus->{$row->[0]}{user};
        print "$cuser: $row->[1] invites: ";
        my %email; # see who we emailed on this comm
        foreach my $mid (@{$maints{$row->[0]}}) {
            print "$mid ";
            next if $email{$mus->{$mid}{email}}++;
            LJ::load_user_props($mus->{$mid}, 'opt_communityjoinemail');
            next unless $mus->{$mid}{opt_communityjoinemail} eq 'D'; # Daily or Digest
        
            my $body = "Dear $mus->{$mid}{user},\n\n" .
                       "Over the past day or so, $row->[1] request(s) to join the \"$cuser\" community have " .
                       "been received.  To look at the currently pending membership requests, please visit the pending " .
                       "membership page:\n\n" .
                       "\t$LJ::SITEROOT/community/pending.bml?comm=$cuser\n\n" .
                       "You may also ignore this email.  Outstanding requests to join will expire after a period of 30 days.\n\n" .
                       "If you wish to no longer receive these emails, visit the community management page and " .
                       "set the relevant options:\n\n\t$LJ::SITEROOT/community/manage.bml\n\n" .
                       "Regards,\n$LJ::SITENAME Team\n";

            LJ::send_mail({
                to => $mus->{$mid}{email},
                from => $LJ::COMMUNITY_EMAIL,
                fromname => $LJ::SITENAME,
                charset => 'utf-8',
                subject => "$cuser Membership Requests",
                body => $body,
                wrap => 76,
            });
        }
        print "\n";
    }
};

1;
