package LJ::Console::Command::ResetPassword;

use strict;
use LJ::Sendmail::Stock;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "reset_password" }

sub desc { "Resets the password for a given account" }

sub args_desc {
    [
        'user'   => "The account to reset the email address for.",
        'reason' => "Reason for the password reset.",
        'num'    => "Number of message in stock to send to user",
    ]
}

sub usage { '<user> <reason> [--stock:num]' }

sub can_execute {
    my $remote = LJ::get_remote();
return LJ::check_priv($remote, "reset_password");
}

sub execute {
    my ($self, $username, $reason, $num, @args) = @_;

    return $self->error("This command takes two or three arguments. Consult the reference.")
        unless $username && $reason && scalar(@args) == 0;

    my $u = LJ::load_user($username);
    return $self->error("Can't change password for community")
        unless $u->journaltype eq 'P';
    return $self->error("Invalid user $username")
        unless $u;

    my $body = '';

    if( $num && $num =~ /^\-\-stock\:(\d+)$/) {
        $num = $1;
        my $dbh = LJ::get_db_reader();
        my $stock = LJ::Sendmail::Stock::from_id($num, $dbh);
        $body = $stock->body;

        my %subst = (
            realname  => $u->{name},
            username  => $u->{user},
            email     => $u->email_raw,
        );

        $body =~ s/\[\[($_)\]\]/$subst{$1}/g for keys %subst;
    }
    else {
        $body = LJ::Lang::get_text(
            $u->prop('browselang'),
            'console.reset_password',
            undef,
            {
                'url'      => "$LJ::SITEROOT/lostinfo.bml",
                'sitename' => $LJ::SITENAME,
                'siteroot' => $LJ::SITEROOT,
                'username' => $u->{user},
            }
        );
    }

    LJ::User::InfoHistory->add($u, 'passwordreset', Digest::MD5::md5_hex($u->clean_password . "change"));

    $u->reset_password()
        or return $self->error("Failed to set new password for $username");

    $u->kill_all_sessions;

    LJ::send_mail({
        'to'      => $u->email_raw,
        'from'    => $LJ::DONOTREPLY_EMAIL,
        'subject' => LJ::Lang::get_text($u->prop('browselang'), 'console.reset_password.subject'),
        'body'    => $body,
    }) or $self->info("New password notification email could not be sent.");

    my $remote = LJ::get_remote();
    LJ::statushistory_add($u, $remote, "reset_password", $reason);

    return $self->print("Password reset for '$username'.");
}

1;
