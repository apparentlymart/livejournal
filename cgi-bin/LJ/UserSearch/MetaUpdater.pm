package LJ::UserSearch::MetaUpdater;

use strict;
use warnings;
use List::Util ();
use Fcntl qw(:seek :DEFAULT);
use LJ::User;
use LJ::Directory::PackedUserRecord;
use LJ::Directory::MajorRegion;

sub update_user {
    my $u = LJ::want_user(shift) or die "No userid specified";
    my $dbh = LJ::get_db_writer() or die "No db";

    my $lastmod = $dbh->selectrow_array("SELECT UNIX_TIMESTAMP(timeupdate) ".
                                        "FROM userusage WHERE userid=?", undef, $u->id);

    my ($age, $good_until) = $u->usersearch_age_with_expire;

    my $regid = LJ::Directory::MajorRegion->most_specific_matching_region_id($u->prop("country"),
                                                                             $u->prop("state"),
                                                                             $u->prop("city"));

    my $newpack = LJ::Directory::PackedUserRecord->new(
                                                       updatetime => $lastmod,
                                                       age        => $age,
                                                       regionid   => $regid,
                                                       )->packed;

    my $rv = $dbh->do("REPLACE INTO usersearch_packdata (userid, packed, good_until, mtime) ".
                      "VALUES (?, ?, ?, UNIX_TIMESTAMP())", undef, $u->id, $newpack, $good_until);

    die "DB Error: " . $dbh->errstr if $dbh->errstr;
    return 1;
}

sub missing_rows {
    my $dbh = LJ::get_db_writer() or die "No db";
    my $highest_uid        = $dbh->selectrow_array("SELECT MAX(userid) FROM user")                || 0;
    my $highest_search_uid = $dbh->selectrow_array("SELECT MAX(userid) FROM usersearch_packdata") || 0;
    return $highest_uid != $highest_search_uid;
}

sub add_some_missing_rows {
    my $dbh = LJ::get_db_writer() or die "No db";
    my $highest_search_uid = $dbh->selectrow_array("SELECT MAX(userid) FROM usersearch_packdata") || 0;
    my $sth = $dbh->prepare("SELECT userid FROM user WHERE userid > ? ORDER BY userid LIMIT 1000");
    $sth->execute($highest_search_uid);
    while (my ($uid) = $sth->fetchrow_array) {
        # TODO: select the whole row and make an LJ::User API to let us make a $u from a user row.
        # note that new_from_row isn't good enough, as it ignores the singleton rules.  should
        # just fix new_from_row.
        my $u = LJ::load_userid($uid);
        LJ::UserSearch::MetaUpdater::update_user($u);
    }
}

sub update_some_rows {
    my $dbh = LJ::get_db_writer() or die "No db";
    my $ids = $dbh->selectcol_arrayref("SELECT userid FROM usersearch_packdata WHERE good_until < UNIX_TIMESTAMP() LIMIT 1000");
    foreach my $uid (List::Util::shuffle(@$ids)) {
        my $lock = LJ::locker()->trylock("dirpackupdate:$uid");
        my $u = LJ::load_userid($uid);
        warn "updating $uid...\n";
        LJ::UserSearch::MetaUpdater::update_user($u);
    }
    return 0;
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
    my $nr_db_thatmod = $dbh->selectrow_array("SELECT COUNT(*) FROM usersearch_packdata WHERE mtime=?",
                                              undef, $file_lastmod);
    if ($nr_db_thatmod != $nr_disk_thatmod) {
        $file_lastmod--;
    }

    my $limit_num = 10000;
    my $sth = $dbh->prepare("SELECT userid, packed, mtime FROM usersearch_packdata WHERE mtime >= ? AND ".
                            "(good_until IS NULL OR good_until > unix_timestamp()) ORDER BY mtime LIMIT $limit_num");
    $sth->execute($file_lastmod);

    die "DB Error: " . $sth->errstr if $sth->errstr;

    my $nr_with_highest_mod = 0;
    my $last_mtime = 0;
    my $rows = 0;

    while (my ($userid, $packed, $mtime) = $sth->fetchrow_array) {
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
    my $newheader = pack("NN", $last_mtime, $nr_with_highest_mod);
    syswrite($fh, $newheader) == 8 or die "Couldn't write header: $!";

    return ($rows == $limit_num) ? 0 : 1;
}


package LJ::User;

# Graft this function into the LJ::User class, we probably need to move this to User.pm someday
sub usersearch_age_with_expire {
    my $u = shift;
    croak "Invalid user object" unless LJ::isu($u);

    my $bdate = $u->{bdate};
    return unless $bdate && length $bdate;

    my ($year, $mon, $day) = $bdate =~ m/^(\d\d\d\d)-(\d\d)-(\d\d)/;
    my $age = LJ::calc_age($year, $mon, $day);

    return unless $age && $age > 0;

    my ($cday, $cmon, $cyear) = (gmtime)[3,4,5];
    $cmon  += 1;    # Normalize the month to 1-12
    $cyear += 1900; # Normalize the year

    # Start off, their next birthday is this year
    $year = $cyear;

    # Increment the year if their birthday was on or before today.
    $year++ if ($mon < $cmon or $mon == $cmon && $day <= $cday);

    my $expire = Time::Local::timegm_nocheck(0, 0, 0, $day, $mon-1, $year);
    return ($age, $expire);
}

1;
