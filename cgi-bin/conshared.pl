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
    my $ucomm = LJ::load_user($comm_name);
    my $unew  = LJ::load_user($newowner_name);

    return $err->("Given community doesn't exist or isn't a community.")
        unless ($ucomm && $ucomm->{'journaltype'} eq "C");

    return $err->("New owner doesn't exist or isn't a person account.")
        unless ($unew && $unew->{'journaltype'} eq "P");

    return $err->("You do not have access to transfer ownership of this community.")
        unless $remote->{'priv'}->{'communityxfer'};

    return $err->("New owner's email address isn't validated.")
        unless ($unew->{'status'} eq "A");
    
    my $commid = $ucomm->{'userid'};
    my $newid = $unew->{'userid'};

    # remove old maintainers' power over it
    LJ::clear_rel($ucomm, '*', 'A');

    # add a new sole maintainer
    LJ::set_rel($ucomm, $newid, 'A');

    # so old maintainers can't regain access:
    $dbh->do("DELETE FROM infohistory WHERE userid=$commid");

    # change password to blank & set email of community to new maintainer's email
    LJ::update_user($ucomm, { password => '', email => $unew->email_raw });

    ## log to status history
    LJ::statushistory_add($commid, $remote->{'userid'}, "communityxfer", "Changed maintainer to '$unew->{'user'}'($newid)");
    LJ::statushistory_add($newid, $remote->{'userid'}, "communityxfer", "Control of '$ucomm->{'user'}'($commid) given.");

    push @$out, [ "info", "Transferred ownership of \"$ucomm->{'user'}\" to \"$unew->{'user'}\"." ];
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
    
    return 0 if $error;

    my ($shared_user, $action, $target_user) = ($args->[1], $args->[2], $args->[3]);
    my $shared = LJ::load_user($shared_user);
    my $shared_id = $shared->{'userid'};
    my $target = LJ::load_user($target_user);
    my $target_id = $target->{'userid'};

    unless ($action eq "add" || $action eq "remove") {
        $error = 1;
        push @$out, [ "error", "Invalid action \"$action\" ... expected 'add' or 'remove'" ];
    }
    unless ($shared_id) {
        $error = 1;
        push @$out, [ "error", "Invalid shared journal \"$shared_user\"" ];
    }
    unless ($shared->{'journaltype'} eq 'S') {
        $error = 1;
        push @$out, [ "error", "\"$shared_user\" is not a shared journal" ];
    }
    unless ($target_id) {
        $error = 1;
        push @$out, [ "error", "Invalid user \"$target_user\" to add/remove" ];
    } elsif ($target_id == $shared_id) {
        $error = 1;
        push @$out, [ "error", "Target user can't be shared journal user." ];
    }
    
    unless (LJ::can_manage($remote, $shared_id) ||
            $remote->{'privarg'}->{'sharedjournal'}->{'*'}) 
    {
        $error = 1;
        push @$out, [ "error", "You don't have access to add/remove users to this shared journal." ];
    }
    
    return 0 if ($error);    
    
    if ($action eq "add") {
        if (LJ::check_rel($shared_id, $target_id, 'P')) {
            push @$out, [ "error", "User \"$target->{'user'}\" already has posting access to this shared journal." ];
            return 0;
        }
        # don't send request if the admin is giving themselves posting access
        if ($target->{'user'} eq $remote->{'user'}) {
            LJ::set_rel($shared, $target, 'P');
            push @$out, [ "info", "User \"$target_user\" has been given posting access to \"$shared_user\"." ];
        } else {
            my $res = LJ::shared_member_request($shared, $target);
            unless ($res) {
                push @$out, [ 'error', "Could not add user." ];
                return 0;
            }
            if ($res->{'datecreate'}) {
                push @$out, [ 'error', "User \"$target->{'user'}\" already mailed on: $res->{'datecreate'}" ];
                return 0;
            }

            push @$out, [ "info", "User \"$target_user\" has been sent a confirmation email and will be able to post in \"$shared_user\" once they confirm this action." ];
        }
    }
    if ($action eq "remove") {
        LJ::clear_rel($shared_id, $target_id, 'P');
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
    my $comm = LJ::load_user($com_user);
    my $com_id = $comm->{'userid'};
    my $target = LJ::load_user($target_user);
    my $target_id = $target->{'userid'};

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
        $ci = $dbh->selectrow_hashref("SELECT userid, membership, postlevel FROM community WHERE userid=$com_id");
        
        unless ($ci) {
            $error = 1;
            push @$out, [ "error", "\"$com_user\" isn't a registered community." ];
        }
    }

    unless ($target_id) {
        $error = 1;
        push @$out, [ "error", "Invalid user \"$target_user\" to add/remove" ];
    } elsif ($target_id == $com_id) {
        $error = 1;
        push @$out, [ "error", "User \"$target_user\" can't be shared journal user." ];
    } elsif ($target->{'journaltype'} ne 'P') {
        $error = 1;
        push @$out, [ "error", "Cannot add community/syndicated account to community." ];
    }

    
    # user doesn't need admin priv to remove themselves from community

    unless (LJ::can_manage_other($remote, $com_id) ||
            $remote->{'privarg'}->{'sharedjournal'}->{'*'} ||
            ($remote->{'user'} eq $target_user && $action eq "remove")) 
    {
        my $modifier = $action eq "add" ? "to" : "from";
        $error = 1;
        push @$out, [ "error", "You don't have access to $action users $modifier this shared journal." ];
    }
    
    return 0 if ($error);    
    
    if ($action eq "add") 
    {
        push @$out, [ 'error', 'The ability to add users to a community through the console has been removed.' ];
        push @$out, [ 'error', 'Users must now request to be added to a community by visiting the community\'s' ];
        push @$out, [ 'error', 'profile page and clicking the link to join.' ];
    }
        
    if ($action eq "remove") {
        LJ::remove_friend($com_id, $target_id);
        push @$out, [ "info", "User \"$target_user\" is no longer a member of \"$com_user\"." ];

        LJ::clear_rel($com_id, $target_id, 'P');
        LJ::clear_rel($com_id, $target_id, 'N');
        push @$out, [ "info", "User \"$target_user\" can no longer post in \"$com_user\"." ];
    }

    return 1;
}

1;
