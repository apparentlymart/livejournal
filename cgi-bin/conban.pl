#!/usr/bin/perl
#

package LJ::Con;

$cmd{'ban_set'}->{'handler'} = \&ban_set_unset;
$cmd{'ban_unset'}->{'handler'} = \&ban_set_unset;

sub ban_set_unset
{
    my ($dbh, $remote, $args, $out) = @_;
    my $error = 0;

    unless ($remote) {
	push @$out, [ "error", "You must be logged in to use this command" ];
	return 0;
    }

    # journal to ban from:
    my $j;

    LJ::load_remote($dbh, $remote);
    unless ($remote->{'journaltype'} eq "P") {
	push @$out, [ "error", "Only people can ban other users, not communities (you're not logged in as a person account." ],
	return 0;
    }

    if (scalar(@$args) == 4) {
	unless ($args->[2] eq "from") {
	    $error = 1;
	    push @$out, [ "error", "2nd argument not 'from'" ];
	}

	$j = LJ::load_user($dbh, $args->[3]);
	if (! $j) {
	    $error = 1;
	    push @$out, [ "error", "Unknown community." ],
	} elsif (! LJ::check_priv($dbh, $remote, "sharedjournal", $j->{'user'})) {
	    $error = 1;
	    push @$out, [ "error", "Not maintainer of this community." ],
	}

    } else {
	if (scalar(@$args) == 2) {
	    # banning from the remote user's journal
	    $j = $remote;
	} else {
	    $error = 1;
	    push @$out, [ "error", "This form of the command takes exactly 1 argument.  Consult the reference." ];
	}
    }
    
    return 0 if ($error);

    my $user = $args->[1];
    my $banid = LJ::get_userid($dbh, $user);

    unless ($banid) {
	$error = 1;
	push @$out, [ "error", "Invalid user \"$user\"" ];
    }
    
    return 0 if ($error);    

    my $qbanid = $banid+0;
    my $quserid = $j->{'userid'}+0;

    if ($args->[0] eq "ban_set") {
	my $sth = $dbh->prepare("REPLACE INTO ban (userid, banneduserid) ".
				"VALUES ($quserid, $qbanid)");
	$sth->execute;
	push @$out, [ "info", "User $user ($banid) banned from $j->{'user'}." ];
	return 1;
    }

    if ($args->[0] eq "ban_unset") {
	my $sth = $dbh->prepare("DELETE FROM ban WHERE ".
				"userid=$quserid AND banneduserid=$qbanid");
	$sth->execute;
	
	push @$out, [ "info", "User $user ($banid) un-banned from $j->{'user'}." ];
	return 1;
    }

    return 0;
}


1;
