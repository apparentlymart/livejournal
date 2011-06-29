#!/usr/bin/perl

use strict;
use warnings;

use lib "$ENV{'LJHOME'}/cgi-bin";
require 'ljlib.pl';

use Getopt::Long;

my ( $cat_from, $cat_to, $usage, $write );

my $getopt_result = GetOptions(
    'from=s'        => \$cat_from,
    'to=s'          => \$cat_to,
    'write'         => \$write,
    'help|usage'    => \$usage,
);

if ( $usage || !$getopt_result || !$cat_from || !$cat_to ) {
    usage();
}

LJ::start_request();
my $spcatid_from = spcatid_from_catkey($cat_from);
unless ($spcatid_from) {
    print "no '$cat_from' found, quitting\n";
    exit 1;
}

my $spcatid_to = spcatid_from_catkey($cat_to);
unless ($spcatid_to) {
    print "no '$cat_to' found, quitting\n";
    exit 1;
}

print "going to merge $cat_from (#$spcatid_from) "
    . "into $cat_to (#$spcatid_to) now\n";

print "locking $cat_from so that no new requests can be submitted\n";
if ($write) {
    lock_cat($spcatid_from);
} else {
    print "(skipped due to dry mode)\n";
}

print "moving requests... ";
my $count_requests = count_requests($spcatid_from);
print "$count_requests found for now, though this may change slightly\n";

my $count_moved = 0;
my $move_message = "(Moved from $cat_from to $cat_to as a part "
                 . "of category merge)\n";

if ($write) {
    while ( my $spids = get_requests_batch( $spcatid_from, 1000 ) ) {
        LJ::start_request();

        foreach my $spid (@$spids) {
            move_request( $spid, $spcatid_to, $move_message );
            $count_moved++;

            print "[$count_moved/$count_requests] #$spid\n";
        }
    }
} else {
    print "(skipped due to dry mode)\n";
}

print "$count_moved requests moved\n";

print "now, processing stock answers\n";

LJ::start_request();
my $stock_answers = get_stock_answers($spcatid_from);
my $stock_answers_count = scalar(@$stock_answers);
my $stock_answers_moved = 0;

foreach my $answer (@$stock_answers) {
    if ($write) {
        move_stock_answer( $answer->{'ansid'}, $spcatid_to,
                           "[from $cat_from] " . $answer->{'subject'} );
    }

    $stock_answers_moved++;
    print "[$stock_answers_moved/$stock_answers_count] "
        . '(#' . $answer->{'ansid'} . ') ' . $answer->{'subject'} . "\n";
}

print "$stock_answers_moved answers moved successfully\n";

unless ($write) {
    print "(they were not actually moved due to dry mode)\n";
}

LJ::start_request();
print "now, working on support notifications\n";
my $notifications = get_notifications($spcatid_from);
print "notifications to requests in $cat_from are as follows right now:\n";

foreach my $notify (@$notifications) {
    my $u = LJ::load_userid( $notify->{'userid'} );
    print $u->username . ', ' . $notify->{'level'} . "\n";
}

print "deleting them... ";
if ($write) {
    drop_notifications($spcatid_from);
    print scalar(@$notifications) . " notifications gone\n";
} else {
    print "(skipped due to dry mode)\n";
}

print "now, working on support tags\n";
LJ::start_request();
my $tags = get_tags($spcatid_from);
my $count_tags = scalar(@$tags);
my $count_tags_moved = 0;

foreach my $tag (@$tags) {
    my $move_result = move_tag( $tag, $spcatid_to, 'pretend' => !$write );

    $count_tags_moved++;

    print "[$count_tags_moved/$count_tags] "
        . '(#' . $tag->{'sptagid'} . ') ' . $tag->{'name'} . " => ";

    if ( $move_result->{'status'} eq 'moved' ) {
        print "moved without collision\n";
    } elsif ( $move_result->{'status'} eq 'merged' ) {
        print "merged into #" . $move_result->{'new_sptagid'} . ', '
            . "affecting " . $move_result->{'affected'} . " requests\n";
    } else {
        print "unknown move status, aborting\n";
        exit 1;
    }
}

print scalar(@$tags) . " tags handled successfully\n";
unless ($write) {
    print "(they were not actually moved due to dry mode)\n";
}

print "all data transferred, we're all set to drop $cat_from now...";
LJ::start_request();

if ($write) {
    drop_cat($spcatid_from);
    print "done\n";
} else {
    print "(skipped due to dry mode)\n";
}

print "merge successful!\n";
exit 0;

sub usage {
    print while ( <DATA> );
    exit;
    return;
}

sub get_db {
    if ($write) {
        return LJ::get_db_writer();
    }

    return LJ::get_db_reader();
}

sub spcatid_from_catkey {
    my ($catkey) = @_;

    my $dbh = get_db();
    my ($spcatid) = $dbh->selectrow_array(
        "SELECT spcatid FROM supportcat WHERE catkey=?",
        undef, $catkey,
    );

    return $spcatid;
}

sub lock_cat {
    my ($spcatid) = @_;

    my $dbh = get_db();
    $dbh->do(
        "UPDATE supportcat SET is_selectable=0 WHERE spcatid=?",
        undef, $spcatid,
    );
}

sub count_requests {
    my ($spcatid) = @_;

    my $dbh = get_db();
    my ($count) = $dbh->selectrow_array(
        "SELECT COUNT(*) FROM support WHERE spcatid=?",
        undef, $spcatid,
    );

    return $count;
}

sub get_requests_batch {
    my ( $spcatid, $size ) = @_;

    my $dbh = get_db();
    my ($spids) = $dbh->selectcol_arrayref(
        "SELECT spid FROM support WHERE spcatid=? LIMIT $size",
        undef, $spcatid,
    );

    return unless @$spids;
    return $spids;
}

sub move_request {
    my ( $spid, $new_spcatid, $message ) = @_;

    my $dbh = get_db();
    my $systemu = LJ::load_user('system') || die 'no "system", what?';

    $dbh->do(
        'INSERT INTO supportlog SET spid=?, timelogged=UNIX_TIMESTAMP(), ' .
        'type="internal", userid=?, message=?',
        undef, $spid, $systemu->userid, $message,
    );

    $dbh->do(
        "UPDATE support SET spcatid=? WHERE spid=?",
        undef, $new_spcatid, $spid,
    );
}

sub get_stock_answers {
    my ($spcatid) = @_;

    my $dbh = get_db();
    my $res = $dbh->selectall_arrayref(
        "SELECT ansid, subject FROM support_answers WHERE spcatid=?",
        { 'Slice' => {} }, $spcatid,
    );

    return $res;
}

sub move_stock_answer {
    my ( $ansid, $new_spcatid, $new_subject ) = @_;

    my $dbh = get_db();
    $dbh->do(
        "UPDATE support_answers SET spcatid=?, subject=? WHERE ansid=?",
        undef, $new_spcatid, $new_subject, $ansid,
    );
}

sub get_notifications {
    my ($spcatid) = @_;

    my $dbh = get_db();
    my $res = $dbh->selectall_arrayref(
        "SELECT userid, level FROM supportnotify WHERE spcatid=?",
        { 'Slice' => {} }, $spcatid,
    );

    return $res;
}

sub drop_notifications {
    my ($spcatid) = @_;

    my $dbh = get_db();
    $dbh->do( "DELETE FROM supportnotify WHERE spcatid=?", undef, $spcatid );
}

sub get_tags {
    my ($spcatid) = @_;

    my $dbh = get_db();
    my $res = $dbh->selectall_arrayref(
        "SELECT sptagid, name FROM supporttag WHERE spcatid=?",
        { 'Slice' => {} }, $spcatid,
    );

    return $res;
}

sub move_tag {
    my ( $tag, $spcatid, %opts ) = @_;

    my $sptagid = $tag->{'sptagid'};
    my $dbh = get_db();

    my ($new_sptagid) = $dbh->selectrow_array(
        "SELECT sptagid FROM supporttag WHERE spcatid=? AND name=?",
        undef, $spcatid, $tag->{'name'},
    );

    if ( $opts{'pretend'} ) {
        if ($new_sptagid) {
            my ($affected) = $dbh->selectrow_array(
                "SELECT COUNT(*) FROM supporttagmap WHERE sptagid=?",
                undef, $new_sptagid,
            );

            return {
                'status' => 'merged',
                'new_sptagid' => $new_sptagid,
                'affected' => $affected,
            };
        }

        return { 'status' => 'moved' };
    }

    if ($new_sptagid) {
        my $affected = int $dbh->do(
            "UPDATE supporttagmap SET sptagid=? WHERE sptagid=?",
            undef, $new_sptagid, $sptagid,
        );

        $dbh->do(
            "DELETE FROM supporttag WHERE sptagid=?",
            undef, $sptagid,
        );

        return {
            'status' => 'merged',
            'new_sptagid' => $new_sptagid,
            'affected' => $affected,
        };
    }

    $dbh->do(
        "UPDATE supporttag SET spcatid=? WHERE sptagid=?",
        undef, $spcatid, $sptagid,
    );

    return { 'status' => 'moved' };
}

sub drop_cat {
    my ($spcatid) = @_;

    my $dbh = get_db();
    $dbh->do( "DELETE FROM supportcat WHERE spcatid=?", undef, $spcatid );
}

__DATA__
Usage:

# this one merges entries into general:
bin/misc/support-merge-cats.pl --from entries --to general

# this one does actually merge entries into general, as opposed to
# only pretending to do so
bin/misc/support-merge-cats.pl --from entries --to general --write

# this one prints usage information:
bin/misc/support-merge-cats.pl --help
