package LJ::User::EmailStatus;
use strict;

#
#   Handles SMTP code for some recipient email
#
sub handle_code {
    my ($class, %params) = @_;
    
    return if $LJ::DISABLED{'revoke_validation_on_errors'};

    die ('No Smtp Code')    if (!defined $params{code});
    die ('No Email')        if (!$params{email});
    die ('Invalid Email')   if (length($params{email}) > 50);
    
    my $cache_key = $class->get_cache_key($params{email});
    
    my $dbh;
    my $data = LJ::MemCache::get($cache_key);
    
    unless (defined $data) {
        $dbh = LJ::get_db_writer() or die ('Failed to get db connection');
        $data = $dbh->selectrow_hashref("SELECT * FROM email_status WHERE email = ?",
                    undef,
                    $params{email}
                );    
    }
    
    # If this email is disabled - we perfom no actions
    return if ($data->{disabled});

    # Address error count is increasing
    if ($params{code} == 5) {
        $dbh ||= LJ::get_db_writer() or die ('Failed to get db connection');
             
        if (!$data->{error_count} || time() - $data->{last_error_time} > $LJ::EMAIL_MAX_FAULTY_PERIOD) {
            $data->{error_count}        = 1;
            $data->{first_error_time}   = time();
            $data->{last_error_time}    = time();

            $dbh->do("REPLACE INTO email_status (email, error_count, first_error_time, last_error_time) VALUES (?, ?, ?, ?)",
                        undef,
                        $params{email}, $data->{error_count}, $data->{first_error_time}, $data->{last_error_time}
                    );
        } else {
            $data->{error_count} ++;
            $data->{last_error_time}  = time();

            # Should put down this email if it is too faulty within minimum period of time
            if ($data->{error_count} >= $LJ::EMAIL_MAX_ERROR_COUNT && ($data->{last_error_time} - $data->{first_error_time} > $LJ::EMAIL_FAULTY_PERIOD)) {
                $data->{disabled}         = 1;
                $class->process_disabled_status(%params, disabled => 1);
            }

            $dbh->do("UPDATE email_status SET error_count = ?, last_error_time = ?, disabled = ? WHERE email = ?",
                        undef,
                        $data->{error_count}, time(), $data->{disabled}, $params{email}
                    ) or die('Failed to update record');
        }
        
        LJ::MemCache::set($cache_key, $data, $LJ::EMAIL_STATUS_CACHE_TIME);
    # Address became OK, being faulty before
    } elsif ($data->{error_count}) {
        $dbh = LJ::get_db_writer() or die ('Failed to get db connection') if(!$dbh);
             
        $dbh->do("DELETE FROM email_status WHERE email = ?",
                            undef,
                            $params{email}
                        );

        $data->{error_count} = 0;
        
        LJ::MemCache::set($cache_key, $data, $LJ::EMAIL_STATUS_CACHE_TIME);
    # Address is just OK
    } else {
        LJ::MemCache::set($cache_key, {error_count => 0}, $LJ::EMAIL_STATUS_CACHE_TIME);
    }
}

#
#   Change email status (active/not active)
#
sub process_disabled_status {
    my ($class, %params) = @_;

    die ('No Email') if (!$params{email});

    my $sclient = LJ::theschwartz();
    unless ($sclient) {
        die "LJ::User::EmailStatus: Could not get TheSchwartz client";
    }

    # Set up the job
    my $status_job = TheSchwartz::Job->new(
        funcname  => "TheSchwartz::Worker::EmailStatus",
        arg       => {  
                        email       => $params{email},
                        disabled    => $params{disabled}
                     }
    );

    $sclient->insert($status_job);
}

#
#   Perfom some operations on the accounts, using affected addresses
#
sub change_email_users_status {
    my ($class, %params) = @_;

    die ('No Email') if (!$params{email});
    
    my $is_disabled = $params{disabled} ? 1 : undef;
    
    LJ::MemCache::delete($class->get_cache_key($params{email})) if(!$params{disabled});
   
    my $dbh = LJ::get_db_writer() or die ('Failed to get db connection');
    
    unless ($is_disabled) {
        $dbh->do("DELETE FROM email_status WHERE email = ?",
                            undef,
                            $params{email}
                        );
    }
    
    my @users;

    unless ( $params{user} ) {
        my $ids = $dbh->selectcol_arrayref("SELECT userid FROM email WHERE email = '" . $params{email} . "'");
        my $users = LJ::load_userids(@$ids);
        @users = values %$users;      
    } else {
        @users = ($params{user});
    }
 
    for my $user (@users) {
       $user->set_prop('email_faulty', $is_disabled);
       LJ::update_user($user, { 'status' => $is_disabled ? 'T' : 'A' } );
    }
}

#
#   Get Memcached cache key based on email address
#
sub get_cache_key {
    my ($class, $email) = @_;
    
    return 'email_status_' . $email;
}

#
#   Drop the old outdated database entries
#
sub cleanup {
    my $dbh = LJ::get_db_writer() or die ('Failed to get db connection');
    
    $dbh->do("DELETE FROM email_status WHERE unix_timestamp() - first_error_time > ? LIMIT 5000",
                undef,
                $LJ::EMAIL_MAX_FAULTY_PERIOD
             );  
}

1;

