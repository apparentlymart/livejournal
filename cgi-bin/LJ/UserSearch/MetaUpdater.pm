package LJ::UserSearch::MetaUpdater;

use strict;
use warnings;

use Fcntl qw(:seek :DEFAULT);
use LJ::User;

sub update_user {
    my $u = LJ::want_user(shift) or die "No userid specified";

    my $dbh = LJ::get_db_writer() or die "No db";

    my $oldpack = $dbh->selectrow_array("SELECT packed FROM usersearch WHERE userid=? AND good_until < ?",
                                    undef, $u->id, time);

    die $dbh->errstr if $dbh->errstr;

    my $lastmod = $dbh->selectrow_array("SELECT UNIX_TIMESTAMP()-UNIX_TIMESTAMP(timeupdate) ".
                                        "AS 'secondsold' FROM userusage ".
                                        "WHERE userid=?", undef, $u->id);

    $lastmod ||= 0;

    my ($age, $good_until) = $u->age_with_expire;

    $age ||= 0;

    my $newpack = pack("NCxxx", $lastmod, $age);

    return if (defined $oldpack and $newpack eq $oldpack);

    my $rv = $dbh->do("REPLACE INTO usersearch (userid, packed, good_until, mtime) ".
                      "VALUES (?, ?, ?, unix_timestamp())", undef, $u->id, $newpack, $good_until);

    die "DB Error: " . $dbh->errstr if $dbh->errstr;
    die "Update count wrong '$rv' should be 1" unless $rv == 1;
}

sub update_file {
    my $filename = shift;

    my $dbh = LJ::get_db_reader() or die "No db";

    sysopen(my $fh, $filename, O_RDWR | O_CREAT) or die "Couldn't open file '$filename' for read/write: $!";
    unless (-s $filename >= 8) {
        my $zeros = "\0" x 8;
        syswrite($fh, $zeros);
    }

    while (! update_file_partial($dbh, $fh)) {
        # do more.
    }
    return 1;
}

sub update_file_partial {
    my ($dbh, $fh) = @_;
    sysseek($fh, 0, SEEK_SET) or die "Couldn't seek: $!";

    sysread($fh, my $header, 8) == 8 or die "Couldn't read 8 byte header: $!";
    my ($file_lastmod, $nr_disk_thatmod) = unpack("NN", $header);

    # the on-disk file and database only keeps second granularity.  if
    # the number of records changed in that particular second changed,
    # step back in time one second and we'll redo a few records, but
    # be sure not to miss any.
    my $nr_db_thatmod = $dbh->selectrow_array("SELECT COUNT(*) FROM usersearch WHERE mtime=?",
                                              undef, $file_lastmod);
    if ($nr_db_thatmod != $nr_disk_thatmod) {
        $file_lastmod--;
    }

    my $limit_num = 10000;
    my $sth = $dbh->prepare("SELECT userid, packed, mtime FROM usersearch WHERE mtime >= ? AND ".
                            "(good_until IS NULL OR good_until > unix_timestamp()) ORDER BY mtime LIMIT $limit_num");
    $sth->execute($file_lastmod);

    die "DB Error: " . $sth->errstr if $sth->errstr;

    my $nr_with_highest_mod = 0;
    my $last_mtime = 0;
    my $rows = 0;

    while (my ($userid, $packed, $mtime) = $sth->fetchrow_array) {
        warn "Processing row";
        unless (length($packed) == 8) {
            die "Pack length was incorrect";
        }
        my $offset = $userid * 8;
        sysseek($fh, $offset, SEEK_SET) or die "Couldn't seek: $!";
        syswrite($fh, $packed) == 8 or die "Syswrite failed to complete: $!";
        $rows++;

        if ($last_mtime == $mtime) {
            $nr_with_highest_mod++;
        } else {
            $nr_with_highest_mod = 1;
            $last_mtime          = $mtime;
        }
    }

    sysseek($fh, 0, SEEK_SET) or die "Couldn't seek: $!";
    my $newheader = pack("NN", $mtime, $modcount);
    syswrite($fh, $newheader) == 8 or die "Couldn't write header: $!";

    return ($rows == $limit_num) ? 0 : 1;
}

# CREATE TABLE usersearch (userid int(10) unsigned NOT NULL PRIMARY KEY, packed CHAR(8) BINARY, mtime INT UNSIGNED NOT NULL, good_until INT UNSIGNED, INDEX(good_until));

1;
