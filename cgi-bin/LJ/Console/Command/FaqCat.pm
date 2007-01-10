package LJ::Console::Command::FaqCat;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "faqcat" }

sub desc { "Tool for managing FAQ categories." }

sub args_desc { [
                 'command' => "One of: list, delete, add, move.  'list' shows all the defined FAQ categories, including their catkey, name, and sortorder.  Also, it shows all the distinct catkeys that are in use by FAQ. 'add' creates or modifies a FAQ category. 'delete' removes a FAQ category (but not the questions that are in it). 'move' moves a FAQ category up or down in the list.",
                 'commandargs' => "'add' takes 3 arguments: a catkey, a catname, and a sort order field. 'delete' takes one argument: the catkey value. 'move' takes two arguments: the catkey and either the word 'up' or 'down'."
                 ] }

sub usage { '<command> <commandargs>' }

sub can_execute {
    my $remote = LJ::get_remote();
    LJ::check_priv($remote, "faqcat");
}

sub execute {
    my ($self, @args) = @_;

    # TODO: If the command is "list", we don't need the user to have any privs
    # at all, but we don't even call ->execute if can_execute returns false

    my $command = shift @args;

    if ($command eq "list") {

    }

    return 1;
}

1;
