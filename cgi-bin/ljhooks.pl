package LJ;
use strict;

# <LJFUNC>
# name: LJ::are_hooks
# des: Returns true if the site has one or more hooks installed for
#      the given hookname.
# args: hookname
# </LJFUNC>
sub are_hooks
{
    my $hookname = shift;
    return defined $LJ::HOOKS{$hookname};
}

# <LJFUNC>
# name: LJ::clear_hooks
# des: Removes all hooks.
# </LJFUNC>
sub clear_hooks
{
    %LJ::HOOKS = ();
}

# <LJFUNC>
# name: LJ::run_hooks
# des: Runs all the site-specific hooks of the given name.
# returns: list of arrayrefs, one for each hook ran, their
#          contents being their own return values.
# args: hookname, args*
# des-args: Arguments to be passed to hook.
# </LJFUNC>
sub run_hooks
{
    my ($hookname, @args) = @_;
    my @ret;
    foreach my $hook (@{$LJ::HOOKS{$hookname} || []}) {
        push @ret, [ $hook->(@args) ];
    }
    return @ret;
}

# <LJFUNC>
# name: LJ::run_hook
# des: Runs single site-specific hook of the given name.
# returns: return value from hook
# args: hookname, args*
# des-args: Arguments to be passed to hook.
# </LJFUNC>
sub run_hook
{
    my ($hookname, @args) = @_;
    return undef unless @{$LJ::HOOKS{$hookname} || []};
    return $LJ::HOOKS{$hookname}->[0]->(@args);
}

# <LJFUNC>
# name: LJ::register_hook
# des: Installs a site-specific hook.
# info: Installing multiple hooks per hookname is valid.
#       They're run later in the order they're registered.
# args: hookname, subref
# des-subref: Subroutine reference to run later.
# </LJFUNC>
sub register_hook
{
    my $hookname = shift;
    my $subref = shift;
    push @{$LJ::HOOKS{$hookname}}, $subref;
}

# <LJFUNC>
# name: LJ::register_setter
# des: Installs code to run for the "set" command in the console.
# info: Setters can be general or site-specific.
# args: key, subref
# des-key: Key to set.
# des-subref: Subroutine reference to run later.
# </LJFUNC>
sub register_setter
{
    my $key = shift;
    my $subref = shift;
    $LJ::SETTER{$key} = $subref;
}

register_setter('synlevel', sub {
    my ($dba, $u, $remote, $key, $value, $err) = @_;
    unless ($value =~ /^(title|summary|full)$/) {
        $$err = "Illegal value.  Must be 'title', 'summary', or 'full'";
        return 0;
    }

    LJ::set_userprop($u, 'opt_synlevel', $value);
    return 1;
});

register_setter("newpost_minsecurity", sub {
    my ($dba, $u, $remote, $key, $value, $err) = @_;
    unless ($value =~ /^(public|friends|private)$/) {
        $$err = "Illegal value.  Must be 'public', 'friends', or 'private'";
        return 0;
    }
    # Don't let commmunities be private
    if ($u->{'journaltype'} eq "C" && $value eq "private") {
        $$err = "newpost_minsecurity cannot be private for communities";
        return 0;
    }
    $value = "" if $value eq "public";
    LJ::set_userprop($u, "newpost_minsecurity", $value);
    return 1;
});

register_setter("stylesys", sub {
    my ($dba, $u, $remote, $key, $value, $err) = @_;
    unless ($value =~ /^[sS]?(1|2)$/) {
        $$err = "Illegal value.  Must be S1 or S2.";
        return 0;
    }
    $value = $1 + 0;
    LJ::set_userprop($u, "stylesys", $value);
    return 1;
});

register_setter("maximagesize", sub {
    my ($dba, $u, $remote, $key, $value, $err) = @_;
    unless ($value =~ m/^(\d+)[x,|](\d+)$/) {
        $$err = "Illegal value.  Must be width,height.";
        return 0;
    }
    $value = "$1|$2";
    LJ::set_userprop($u, "opt_imagelinks", $value);
    return 1;
});

register_setter("opt_ljcut_disable_lastn", sub {
    my ($dba, $u, $remote, $key, $value, $err) = @_;
    unless ($value =~ /^(0|1)$/) {
        $$err = "Illegal value. Must be '0' or '1'";
        return 0;
    }
    LJ::set_userprop($u, "opt_ljcut_disable_lastn", $value);
    return 1;
});

register_setter("opt_ljcut_disable_friends", sub {
    my ($dba, $u, $remote, $key, $value, $err) = @_;
    unless ($value =~ /^(0|1)$/) {
        $$err = "Illegal value. Must be '0' or '1'";
        return 0;
    }
    LJ::set_userprop($u, "opt_ljcut_disable_friends", $value);
    return 1;
});

register_setter("disable_quickreply", sub {
    my ($dba, $u, $remote, $key, $value, $err) = @_;
    unless ($value =~ /^(0|1)$/) {
        $$err = "Illegal value. Must be '0' or '1'";
        return 0;
    }
    LJ::set_userprop($u, "opt_no_quickreply", $value);
    return 1;
});

register_setter("disable_nudge", sub {
    my ($dba, $u, $remote, $key, $value, $err) = @_;
    unless ($value =~ /^(0|1)$/) {
        $$err = "Illegal value. Must be '0' or '1'";
        return 0;
    }
    LJ::set_userprop($u, "opt_no_nudge", $value);
    return 1;
});

register_setter("trusted_s1", sub {
    my ($dba, $u, $remote, $key, $value, $err) = @_;
    unless ($value =~ /^(\d+,?)+$/) {
        $$err = "Illegal value. Must be a comma separated list of style ids";
        return 0;
    }
    LJ::set_userprop($u, "trusted_s1", $value);
    return 1;
});

register_setter("icbm", sub {
    my ($dba, $u, $remote, $key, $value, $err) = @_;
    my $loc = eval { LJ::Location->new(coords => $value); };
    unless ($loc) {
        LJ::set_userprop($u, "icbm", "");  # unset
        $$err = "Illegal value.  Not a recognized format." if $value;
        return 0;
    }
    LJ::set_userprop($u, "icbm", $loc->as_posneg_comma);
    return 1;
});

1;
