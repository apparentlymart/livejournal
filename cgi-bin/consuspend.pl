#!/usr/bin/perl
#

package LJ::Con;

$cmd{'suspend'}->{'handler'} = \&suspend;
$cmd{'unsuspend'}->{'handler'} = \&suspend;
$cmd{'getemail'}->{'handler'} = \&getemail;
$cmd{'get_maintainer'}->{'handler'} = \&get_maintainer;

sub suspend
{
    my ($dbh, $remote, $args, $out) = @_;

    unless (scalar(@$args) == 3) {
        push @$out, [ "error", "This command takes exactly 2 arguments.  Consult the reference." ];
        return 0;
    }
    

    my $cmd = $args->[0];
    my ($user, $reason) = ($args->[1], $args->[2]);
    my $userid = LJ::get_userid($dbh, $user);
    if ($cmd eq "suspend" && $reason eq "off") {
        push @$out, [ "error", "The second argument to the 'suspend' command is no longer 'off' to unsuspend.  Use the 'unsuspend' command instead." ];
        return 0;
    }

    unless ($remote->{'priv'}->{'suspend'}) {
        push @$out, [ "error", "You don't have access to $cmd users." ];
        return 0;

    }

    unless ($userid) {
        push @$out, [ "error", "Invalid user \"$user\"" ];
        return 0;
    }
    
    my $status = ($cmd eq "unsuspend") ? "V" : "S";
    $dbh->do("UPDATE user SET statusvis='$status', statusvisdate=NOW() WHERE userid=$userid AND statusvis<>'$status'");

    LJ::statushistory_add($dbh, $userid, $remote->{'userid'}, $cmd, $reason);

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
    my $userid = &LJ::get_userid($dbh, $user);

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

sub get_maintainer
{
    my ($dbh, $remote, $args, $out) = @_;

    unless (scalar(@$args) == 2) {
        push @$out, [ "error", "This command takes exactly 1 argument.  Consult the reference." ];
        return 0;
    }
    
    my ($user) = ($args->[1]);
    my $userid = LJ::get_userid($dbh, $user);

    unless ($remote->{'priv'}->{'finduser'}) {
        push @$out, [ "error", "$remote->{'user'}, you are not authorized to use this command." ];
        return 0;
    }

    unless ($userid) {
        push @$out, [ "error", "Invalid user \"$user\"" ];
        return 0;
    }
    
    $commname = $dbh->quote($user);
    
    my $sth = $dbh->prepare("SELECT pm.userid FROM priv_map pm, priv_list pl WHERE ".
                            "pl.privcode='sharedjournal' AND pm.prlid=pm.prlid AND pm.arg=$commname");
    $sth->execute;
    while (my $r = $sth->fetchrow_hashref) {
        $username = LJ::get_username($dbh, $r->{'userid'});
        push @$out, [ "info", "User: $username" ];
    }

    return 1;
}
1;


