#!/usr/bin/perl
#

use strict;
use Class::Autouse qw(LJ::Event);

require "$ENV{LJHOME}/cgi-bin/ljlib.pl";
require "$ENV{LJHOME}/cgi-bin/supportlib.pl";
require "$ENV{LJHOME}/cgi-bin/ljmail.pl";

package LJ::Cmdbuffer;

# built-in commands
%LJ::Cmdbuffer::cmds =
    (

     # delete journal entries
     delitem => {
         run => \&LJ::Cmdbuffer::_delitem,
     },

     # ping weblogs.com with updates?  takes a $u argument
     weblogscom => {
         too_old => 60*60*2,  # 2 hours old = qbufferd not running?
         once_per_user => 1,
         run => \&LJ::Cmdbuffer::_weblogscom,
     },

     # emails that previously failed to send
     send_mail => {
         arg_format => 'raw',
         too_old => 60*60*24*30, # 30 days is way too old for mail to be relevant
         unordered => 1,         # order irrelevant
         run => \&LJ::Cmdbuffer::_send_mail,
     },

     # notify fotobilder of dirty friends
     dirty => {
         once_per_user => 1,
         kill_mem_size => 50_000, # bytes
         kill_job_ct   => 250,    # calls to LJ::Cmdbuffer::flush
         run => \&LJ::Cmdbuffer::_dirty,
     },

     # send notifications for support requests
     support_notify => {
         too_old => 60*60*2, # after two hours, notification seems kinda pointless
         run => \&LJ::Cmdbuffer::_support_notify,
     },

     );

# <LJFUNC>
# name: LJ::Cmdbuffer::flush
# des: flush up to 500 rows of a given command type from the cmdbuffer table
# args: dbh, db, cmd, userid?
# des-dbh: master database handle
# des-db: database cluster master
# des-cmd: a command type registered in %LJ::Cmdbuffer::cmds
# des-userid: optional userid to which flush should be constrained
# returns: 1 on success, 0 on failure
# </LJFUNC>
sub LJ::Cmdbuffer::flush
{
    my ($dbh, $db, $cmd, $userid) = @_;
    return 0 unless $cmd;

    my $mode = "run";
    if ($cmd =~ s/:(\w+)//) {
        $mode = $1;
    }

    my $code = $LJ::Cmdbuffer::cmds{$cmd} ?
        $LJ::Cmdbuffer::cmds{$cmd}->{$mode} : $LJ::HOOKS{"cmdbuf:$cmd:$mode"}->[0];
    return 0 unless $code;

    # start/finish modes
    if ($mode ne "run") {
        $code->($dbh);
        return 1;
    }

    # 0 = never too old
    my $too_old = LJ::Cmdbuffer::get_property($cmd, 'too_old') || 0;

    # 0 == okay to run more than once per user
    my $once_per_user = LJ::Cmdbuffer::get_property($cmd, 'once_per_user') || 0;

    # 'url' = urlencode, 'raw' = don't urlencode
    my $arg_format = LJ::Cmdbuffer::get_property($cmd, 'arg_format') || 'url';

    # 0 == order of the jobs matters, process oldest first
    my $unordered = LJ::Cmdbuffer::get_property($cmd, 'unordered') || 0;

    my $clist;
    my $loop = 1;

    my $where = "cmd=" . $dbh->quote($cmd);
    if ($userid) {
        $where .= " AND journalid=" . $dbh->quote($userid);
    }

    my $orderby;
    unless ($unordered) {
        $orderby = "ORDER BY cbid";
    }

    my $LIMIT = 500;

    while ($loop &&
           ($clist = $db->selectall_arrayref("SELECT cbid, UNIX_TIMESTAMP() - UNIX_TIMESTAMP(instime), journalid ".
                                             "FROM cmdbuffer ".
                                             "WHERE $where $orderby LIMIT $LIMIT")) &&
           $clist && @$clist)
    {
        my @too_old;
        my @cbids;

        # citem: [ cbid, age, journalid ]
        foreach my $citem (@$clist) {
            if ($too_old && $citem->[1] > $too_old) {
                push @too_old, $citem->[0];
            } else {
                push @cbids, $citem->[0];
            }
        }
        if (@too_old) {
            local $" = ",";
            $db->do("DELETE FROM cmdbuffer WHERE cbid IN (@too_old)");
        }

        foreach my $cbid (@cbids) {
            my $got_lock = $db->selectrow_array("SELECT GET_LOCK('cbid-$cbid',10)");
            return 0 unless $got_lock;
            # sadly, we have to do another query here to verify the job hasn't been
            # done by another thread.  (otherwise we could've done it above, instead
            # of just getting the id)

            my $c = $db->selectrow_hashref("SELECT cbid, journalid, cmd, instime, args " .
                                           "FROM cmdbuffer WHERE cbid=?", undef, $cbid);
            next unless $c;

            if ($arg_format eq "url") {
                my $a = {};
                LJ::decode_url_string($c->{'args'}, $a);
                $c->{'args'} = $a;
            }
            # otherwise, arg_format eq "raw"

            # run handler
            $code->($dbh, $db, $c);

            # if this task is to be run once per user, go ahead and delete any jobs
            # for this user of this type and remove them from the queue
            my $wh = "cbid=$cbid";
            if ($once_per_user) {
                $wh = "cmd=" . $db->quote($cmd) . " AND journalid=" . $db->quote($c->{journalid});
                @$clist = grep { $_->[2] != $c->{journalid} } @$clist;
            }

            $db->do("DELETE FROM cmdbuffer WHERE $wh");
            $db->do("SELECT RELEASE_LOCK('cbid-$cbid')");
        }
        $loop = 0 unless scalar(@$clist) == $LIMIT;
    }

    return 1;
}

# <LJFUNC>
# name: LJ::Cmdbuffer::get_property
# des: get a property of an async job type, either built-in or site-specific
# args: cmd, prop
# des-cmd: a registered async job type
# des-prop: the property name to look up
# returns: value of property (whatever it may be) on success, undef on failure
# </LJFUNC>
sub get_property {
    my ($cmd, $prop) = @_;
    return undef unless $cmd && $prop;

    if (my $c = $LJ::Cmdbuffer::cmds{$cmd}) {
        return $c->{$prop};
    }

    if (LJ::are_hooks("cmdbuf:$cmd:$prop")) {
        return LJ::run_hook("cmdbuf:$cmd:$prop");
    }

    return undef;
}

sub _delitem {
    my ($dbh, $db, $c) = @_;
    my $a = $c->{'args'};
    return LJ::delete_entry($c->{'journalid'}, $a->{'itemid'},
                            0, $a->{'anum'});
}

sub _weblogscom {
    # user, title, url
    my ($dbh, $db, $c) = @_;
    my $a = $c->{'args'};
    eval {
        eval "use XMLRPC::Lite;";
        unless ($@) {
            XMLRPC::Lite
                ->new( proxy => "http://rpc.weblogs.com/RPC2",
                       timeout => 5 )
                ->call('weblogUpdates.ping', # xml-rpc method call
                       LJ::ehtml($a->{'title'}) . " \@ $LJ::SITENAMESHORT",
                       $a->{'url'},
                       "$LJ::SITEROOT/misc/weblogs-change.bml?user=$a->{'user'}");
        }
    };

    return 1;
}

sub _send_mail {
    my ($dbh, $db, $c) = @_;

    my $msg = Storable::thaw($c->{'args'});
    return LJ::send_mail($msg, "async");
}

sub _dirty {
    my ($dbh, $db, $c) = @_;

    my $a = $c->{args};
    my $what = $a->{what};

    if ($what eq 'friends') {
        eval {
            eval qq{
                use RPC::XML;
                use RPC::XML::Client;
            };
            unless ($@) {
                my $u = LJ::load_userid($c->{journalid});
                my %req = ( user => $u->{user} );

                # fill in groups info
                LJ::fill_groups_xmlrpc($u, \%req);

                my $res = RPC::XML::Client
                    ->new("$LJ::FB_SITEROOT/interface/xmlrpc")
                    ->send_request('FB.XMLRPC.groups_push',
                                   # FIXME: don't be lazy with the smart_encode
                                   # FIXME: log useful errors from outcome
                                   RPC::XML::smart_encode(\%req));
            }
        };
    }

    return 1;
}

sub _support_notify {
    my ($dbh, $db, $c) = @_;

    # load basic stuff common to both paths
    my $a = $c->{args};
    my $type = $a->{type};
    my $spid = $a->{spid}+0;
    my $sp = LJ::Support::load_request($spid, $type eq 'new' ? 1 : 0); # 1 means load body
    my $dbr = LJ::get_db_reader();

    # now branch a bit to select the right user information
    my ($select, $level) = $type eq 'new' ?
        ('u.email', "'new', 'all'") :
        ('u.email, u.userid, u.user', "'all'");

    my $data = $dbr->selectall_arrayref("SELECT $select FROM supportnotify sn, user u " .
                                        "WHERE sn.userid=u.userid AND sn.spcatid=? " .
                                        "AND sn.level IN ($level)", undef, $sp->{_cat}{spcatid});

    # prepare the email
    my $body;
    my @emails;
    if ($type eq 'new') {
        $body = "A $LJ::SITENAME support request has been submitted regarding the following:\n\n";
        $body .= "Category: $sp->{_cat}{catname}\n";
        $body .= "Subject:  $sp->{subject}\n\n";
        $body .= "You can track its progress or add information here:\n\n";
        $body .= "$LJ::SITEROOT/support/see_request.bml?id=$spid";
        $body .= "\n\nIf you do not wish to receive notifications of incoming support requests, you may change your notification settings here:\n\n";
        $body .= "$LJ::SITEROOT/support/changenotify.bml";
        $body .= "\n\n" . "="x70 . "\n\n";
        $body .= $sp->{body};

        # just copy this out
        push @emails, $_->[0] foreach @$data;
    } elsif ($type eq 'update') {
        # load the response we want to stuff in the email
        my ($resp, $rtype, $posterid) =
            $dbr->selectrow_array("SELECT message, type, userid FROM supportlog WHERE spid = ? AND splid = ?",
                                  undef, $sp->{spid}, $a->{splid}+0);

        # build body
        $body = "A follow-up to the request regarding \"$sp->{subject}\" has ";
        $body .= "been submitted.  You can track its progress or add ";
        $body .= "information here:\n\n  ";
        $body .= "$LJ::SITEROOT/support/see_request.bml?id=$spid";
        $body .= "\n\n" . "="x70 . "\n\n";
        $body .= $resp;

        # now see who this should be sent to
        foreach my $erow (@$data) {
            next if $posterid == $erow->[1];
            next if $rtype eq 'screened' &&
                !LJ::Support::can_read_screened($sp, LJ::load_userid($erow->[1]));
            next if $rtype eq 'internal' &&
                !LJ::Support::can_read_internal($sp, LJ::load_userid($erow->[2]));
            push @emails, $erow->[0];
        }
    }

    # send the email
    LJ::send_mail({
        bcc => join(', ', @emails),
        from => $LJ::BOGUS_EMAIL,
        fromname => "$LJ::SITENAME Support",
        charset => 'utf-8',
        subject => ($type eq 'update' ? 'Re: ' : '') . "Support Request \#$spid",
        body => $body,
        wrap => 1,
    }) if @emails;

    return 1;
}

1;
