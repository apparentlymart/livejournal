#!/usr/bin/perl
#

package ljcon;

$cmd{'ban_set'}->{'handler'} = \&ban_set;
$cmd{'ban_unset'}->{'handler'} = \&ban_unset;

sub ban_set
{
    my ($dbh, $remote, $args, $out) = @_;
    my $error = 0;

    unless (scalar(@$args) == 2) {
	$error = 1;
	push @$out, [ "error", "This command takes exactly 1 argument.  Consult the reference." ];
    }
    
    return 0 if ($error);

    my ($user) = ($args->[1]);
    my $banid = &LJ::get_userid($dbh, $user);

    unless ($banid) {
	$error = 1;
	push @$out, [ "error", "Invalid user \"$user\"" ];
    }
    unless ($remote->{'userid'}) {
	$error = 1;
	push @$out, [ "error", "You have to be logged in to LiveJournal to use this command" ];
    }
    
    return 0 if ($error);    

    my $qbanid = $banid+0;
    my $quserid = $remote->{'userid'}+0;

    my $sth = $dbh->prepare("REPLACE INTO ban (userid, banneduserid) VALUES ($quserid, $qbanid)");
    $sth->execute;

    push @$out, [ "info", "User $user ($banid) banned." ];
    return 1;
}

sub ban_unset
{
    my ($dbh, $remote, $args, $out) = @_;
    my $error = 0;

    unless (scalar(@$args) == 2) {
	$error = 1;
	push @$out, [ "error", "This command takes exactly 1 argument.  Consult the reference." ];
    }
    
    return 0 if ($error);

    my ($user) = ($args->[1]);
    my $banid = &LJ::get_userid($dbh, $user);

    unless ($banid) {
	$error = 1;
	push @$out, [ "error", "Invalid user \"$user\"" ];
    }
    unless ($remote->{'userid'}) {
	$error = 1;
	push @$out, [ "error", "You have to be logged in to LiveJournal to use this command" ];
    }
    
    return 0 if ($error);    

    my $qbanid = $banid+0;
    my $quserid = $remote->{'userid'}+0;

    my $sth = $dbh->prepare("DELETE FROM ban WHERE userid=$quserid AND banneduserid=$qbanid");
    $sth->execute;

    push @$out, [ "info", "User $user ($banid) un-banned." ];
    return 1;
}


1;


