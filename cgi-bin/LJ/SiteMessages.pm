package LJ::SiteMessages;
use strict;
use Carp qw(croak);

use constant AccountMask => {
    Permanent   => {    
                        value       => 1,
                        group       => 0,
                        selected    => 1,
                        validate    => sub {
                                            my ($u) = @_;
                                            
                                            return $u->in_class('perm');
                                       },
                    },
    
    Sponsored   => {    
                        value       => 2,
                        group       => 0,
                        selected    => 1,
                        validate    => sub {
                                            my ($u) = @_;
                                            
                                            return $u->in_class('sponsored');
                                       },
                    },
                    
    Paid        => {    
                        value       => 4,
                        group       => 0,
                        selected    => 1,
                        validate    => sub {
                                            my ($u) = @_;
                                            
                                            return $u->get_cap('paid');
                                       },
                    },
    
    Plus        => {    
                        value       => 8,
                        group       => 0,
                        selected    => 1,
                        validate    => sub {
                                            my ($u) = @_;
                                            
                                            return $u->in_class('plus') && !$u->get_cap('paid');
                                       },
                    },
    
    Basic       => {    
                        
                        value       => 16,
                        group       => 0,
                        selected    => 1,
                        validate    => sub {
                                            my ($u) = @_;

                                            return !($u->in_class('plus') || $u->get_cap('paid'));
                                       }
                    },
    
    SUP         => {    
                        value       => 32,
                        group       => 1,
                        selected    => 1,
                        validate    => sub {
                                            my ($u) = @_;
                                            
                                            return LJ::SUP->is_sup_enabled($u);
                                       }
                    },
    
    NonSUP      => {    
                        value       => 64,
                        group       => 1,
                        selected    => 1,
                        validate    => sub {
                                            my ($u) = @_;
                                            
                                            return !LJ::SUP->is_sup_enabled($u);
                                       }
                    },
    
    
    OfficeOnly  => {    
                        value       => 128,
                        group       => 2,
                        validate    => sub {
                                            my ($u) = @_;
                                            
                                            my $country = LJ::GeoLocation->get_country_info_by_ip(
                                                                                                    LJ::get_remote_ip(),
                                                                                                    { allow_spec_country => 1 } 
                                                                                                   );

                                            return $country eq '1S' || $country eq '6A';
                                       }
                    },


    TryNBuy     => {    
                        value       => 256,
                        group       => 3,
                        selected    => 1,
                        validate    => sub {
                                            my ($u) = @_;

                                            return $u->get_cap('trynbuy');      
                                       }
                    },
    
    AlreadyTryNBuy => { 
                        value       => 512,
                        group       => 3,
                        selected    => 1,
                        validate    => sub {
                                            my ($u) = @_;

                                            return LJ::TryNBuy->already_used($u);
                                       }
                    },
    
    NeverTryNBuy   => { 
                        value       => 1024,
                        group       => 3,
                        selected    => 1,
                        validate    => sub {
                                            my ($u) = @_;

                                            return !(LJ::TryNBuy->already_used($u) || $u->get_cap('trynbuy'));
                                       }
                    },
    
    EmailFaulty    => { 
                        value       => 2048,
                        group       => 4,
                        validate    => sub {
                                            my ($u) = @_;
                                            
                                            return $u->prop('email_faulty');
                                       }
                    },
};

#
#   Get all options names for form output
#
sub get_options_list {
    return sort { 
            AccountMask->{$b}->{value} <=> AccountMask->{$a}->{value}
         } keys %{&AccountMask};
}

#
#   Get default selected masks bits together
#
sub get_default_masks_value {
    my $result = 0;
     
    for my $name (keys %{&AccountMask}) {
        $result += AccountMask->{$name}->{value} if ( AccountMask->{$name}->{selected});    
    }
    
    return $result;
}

#
#   Get mask group number
#
sub get_group {
    my ($class, $name) = @_;

    return AccountMask->{$name}->{group};
}

#
#   Check some value against given message type mask
#
sub check_mask {
    my ($class, $mask_name, $value) = @_;

    return $value & int(AccountMask->{$mask_name}->{value});
}

sub get_class_string {
    my $class = shift;
    my $mask = shift;

    return join(', ', grep { $mask & AccountMask->{$_}->{value} } 
                      sort { LJ::SiteMessages::AccountMask->{$b}->{value} <=> LJ::SiteMessages::AccountMask->{$a}->{value} } 
                      keys %{&AccountMask} );    
}

sub memcache_key {
    my $class = shift;

    return "sitemessages";
}

sub cache_get {
    my $class = shift;

    # first, is it in our per-request cache?
    my $questions = $LJ::SiteMessages::REQ_CACHE_MESSAGES;
    return $questions if $questions;

    my $memkey = $class->memcache_key;
    my $memcache_data = LJ::MemCache::get($memkey);
    if ($memcache_data) {
        # fill the request cache since it was empty
        $class->request_cache_set($memcache_data);
    }
    return $memcache_data;
}

sub request_cache_set {
    my $class = shift;
    my $val = shift;

    $LJ::SiteMessages::REQ_CACHE_MESSAGES = $val;
}

sub cache_set {
    my $class = shift;
    my $val = shift;

    # first set in request cache
    $class->request_cache_set($val);

    # now set in memcache
    my $memkey = $class->memcache_key;
    my $expire = 60*5; # 5 minutes
    return LJ::MemCache::set($memkey, $val, $expire);
}

sub cache_clear {
    my $class = shift;

    # clear request cache
    $LJ::SiteMessages::REQ_CACHE_MESSAGES = undef;

    # clear memcache
    my $memkey = $class->memcache_key;
    return LJ::MemCache::delete($memkey);
}

sub load_messages {
    my $class = shift;

    my $messages = $class->cache_get;
    return @$messages if $messages;

    my $dbh = LJ::get_db_writer()
        or die "no global database writer for SiteMessages";

    my $sth = $dbh->prepare(
        "SELECT * FROM site_messages WHERE time_start <= UNIX_TIMESTAMP() AND time_end >= UNIX_TIMESTAMP() AND active='Y'"
    );
    $sth->execute;

    my @rows = ();
    while (my $row = $sth->fetchrow_hashref) {
        push @rows, $row;
    }
    $class->cache_set(\@rows);

    return @rows;
}

sub filter_by_country {
    my $class = shift;
    my $u = shift;
    my @questions = @_;

    # split the list into a list of questions with countries and a list of questions without countries
    my @questions_with_countries;
    my @questions_without_countries;

    foreach my $question (@questions) {
        if ($question->{countries}) {
            push @questions_with_countries, $question;
        } else {
            push @questions_without_countries, $question;
        }
    }

    # get the user's country if defined, otherwise the country of the remote IP
    my $country;
    $country = lc $u->country if $u;
    $country = lc LJ::country_of_remote_ip() unless $country;

    my @questions_ret;

    # get the questions that are targeted at the user's country
    if ($country) {
        foreach my $question (@questions_with_countries) {
            next unless grep { $_ eq $country } split(/\s*,\s*/, $question->{countries});
            push @questions_ret, $question;
        }
    }

    return (@questions_ret, @questions_without_countries);
}

sub get_messages {
    my $class = shift;
    my %opts = @_;

    # direct the questions at the given $u, or remote if no $u given
    my $u = $opts{user} && LJ::isu($opts{user}) ? $opts{user} : LJ::get_remote();

    return unless $u; # there are no messages for logged out users

    my @messages = $class->load_messages;
    @messages = grep { ref $_ } @messages;

    @messages = $class->filter_messages($u, @messages);
    @messages = $class->filter_by_country($u, @messages);

    return @messages;
}

#
#   Filter the messages list for given remote
#
sub filter_messages {
    my ($class, $u, @messages) = @_;
    
    return grep {
        my $last_group = -1;
        my $group_match = 1;
        my $accept = 1;

        for my $key ($class->get_options_list) {
            # If entering a new group
            if ($last_group != AccountMask->{$key}->{group}) {
                unless ($group_match) {
                    $accept = 0;
                    last;
                }
            }

            if (int($_->{accounts}) & AccountMask->{$key}->{value}) {
                $group_match = AccountMask->{$key}->{validate}($u);
            }

            $last_group = AccountMask->{$key}->{group};
        }

        $accept;
    } @messages;
}

#
#   Check if mask has some certain bit set
#
sub has_mask {
    my ($class, $mask_name, $mask_value) = @_;

    if (defined AccountMask->{$mask_name} && defined AccountMask->{$mask_name}->{validate}) {
        return int(AccountMask->{$mask_name}->{value}) & $mask_value;
    } else {
        return 0;
    }
}

sub store_message {
    my $class = shift;
    my %vals = @_;

    my $dbh = LJ::get_db_writer()
        or die "Unable to store message: no global dbh";

    my $mid;

    # update existing message
    if ($vals{mid}) {
        $dbh->do("UPDATE site_messages SET time_start=?, time_end=?, active=?, text=?, countries=?, accounts=?  WHERE mid=?",
                 undef, (map { $vals{$_} } qw(time_start time_end active text countries accounts mid)))
            or die "Error updating site_messages: " . $dbh->errstr;
        $mid = $vals{mid};
    }
    # insert new message
    else {
        $dbh->do("INSERT INTO site_messages (mid, time_start, time_end, active, text, countries, accounts) VALUES (?,?,?,?,?,?,?)",
                 undef, "null", (map { $vals{$_} } qw(time_start time_end active text countries accounts)))
            or die "Error adding site_messages: " . $dbh->errstr;
        $mid = $dbh->{mysql_insertid};
    }

    # insert/update message in translation system
    my $ml_key = LJ::Widget::SiteMessages->ml_key("$mid.text");
    LJ::Widget->ml_set_text($ml_key => $vals{text});

    # clear cache
    $class->cache_clear;
    return 1;
}

# returns all messages that started during the given month
sub get_all_messages_for_month {
    my $class = shift;
    my ($year, $month) = @_;

    my $dbh = LJ::get_db_writer()
        or die "Error: no global dbh";

    my $time_start = DateTime->new( year => $year, month => $month, time_zone => 'America/Los_Angeles' );
    my $time_end = $time_start->clone;
    $time_end = $time_end->add( months => 1 );
    $time_end = $time_end->subtract( seconds => 1 ); # we want time_end to be the end of the last day of the month

    my $sth = $dbh->prepare("SELECT * FROM site_messages WHERE time_start >= ? AND time_start <= ?");
    $sth->execute($time_start->epoch, $time_end->epoch)
        or die "Error getting this month's messages: " . $dbh->errstr;

    my @rows = ();
    while (my $row = $sth->fetchrow_hashref) {
        push @rows, $row;
    }

    # sort messages in descending order by start time (newest first)
    @rows =
        sort { $b->{time_start} <=> $a->{time_start} }
        grep { ref $_ } @rows;

    return @rows;
}

# given an id for a message, returns the info for it
sub get_single_message {
    my $class = shift;
    my $mid = shift;

    my $dbh = LJ::get_db_writer()
        or die "Error: no global dbh";

    my $sth = $dbh->prepare("SELECT * FROM site_messages WHERE mid = ?");
    $sth->execute($mid)
        or die "Error getting single message: " . $dbh->errstr;

    return $sth->fetchrow_hashref;
}

# change the active status of the given message
sub change_active_status {
    my $class = shift;
    my $mid = shift;

    my %opts = @_;
    my $to = delete $opts{to};
    croak "invalid 'to' field" unless $to =~ /^(active|inactive)$/; 

    my $question = $class->get_single_message($mid)
        or die "Invalid message: $mid";

    my $dbh = LJ::get_db_writer()
        or die "Error: no global dbh";

    my $active_val = $to eq 'active' ? 'Y' : 'N';
    my $rv = $dbh->do("UPDATE site_messages SET active = ? WHERE mid = ?", undef, $active_val, $mid)
        or die "Error updating active status of message: " . $dbh->errstr;

    $class->cache_clear;

    return $rv;
}

# get one message, that will be shown to current remote user
sub get_open_message {
    my $class = shift;

    my $remote = LJ::get_remote();
    return unless $remote; # this feature only for logged in users

    ## tiny optimization
    $remote->preload_props(qw/country closed_sm/);

    ##
    my @messages = $class->get_messages(user => $remote);

    my $closed = $remote->prop('closed_sm');
    if ($closed) {
        my %closed = map { $_ => 1 } split(',', $closed);
        @messages = grep { not $closed{$_->{mid}} } @messages;
    }

    return unless scalar @messages;

    my $index = int(rand(scalar @messages));
    return $messages[$index];
}

sub close_message {
    my $class = shift;
    my $mid = shift;

    my $remote = LJ::get_remote();
    return unless $remote; # this feature only for logged in users

    my @messages = $class->load_messages; # without filtering on country and account type
    my %active = map { $_->{mid} => 1  } @messages;

    my $closed = $remote->prop('closed_sm');
    my @closed = split(',', $closed);

    @closed = grep { $active{$_} } @closed;
    push @closed, $mid;

    $remote->set_prop('closed_sm', join(',', @closed));
}

1;
