#!/usr/bin/perl
#

use strict;
package LJ::Con;

use vars qw(%cmd);

$cmd{'shared'}->{'handler'} = \&shared;
$cmd{'community'}->{'handler'} = \&community;
$cmd{'change_community_admin'}->{'handler'} = \&change_community_admin;

sub change_community_admin
{
    my ($dbh, $remote, $args, $out) = @_;
    my $sth;
    my $err = sub { push @$out, [ "error", $_[0] ]; return 0; };

    return $err->("This command takes exactly 2 arguments.  Consult the reference.")
	unless scalar(@$args) == 3;

    my ($comm_name, $newowner_name) = ($args->[1], $args->[2]);
    my $ucomm = LJ::load_user($dbh, $comm_name);
    my $unew  = LJ::load_user($dbh, $newowner_name);

    return $err->("Given community doesn't exist or isn't a community.")
	unless ($ucomm && $ucomm->{'journaltype'} eq "C");

    return $err->("New owner doesn't exist or isn't a person account.")
	unless ($unew && $unew->{'journaltype'} eq "P");

    return $err->("You do not have access to transfer ownership of this community.")
	unless ($remote->{'privarg'}->{'sharedjournal'}->{$ucomm->{'user'}} ||
		$remote->{'priv'}->{'communityxfer'} );

    return $err->("New owner's email address isn't validated.")
	unless ($unew->{'status'} eq "A");
    
    my $commid = $ucomm->{'userid'};
    my $newid = $unew->{'userid'};

    my $prlid = $dbh->selectrow_array("SELECT prlid FROM priv_list WHERE privcode='sharedjournal'");
    return $err->("No sharedjournal priv.  (broken LJ installation?)")
	unless $prlid;

    my $oldid = $dbh->selectrow_array("SELECT ownerid FROM community WHERE userid=$commid");
    my $uold = LJ::load_userid($dbh, $oldid);

    # remove old maintainer's power over it
    $dbh->do("DELETE FROM priv_map WHERE prlid=$prlid AND arg='$ucomm->{'user'}'");
    $dbh->do("UPDATE community SET ownerid=$newid WHERE userid=$commid");
    $dbh->do("INSERT INTO priv_map (userid, prlid, arg) VALUES ($newid, $prlid, '$ucomm->{'user'}')");

    # so old maintainer can't regain access:
    $dbh->do("DELETE FROM infohistory WHERE userid=$commid");

    # change password of community to new maintainer's password
    my $qpass = $dbh->quote($unew->{'password'});
    $dbh->do("UPDATE user SET password=$qpass WHERE userid=$commid");

    ## log to status history
    if ($uold) {
	LJ::statushistory_add($dbh, $oldid, $remote->{'userid'}, "communityxfer", "Control of '$ucomm->{'user'}'($commid) taken away.");
    }
    LJ::statushistory_add($dbh, $commid, $remote->{'userid'}, "communityxfer", "Changed maintainer from '$uold->{'user'}'($oldid) to '$unew->{'user'}'($newid)");
    LJ::statushistory_add($dbh, $newid, $remote->{'userid'}, "communityxfer", "Control of '$ucomm->{'user'}'($commid) given.");

    push @$out, [ "info", "Transfered ownership of \"$ucomm->{'user'}\"." ];
    return 1;
}

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
    my $shared_id = LJ::get_userid($dbh, $shared_user);
    my $target_id = LJ::get_userid($dbh, $target_user);

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
    my $com_id = LJ::get_userid($dbh, $com_user);
    my $target_id = LJ::get_userid($dbh, $target_user);

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


