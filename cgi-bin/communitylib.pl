#!/usr/bin/perl

package LJ;

use strict;

# <LJFUNC>
# name: LJ::leave_community
# des: Makes a user leave a community.  Takes care of all reluser and friend stuff.
# args: uuserid, ucommid, defriend
# des-uuserid: a userid or u object of the user doing the leaving
# des-ucommid: a userid or u object of the community being left
# des-defriend: remove comm from user's friends list
# returns: 1 if success, undef if error of some sort (ucommid not a comm, uuserid not in
#   comm, db error, etc)
# </LJFUNC>
sub leave_community {
    my ($uuid, $ucid, $defriend) = @_;
    my $u = LJ::want_user($uuid);
    my $cu = LJ::want_user($ucid);
    $defriend = $defriend ? 1 : 0;
    return LJ::error('comm_not_found') unless $u && $cu;

    # defriend comm -> user
    return LJ::error('comm_not_comm') unless $cu->{journaltype} eq 'C';
    my $ret = LJ::delete_friend_edge($cu->{userid}, $u->{userid});
    return LJ::error('comm_not_member') unless $ret; # $ret = number of rows deleted, should be 1 if the user was in the comm

    # clear edges that effect this relationship
    LJ::clear_rel($cu->{userid}, $u->{userid}, 'P'); # posting access
    LJ::clear_rel($cu->{userid}, $u->{userid}, 'N'); # unmoderated flag

    # defriend user -> comm?
    return 1 unless $defriend;
    LJ::friends_do($u->{userid}, 'DELETE FROM friends WHERE userid=? AND friendid=?',
                   $u->{userid}, $cu->{userid});

    # don't care if we failed the removal of comm from user's friends list...
    return 1;
}

# <LJFUNC>
# name: LJ::join_community
# des: Makes a user join a community.  Takes care of all reluser and friend stuff.
# args: uuserid, ucommid, friend?
# des-uuserid: a userid or u object of the user doing the joining
# des-ucommid: a userid or u object of the community being joined
# des-friend: 1 to add this comm to user's friends list, else not
# returns: 1 if success, undef if error of some sort (ucommid not a comm, uuserid already in
#   comm, db error, etc)
# </LJFUNC>
sub join_community {
    my ($uuid, $ucid, $friend) = @_;
    my $u = LJ::want_user($uuid);
    my $cu = LJ::want_user($ucid);
    my $crow = LJ::get_community_row($cu);
    $friend = $friend ? 1 : 0;
    return LJ::error('comm_not_found') unless $u && $cu && ref $crow;
   
    # friend comm -> user
    return LJ::error('comm_not_comm') unless $cu->{journaltype} eq 'C';
    LJ::add_friend($cu->{userid}, $u->{userid});

    # add edges that effect this relationship
    LJ::set_rel($cu->{userid}, $u->{userid}, 'P') if $crow->{postlevel} eq 'members';

    # friend user -> comm?
    return 1 unless $friend;
    LJ::add_friend($u->{userid}, $cu->{userid}, { defaultview => 1 });

    # done
    return 1;
}

# <LJFUNC>
# name: LJ::get_community_row
# des: Gets data relevant to a community such as their membership level and posting access.
# args: ucommid
# des-ucommid: a userid or u object of the community
# returns: a hashref with user, userid, name, membership, and postlevel data from the
#   user and community tables; undef if error
# </LJFUNC>
sub get_community_row {
    my $ucid = shift;
    my $cu = LJ::want_user($ucid);
    return unless $cu;

    # hit up database
    my $dbr = LJ::get_db_reader();
    my ($membership, $postlevel) = 
        $dbr->selectrow_array('SELECT membership, postlevel FROM community WHERE userid=?',
                              undef, $cu->{userid});
    return if $dbr->err;
    return unless $membership && $postlevel;

    # return result hashref
    my $row = {
        user => $cu->{user},
        userid => $cu->{userid},
        name => $cu->{name},
        membership => $membership,
        postlevel => $postlevel,
    };
    return $row;
}

# <LJFUNC>
# name: LJ::get_pending_members
# des: Gets a list of userids for people that have requested to be added to a community
#   but haven't yet actually been approved or rejected.
# args: comm
# des-comm: a userid or u object of the community to get pending members of
# returns: an arrayref of userids of people with pending membership requests
# </LJFUNC>
sub get_pending_members {
    my $comm = shift;
    my $cu = LJ::want_user($comm);
    
    # database request
    my $dbr = LJ::get_db_reader();
    my $args = $dbr->selectcol_arrayref('SELECT arg1 FROM authactions WHERE userid = ? ' .
                                        "AND action = 'comm_join_request' AND used = 'N'",
                                        undef, $cu->{userid}) || [];

    # parse out the args
    my @list;
    foreach (@$args) {
        push @list, $1+0 if $_ =~ /^targetid=(\d+)$/;
    }
    return \@list;
}

# <LJFUNC>
# name: LJ::approve_pending_member
# des: Approves someone's request to join a community.  This updates the authactions table
#   as appropriate as well as does the regular join logic.  This also generates an email to
#   be sent to the user notifying them of the acceptance.
# args: commid, userid
# des-commid: userid of the community
# des-userid: userid of the user doing the join
# returns: 1 on success, 0/undef on error
# </LJFUNC>
sub approve_pending_member {
    my ($commid, $userid) = @_;
    my $cu = LJ::want_user($commid);
    my $u = LJ::want_user($userid);
    return unless $cu && $u;

    # step 1, update authactions table
    my $dbh = LJ::get_db_writer();
    my $count = $dbh->do("UPDATE authactions SET used = 'Y' WHERE userid = ? AND arg1 = ?",
                         undef, $cu->{userid}, "targetid=$u->{userid}");
    return unless $count;

    # step 2, make user join the community
    return unless LJ::join_community($u->{userid}, $cu->{userid});

    # step 3, email the user
    my $email = "Dear $u->{name},\n\n" .
                "Your request to join the \"$cu->{user}\" community has been approved.  If you " .
                "wish to add this community to your friends page reading list, click the link below.\n\n" .
                "\t$LJ::SITEROOT/friends/add.bml?user=$cu->{user}\n\n" .
                "Regards,\n$LJ::SITENAME Team";
    LJ::send_mail({
        to => $u->{email},
        from => $LJ::COMMUNITY_EMAIL,
        fromname => $LJ::SITENAME,
        charset => 'utf-8',
        subject => "Your Request to Join $cu->{user}",
        body => $email,
    });
    return 1;
}

# <LJFUNC>
# name: LJ::reject_pending_member
# des: Rejects someone's request to join a community.  Updates authactions and generates
#   an email to the user.
# args: commid, userid
# des-commid: userid of the community
# des-userid: userid of the user doing the join
# returns: 1 on success, 0/undef on error
# </LJFUNC>
sub reject_pending_member {
    my ($commid, $userid) = @_;
    my $cu = LJ::want_user($commid);
    my $u = LJ::want_user($userid);
    return unless $cu && $u;

    # step 1, update authactions table
    my $dbh = LJ::get_db_writer();
    my $count = $dbh->do("UPDATE authactions SET used = 'Y' WHERE userid = ? AND arg1 = ?",
                         undef, $cu->{userid}, "targetid=$u->{userid}");
    return unless $count;

    # step 2, email the user
    my $email = "Dear $u->{name},\n\n" .
                "Your request to join the \"$cu->{user}\" community has been declined.  You " .
                "may wish to contact the maintainer(s) of this community if you are still " .
                "interested in joining.\n\n" .
                "Regards,\n$LJ::SITENAME Team";
    LJ::send_mail({
        to => $u->{email},
        from => $LJ::COMMUNITY_EMAIL,
        fromname => $LJ::SITENAME,
        charset => 'utf-8',
        subject => "Your Request to Join $cu->{user}",
        body => $email,
    });
    return 1;
}

# <LJFUNC>
# name: LJ::comm_join_request
# des: Registers an authaction to add a user to a
#      community and sends an approval email to the maintainers
# returns: Hashref; output of LJ::register_authaction()
#          includes datecreate of old row if no new row was created
# args: comm, u
# des-comm: Community user object
# des-u: User object to add to community
# </LJFUNC>
sub comm_join_request {
    my ($comm, $u) = @_;
    return undef unless ref $comm && ref $u;

    my $arg = "targetid=$u->{userid}";
    my $dbh = LJ::get_db_writer();

    # check for duplicates within the same hour (to prevent spamming)
    my $oldaa = $dbh->selectrow_hashref("SELECT aaid, authcode, datecreate FROM authactions " .
                                        "WHERE userid=? AND arg1=? " .
                                        "AND action='comm_join_request' AND used='N' " .
                                        "AND NOW() < datecreate + INTERVAL 1 HOUR " .
                                        "ORDER BY 1 DESC LIMIT 1",
                                        undef, $comm->{'userid'}, $arg);
    return $oldaa if $oldaa;

    # insert authactions row
    my $aa = LJ::register_authaction($comm->{'userid'}, 'comm_join_request', $arg);
    return undef unless $aa;

    # if there are older duplicates, invalidate any existing unused authactions of this type
    $dbh->do("UPDATE authactions SET used='Y' WHERE userid=? AND aaid<>? AND arg1=? " .
             "AND action='comm_invite' AND used='N'",
             undef, $comm->{'userid'}, $aa->{'aaid'}, $arg);

    # get maintainers of community
    my $adminids = LJ::load_rel_user($comm->{userid}, 'A') || [];
    my $admins = LJ::load_userids(@$adminids);

    # now prepare the emails
    my %dests;
    my $cuser = $comm->{user};
    foreach my $au (values %$admins) {
        next if $dests{$au->{email}}++;
        LJ::load_user_props($au, 'opt_communityjoinemail');
        next if $au->{opt_communityjoinemail} =~ /[DN]/; # Daily, None
        
        my $body = "Dear $au->{name},\n\n" .
                   "The user \"$u->{user}\" has requested to join the \"$cuser\" community.  If you wish " .
                   "to add this user to your community, please click this link:\n\n" .
                   "\t$LJ::SITEROOT/approve/$aa->{aaid}.$aa->{authcode}\n\n" .
                   "Alternately, to approve or reject all outstanding membership requests at the same time, " .
                   "visit the community member management page:\n\n" .
                   "\t$LJ::SITEROOT/community/pending.bml?comm=$cuser\n\n" .
                   "You may also ignore this e-mail.  The request to join will expire after a period of 30 days.\n\n" .
                   "If you wish to no longer receive these e-mails, visit the community management page and " .
                   "set the relevant options:\n\n\t$LJ::SITEROOT/community/manage.bml\n\n" .
                   "Regards,\n$LJ::SITENAME Team\n";

        LJ::send_mail({
            to => $au->{email},
            from => $LJ::COMMUNITY_EMAIL,
            fromname => $LJ::SITENAME,
            charset => 'utf-8',
            subject => "$cuser Membership Request by $u->{user}",
            body => $body,
            wrap => 76,
        });
    }

    return $aa;
}

1;
