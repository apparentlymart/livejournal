package LJ::Console::Command::PrivPackage;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "priv_package" }

sub desc { "Manage packages of admin privs. Basic workflow: priv_package create mypkg \"Test Package\", priv_package add mypkg admin:*, priv_package list. To actually grant a package to someone, priv grant #mypkg username. Works for revoke as well." }

sub args_desc { [
                 'command' => 'One of "list", "create", "add", "remove", "delete".',
                 'package' => 'The package to operate on.  Use a short name.',
                 'arg' => 'If command is "list", no argument to see all packages, or provide a package to see the privs inside. For "create" and "delete" of a package, no argument.  For "add" and "remove", arg is the privilege being granted in "privname:privarg" format.',
                 ] }

sub usage { '<command> [ <package> [ <arg> ] ]' }

sub can_execute { 1 }

sub execute {
    my ($self, @args) = @_;

    return 1;
}

1;
