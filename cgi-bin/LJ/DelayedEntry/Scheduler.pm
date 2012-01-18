package LJ::DelayedEntry::Scheduler;
use LJ::DelayedEntry;
use LJ::Text;

use strict;
use warnings;
use Data::Dumper;

my $PULSE_TIME = 1 * 60; 

sub pulse_time {
    return $PULSE_TIME;
}

sub __load_delayed_entries {
    my ($dbh) = @_;
    my @entries;
    
    my $list = $dbh->selectall_arrayref("SELECT journalid, delayedid, posterid " .
                                        "FROM delayedlog2 ".
                                        "WHERE posttime <= NOW()");

    foreach my $tuple (@$list) {
        push @entries, LJ::DelayedEntry->load_data($dbh,
                                                   { journalid  => $tuple->[0],
                                                     delayed_id => $tuple->[1],
                                                     posterid   => $tuple->[2]} );
    }
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
        'body'      =>  LJ::Lang::get_text($poster->prop('browselang'),
                                        'email.delayed_error.body',
        {subject => $subject, reason=>$error}),
    });    
}

sub on_pulse {
    my ($clusterid, $dbh) = @_;
    __assert($dbh);
    my $entries = __load_delayed_entries($dbh);

    foreach my $entry(@$entries) {
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

sub __assert() {
    my ($statement) = @_;
    unless ($statement) {
        die "assertion failed!";
    }
}

1;
