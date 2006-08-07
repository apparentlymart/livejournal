package LJ::SMS;

# LJ::SMS object
#
# wrangles LJ::SMS::Messages and the app logic associated
# with them...
#
# also contains LJ::Worker class for incoming SMS
#

use strict;
use Carp qw(croak);

sub schwartz_capabilities {
    return qw(LJ::Worker::IncomingSMS);
}

# get the userid of a given number from smsusermap
sub num_to_uid {
    my $class = shift;
    my $num  = shift;

    # TODO: optimize
    my $dbr = LJ::get_db_reader();
    return $dbr->selectrow_array
        ("SELECT userid FROM smsusermap WHERE number=? LIMIT 1", undef, $num);
}

sub uid_to_num {
    my $class = shift;
    my $uid  = LJ::want_userid(shift);

    # TODO: optimize
    my $dbr = LJ::get_db_reader();
    return $dbr->selectrow_array
        ("SELECT number FROM smsusermap WHERE userid=? LIMIT 1", undef, $uid);
}

sub replace_mapping {
    my ($class, $uid, $num) = @_;
    $uid = LJ::want_userid($uid);
    croak "invalid userid" unless int($uid) > 0;
    croak "invalid number" unless $num =~ /^\+?(\d+)$/;
    $num = $1;

    my $dbh = LJ::get_db_writer();
    return $dbh->do("REPLACE INTO smsusermap (number, userid) VALUES (?,?)",
                      undef, $num, $uid);
}

# enqueue an incoming SMS for processing
sub enqueue_as_incoming {
    my $class = shift;
    croak "enqueue_as_incoming is a class method"
        unless $class eq __PACKAGE__;

    my $msg = shift;
    die "invalid msg argument"
        unless $msg && $msg->isa("LJ::SMS::Message");

    return unless $msg->should_enqueue;

    my $sclient = LJ::theschwartz();
    die "Unable to contact TheSchwartz!"
        unless $sclient;

    my $shandle = $sclient->insert("LJ::Worker::IncomingSMS", $msg);
    return $shandle ? 1 : 0;
}

# is sms sending configured?
sub configured {
    my $class = shift;

    return %LJ::SMS_GATEWAY_CONFIG && LJ::sms_gateway() ? 1 : 0;
}

sub configured_for_user {
    my $class = shift;
    my $u = shift;

    # FIXME: for now just check to see if the user has
    #        a uid -> number mapping in smsusermap
    return $u->sms_number ? 1 : 0;
}

sub messages_remaining {
    my ($class, $u, $type) = @_;

    return LJ::run_hook("sms_check_quota", $u, $type) || 0;
}

# BARF: wtf with this locking?
sub add_free_messages {
    my ($class, $u, $cnt) = @_;

    # get lock
    my $lockkey = "sms_quota:$u->{userid}";
    LJ::get_lock($u, 'user', $lockkey);

    $u->begin_work;

    my $sth = $u->prepare("SELECT quota_used, quota_updated, free_qty, paid_qty FROM sms_quota WHERE userid=?");
    $sth->execute($u->id);
    if ($sth->errstr) {
        $u->rollback;
        die $sth->errstr;
    }

    my ($quota_used, $quota_updated, $free_qty, $paid_qty) = $sth->fetchrow_array;

    $free_qty ||= 0;
    $free_qty += $cnt;

    # time to update the DB
    $u->do("REPLACE INTO sms_quota (quota_used, quota_updated, userid, free_qty, paid_qty) VALUES (?, ?, ?, ?, ?) WHERE userid=?",
           undef, $quota_used, $quota_updated, $u->id, $free_qty, $paid_qty, $u->id);
    if ($sth->errstr) {
        $u->rollback;
        die $sth->errstr;
    }

    $u->commit;

    # free lock
    LJ::release_lock($u, 'user', $lockkey);
}

# Schwartz worker for responding to incoming SMS messages
package LJ::Worker::IncomingSMS;
use base 'TheSchwartz::Worker';

use Class::Autouse qw(LJ::SMS::MessageHandler);

sub work {
    my ($class, $job) = @_;

    my $msg = $job->arg;

    unless ($msg) {
        $job->failed;
        return;
    }

    # save msg to the db
    $msg->save_to_db
        or die "unable to save message to db";

    warn "calling messagehandler";
    LJ::SMS::MessageHandler->handle($msg);

    return $job->completed;
}

sub keep_exit_status_for { 0 }
sub grab_for { 300 }
sub max_retries { 5 }
sub retry_delay {
    my ($class, $fails) = @_;
    return (10, 30, 60, 300, 600)[$fails];
}

1;
