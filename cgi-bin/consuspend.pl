#!/usr/bin/perl
#

package LJ::Con;

use strict;
use vars qw(%cmd);

$cmd{'suspend'}->{'handler'} = \&suspend;
$cmd{'unsuspend'}->{'handler'} = \&suspend;
$cmd{'getemail'}->{'handler'} = \&getemail;
$cmd{'get_maintainer'}->{'handler'} = \&get_maintainer;
$cmd{'finduser'}->{'handler'} = \&finduser;
$cmd{'infohistory'}->{'handler'} = \&infohistory;

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
                      "($u->{'userid'}), statusvis: $u->{'statusvis'}, email: ($u->{'status'}) $u->{'email'}" ];
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
    my ($dbh, $remote, $args, $out) = @_;

    unless (scalar(@$args) == 2) {
        push @$out, [ "error", "This command takes exactly 1 argument.  Consult the reference." ];
        return 0;
    }
    
    my ($user) = ($args->[1]);
    my $userid = LJ::get_userid($user);

    unless ($remote->{'priv'}->{'finduser'}) {
        push @$out, [ "error", "$remote->{'user'}, you are not authorized to use this command." ];
        return 0;
    }

    unless ($userid) {
        push @$out, [ "error", "Invalid user \"$user\"" ];
        return 0;
    }
    
    my $admins = LJ::load_rel_user($userid, 'A') || [];
    foreach (@$admins) {
        finduser($dbh, $remote, ['finduser', 'userid', $_], $out);
    }

    return 1;
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

