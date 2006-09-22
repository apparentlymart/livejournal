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

    sysseek($fh, 0, SEEK_SET) or die "Couldn't seek: $!";

    my ($file_lastmod, $file_count) = (0, 0);
    
    if (-s $filename) {
        sysread($fh, my $header, 8) == 8 or die "Couldn't read 8 byte header: $!";
        ($file_lastmod, $file_count) = unpack("NN", $header);
    }

    my $db_count = $dbh->selectrow_array("SELECT count(*) FROM usersearch WHERE mtime=?",
                                         undef, $file_lastmod);

    my $sth = $dbh->prepare("SELECT userid, packed, mtime FROM usersearch WHERE mtime >= ? AND ".
                            "(good_until IS NULL OR good_until > unix_timestamp()) ORDER BY mtime");

    $sth->execute($file_lastmod);

    die "DB Error: " . $sth->errstr if $sth->errstr;

    my $modcount = 0;
    my $mtime = 0;
    while (my $row = $sth->fetchrow_hashref) {
        warn "Processing row";
        my $packed = $row->{packed};
        unless (length($packed) == 8) {
            die "Pack length was incorrect";
        }
        my $offset = $row->{userid} * 8;
        sysseek($fh, $offset, SEEK_SET) or die "Couldn't seek: $!";
        syswrite($fh, $packed) == 8 or die "Syswrite failed to complete: $!";

        if ($mtime == $row->{mtime}) {
            $modcount++;
        } else {
            $modcount = 0;
            $mtime = $row->{mtime};
        }
    }

    sysseek($fh, 0, SEEK_SET) or die "Couldn't seek: $!";
    my $newheader = pack("NN", $mtime, $modcount);
    syswrite($fh, $newheader) == 8 or die "Couldn't write header: $!";
    
    return;
}

# CREATE TABLE usersearch (userid int(10) unsigned NOT NULL PRIMARY KEY, packed CHAR(8) BINARY, mtime INT UNSIGNED NOT NULL, good_until INT UNSIGNED, INDEX(good_until));

1;
