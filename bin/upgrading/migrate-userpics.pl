#!/usr/bin/perl

use strict;
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';
use LJ::Blob;
use LJ::User;
use Getopt::Long;
use IPC::Open3;

# this script is a migrater that will move userpics from an old storage method
# into mogilefs.

# the basic theory is that we iterate over all clusters, find all userpics that
# aren't in mogile right now, and put them there

# determine 
my ($picker, $one, $ignoreempty, $dryrun);
my $rv = GetOptions("picker=s"     => \$picker,
                    "ignore-empty" => \$ignoreempty,
                    "one"          => \$one,
                    "dry-run"      => \$dryrun);
unless ($rv) {
    die <<ERRMSG;
This script supports the following command line arguments:

    --picker=/path/to/picker
        Instruct us to use the picker program to get userids.

    --one
        Only move one user.  (But it moves all their pictures.)
        This is used for testing.

    --dry-run
        If on, do not update the database.  This mode will put the
        userpic in MogileFS and give you paths to examine the picture
        and make sure everything is okay.  It will not update the
        userpic2 table, though.

    --ignore-empty
        Normally if we encounter a 0 byte userpic we die.  This
        makes it so that we just warn instead.
ERRMSG
}

# make sure ljconfig is setup right (or so we hope)
die "Please define a 'userpics' class in your \%LJ::MOGILEFS_CONFIG\n"
    unless defined $LJ::MOGILEFS_CONFIG{classes}->{userpics};
die "Unable to find MogileFS object (\%LJ::MOGILEFS_CONFIG not setup?)\n"
    unless $LJ::MogileFS;
die "You must enable \$LJ::USERPIC_MOGILEFS in ljconfig.pl to use this script\n"
    unless $LJ::USERPIC_MOGILEFS;

# if picker, set it up
if ($picker) {
    die "Error: picker path does not exist\n" unless -e $picker;

    my ($p_in, $p_out, $p_pid);
    $p_pid = open3($p_out, $p_in, $p_in, $picker);

    # ask the picker for a userid
    while (1) {
        print $p_out "next_userid\n";
        my $resp = <$p_in>;
        last unless defined $resp;

        if ($resp =~ /^userid (\d+)/) {
            # got a userid, handle it
            handle_userid($1);
        } elsif ($resp =~ /^done/) {
            # no more userids, end this run
            last;
        } else {
            # don't know what they said, so die
            die "Unknown line from picker: $resp";
        }
    }

    # close the picker, we're done
    print "Closing picker...\n";
    print $p_out "done\n";
    waitpid $p_pid, 0;
} else {
    # now iterate over the clusters to pick
    foreach my $cid (sort { $a <=> $b } @LJ::CLUSTERS) {
        # status report
        print "\nChecking cluster $cid...\n\n";

        # get a handle
        my $dbcm = get_db_handle($cid);

        # get all userids
        my $limit = $one ? 'LIMIT 1' : '';
        my $userids = $dbcm->selectcol_arrayref
            ("SELECT DISTINCT userid FROM userpic2 WHERE location <> 'mogile' OR location IS NULL $limit");

        # iterate over userids
        foreach my $userid (@$userids) {
            # move this userpic
            handle_userid($userid, $dbcm);
        }

        # don't hit up more clusters
        last if $one;
    }
}
print "\n";

print "Updater terminating.\n";

#############################################################################
### helper subs down here

# take a userid and move their pictures.  returns 0 on error, 1 on successful
# move of a user's pictures, and 2 meaning the user isn't ready for moving
# (dversion < 7, etc)
sub handle_userid {
    my ($userid, $dbcm) = @_;
    
    my $u = LJ::load_userid($userid);
    $dbcm ||= get_db_handle($u->{clusterid});

    # get all their photos that aren't in mogile already
    my $picids = $dbcm->selectall_arrayref
        ("SELECT picid, fmt FROM userpic2 WHERE userid = ? OR location <> 'mogile' OR location IS NULL",
         undef, $u->{userid});
    return unless @$picids;

    # now we have a userid and picids, get the photos from the blob server
    foreach my $row (@$picids) {
        my ($picid, $fmt) = @$row;
        print "$u->{user}($u->{userid}): starting move for picid=$picid\n";
        my $format = { G => 'gif', J => 'jpg', P => 'png' }->{$fmt};
        my $data = LJ::Blob::get($u, "userpic", $format, $picid);

        # get length
        my $len = length($data);
        if ($ignoreempty && !$len) {
            print "\tWarning: empty userpic.\n\n";
            next;
        }
        die "Error: data from blob empty ($u->{user}, 'userpic', $format, $picid)\n"
            unless $len;
        print "\tdata length = $len bytes, uploading to MogileFS...\n";

        # get filehandle to Mogile and put the file there
        my $fh = $LJ::MogileFS->new_file($u->mogfs_userpic_key($picid), 'userpics')
            or die "Unable to get filehandle to save file to MogileFS\n";
        $fh->print($data);
        $fh->close
            or die "Unable to save file to MogileFS: $@\n";

        # extra verification
        my $data2 = $LJ::MogileFS->get_file_data($u->mogfs_userpic_key($picid));
        print "\tverified length = " . length($$data2) . " bytes...\n";

        # done moving this picture
        unless ($dryrun) {
            print "\tupdating database for this picture...\n";
            $dbcm->do("UPDATE userpic2 SET location = 'mogile' WHERE userid = ? AND picid = ?",
                      undef, $userid, $picid);
        }

        # get the paths so the user can verify if they want
        my @paths = $LJ::MogileFS->get_paths($u->mogfs_userpic_key($picid), 1);
        print "\tverify mogile path: $_\n" foreach @paths;
        print "\tverify site url: $LJ::SITEROOT/userpic/$picid/$u->{userid}\n";

        # update complete
        print "\tpicture update complete.\n\n";
    }
}

# a sub to get a cluster handle and set it up for our use
sub get_db_handle {
    my $cid = shift;
    
    my $dbcm = LJ::get_cluster_master({ raw => 1 }, $cid);
    eval {
        $dbcm->do("SET wait_timeout = 28800");
    };
    $dbcm->{'RaiseError'} = 1;
    
    return $dbcm;
}
