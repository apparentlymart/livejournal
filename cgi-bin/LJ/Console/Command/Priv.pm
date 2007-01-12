package LJ::Console::Command::Priv;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "priv" }

sub desc { "Grant or revoke user privileges." }

sub args_desc { [
                 'action'    => "'grant', 'revoke', or 'revoke_all' to revoke all args for a given priv",
                 'privs'     => "Comma-delimited list of priv names, priv:arg pairs, or package names (prefixed with #)",
                 'usernames' => "Comma-delimited list of usernames",
                 ] }

sub usage { '<action> <privs> <usernames>' }

sub can_execute { 1 }

sub execute {
    my ($self, $action, $privs, $usernames, @args) = @_;

    return $self->error("This command takes three arguments. Consult the reference.")
        unless $action && $privs && $usernames && scalar(@args) == 0;

    return $self->error("Action must be one of 'grant', 'revoke', or 'revoke_all'")
        unless $action =~ /(?:grant|revoke|revoke\_all)/;

    my @users = split /,/, $usernames;
    my @privlist = split /,/, $privs;
    my $dbh = LJ::get_db_reader();

    my @privs;

    foreach my $priv (split /,/, $privs) {
        if ($priv !~ /^#/) {
            push @privs, [ split /:/, $priv, 2 ];
        } else {
            # now we have a priv package
            my $pname = substr($_, 1);
            my $privs = $dbh->selectall_arrayref("SELECT c.privname, c.privarg "
                                                 . "FROM priv_packages p, priv_packages_content c "
                                                 . "WHERE c.pkgid = p.pkgid AND p.name = ?", undef, $pname);
            push @privs, [ @$_ ] foreach @{$privs || []};
        }
    }

    return $self->error("No privs or priv packages specified")
        unless @privs;

    my $remote = LJ::get_remote();
    foreach my $pair (@privs) {
        my ($priv, $arg) = @$pair;
        unless (LJ::check_priv($remote, "admin", "$priv") || LJ::check_priv($remote, "admin", "$priv/$arg")) {
            $self->error("You are not permitted to $action $priv:$arg");
            next;
        }

        foreach my $user (@users) {
            my $u = LJ::load_user($user);
            if (LJ::check_priv($u, $priv, $arg)) {
                $self->error("$user already has $priv:$arg");
                next;
            }

            my $shmsg;
            my $rv;
            if ($action eq "grant") {
                $rv = $u->grant_priv($priv, $arg);
                $shmsg = "Granting: '$priv' with arg '$arg'";
            } elsif ($action eq "revoke") {
                $rv = $u->revoke_priv($priv, $arg);
                $shmsg = "Denying: '$priv' with arg '$arg'";
            } else {
                $rv = $u->revoke_priv_all($priv);
                $shmsg = "Denying: '$priv' with all args";
            }

            return $self->error("Unable to $action $priv:$arg")
                unless $rv;

            $self->info($shmsg);

            my $shtype = ($action eq "grant") ? "privadd" : "privdel";
            LJ::statushistory_add($u, $remote, $shtype, $shmsg);
        }
    }

    return 1;
}

1;
