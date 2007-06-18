package LJ::Console::Command::EmailAlias;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "email_alias" }

sub desc { "View and edit email aliases." }

sub args_desc { [
                      action        => "One of: 'show' (to view recipient), 'delete' (to delete), or 'set' (to set a value)",
                      alias         => "The first portion of the email alias (eg, just the username)",
                      value         => "Value to set the email alias to, if using 'set'.",
                 ] }

sub usage { '<action> <alias> [ <value> ]' }

sub can_execute {
    my $remote = LJ::get_remote();
    return LJ::check_priv($remote, "reset_email");
}

sub execute {
    my ($self, $action, $alias, $value, @args) = @_;

    return $self->error("This command takes two or three arguments. Consult the reference.")
        unless $action && $alias && scalar(@args) == 0;

    return $self->error("Invalid action. Must be either 'show', 'delete', or 'set'.")
        unless $action =~ /^(?:show|delete|set)$/;

    # canonicalize
    $alias =~ s/\@.*//;
    $alias .= "@" . $LJ::USER_DOMAIN;

    my $dbh = LJ::get_db_writer();

    if ($action eq "set") {
        my @emails = split(/,/, $value);
        return $self->error("You must specify a recipient for the email alias.")
            unless scalar(@emails);

        my @errors;
        LJ::check_email($_, \@errors) foreach @emails;
        return $self->error("One or more of the email addresses you have specified is invalid.")
            if @errors;

        $dbh->do("REPLACE INTO email_aliases VALUES (?, ?)", undef, $alias, $value);
        return $self->error("Database error: " . $dbh->errstr)
            if $dbh->err;
        return $self->print("Successfully set $alias => $value");

    } elsif ($action eq "delete") {
        $dbh->do("DELETE FROM email_aliases WHERE alias=?", undef, $alias);
        return $self->error("Database error: " . $dbh->errstr)
            if $dbh->err;
        return $self->print("Successfully deleted $alias alias.");

    } else {

        my ($rcpt) = $dbh->selectrow_array("SELECT rcpt FROM email_aliases WHERE alias=?", undef, $alias);
        return $self->error("Database error: " . $dbh->errstr)
            if $dbh->err;

        if ($rcpt) {
            return $self->print("$alias aliases to $rcpt");
        } else {
            return $self->error("$alias is not currently defined.");
        }
    }

}

1;
