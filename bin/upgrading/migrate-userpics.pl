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
my ($one, $ignoreempty, $dryrun, $user, $verify, $verbose, $clusters);
my $rv = GetOptions("ignore-empty" => \$ignoreempty,
                    "one"          => \$one,
                    "dry-run"      => \$dryrun,
                    "user=s"       => \$user,
                    "verify"       => \$verify,
                    "verbose"      => \$verbose,
                    "clusters=s"   => \$clusters,);
unless ($rv) {
    die <<ERRMSG;
This script supports the following command line arguments:

    --clusters=X[-Y]
        Only handle clusters in this range.  You can specify a
        single number, or a range of two numbers with a dash.

    --user=username
        Only move this particular user.
        
    --one
        Only move one user.  (But it moves all their pictures.)
        This is used for testing.

    --verify
        If specified, this option will reload the userpic from
        MogileFS and make sure it's been stored successfully.

    --dry-run
        If on, do not update the database.  This mode will put the
        userpic in MogileFS and give you paths to examine the picture
        and make sure everything is okay.  It will not update the
        userpic2 table, though.

    --ignore-empty
        Normally if we encounter a 0 byte userpic we die.  This
        makes it so that we just warn instead.

    --verbose
        Be very chatty.
ERRMSG
}

# make sure ljconfig is setup right (or so we hope)
die "Please define a 'userpics' class in your \%LJ::MOGILEFS_CONFIG\n"
    unless defined $LJ::MOGILEFS_CONFIG{classes}->{userpics};
die "Unable to find MogileFS object (\%LJ::MOGILEFS_CONFIG not setup?)\n"
    unless $LJ::MogileFS;

# operation modes
if ($user) {
    # move a single user
    my $u = LJ::load_user($user);
    die "No such user: $user\n" unless $u;
    handle_userid($u->{userid});
    
} else {
    # parse the clusters
    my @clusters;
    if ($clusters) {
        if ($clusters =~ /^(\d+)(?:-(\d+))?$/) {
            my ($min, $max) = map { $_ + 0 } ($1, $2 || $1);
            push @clusters, $_ foreach $min..$max;
        } else {
            die "Error: --clusters argument not of right format.\n";
        }
    } else {
        @clusters = @LJ::CLUSTERS;
    }
    
    # now iterate over the clusters to pick
    my $ctotal = scalar(@clusters);
    my $ccount = 0;
    foreach my $cid (sort { $a <=> $b } @clusters) {
        # status report
        $ccount++;
        print "\nChecking cluster $cid...\n\n";

        # get a handle
        my $dbcm = get_db_handle($cid);

        # get all userids
        print "Getting userids...\n";
        my $limit = $one ? 'LIMIT 1' : '';
        my $userids = $dbcm->selectcol_arrayref
            ("SELECT DISTINCT userid FROM userpic2 WHERE location <> 'mogile' OR location IS NULL $limit");
        my $total = scalar(@$userids);

        # iterate over userids
        my $count = 0;
        print "Beginning iteration over userids...\n";
        foreach my $userid (@$userids) {
            # move this userpic
            my $extra = sprintf("[%6.2f%%, $ccount of $ctotal] ", (++$count/$total*100));
            handle_userid($userid, $cid, $dbcm, $extra);
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
    my ($userid, $cid, $dbcm, $extra) = @_;
    
    # load user to move and do some sanity checks
    my $u = LJ::load_userid($userid)
        or die "ERROR: Unable to load userid $userid\n";

    # if a user has been moved to another cluster, but the source data from
    # userpic2 wasn't deleted, we need to ignore the user
    return unless $u->{clusterid} == $cid;

    # get a handle if we weren't given one
    $dbcm ||= get_db_handle($u->{clusterid});

    # get all their photos that aren't in mogile already
    my $picids = $dbcm->selectall_arrayref
        ("SELECT picid, fmt FROM userpic2 WHERE userid = ? AND (location <> 'mogile' OR location IS NULL)",
         undef, $u->{userid});
    return unless @$picids;

    # print that we're doing this user
    print "$extra$u->{user}($u->{userid})\n";

    # now we have a userid and picids, get the photos from the blob server
    foreach my $row (@$picids) {
        my ($picid, $fmt) = @$row;
        print "\tstarting move for picid $picid\n"
            if $verbose;
        my $format = { G => 'gif', J => 'jpg', P => 'png' }->{$fmt};
        my $data = LJ::Blob::get($u, "userpic", $format, $picid);

        # get length
        my $len = length($data);
        if ($ignoreempty && !$len) {
            print "\twarning: empty userpic.\n\n"
                if $verbose;
            next;
        }
        die "Error: data from blob empty ($u->{user}, 'userpic', $format, $picid)\n"
            unless $len;
        print "\tdata length = $len bytes, uploading to MogileFS...\n"
            if $verbose;

        # get filehandle to Mogile and put the file there
        my $fh = $LJ::MogileFS->new_file($u->mogfs_userpic_key($picid), 'userpics')
            or die "Unable to get filehandle to save file to MogileFS\n";
        $fh->print($data);
        $fh->close
            or die "Unable to save file to MogileFS: $@\n";

        # extra verification
        if ($verify) {
            my $data2 = $LJ::MogileFS->get_file_data($u->mogfs_userpic_key($picid));
            print "\tverified length = " . length($$data2) . " bytes...\n"
                if $verbose;
            die "\tERROR: picture NOT stored successfully, content mismatch\n"
                unless $$data2 eq $data;
        }

        # done moving this picture
        unless ($dryrun) {
            print "\tupdating database for this picture...\n"
                if $verbose;
            $dbcm->do("UPDATE userpic2 SET location = 'mogile' WHERE userid = ? AND picid = ?",
                      undef, $u->{userid}, $picid);
        }

        # get the paths so the user can verify if they want
        if ($verbose) {
            my @paths = $LJ::MogileFS->get_paths($u->mogfs_userpic_key($picid), 1);
            print "\tverify mogile path: $_\n" foreach @paths;
            print "\tverify site url: $LJ::SITEROOT/userpic/$picid/$u->{userid}\n";
            print "\tpicture update complete.\n\n";
        }
    }
}

# a sub to get a cluster handle and set it up for our use
sub get_db_handle {
    my $cid = shift;
    
    my $dbcm = LJ::get_cluster_master({ raw => 1 }, $cid)
        or die "ERROR: unable to get raw handle to cluster $cid\n";
    eval {
        $dbcm->do("SET wait_timeout = 28800");
    };
    $dbcm->{'RaiseError'} = 1;
    
    return $dbcm;
}
