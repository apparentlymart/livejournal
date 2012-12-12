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
                'url'      => "$LJ::SITEROOT/changepassword.bml",
                'sitename' => $LJ::SITENAME,
                'siteroot' => $LJ::SITEROOT,
            }
        );
    }

    my $newpass = LJ::rand_chars(8);
    my $oldpass = Digest::MD5::md5_hex($u->password . "change");
    LJ::User::InfoHistory->add( $u, 'passwordreset', $oldpass );

    LJ::update_user($u, { password => $newpass, })
        or return $self->error("Failed to set new password for $username");

    $u->kill_all_sessions;

    LJ::send_mail({
        'to'      => $u->email_raw,
        'from'    => $LJ::DONOTREPLY_EMAIL,
        'subject' => "Password Reset",
        'body'    => $body,
    }) or $self->info("New password notification email could not be sent.");

    my $remote = LJ::get_remote();
    LJ::statushistory_add($u, $remote, "reset_password", $reason);
    return $self->print("Password reset for '$username'.");
}

1;
