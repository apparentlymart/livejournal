package LJ::UserSearch::MetaUpdater;

use strict;
use warnings;

use Fcntl qw(:seek :DEFAULT);
use LJ::User;

sub update_user {
    my $u = LJ::want_user(shift) or die "No userid specified";

    my %fields = @_;

    my $dbh = LJ::get_db_writer() or die "No db";

    my $oldpack = $dbh->selectrow_array("SELECT packed FROM usersearch WHERE userid=? AND good_until < ?",
                                    undef, $u->id, time);

    die $dbh->errstr if $dbh->errstr;
    
    if (!defined $oldpack) {
        # Populate full user data
        # return
    }

    my ($lastmod, $age) = unpack("NCxxx", $oldpack);

    $lastmod = $fields{lastmod} if exists($fields{lastmod});
    $age = $fields{age} if exists($fields{age});

    my $newpack = pack("NCxxx", $lastmod, $age);

    if ($newpack ne $oldpack) {
        my $rv = $dbh->do("UPDATE usersearch SET packed=? mtime=unix_timestamp() WHERE userid=?",
                          undef, $newpack, $u->id);
        die "Update count wrong '$rv' should be 1" unless $rv == 1;
    }
}

sub update_file {
    my $filename = shift;

    my $dbh = LJ::get_db_reader() or die "No db";

    sysopen(my $fh, O_RDWR, $filename) or die "Couldn't open file '$filename' for read/write: $!";

    sysseek($fh, 0, SEEK_SET) or die "Couldn't seek: $!";
    sysread($fh, my $header, 8) == 8 or die "Couldn't read 8 byte header: $!";

    my ($file_lastmod, $file_count) = unpack("NN", $header);

    my $db_count = $dbh->selectrow_array("SELECT count(*) FROM usersearch WHERE mtime=?",
                                         undef, $file_lastmod);

    my $sth = $dbh->prepare("SELECT userid, pack, mtime WHERE mtime=? ORDER BY mtime");

    $sth->execute($file_lastmod);

    my $modcount = 0;
    my $mtime = 0;
    while (my $row = $sth->fetchrow_hashref) {
        my $pack = $row->{pack};
        unless (length($pack) == 8) {
            die "Pack length was incorrect";
        }
        my $offset = $row->{userid} * 8;
        sysseek($fh, $offset, SEEK_SET) or die "Couldn't seek: $!";
        syswrite($fh, $pack) == 8 or die "Syswrite failed to complete: $!";

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

# CREATE TABLE usersearch (userid int(10) unsigned NOT NULL, packed CHAR(8) BINARY, mtime INT UNSIGNED NOT NULL, good_until INT UNSIGNED NOT NULL, INDEX(good_until));

1;
