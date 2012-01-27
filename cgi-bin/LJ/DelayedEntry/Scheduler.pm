package LJ::DelayedEntry::Scheduler::TableLock;
use strict;
use warnings;

my $DELAYED_ENTRIES_LOCK_NAME = 'delayed_entries_lock';

sub new {
    my ($class, $dbh) = @_;

    if (!try_lock($dbh)) {
        return undef;
    }

    my $self = bless {}, $class;
    $self->{dbh} = $dbh;

    return $self;
}

sub try_lock {
    my ($dbh) = @_;

    my ($free) = 
        $dbh->selectrow_array("SELECT IS_FREE_LOCK('$DELAYED_ENTRIES_LOCK_NAME')");

    if (!$free) {
        return 0;
    }

    my ($result) = 
        $dbh->selectrow_array("SELECT GET_LOCK('$DELAYED_ENTRIES_LOCK_NAME', 10)");
    return $result;
}

sub DESTROY {
    my ($self) = @_;
    my $dbh = $self->{dbh};

    $dbh->selectrow_array("SELECT RELEASE_LOCK('$DELAYED_ENTRIES_LOCK_NAME')");
}


package LJ::DelayedEntry::Scheduler;
use LJ::DelayedEntry;
use LJ::Text;

use strict;
use warnings;

my $PULSE_TIME = 1 * 60;

sub pulse_time {
    return $PULSE_TIME;
}

sub __load_delayed_entries {
    my ($dbh) = @_;
    my @entries;
    
    my $list = $dbh->selectall_arrayref("SELECT journalid, delayedid, posterid " .
                                        "FROM delayedlog2 ".
                                        "WHERE posttime <= NOW() LIMIT 1000");
    foreach my $tuple (@$list) {
        push @entries, LJ::DelayedEntry->load_data($dbh,
                                                   { journalid  => $tuple->[0],
                                                     delayed_id => $tuple->[1],
                                                     posterid   => $tuple->[2]} );
    }
    return undef if !scalar @entries;
    return \@entries;
}

sub __send_error {
    my ($poster, $subject, $error) = @_;
    my $email = $poster->email_raw;
    
    LJ::send_mail({
        'to'        => $email,
        'from'      => $LJ::ADMIN_EMAIL,
        'fromname'  => $LJ::SITENAME,
        'charset'   => 'utf-8',
        'subject'   => LJ::Lang::get_text($poster->prop('browselang'),
                                        'email.delayed_error.subject'),
        'body'      => LJ::Lang::get_text($poster->prop('browselang'),
                                        'email.delayed_error.body',
        {subject => $subject, reason=>$error}),
    });
}


sub on_pulse {
    my ($clusterid, $dbh) = @_;
    __assert($dbh);

    my $lock = new LJ::DelayedEntry::Scheduler::TableLock($dbh);

    if (!$lock) {
        return;
    }

    eval {
        while ( my $entries = __load_delayed_entries($dbh) ) {
            foreach my $entry (@$entries) {
                my $post_status = $entry->convert();
        
                # do we need to send error
                if ( $post_status->{error_message} ) {
                    __send_error($entry->poster, 
                                $entry->data->{subject},
                                $post_status->{error_message});
                }
                if ( $post_status->{delete_entry} ) {
                    $entry->delete();
                }
            }
        } 
    };
    if ($@) {
        warn 'worker has failed: ' . $@;
    }
}

sub __assert() {
    my ($statement) = @_;
    unless ($statement) {
        die "assertion failed!";
    }
}

1;
