#!/usr/bin/perl
#

package LJ::Con;

$cmd{'ban_set'}->{'handler'} = \&ban_set_unset;
$cmd{'ban_unset'}->{'handler'} = \&ban_set_unset;
$cmd{'ban_list'}->{'handler'} = \&ban_list;

sub ban_list
{
    my ($dbh, $remote, $args, $out) = @_;

    unless ($remote) {
        push @$out, [ "error", "You must be logged in to use this command." ];
        return 0;
    }

    # journal to list from
    my $j = $remote;

    unless ($remote->{'journaltype'} eq "P") {
        push @$out, [ "error", "Only people can list banned users, not communities (you're not logged in as a person account)." ];
        return 0;
    }

    if (scalar(@$args) == 3) {
        unless ($args->[1] eq "from") {
            push @$out, [ "error", "First argument not 'from'." ];
            return 0;
        }

        $j = LJ::load_user($args->[2]);
        if (!$j) {
            push @$out, [ "error", "Unknown account." ];
            return 0;
        }

        unless (LJ::check_priv($remote, "finduser")) {
            if ($j->{journaltype} ne 'C') {
                push @$out, [ "error", "Account is not a community." ];
                return 0;
            } elsif (!LJ::can_manage($remote, $j)) {
                push @$out, [ "error", "Not maintainer of this community." ];
                return 0;
            }
        }
    }
    
    my $banids = LJ::load_rel_user($j->{userid}, 'B') || [];
    my $us = LJ::load_userids(@$banids);
    my @userlist = map { $us->{$_}{user} } keys %$us;

    foreach my $username (@userlist) {
        push @$out, [ 'info', $username ];
    }
    push @$out, [ "info", "$j->{user} has not banned any other users." ] unless @userlist;
    return 1;
}

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

    unless ($remote->{'journaltype'} eq "P") {
        push @$out, [ "error", "Only people can ban other users, not communities (you're not logged in as a person account)." ],
        return 0;
    }

    if (scalar(@$args) == 4) {
        unless ($args->[2] eq "from") {
            $error = 1;
            push @$out, [ "error", "2nd argument not 'from'" ];
        }

        $j = LJ::load_user($args->[3]);
        if (! $j) {
            $error = 1;
            push @$out, [ "error", "Unknown community." ],
        } elsif (! LJ::can_manage_other($remote, $j)) {
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

    # exceeded ban limit?
    if ($args->[0] eq 'ban_set') {
        my $banlist = LJ::load_rel_user($quserid, 'B') || [];
        if (scalar(@$banlist) >= ($LJ::MAX_BANS || 5000)) {
            push @$out, [ "error", "You have reached the maximum number of bans.  Unban someone and try again." ];
            return 0;
        }
    }

    if ($args->[0] eq "ban_set") {
        LJ::set_rel($quserid, $qbanid, 'B');
        $j->log_event('ban_set', { actiontarget => $banid, remote => $remote });
        push @$out, [ "info", "User $user ($banid) banned from $j->{'user'}." ];
        return 1;
    }

    if ($args->[0] eq "ban_unset") {
        LJ::clear_rel($quserid, $qbanid, 'B');
        $j->log_event('ban_unset', { actiontarget => $banid, remote => $remote });
        push @$out, [ "info", "User $user ($banid) un-banned from $j->{'user'}." ];
        return 1;
    }

    return 0;
}


1;
