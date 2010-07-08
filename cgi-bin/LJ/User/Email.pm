package LJ::User::Email;
use strict;

# status_code:
#   undef   - OK: forget about problems with this address
#   0       - cannot connect to MX-host or email domain.
#   5xx     - smtp-status
#
sub mark {
    my $self        = shift;
    my $status_code = shift;
    my $emails      = shift;    # One email if scalar or list of emails if array ref.

    return if $LJ::DISABLED{'revoke_validation_on_errors'};

    if ('ARRAY' eq ref $emails) {
        foreach my $email (@$emails) {
            $self->_log_one_email_status($status_code, $email);
        }
    } else {
        $self->_log_one_email_status($status_code, $emails);
    }
}

sub _log_one_email_status {
    my $self        = shift;
    my $status_code = shift;
    my $email       = shift;

    eval {  # Don't die if somthing wrong with database.
        my $dbh = LJ::get_db_writer();
        if (defined $status_code) {
            $dbh->do("INSERT IGNORE INTO send_email_errors (email, time) VALUES (?, NOW())",
            undef, $email);
        } else { # undef: OK, remove row if any
            $dbh->do("DELETE FROM send_email_errors WHERE email = ?", undef, $email);
        }
    };
}

sub get_marked {
    my $self    = shift;
    my %opts    = @_;

    return () if $LJ::DISABLED{'revoke_validation_on_errors'};

    my $limit   = $opts{limit}  || 1000;
    my $timeout = $opts{timeout}|| 72;

    my $dbh = LJ::get_db_reader();
    return $dbh->selectcol_arrayref(qq{
        SELECT email
        FROM send_email_errors
        WHERE (UNIX_TIMESTAMP()-UNIX_TIMESTAMP(time))/3600 > $timeout
        ORDER BY last_time DESC
        LIMIT $limit
    });
}

sub get_user_ids {
    my $self    = shift;
    my %opts    = @_;

    return undef if $LJ::DISABLED{'revoke_validation_on_errors'};

    my $dbh = LJ::get_db_reader();

    my $emails = $self->get_marked(%opts);
    my %user_ids = ();

    foreach my $email (@$emails) {
        my $userids = $dbh->selectcol_arrayref(qq{
            SELECT userid
            FROM email
            WHERE email = ?
        }, undef, $email);

        foreach my $userid (@$userids) {
            push @{$user_ids{$email}}, $userid;
        }
    }

    return %user_ids;
}

1;

