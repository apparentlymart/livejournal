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
use LJ::QotD;
use LJ::PersistentQueue;

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

sub __notify_user {
    my ($poster, $journal) = @_;
    my $email = $poster->email_raw;

    my $lang = $poster->prop('browselang') || $LJ::DEFAULT_LANG;
    my $html = LJ::Lang::get_text($lang, 'community.members.delayed.remove.email_html', undef, {
                         sitenameshort   => $LJ::SITENAMESHORT,
                         user            => $poster->user,
                         usercname       => $journal->user,
                         sitename        => $LJ::SITENAME,
                         siteroot        => $LJ::SITEROOT,
                    });

    my $plain = LJ::Lang::get_text($lang, 'community.members.delayed.remove.email_plain', undef, {
                         sitenameshort   => $LJ::SITENAMESHORT,
                         user            => $poster->user,
                         usercname       => $journal->user,
                         sitename        => $LJ::SITENAME,
                         siteroot        => $LJ::SITEROOT,
                    });

    my $text = $poster->{opt_htmlemail} eq 'Y' ? $html : $plain;

    my $subject = LJ::Lang::get_text($lang, 'community.members.delayed.remove.email_subject', undef,
                    { mailusercname => $journal->user }
                    );

    LJ::send_mail({
        'to'        => $email,
        'from'      => $LJ::ADMIN_EMAIL,
        'fromname'  => $LJ::SITENAME,
        'charset'   => 'utf-8',
        'subject'   => $subject,
        'body'      => $text,
    });
}


sub on_pulse {
    my ($clusterid, $dbh, $verbose) = @_;
    __assert($dbh);

    my $lock = new LJ::DelayedEntry::Scheduler::TableLock($dbh);

    if (!$lock) {
        return;
    }

    eval {
        while ( my $entries = __load_delayed_entries($dbh) ) {
            foreach my $entry (@$entries) {
                if (!LJ::DelayedEntry::can_post_to($entry->journal,
                                                   $entry->poster)) {
                    
                    if ($verbose) {
                        print "The entry with subject " . $entry->subject;
                        print "\ndelayed id = " . $entry->delayedid . 
                        print " and post date " . $entry->posttime;
                        print " is deleted because USER CANNOT POST\n";
                    }

                    __notify_user(  $entry->poster,
                                    $entry->journal);
                    $entry->delete();
                    next;
                }

                my $post_status = $entry->convert();

                # do we need to send error
                if ( $post_status->{'error_message'} ) {
                    warn "(posting failed) The entry with subject " . $entry->subject .
                          "\ndelayed id = " . $entry->delayedid . 
                          " and post date " . $entry->posttime . 
                          " error : " . $post_status->{'error_message'};
                    
                } elsif ($verbose) {
                        print "(posting)The entry with subject " . $entry->subject;
                        print "\ndelayed id = " . $entry->delayedid . 
                        print " and post date " . $entry->posttime . "\n";
                }

                if ( $post_status->{delete_entry} ) {
                    if ($verbose) {
                        print "The entry with subject " . $entry->subject;
                        print "\ndelayed id = " . $entry->delayedid . 
                        print " and post date " . $entry->posttime;
                        print " is deleted\n";
                    }

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
