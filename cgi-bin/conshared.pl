#!/usr/bin/perl
#

package ljcon;

$cmd{'shared'}->{'handler'} = \&shared;
$cmd{'community'}->{'handler'} = \&community;

sub shared
{
    my ($dbh, $remote, $args, $out) = @_;
    my $error = 0;

    unless (scalar(@$args) == 4) {
	$error = 1;
	push @$out, [ "error", "This command takes exactly 3 arguments.  Consult the reference." ];
    }
    
    return 0 if ($error);

    my ($shared_user, $action, $target_user) = ($args->[1], $args->[2], $args->[3]);
    my $shared_id = &LJ::get_userid($dbh, $shared_user);
    my $target_id = &LJ::get_userid($dbh, $target_user);

    unless ($action eq "add" || $action eq "remove") {
	$error = 1;
	push @$out, [ "error", "Invalid action \"$action\" ... expected 'add' or 'remove'" ];
    }
    unless ($shared_id) {
	$error = 1;
	push @$out, [ "error", "Invalid shared journal \"$shared_user\"" ];
    }
    unless ($target_id) {
	$error = 1;
	push @$out, [ "error", "Invalid user \"$target_user\" to add/remove" ];
    }
    if ($target_id && $target_id==$shared_id) {
	$error = 1;
	push @$out, [ "error", "Target user can't be shared journal user." ];
    }
    
    unless ($remote->{'privarg'}->{'sharedjournal'}->{$shared_user} ||
	    $remote->{'privarg'}->{'sharedjournal'}->{'all'}) 
    {
	$error = 1;
	push @$out, [ "error", "You don't have access to add/remove users to this shared journal." ];
    }
    
    return 0 if ($error);    
    
    if ($action eq "add") {
	$dbh->do("REPLACE INTO logaccess (ownerid, posterid) VALUES ($shared_id, $target_id)");
	push @$out, [ "info", "User \"$target_user\" can now post in \"$shared_user\"." ];
    } 
    if ($action eq "remove") {
	$dbh->do("DELETE FROM logaccess WHERE ownerid=$shared_id AND posterid=$target_id");
	push @$out, [ "info", "User \"$target_user\" can no longer post in \"$shared_user\"." ];
    }

    return 1;
}

sub community
{
    my ($dbh, $remote, $args, $out) = @_;
    my $error = 0;
    my $sth;

    unless (scalar(@$args) == 4) {
	$error = 1;
	push @$out, [ "error", "This command takes exactly 3 arguments.  Consult the reference." ];
    }
    
    return 0 if ($error);

    my ($com_user, $action, $target_user) = ($args->[1], $args->[2], $args->[3]);
    my $com_id = &LJ::get_userid($dbh, $com_user);
    my $target_id = &LJ::get_userid($dbh, $target_user);

    my $ci;
    
    unless ($action eq "add" || $action eq "remove") {
	$error = 1;
	push @$out, [ "error", "Invalid action \"$action\" ... expected 'add' or 'remove'" ];
    }
    unless ($com_id) {
	$error = 1;
	push @$out, [ "error", "Invalid community \"$com_user\"" ];
    } 
    else 
    {
	$sth = $dbh->prepare("SELECT userid, ownerid, membership, postlevel FROM community WHERE userid=$com_id");
	$sth->execute;
	$ci = $sth->fetchrow_hashref;
	
	unless ($ci) {
	    $error = 1;
	    push @$out, [ "error", "\"$com_user\" isn't a registered community." ];
	}
    }

    unless ($target_id) {
	$error = 1;
	push @$out, [ "error", "Invalid user \"$target_user\" to add/remove" ];
    }
    if ($target_id && $target_id==$com_id) {
	$error = 1;
	push @$out, [ "error", "Target user can't be shared journal user." ];
    }
    
    unless ($remote->{'privarg'}->{'sharedjournal'}->{$com_user} ||
	    $remote->{'privarg'}->{'sharedjournal'}->{'all'}) 
    {
	$error = 1;
	push @$out, [ "error", "You don't have access to add/remove users to this shared journal." ];
    }
    
    return 0 if ($error);    
    
    if ($action eq "add") 
    {
	$dbh->do("INSERT INTO friends (userid, friendid, fgcolor, bgcolor, groupmask) VALUES ($com_id, $target_id, '#000000', '#ffffff', 1)");
	push @$out, [ "info", "User \"$target_user\" is now a member of \"$com_user\"." ];
	
	if ($ci->{'postlevel'} eq "members") {
	    $dbh->do("REPLACE INTO logaccess (ownerid, posterid) VALUES ($com_id, $target_id)");
	    push @$out, [ "info", "User \"$target_user\" can now post in \"$com_user\"." ];
	} 
    }
	
    if ($action eq "remove") {
	$dbh->do("DELETE FROM friends WHERE userid=$com_id AND friendid=$target_id");
	push @$out, [ "info", "User \"$target_user\" is no longer a member of \"$com_user\"." ];

	$dbh->do("DELETE FROM logaccess WHERE ownerid=$com_id AND posterid=$target_id");
	push @$out, [ "info", "User \"$target_user\" can no longer post in \"$com_user\"." ];
    }

    return 1;
}

1;


