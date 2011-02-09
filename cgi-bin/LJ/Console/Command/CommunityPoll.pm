package LJ::Console::Command::CommunityPoll;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "community_poll" }

sub desc { "Start an election for choosen community and maintainers." }

sub args_desc { [
                 'communityname' => "The community for start election on.",
                 'maintainer<n>' => "Maintainer(s) for election",
                 ] }

sub usage { '<community> [<maintainer1>,<maintainer2>,...]' }

sub can_execute {
    my $remote = LJ::get_remote();
    return LJ::check_priv($remote, "communityxfer", "*");
}

sub execute {
    my ($self, @args) = @_;

    return $self->error("This command takes at least one argument. Consult the reference.")
        if scalar(@args) < 1;

    my $comm_name = shift @args;
    my $c = LJ::load_user($comm_name);
    return $self->error("Community must be undeleted")
        if $c->is_expunged;

    my $maint_list = shift @args;
    my $confirm = undef;
    if ($maint_list eq 'confirm') {
        $confirm = 'confirm';
        my $m_list = LJ::load_rel_user($c->userid, 'A');
        $maint_list = join ',', map { $_->{user} } values %{LJ::load_userids(@$m_list)};
    } else {
        $confirm = shift @args;
    }

    my @maintainers = split /,/, $maint_list;

    return $self->error("Election poll exists already")
        if ($c->prop("election_poll_id") && $confirm ne 'confirm');

    ## Check for maintainers alive
    @maintainers = map {
        my $u = LJ::load_user($_);
        $u;
    } grep {
        my $u = LJ::load_user($_);
        $u && $u->is_visible && !$u->is_expunged && $u->can_manage($c) ? 1 : 0;
    } @maintainers;

    my $log = '';
    my $poll_id = LJ::create_supermaintainer_election_poll (
            comm_id     => $c->userid, 
            maint_list  => \@maintainers, 
            log         => \$log,
            no_job      => 0,
    );

    return $self->error("Can't create poll")
        unless $poll_id;

    $c->set_prop ("election_poll_id", $poll_id);

    return 1;
}

1;
