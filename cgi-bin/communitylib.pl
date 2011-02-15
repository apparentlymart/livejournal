#!/usr/bin/perl

package LJ;

use strict;
use Class::Autouse qw(
                      LJ::Event::CommunityInvite
                      LJ::Event::CommunityJoinRequest
                      LJ::Event::CommunityJoinApprove
                      LJ::Event::CommunityJoinReject
                      );

## Create supermaintainer poll
## Args:
##      comm_id           = community id
##      alive_maintainers = array ref of alive maintainers (visible, active, is maintainers, etc)
##      no_job            = nothing to do. only logging.
##      textref           = where save log info
##      to_journal        = which journal save polls to?
## Return:
##      pollid            = id of new created poll
sub create_supermaintainer_election_poll {
    my %args = @_;
    my $comm_id = $args{'comm_id'};
    my $alive_maintainers = $args{'maint_list'};
    my $textref = $args{'log'};
    my $no_job = $args{'no_job'} || 0;
    my $check_active = $args{'check_active'} || 0;
    my $to_journal = $args{'to_journal'} || LJ::load_user('lj_elections');

    my $comm = LJ::load_userid($comm_id);
    my $entry = undef;
    unless ($no_job) {
        $entry = _create_post (to => $to_journal, comm => $comm);
        die "Entry for Poll does not created\n" unless $entry;
        $$textref .= "Entry url: " . $entry->url . "\n";
    }

    my @items = ();
    foreach my $u (@$alive_maintainers) {
        $$textref .= "\tAdd ".$u->user." as item to poll\n";
        push @items, {
            item    => "<lj user='".$u->user."'>",
        };
    }


    my @q = (
        {
            qtext   => LJ::Lang::ml('poll.election.subject'),
            type    => 'radio',
            items   => \@items,
        }
    );

    my $poll = undef;
    unless ($no_job) {
        $poll = LJ::Poll->create (entry => $entry, whovote => 'all', whoview => 'all', questions => \@q)
            or die "Poll was not created";

        eval {
            $poll->set_prop ('createdate' => $entry->eventtime_mysql)
                or die "Can't set prop 'createdate'";

            $poll->set_prop ('supermaintainer' => $comm->userid)
                or die "Can't set prop 'supermaintainer'";

            _edit_post (to => $to_journal, comm => $comm, entry => $entry, poll => $poll) 
                or die "Can't edit post";
        };

        ## ugly, but reliable
        if ($@) {
            print $$textref;
            use Data::Dumper;
            warn Dumper($poll);
            warn Dumper($to_journal);
            die $@;
        }
    }

    ## All are ok. Emailing to all maintainers about election.
    my $subject = LJ::Lang::ml('poll.election.email.subject');
    $$textref .= "Sending emails to all maintainers for community " . $comm->user . "\n";
    foreach my $u (@$alive_maintainers) {
        next unless $u && $u->is_visible && $u->can_manage($comm);
        next if !$check_active && $u->check_activity(90);
        $$textref .= "\tSend email to maintainer ".$u->user."\n";
        LJ::send_mail({ 'to'        => $u->email_raw,
                        'from'      => $LJ::ACCOUNTS_EMAIL,
                        'fromname'  => $LJ::SITENAMESHORT,
                        'wrap'      => 1,
                        'charset'   => $u->mailencoding || 'utf-8',
                        'subject'   => $subject,
                        'html'      => (LJ::Lang::ml('poll.election.start.email', {
                                                username        => LJ::ljuser($u),
                                                communityname   => LJ::ljuser($comm),
                                                faqlink         => '#',
                                                shortsite       => $LJ::SITENAMESHORT,
                                                authas          => $comm->{user},
                                                siteroot        => $LJ::SITEROOT,
                                            })
                                        ),
                        'body'      => (LJ::Lang::ml('poll.election.start.email.plain', {
                                                username        => LJ::ljuser($u),
                                                communityname   => LJ::ljuser($comm),
                                                faqlink         => '#',
                                                shortsite       => $LJ::SITENAMESHORT,
                                                authas          => $comm->{user},
                                                siteroot        => $LJ::SITEROOT,
                                            })
                                        ),
                    }) unless ($no_job);
    }

    return $no_job ? undef : $poll->pollid;
}

sub _edit_post {
    my %opts = @_;

    my $u = $opts{to};
    my $comm = $opts{comm};
    my $entry = $opts{entry};
    my $poll = $opts{poll};

    my $security = delete $opts{security} || 'private';
    my $proto_sec = $security;
    if ($security eq "friends") {
        $proto_sec = "usemask";
    }

    my $subject = delete $opts{subject} || LJ::Lang::ml('poll.election.post_subject');
    my $body    = delete $opts{body}    || LJ::Lang::ml('poll.election.post_body', { comm => $comm->user });

    my %req = (
               mode     => 'editevent',
               ver      => $LJ::PROTOCOL_VER,
               user     => $u->{user},
               password => '',
               event    => $body . "<br/>" . "<lj-poll-".$poll->pollid.">",
               subject  => $subject,
               tz       => 'guess',
               security => $proto_sec,
               itemid   => $entry->jitemid,
               );

    $req{allowmask} = 1 if $security eq 'friends';

    my %res;
    my $flags = { noauth => 1, nomod => 1 };

    LJ::do_request(\%req, \%res, $flags);

    die "Error posting: $res{errmsg}" unless $res{'success'} eq "OK";
    my $jitemid = $res{itemid} or die "No itemid";

    return LJ::Entry->new($u, jitemid => $jitemid);
}

sub _create_post {
    my %opts = @_;

    my $u = $opts{to};
    my $comm = $opts{comm};

    my $security = delete $opts{security} || 'private';
    my $proto_sec = $security;
    if ($security eq "friends") {
        $proto_sec = "usemask";
    }

    my $subject = delete $opts{subject} || LJ::Lang::ml('poll.election.post_subject');
    my $body    = delete $opts{body}    || LJ::Lang::ml('poll.election.post_body', { comm => $comm->user });

    my %req = (
               mode => 'postevent',
               ver => $LJ::PROTOCOL_VER,
               user => $u->{user},
               password => '',
               event => $body,
               subject => $subject,
               tz => 'guess',
               security => $proto_sec,
               );

    $req{allowmask} = 1 if $security eq 'friends';

    my %res;
    my $flags = { noauth => 1, nomod => 1 };

    LJ::do_request(\%req, \%res, $flags);

    die "Error posting: $res{errmsg}" unless $res{'success'} eq "OK";
    my $jitemid = $res{itemid} or die "No itemid";

    return LJ::Entry->new($u, jitemid => $jitemid);
}

# <LJFUNC>
# name: LJ::get_sent_invites
# des: Get a list of sent invitations from the past 30 days.
# args: cuserid
# des-cuserid: a userid or u object of the community to get sent invitations for
# returns: hashref of arrayrefs with keys userid, maintid, recvtime, status, args (itself
#          a hashref of what abilities the user would be given)
# </LJFUNC>
sub get_sent_invites {
    my $cu = shift;
    $cu = LJ::want_user($cu);
    return undef unless $cu;

    # now hit the database for their recent invites
    my $dbcr = LJ::get_cluster_def_reader($cu);
    return LJ::error('db') unless $dbcr;
    my $data = $dbcr->selectall_arrayref('SELECT userid, maintid, recvtime, status, args FROM invitesent ' .
                                         'WHERE commid = ? AND recvtime > UNIX_TIMESTAMP(DATE_SUB(NOW(), INTERVAL 30 DAY))',
                                          undef, $cu->{userid});

    # now break data down into usable format for caller
    my @res;
    foreach my $row (@{$data || []}) {
        my $temp = {};
        LJ::decode_url_string($row->[4], $temp);
        push @res, {
            userid => $row->[0]+0,
            maintid => $row->[1]+0,
            recvtime => $row->[2],
            status => $row->[3],
            args => $temp,
        };
    }

    # all done
    return \@res;    
}

# <LJFUNC>
# name: LJ::send_comm_invite
# des: Sends an invitation to a user to join a community with the passed abilities.
# args: uuserid, cuserid, muserid, attrs
# des-uuserid: a userid or u object of the user to invite.
# des-cuserid: a userid or u object of the community to invite the user to.
# des-muserid: a userid or u object of the maintainer doing the inviting.
# des-attrs: a hashref of abilities this user should have (e.g. member, post, unmoderated, ...)
# returns: 1 for success, undef if failure
# </LJFUNC>
sub send_comm_invite {
    my ($u, $cu, $mu, $attrs) = @_;
    $u = LJ::want_user($u);
    $cu = LJ::want_user($cu);
    $mu = LJ::want_user($mu);
    return undef unless $u && $cu && $mu;

    # step 1: if the user has banned the community, don't accept the invite
    return LJ::error('comm_user_has_banned') if LJ::is_banned($cu, $u);

    # step 2: lazily clean out old community invites.
    return LJ::error('db') unless $u->writer;
    $u->do('DELETE FROM inviterecv WHERE userid = ? AND ' .
           'recvtime < UNIX_TIMESTAMP(DATE_SUB(NOW(), INTERVAL 30 DAY))',
           undef, $u->{userid});

    return LJ::error('db') unless $cu->writer;
    $cu->do('DELETE FROM invitesent WHERE commid = ? AND ' .
            'recvtime < UNIX_TIMESTAMP(DATE_SUB(NOW(), INTERVAL 30 DAY))',
            undef, $cu->{userid});

    my $dbcr = LJ::get_cluster_def_reader($u);
    return LJ::error('db') unless $dbcr;
    my $argstr = $dbcr->selectrow_array('SELECT args FROM inviterecv WHERE userid = ? AND commid = ?',
                                        undef, $u->{userid}, $cu->{userid});

    # step 4: exceeded outstanding invitation limit?  only if no outstanding invite
    unless ($argstr) {
        my $cdbcr = LJ::get_cluster_def_reader($cu);
        return LJ::error('db') unless $cdbcr;
        my $count = $cdbcr->selectrow_array("SELECT COUNT(*) FROM invitesent WHERE commid = ? " .
                                            "AND userid <> ? AND status = 'outstanding'",
                                            undef, $cu->{userid}, $u->{userid});
        my $fr = LJ::get_friends($cu) || {};
        my $max = int(scalar(keys %$fr) / 10); # can invite up to 1/10th of the community
        $max = 50 if $max < 50;                # or 50, whichever is greater
        return LJ::error('comm_invite_limit') if $count > $max;
    }

    # step 5: setup arg string as url-encoded string
    my $newargstr = join('=1&', map { LJ::eurl($_) } @$attrs) . '=1';

    # step 6: branch here to update or insert
    if ($argstr) {
        # merely an update, so just do it quietly
        $u->do("UPDATE inviterecv SET args = ? WHERE userid = ? AND commid = ?",
               undef, $newargstr, $u->{userid}, $cu->{userid});

        $cu->do("UPDATE invitesent SET args = ?, status = 'outstanding' WHERE userid = ? AND commid = ?",
                undef, $newargstr, $cu->{userid}, $u->{userid});
    } else {
         # insert new data, as this is a new invite
         $u->do("INSERT INTO inviterecv VALUES (?, ?, ?, UNIX_TIMESTAMP(), ?)",
                undef, $u->{userid}, $cu->{userid}, $mu->{userid}, $newargstr);

         $cu->do("REPLACE INTO invitesent VALUES (?, ?, ?, UNIX_TIMESTAMP(), 'outstanding', ?)",
                 undef, $cu->{userid}, $u->{userid}, $mu->{userid}, $newargstr);
    }

    # Fire community invite event
    LJ::Event::CommunityInvite->new($u, $mu, $cu)->fire unless $LJ::DISABLED{esn};

    # step 7: error check database work
    return LJ::error('db') if $u->err || $cu->err;

    # success
    return 1;
}

# <LJFUNC>
# name: LJ::accept_comm_invite
# des: Accepts an invitation a user has received.  This does all the work to make the
#      user join the community as well as sets up privileges.
# args: uuserid, cuserid
# des-uuserid: a userid or u object of the user to get pending invites for
# des-cuserid: a userid or u object of the community to reject the invitation from
# returns: 1 for success, undef if failure
# </LJFUNC>
sub accept_comm_invite {
    my ($u, $cu) = @_;
    $u = LJ::want_user($u);
    $cu = LJ::want_user($cu);
    return undef unless $u && $cu;

    # get their invite to make sure they have one
    my $dbcr = LJ::get_cluster_def_reader($u);
    return LJ::error('db') unless $dbcr;
    my ($argstr, $maintid) = $dbcr->selectrow_array('SELECT args, maintid FROM inviterecv WHERE userid = ? AND commid = ? ' .
                                        'AND recvtime > UNIX_TIMESTAMP(DATE_SUB(NOW(), INTERVAL 30 DAY))',
                                        undef, $u->{userid}, $cu->{userid});
    return undef unless $argstr;

    # decode to find out what they get
    my $args = {};
    LJ::decode_url_string($argstr, $args);

    # valid invite.  let's accept it as far as the community listing us goes.
    # 1, 0 means add comm to user's friends list, but don't auto-add P edge.
    if ($args->{'member'}) {
        if (!LJ::join_community($u, $cu, 1, 0)) {
            return LJ::error("Can't call LJ::join_community($u->{user}, $cu->{user})");
        }
    }

    # now grant necessary abilities
    my %edgelist = (
        post => 'P',
        preapprove => 'N',
        moderate => 'M',
        admin => 'A',
    );
    my ($is_super, $poll) = (undef, undef);
    my $poll_id = $cu->prop('election_poll_id');
    if ($poll_id) {
        $poll = LJ::Poll->new ($poll_id);
        $is_super = $poll->prop('supermaintainer');
    }
    my $flag_set_owner_error = 0;
    foreach (keys %edgelist) {
        if ($poll && $is_super && !$poll->is_closed && $_ eq 'admin' && $args->{$_}) {
            $flag_set_owner_error = 1;
        } else {
            LJ::set_rel($cu->{userid}, $u->{userid}, $edgelist{$_}) if $args->{$_};
            $cu->log_event('maintainer_add', { actiontarget => $u->{userid}, remote => LJ::load_userid($maintid) || $u }) if $_ eq 'admin' && $args->{$_};
        }
    }

    # now we can delete the invite and update the status on the other side
    return LJ::error('db') unless $u->writer;
    $u->do("DELETE FROM inviterecv WHERE userid = ? AND commid = ?",
           undef, $u->{userid}, $cu->{userid});

    return LJ::error('db') unless $cu->writer;
    $cu->do("UPDATE invitesent SET status = 'accepted' WHERE commid = ? AND userid = ?",
            undef, $cu->{userid}, $u->{userid});

    if ($flag_set_owner_error) {
        ## Save for later acceptance after the elections will be closed
        $u->do("INSERT INTO inviterecv VALUES (?, ?, ?, UNIX_TIMESTAMP(), ?)",
                undef, $u->{userid}, $cu->{userid}, $maintid, 'A');
        $cu->do("REPLACE INTO invitesent VALUES (?, ?, ?, UNIX_TIMESTAMP(), 'outstanding', ?)",
                undef, $cu->{userid}, $u->{userid}, $maintid, 'A');
        return LJ::error("Can't set user $u->{user} as maintainer for $cu->{user}")
    }

    # done
    return 1;
}

# <LJFUNC>
# name: LJ::reject_comm_invite
# des: Rejects an invitation a user has received.
# args: uuserid, cuserid
# des-uuserid: a userid or u object of the user to get pending invites for.
# des-cuserid: a userid or u object of the community to reject the invitation from
# returns: 1 for success, undef if failure
# </LJFUNC>
sub reject_comm_invite {
    my ($u, $cu) = @_;
    $u = LJ::want_user($u);
    $cu = LJ::want_user($cu);
    return undef unless $u && $cu;

    # get their invite to make sure they have one
    my $dbcr = LJ::get_cluster_def_reader($u);
    return LJ::error('db') unless $dbcr;
    my $test = $dbcr->selectrow_array('SELECT userid FROM inviterecv WHERE userid = ? AND commid = ? ' .
                                      'AND recvtime > UNIX_TIMESTAMP(DATE_SUB(NOW(), INTERVAL 30 DAY))',
                                      undef, $u->{userid}, $cu->{userid});
    return undef unless $test;

    # now just reject it
    return LJ::error('db') unless $u->writer;
    $u->do("DELETE FROM inviterecv WHERE userid = ? AND commid = ?",
              undef, $u->{userid}, $cu->{userid});

    return LJ::error('db') unless $cu->writer;
    $cu->do("UPDATE invitesent SET status = 'rejected' WHERE commid = ? AND userid = ?",
            undef, $cu->{userid}, $u->{userid});

    # done
    return 1;
}

# <LJFUNC>
# name: LJ::get_pending_invites
# des: Gets a list of pending invitations for a user to join a community.
# args: uuserid
# des-uuserid: a userid or u object of the user to get pending invites for.
# returns: [ [ commid, maintainerid, time, args(url encoded) ], [ ... ], ... ] or
#          undef if failure
# </LJFUNC>
sub get_pending_invites {
    my $u = shift;
    $u = LJ::want_user($u);
    return undef unless $u;

    # hit up database for invites and return them
    my $dbcr = LJ::get_cluster_def_reader($u);
    return LJ::error('db') unless $dbcr;
    my $pending = $dbcr->selectall_arrayref('SELECT commid, maintid, recvtime, args FROM inviterecv WHERE userid = ? ' .
                                            'AND recvtime > UNIX_TIMESTAMP(DATE_SUB(NOW(), INTERVAL 30 DAY))', 
                                            undef, $u->{userid});
    return undef if $dbcr->err;
    return $pending;
}

# <LJFUNC>
# name: LJ::revoke_invites
# des: Revokes a list of outstanding invitations to a community.
# args: cuserid, userids
# des-cuserid: a userid or u object of the community.
# des-ruserids: userids to revoke invitations from.
# returns: 1 if success, undef if error
# </LJFUNC>
sub revoke_invites {
    my $cu = shift;
    my @uids = @_;
    $cu = LJ::want_user($cu);
    return undef unless ($cu && @uids);

    foreach my $uid (@uids) {
        return undef unless int($uid) > 0;
    }
    my $in = join(',', @uids);

    return LJ::error('db') unless $cu->writer;
    $cu->do("DELETE FROM invitesent WHERE commid = ? AND " .
            "userid IN ($in)", undef, $cu->{userid});
    return LJ::error('db') if $cu->err;

    my $stats = {
        journalid   => $cu->userid,
        journalcaps => $cu->caps,
        users       => []
    };

    # remove from inviterecv also,
    # otherwise invite cannot be resent for over 30 days
    foreach my $uid (@uids) {
        my $u =  LJ::want_user($uid);
        my $res = $u->do("DELETE FROM inviterecv WHERE userid = ? AND " .
                         "commid = ?", undef, $uid, $cu->{userid});

        push @{$stats->{users}}, { id => $u->userid, caps => $u->caps } if $res;
    }

    LJ::run_hooks('revoke_invite', $stats);

    # success
    return 1;
}

# <LJFUNC>
# name: LJ::leave_community
# des: Makes a user leave a community.  Takes care of all [special[reluserdefs]] and friend stuff.
# args: uuserid, ucommid, defriend
# des-uuserid: a userid or u object of the user doing the leaving.
# des-ucommid: a userid or u object of the community being left.
# des-defriend: remove comm from user's friends list.
# returns: 1 if success, undef if error of some sort (ucommid not a comm, uuserid not in
#          comm, db error, etc)
# </LJFUNC>
sub leave_community {
    my ($uuid, $ucid, $defriend) = @_;
    my $u = LJ::want_user($uuid);
    my $cu = LJ::want_user($ucid);
    $defriend = $defriend ? 1 : 0;
    return LJ::error('comm_not_found') unless $u && $cu;

    # defriend comm -> user
    return LJ::error('comm_not_comm') unless $cu->{journaltype} =~ /[CS]/;
    my $ret = $cu->remove_friend($u);
    return LJ::error('comm_not_member') unless $ret; # $ret = number of rows deleted, should be 1 if the user was in the comm

    # clear edges that effect this relationship
    foreach my $edge (qw(P N A M)) {
        LJ::clear_rel($cu->{userid}, $u->{userid}, $edge);
    }

    # defriend user -> comm?
    return 1 unless $defriend;
    $u->remove_friend($cu);

    # don't care if we failed the removal of comm from user's friends list...
    return 1;
}

# <LJFUNC>
# name: LJ::join_community
# des: Makes a user join a community.  Takes care of all [special[reluserdefs]] and friend stuff.
# args: uuserid, ucommid, friend?, noauto?
# des-uuserid: a userid or u object of the user doing the joining
# des-ucommid: a userid or u object of the community being joined
# des-friend: 1 to add this comm to user's friends list, else not
# des-noauto: if defined, 1 adds P edge, 0 does not; else, base on community postlevel
# returns: 1 if success, undef if error of some sort (ucommid not a comm, uuserid already in
#          comm, db error, etc)
# </LJFUNC>
sub join_community {
    my ($uuid, $ucid, $friend, $canpost) = @_;
    my $u = LJ::want_user($uuid);
    my $cu = LJ::want_user($ucid);
    $friend = $friend ? 1 : 0;
    return LJ::error('comm_not_found') unless $u && $cu;
    return LJ::error('comm_not_comm') unless $cu->{journaltype} eq 'C';

    return LJ::error(qq|Sorry, you aren't allowed to join communities until your email address has been validated. If you've lost the confirmation email to do this, you can <a href="$LJ::SITEROOT/register.bml">have it re-sent.</a>|)
        unless $u->is_validated;

    # friend comm -> user
    LJ::add_friend($cu->{userid}, $u->{userid});

    # add edges that effect this relationship... if the user sent a fourth
    # argument, use that as a bool.  else, load commrow and use the postlevel.
    my $addpostacc = 0;
    if (defined $canpost) {
        $addpostacc = $canpost ? 1 : 0;
    } else {
        my $crow = LJ::get_community_row($cu);
        $addpostacc = $crow->{postlevel} eq 'members' ? 1 : 0;
    }
    LJ::set_rel($cu->{userid}, $u->{userid}, 'P') if $addpostacc;

    # friend user -> comm?
    return 1 unless $friend;

    # don't do the work if they already friended the comm
    return 1 if $u->has_friend($cu);

    my $err = "";
    return LJ::error("You have joined the community, but it has not been added to ".
                     "your Friends list. " . $err) unless $u->can_add_friends(\$err, { friend => $cu });

    $u->friend_and_watch($cu);

    # done
    return 1;
}

# <LJFUNC>
# name: LJ::get_community_row
# des: Gets data relevant to a community such as their membership level and posting access.
# args: ucommid
# des-ucommid: a userid or u object of the community
# returns: a hashref with user, userid, name, membership, and postlevel data from the
#          user and community tables; undef if error.
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
# name: LJ::get_community_moderation_queue
# des: Gets a list of hashrefs for posts that people have requested to be posted to a community
#      but have not yet actually been approved or rejected.
# args: comm
# des-comm: a userid or u object of the community to get pending members of
# returns: an array of requests as it is in modlog db table
# </LJFUNC>
sub get_community_moderation_queue {
    my $comm = shift;
    my $c = LJ::want_user($comm);

    my $dbcr = LJ::get_cluster_reader($c);
    my @e;              # fetched entries
    my @entries;        # entries to show
    my @entries2del;    # entries to delete
    my $sth = $dbcr->prepare("SELECT * FROM modlog WHERE journalid=$c->{'userid'}");
    $sth->execute;
    while ($_ = $sth->fetchrow_hashref) {
            push @e, $_;
    }

    my %users;
    my $suspend_time = $LJ::SUSPENDED_REQUESTS_TIMEOUT || 60; # days.
    if (@e) {
        LJ::load_userids_multiple([ map { $_->{'posterid'}, \$users{$_->{'posterid'}} } @e ]);
        foreach my $e (@e) {
            next unless keys %$e;
            my $e_poster = $users{$e->{'posterid'}};
            if (LJ::isu($e_poster)) {
                if ($e_poster->is_suspended()) {
                    if (time - $e_poster->statusvisdate_unix() > $suspend_time * 24 * 3600) {
                        push @entries2del, $e;
                    }
                } else {
                    push @entries, $e;
                }
            } else {
                push @entries2del, $e;
            }
        }
    }

    if (@entries2del) {
        # Users has been suspended more then 60 days ago.
        # Delete entries of this user(s) from modlog and modblob.
        my $count = scalar @entries2del;
        my $max_count = $count > 50 ? 50 : $count;
        while($count) {
            my $lst = join(',', map {$_->{modid}} splice(@entries2del, 0, $max_count));
            $c->do("DELETE FROM modlog WHERE modid in ($lst)");
            $c->do("DELETE FROM modblob WHERE modid in ($lst)");
            $count -= $max_count;
        }
    }

    return @entries;
}

# <LJFUNC>
# name: LJ::get_pending_members
# des: Gets a list of userids for people that have requested to be added to a community
#      but have not yet actually been approved or rejected.
# args: comm
# des-comm: a userid or u object of the community to get pending members of
# returns: an arrayref of userids of people with pending membership requests
# </LJFUNC>
sub get_pending_members {
    my $comm = shift;
    my $cu = LJ::want_user($comm);
    
    # database request
    my $dbr = LJ::get_db_reader();

    my $sth = $dbr->prepare('SELECT aaid, arg1 FROM authactions' .
                                ' WHERE userid = ' . $cu->{userid} .
                                " AND action = 'comm_join_request' AND used = 'N'");
    # parse out the args
    my @list;
    my @delete;
    $sth->execute;
    my $suspend_time = $LJ::SUSPENDED_REQUESTS_TIMEOUT || 60; # days.
    while (my $row = $sth->fetchrow_hashref) {
        if ($row->{arg1} =~ /^targetid=(\d+)$/) {
            my ($uid, $u) = ($1, LJ::want_user($1));
            if (LJ::isu($u)) {
                if ($u->is_suspended()) {
                    if (time - $u->statusvisdate_unix() > $suspend_time * 24 * 3600) {
                        push @delete, $row->{aaid};
                    }
                } else {
                    push @list, $uid;
                }
            } else {
                push @delete, $row->{aaid};
            }
        }
    }

    if (@delete) {
        my $count = scalar @delete;
        my $max_count = $count > 50 ? 50 : $count;
        while($count) {
            my $lst = join(',', splice(@delete, 0, $max_count));
            my $dbh = LJ::get_db_writer();
            $dbh->do("DELETE FROM authactions WHERE aaid in ($lst)");
            $count -= $max_count;
        }
    }

    return \@list;
}

# <LJFUNC>
# name: LJ::approve_pending_member
# des: Approves someone's request to join a community.  This updates the [dbtable[authactions]] table
#      as appropriate as well as does the regular join logic.  This also generates an e-mail to
#      be sent to the user notifying them of the acceptance.
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

    LJ::run_hooks('approve_member',
        {
            journalid   => $cu->userid,
            journalcaps => $cu->caps,
            users       => [ { id => $u->userid, caps => $u->caps } ]
        }
    );

    # step 2, make user join the community
    # 1 means "add community to user's friends list"
    return unless LJ::join_community($u->{userid}, $cu->{userid}, 1);

    # step 3, email the user
    my %params = (event => 'CommunityJoinApprove', journal => $u);
    unless ($u->has_subscription(%params)) {
        $u->subscribe(%params, method => 'Email');
    }
    LJ::Event::CommunityJoinApprove->new($u, $cu)->fire unless $LJ::DISABLED{esn};

    return 1;
}

# <LJFUNC>
# name: LJ::reject_pending_member
# des: Rejects someone's request to join a community.
#      Updates [dbtable[authactions]] and generates an e-mail to the user.
# args: commid, userid
# des-commid: userid of the community
# des-userid: userid of the user doing the join
# returns: 1 on success, 0/undef on error
# </LJFUNC>
## LJ::reject_pending_member($cid, $id, $remote->{userid}, $POST{'reason'});
sub reject_pending_member {
    my ($commid, $userid, $maintid, $reason) = @_;

    $reason = LJ::Lang::ml('/community/pending.bml.reason.default.text') if $reason eq '0';
    my $cu = LJ::want_user($commid);
    my $u = LJ::want_user($userid);
    my $mu = LJ::want_user($maintid);
    return unless $cu && $u && $mu;

    # step 1, update authactions table
    my $dbh = LJ::get_db_writer();

    my $count = $dbh->do("UPDATE authactions SET used = 'Y' WHERE userid = ? AND arg1 = ?",
                         undef, $cu->{userid}, "targetid=$u->{userid}");
    return unless $count;

    LJ::run_hooks(
        'reject_member',
        {
            journalid   => $cu->userid,
            journalcaps => $cu->caps,
            users       => [ { id => $u->userid, caps => $u->caps } ]
        }
    );

    # step 2, email the user
    my %params = (event => 'CommunityJoinReject', journal => $cu);
    unless ($u->has_subscription(%params)) {
        $u->subscribe(%params, method => 'Email');
    }

    # Email to user about rejecting
    LJ::Event::CommunityJoinReject->new($cu, $u, undef, undef, $reason)->fire unless $LJ::DISABLED{esn};

    # Email to maints about user rejecting
    my $maintainers = LJ::load_rel_user($commid, 'A');
    foreach my $mid (@$maintainers) {
        next if $mid == $maintid;
        my $maintu = LJ::load_userid($mid);
        my %params = (event => 'CommunityJoinReject', journal => $cu);
        if ($maintu && $maintu->has_subscription(%params)) {
            LJ::Event::CommunityJoinReject->new($cu, $maintu, $mu, $u, $reason)->fire unless $LJ::DISABLED{esn};
        }
    }

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

    my $arg = "targetid=" . $u->id;
    my $dbh = LJ::get_db_writer();

    # check for duplicates within the same hour (to prevent spamming)
    my $oldaa = $dbh->selectrow_hashref("SELECT aaid, authcode, datecreate FROM authactions " .
                                        "WHERE userid=? AND arg1=? " .
                                        "AND action='comm_join_request' AND used='N' " .
                                        "AND NOW() < datecreate + INTERVAL 1 HOUR " .
                                        "ORDER BY 1 DESC LIMIT 1",
                                        undef, $comm->id, $arg);

    return $oldaa if $oldaa;

    # insert authactions row
    my $aa = LJ::register_authaction($comm->id, 'comm_join_request', $arg);
    return undef unless $aa;

    # if there are older duplicates, invalidate any existing unused authactions of this type
    $dbh->do("UPDATE authactions SET used='Y' WHERE userid=? AND aaid<>? AND arg1=? " .
             "AND action='comm_invite' AND used='N'",
             undef, $comm->id, $aa->{'aaid'}, $arg);

    # get maintainers of community
    my $adminids = LJ::load_rel_user($comm->{userid}, 'A') || [];
    my $admins = LJ::load_userids(@$adminids);

    # now prepare the emails
    foreach my $au (values %$admins) {
        next unless $au && !$au->is_expunged;

        # unless it's a hyphen, we need to migrate
        my $prop = $au->prop("opt_communityjoinemail");
        if ($prop ne "-") {
            if ($prop ne "N") {
                my %params = (event => 'CommunityJoinRequest', journal => $au);
                unless ($au->has_subscription(%params)) {
                    $au->subscribe(%params, method => $_) foreach qw(Inbox Email);
                }
            }

            $au->set_prop("opt_communityjoinemail", "-");
        }

        LJ::Event::CommunityJoinRequest->new($au, $u, $comm)->fire;
    }

    return $aa;
}

sub maintainer_linkbar {
    my $comm = shift;
    my $page = shift;

    my $username = $comm->user;
    my @links;

    my %manage_link_info = LJ::run_hook('community_manage_link_info', $username);
    if (keys %manage_link_info) {
        push @links, $page eq "account" ?
            "<strong>$manage_link_info{text}</strong>" :
            "<a href='$manage_link_info{url}'>$manage_link_info{text}</a>";
    }

    push @links, (
        $page eq "profile" ?
            "<strong>" . LJ::Lang::ml('/community/manage.bml.commlist.actinfo2') . "</strong>" :
            "<a href='$LJ::SITEROOT/manage/profile/?authas=$username'>" . LJ::Lang::ml('/community/manage.bml.commlist.actinfo2') . "</a>",
        $page eq "customize" ?
            "<strong>" . LJ::Lang::ml('/community/manage.bml.commlist.customize2') . "</strong>" :
            "<a href='$LJ::SITEROOT/customize/?authas=$username'>" . LJ::Lang::ml('/community/manage.bml.commlist.customize2') . "</a>",
        $page eq "settings" ?
            "<strong>" . LJ::Lang::ml('/community/manage.bml.commlist.actsettings2') . "</strong>" :
            "<a href='$LJ::SITEROOT/community/settings.bml?authas=$username'>" . LJ::Lang::ml('/community/manage.bml.commlist.actsettings2') . "</a>",
        $page eq "invites" ?
            "<strong>" . LJ::Lang::ml('/community/manage.bml.commlist.actinvites') . "</strong>" :
            "<a href='$LJ::SITEROOT/community/sentinvites.bml?authas=$username'>" . LJ::Lang::ml('/community/manage.bml.commlist.actinvites') . "</a>",
        $page eq "members" ?
            "<strong>" . LJ::Lang::ml('/community/manage.bml.commlist.actmembers2') . "</strong>" :
            "<a href='$LJ::SITEROOT/community/members.bml?authas=$username'>" . LJ::Lang::ml('/community/manage.bml.commlist.actmembers2') . "</a>",
    );

    my $ret .= "<strong>" . LJ::Lang::ml('/community/manage.bml.managelinks', { user => $comm->ljuser_display }) . "</strong> ";
    $ret .= join(" | ", @links);

    return "<p style='margin-bottom: 20px;'>$ret</p>";
}

# Get membership and posting level settings for a community
sub get_comm_settings {
    my $c = shift;

    my $cid = $c->{userid};
    my ($membership, $postlevel);
    my $memkey = [ $cid, "commsettings:$cid" ];

    my $memval = LJ::MemCache::get($memkey);
    ($membership, $postlevel) = @$memval if ($memval);
    return ($membership, $postlevel)
        if ( $membership && $postlevel );

    my $dbr = LJ::get_db_reader();
    ($membership, $postlevel) =
        $dbr->selectrow_array("SELECT membership, postlevel FROM community WHERE userid=?", undef, $cid);

    LJ::MemCache::set($memkey, [$membership,$postlevel] ) if ( $membership && $postlevel );

    return ($membership, $postlevel);
}

# Set membership and posting level settings for a community
sub set_comm_settings {
    my ($c, $u, $opts) = @_;

    die "User cannot modify this community"
        unless (LJ::can_manage_other($u, $c));

    die "Membership and posting levels are not available"
        unless ($opts->{membership} && $opts->{postlevel});

    my $cid = $c->{userid};

    my $dbh = LJ::get_db_writer();
    $dbh->do("REPLACE INTO community (userid, membership, postlevel) VALUES (?,?,?)" , undef, $cid, $opts->{membership}, $opts->{postlevel});

    my $memkey = [ $cid, "commsettings:$cid" ];
    LJ::MemCache::delete($memkey);

    return;
}

1;

