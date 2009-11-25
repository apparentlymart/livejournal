package LJ::Console::Command::DumpEmails;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "dump_emails" }

sub desc { "Dumps information about all email addresses that a particular user has used previously or uses now." }

sub args_desc { [
                 'user' => "Username.",
                 ] }

sub usage { '<user>' }

sub can_execute {
    my $remote = LJ::get_remote();
    return LJ::check_priv($remote, "finduser", "dump_emails");
}

sub execute {
    my ($self, @args) = @_;

    my ($username) = @args;

    my $userid = LJ::get_userid($username);

    return $self->error('Cannot find the specified user.')
        unless $userid;

    my $u = LJ::want_user($userid);

    my $dump_time = sub {
        my $timestamp = shift;
        return scalar localtime $timestamp;
    };

    my $emails = $u->emails_info;
    foreach my $email (@$emails) {
        my @info;

        push @info, $email->{'email'};

        push @info, 'current'
            if $email->{'current'};

        push @info, $email->{'status'};

        push @info, 'set on '.$dump_time->($email->{'set'})
            if $email->{'set'};

        push @info, 'changed on '.$dump_time->($email->{'changed'})
            if $email->{'changed'};

        push @info, 'deleted on '.$dump_time->($email->{'deleted'})
            if ($email->{'deleted'});

        $self->info(join '; ', @info);
    }

    return 1;
}

1;
