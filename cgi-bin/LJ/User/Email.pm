package LJ::User::Email;
use strict;

#
#   THIS PACKAGE IS OBSOLETE DO NOT USE
#

# status_code:
#   undef   - OK: forget about problems with this address
#   0       - cannot connect to MX-host or email domain.
#   5xx     - smtp-status
#
sub mark {
    my $self        = shift;
    my $status_code = shift;
    my $emails      = shift;    # One email if scalar or list of emails if array ref.
    my $message     = shift;

    return;
    return if $LJ::DISABLED{'revoke_validation_on_errors'};

    if ('ARRAY' eq ref $emails) {
        foreach my $email (@$emails) {
            $self->_log_one_email_status($status_code, $email, $message);
        }
    } else {
        $self->_log_one_email_status($status_code, $emails, $message);
    }
}

sub _log_one_email_status {
    my $self        = shift;
    my $status_code = shift;
    my $email       = shift;
    my $message     = shift;

    eval {  # Don't die if somthing wrong with database.
        my $dbh = LJ::get_db_writer();
        if (defined $status_code) {
            $dbh->do("INSERT IGNORE INTO send_email_errors (email, time, message) VALUES (?, NOW(), ?)",
            undef, $email, $message);
        } else { # undef: OK, remove row if any
            $dbh->do("DELETE FROM send_email_errors WHERE email = ?", undef, $email);
        }
    };
}

# returns hashref whith emails as keys and fields: 'time' and 'message'.
sub get_marked {
    my $self    = shift;
    my %opts    = @_;

    return () if $LJ::DISABLED{'revoke_validation_on_errors'};

    my $limit   = $opts{limit}  || 1000;
    # 97 = 1 + 24 + 72. It's a total time to deliver mail.
    my $timeout = (int($opts{timeout})|| 97) . ':00:00';    # get this as 'hh:00:00'.

    my $dbh = LJ::get_db_reader();
    my $sth = $dbh->prepare(qq{
        SELECT email, time, message
        FROM send_email_errors
        WHERE time < SUBTIME(NOW(), ?)
        ORDER BY time DESC
        LIMIT $limit
        });

    $sth->execute($timeout);

    return $sth->fetchall_hashref('email');
}

# Like get_marked(), but with user_ids: ref to array of uids.
sub get_marked_with_uids {
    my $self    = shift;
    my %opts    = @_;

    return undef if $LJ::DISABLED{'revoke_validation_on_errors'};

    my $dbh = LJ::get_db_reader();

    my $emails = $self->get_marked(%opts);

    my $sth = $dbh->prepare("SELECT userid FROM email WHERE email = ?");
    foreach my $email (keys %$emails) {
        $sth->execute($email);
        $emails->{$email}->{user_ids} = [ map { @{$_}[0] } @{$sth->fetchall_arrayref()} ];
    }

    return $emails;
}

1;

