package LJ::Console::Command::BanUnset;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "ban_unset" }

sub desc { "Remove a ban on a user." }

sub args_desc { [
                 'user' => "The user you want to unban.",
                 'community' => "Optional; to unban a user from a community you maintain.",
               ] }

sub usage { '[<user>|+inactive] [ "from" <community> ]' }

sub can_execute { 1 }

sub execute {
    my ($self, $user, @args) = @_;
    my $remote = LJ::get_remote();
    my $journal = $remote;         # may be overridden later

    return $self->error("Incorrect number of arguments. Consult the reference.")
        unless $user && (scalar(@args) == 0 || scalar(@args) == 2);

    if (scalar(@args) == 2) {
        my ($from, $comm) = @args;
        return $self->error("First argument must be 'from'")
            if $from ne "from";

        $journal = LJ::load_user($comm);
        return $self->error("Unknown account: $comm")
            unless $journal;

        return $self->error("You are not a maintainer of this account")
            unless $remote && $remote->can_manage($journal);
    }

    ## 
    ## It's possible to remove users from a ban list one by one
    ## or perform a mass action.
    ## Currently supported only one form of a mass unban command:
    ##
    ##      ban_unset +inactive [from <community>]
    ##
    ##   It removes suspended (eXpurged) users from ban list, 
    ##   becouse there no any reason to keep such users in the list.
    ##

    if ($user eq '+inactive'){
    ## remove suspended users from ban list
        
        ## get User IDs
        my $banids  = LJ::load_rel_user($journal, 'B') || [];
        
        while (my @ids_batch = splice(@$banids, 0 => 500)){
            ## load users
            my $us = LJ::load_userids(@ids_batch);
            while (my (undef, $banuser) = each %$us){
                ## We are interested in suspended or expunged users only.
                if ($banuser->is_suspended or $banuser->is_expunged){
                    ## remove suspended user from ban list
                    ban_unset($remote, $journal, $banuser);
                    $self->print("User " . $banuser->user . " unbanned from " . $journal->user);
                }
            }
        }
    } else {
    ## remove specified users from ban list
        my $banuser = LJ::load_user($user);
        return $self->error("Unknown account: $user")
            unless $banuser;

        ban_unset($remote, $journal, $banuser);

        return $self->print("User " . $banuser->user . " unbanned from " . $journal->user);
    }

    return 1;
}

sub ban_unset {
    my ($remote, $journal, $banuser) = @_;

    LJ::clear_rel($journal, $banuser, 'B');
    $journal->log_event('ban_unset', { actiontarget => $banuser->id, remote => $remote });

    LJ::run_hooks('ban_unset', $journal, $banuser);


}





1;
