#!/usr/bin/perl
#

package LJ::Con;

use strict;
use vars qw(%cmd);

$cmd{'expunge_userpic'}->{'handler'} = \&expunge_userpic;
$cmd{'suspend'}->{'handler'} = \&suspend;
$cmd{'unsuspend'}->{'handler'} = \&suspend;
$cmd{'getemail'}->{'handler'} = \&getemail;
$cmd{'get_maintainer'}->{'handler'} = \&get_maintainer;
$cmd{'get_moderator'}->{'handler'} = \&get_moderator;
$cmd{'finduser'}->{'handler'} = \&finduser;
$cmd{'infohistory'}->{'handler'} = \&infohistory;
$cmd{'change_journal_status'}->{'handler'} = \&change_journal_status;
$cmd{'set_underage'}->{'handler'} = \&set_underage;

sub set_underage {
    my ($dbh, $remote, $args, $out) = @_;

    my $err = sub { push @$out, [ "error", shift ]; 0; };
    my $info = sub { push @$out, [ "info", shift ]; 1; };

    return $err->("This command takes three arguments.  Consult the reference for details.")
        unless scalar(@$args) == 4;
    return $err->("You don't have the necessary privilege (siteadmin:underage) to change an account's underage flag.")
        unless LJ::check_priv($remote, 'siteadmin', 'underage') || LJ::check_priv($remote, 'siteadmin', '*');

    my $u = LJ::load_user($args->[1]);
    return $err->("Invalid user.")
        unless $u;
    return $err->("Account is not a person type account.")
        unless $u->{journaltype} eq 'P';

    return $err->("Second argument must be 'on' or 'off'.")
        unless $args->[2] =~ /^(?:on|off)$/;
    my $on = $args->[2] eq 'on' ? 1 : 0;

    my $note = $args->[3];
    return $err->("You must provide a reason for this change as the third argument.")
        unless $note;

    # can't set state to what it is already
    return $err->("User is already of the requested underage state.")
        unless $on ^ $u->underage;

    my ($res, $sh, $status);
    if ($on) {
        $status = 'M'; # "M"anually turned on
        $res = "User marked as underage.";
        $sh = "marked; $note";
    } else {
        $status = undef; # no status change
        $res = "User no longer marked as underaged.";
        $sh = "unmarked; $note";
    }

    # now record this change
    LJ::statushistory_add($u->{userid}, $remote->{userid}, "set_underage", $sh);
    $u->underage($on, $status);
    return $info->($res);
}

sub change_journal_status {
    my ($dbh, $remote, $args, $out) = @_;

    my $err = sub { push @$out, [ "error", shift ]; 0; };
    my $info = sub { push @$out, [ "info", shift ]; 1; };

    return $err->("This command takes two arguments.  Consult the reference for details.")
        unless scalar(@$args) == 3;
    return $err->("You don't have the necessary privilege (siteadmin:users) to change account status.")
        unless LJ::check_priv($remote, 'siteadmin', 'users') || LJ::check_priv($remote, 'siteadmin', '*');

    my $u = LJ::load_user($args->[1]);
    return $err->("Invalid user.")
        unless $u;

    # figure out the new status
    my $status = $args->[2];
    my $opts = {
        #name  =>   [ 'status-to', 'valid-statuses-from', 'error-message-if-from-fails', 'success-message' ]
        normal =>   [ 'V', 'ML', 'The user must be in memorial or locked status first.', 'User status set back to normal.' ],
        memorial => [ 'M', 'V', 'The user must be in normal status first.', 'User account set as memorial.' ],
        locked =>   [ 'L', 'V', 'The user must be in normal status first.', 'User account has been locked.' ],
    }->{$status};

    # make sure we got a valid $opts arrayref
    return $err->("Invalid status.  Consult the reference for more information.")
        unless defined $opts && ref $opts eq 'ARRAY';

    # verify user's from-statusvis is okay (it's contained in $opts->[1])
    return $err->($opts->[2]) unless $opts->[1] =~ /$u->{statusvis}/;

    # okay, so we need to update the user now and update statushistory
    LJ::statushistory_add($u->{userid}, $remote->{userid}, "journal_status", "Changed status to $status from $u->{statusvis}.");
    LJ::update_user($u->{'userid'}, { statusvis => $opts->[0], raw => 'statusvisdate=NOW()' });
    return $info->($opts->[3]);
}

sub expunge_userpic {
    my ($dbh, $remote, $args, $out) = @_;

    unless (scalar(@$args) == 3) {
        push @$out, [ "error", "This command takes exactly two arguments, username and picid.  Consult the reference." ];
        return 0;
    }

    my $user = $args->[1];
    my $picid = $args->[2]+0;

    unless (LJ::check_priv($remote, 'siteadmin', 'userpics') || LJ::check_priv($remote, 'siteadmin', '*')) {
        push @$out, [ "error", "You don't have access to expunge user picture icons." ];
        return 0;
    }

    my $u = LJ::load_user($user);

    # the actual expunging happens in ljlib
    my ($rval, $hookval) = LJ::expunge_userpic($u, $picid);
    push @$out, $hookval if @{$hookval || []};

    # now load up from the return value we got
    unless ($rval && $u) {
        push @$out, [ "error", "Error expunging user picture icon." ];
        return 0;
    }

    # but make sure to log it
    LJ::statushistory_add($u->{userid}, $remote->{userid}, 'expunge_userpic', "expunged userpic; id=$picid");
    push @$out, [ "info", "User picture icon $picid for $u->{user} expunged from $LJ::SITENAMESHORT." ];

    return 1;
}

sub suspend
{
    my ($dbh, $remote, $args, $out) = @_;

    unless (scalar(@$args) == 3) {
        push @$out, [ "error", "This command takes exactly 2 arguments.  Consult the reference." ];
        return 0;
    }

    my $cmd = $args->[0];
    my ($user, $reason) = ($args->[1], $args->[2]);

    if ($cmd eq "suspend" && $reason eq "off") {
        push @$out, [ "error", "The second argument to the 'suspend' command is no longer 'off' to unsuspend.  Use the 'unsuspend' command instead." ];
        return 0;
    }

    unless ($remote->{'priv'}->{'suspend'}) {
        push @$out, [ "error", "You don't have access to $cmd users." ];
        return 0;
    }

    my $u = LJ::load_user($user);
    my $status = ($cmd eq "unsuspend") ? "V" : "S";
    unless ($u) {
        push @$out, [ "error", "Invalid user." ];
        return 0;
    }

    if ($u->{'statusvis'} eq $status) {
        push @$out, [ "error", "User was already in that state ($status)" ];
        return 0;
    }

    LJ::update_user($u->{'userid'}, { statusvis => $status, raw => 'statusvisdate=NOW()' });

    LJ::statushistory_add($u->{'userid'}, $remote->{'userid'}, $cmd, $reason);

    push @$out, [ "info", "User ${cmd}ed." ];

    return 1;
}

sub getemail
{
    my ($dbh, $remote, $args, $out) = @_;

    unless (scalar(@$args) == 2) {
        push @$out, [ "error", "This command takes exactly 1 argument.  Consult the reference." ];
        return 0;
    }
    
    my ($user) = ($args->[1]);
    my $userid = &LJ::get_userid($user);

    unless ($remote->{'priv'}->{'suspend'}) {
        push @$out, [ "error", "You don't have access to see email addresses." ];
        return 0;
    }

    unless ($userid) {
        push @$out, [ "error", "Invalid user \"$user\"" ];
        return 0;
    }
    
    my $sth = $dbh->prepare("SELECT email, status FROM user WHERE userid=$userid");
    $sth->execute;
    my ($email, $status) = $sth->fetchrow_array;
    
    push @$out, [ "info", "User: $user" ];
    push @$out, [ "info", "Email: $email" ];
    push @$out, [ "info", "Status: $status  (A=approved, N=new, T=transferring)" ];

    return 1;
}

sub finduser
{
    my ($dbh, $remote, $args, $out) = @_;

    unless ($remote->{'priv'}->{'finduser'}) {
        push @$out, [ "error", "$remote->{'user'}, you are not authorized to use this command." ];
        return 0;
    }

    my $crit = $args->[1];
    my $data = $args->[2];
    my $qd = $dbh->quote($data);

    my $where;
    if ($crit eq "email") {
        $where = "email=$qd";
    } elsif ($crit eq "userid") {
        $where = "userid=$qd";
    } elsif ($crit eq "user") {
        $where = "user=$qd";
    }

    unless ($where) {
        push @$out, [ "error", "Invalid search criteria.  See reference." ];
        return 0;
    }

    my $sth = $dbh->prepare("SELECT * FROM user WHERE $where");
    $sth->execute;
    if (! $sth->rows) {
        push @$out, [ "error", "No matches." ];
    }
    while (my $u = $sth->fetchrow_hashref) {        
        push @$out, [ "info", "User: $u->{'user'} ".
                      "($u->{'userid'}), journaltype: $u->{'journaltype'}, statusvis: $u->{'statusvis'}, email: ($u->{'status'}) $u->{'email'}" ];
        foreach (LJ::run_hooks("finduser_extrainfo", { 'dbh' => $dbh, 'u' => $u })) {
            next unless $_->[0];
            foreach (split(/\n/, $_->[0])) {
                push @$out, [ "info", $_ ];
            }
        }
    }
    
    return 1;
}

sub get_maintainer
{
    my ($dbh, $remote, $args, $out, $edge) = @_;
    $edge ||= 'A';

    unless (scalar(@$args) == 2) {
        push @$out, [ "error", "This command takes exactly 1 argument.  Consult the reference." ];
        return 0;
    }
    
    unless ($remote->{'priv'}->{'finduser'}) {
        push @$out, [ "error", "$remote->{'user'}, you are not authorized to use this command." ];
        return 0;
    }

    my $user = $args->[1];
    my $u = LJ::load_user($user);

    unless ($u) {
        push @$out, [ "error", "Invalid user \"$user\"" ];
        return 0;
    }

    # journaltype eq 'P' means we're calling get_maintainer on a
    # plain user and we should get a list of what they maintain instead of
    # getting a list of what maintains them
    my $ids = $u->{journaltype} eq 'P' ?
              LJ::load_rel_target($u->{userid}, $edge) :
              LJ::load_rel_user($u->{userid}, $edge);
    $ids ||= [];

    # finduser loop
    finduser($dbh, $remote, ['finduser', 'userid', $_], $out) foreach @$ids;

    return 1;
}

sub get_moderator
{
    # simple pass through, but specify to use the 'M' edge
    return get_maintainer(@_, 'M');
}

sub infohistory
{
    my ($dbh, $remote, $args, $out) = @_;

    unless ($remote->{'privarg'}->{'finduser'}->{'infohistory'}) {
        push @$out, [ "error", "$remote->{'user'}, you are not authorized to use this command." ];
        return 0;
    }

    my $user = $args->[1];
    my $userid = LJ::get_userid($user);

    unless ($userid) {
        push @$out, [ "error", "Invalid user $user" ];
        return 0;
    }

    my $sth = $dbh->prepare("SELECT * FROM infohistory WHERE userid='$userid'");
    $sth->execute;
    if (! $sth->rows) {
        push @$out, [ "error", "No matches." ];
    } else {
        push @$out, ["info", "Infohistory of user: $user"];
        while (my $info = $sth->fetchrow_hashref) {        
            $info->{'oldvalue'} ||= '(none)';
            push @$out, [ "info", 
                          "Changed $info->{'what'} at $info->{'timechange'}.\n".
                          "Old value of $info->{'what'} was $info->{'oldvalue'}.".
                          ($info->{'other'} ? 
                           "\nOther information recorded: $info->{'other'}" : "") ];
        }
    }
    return 1;
}

1;

