#!/usr/bin/perl
#

package LJ::Con;

$cmd{'suspend'}->{'handler'} = \&suspend;
$cmd{'getemail'}->{'handler'} = \&getemail;

sub suspend
{
    my ($dbh, $remote, $args, $out) = @_;
    my $error = 0;

    unless (scalar(@$args) == 2 || scalar(@$args) == 3) {
	$error = 1;
	push @$out, [ "error", "This command takes exactly 1 or 2 arguments.  Consult the reference." ];
    }
    
    return 0 if ($error);

    my ($user, $off) = ($args->[1], $args->[2]);
    my $userid = &LJ::get_userid($dbh, $user);

    unless ($off eq "" || $off eq "off") {
	$error = 1;
	push @$out, [ "error", "Final parameter must either be blank, or 'off'" ];
    }
    unless ($userid) {
	$error = 1;
	push @$out, [ "error", "Invalid user \"$user\"" ];
    }
    
    unless ($remote->{'priv'}->{'suspend'}) {
	$error = 1;
	push @$out, [ "error", "You don't have access to suspend users." ];
    }
    
    return 0 if ($error);    
    
    my $status = $off ? "V" : "S";
    $dbh->do("UPDATE user SET statusvis='$status', statusvisdate=NOW() WHERE userid=$userid AND statusvis<>'$status'");

    my $verb = $off ? "unsuspended" : "suspended";
    push @$out, [ "info", "User \"$user\" $verb" ];

    return 1;
}

sub getemail
{
    my ($dbh, $remote, $args, $out) = @_;
    my $error = 0;

    unless (scalar(@$args) == 2) {
	$error = 1;
	push @$out, [ "error", "This command takes exactly 1 argument.  Consult the reference." ];
    }
    
    return 0 if ($error);

    my ($user) = ($args->[1]);
    my $userid = &LJ::get_userid($dbh, $user);

    unless ($remote->{'priv'}->{'suspend'}) {
	$error = 1;
	push @$out, [ "error", "You don't have access to see email addresses." ];
    }

    unless ($userid) {
	$error = 1;
	push @$out, [ "error", "Invalid user \"$user\"" ];
    }
    
    return 0 if ($error);    
    
    my $sth = $dbh->prepare("SELECT email, status FROM user WHERE userid=$userid");
    $sth->execute;
    my ($email, $status) = $sth->fetchrow_array;
    
    push @$out, [ "info", "User: $user" ];
    push @$out, [ "info", "Email: $email" ];
    push @$out, [ "info", "Status: $status  (A=approved, N=new, T=transferring)" ];

    return 1;
}


1;


