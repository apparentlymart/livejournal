#!/usr/bin/perl
#
# <LJDEP>
# lib: Getopt::Long
# </LJDEP>

use strict;
use Getopt::Long;

my $help = '';
my $sync = '';
my $full = '';
my $diff = '';
my $cvsonly = '';

exit 1 unless GetOptions('help' => \$help,
			 'full' => \$full,
			 'sync' => \$sync,
			 'diff' => \$diff,
			 'cvsonly' => \$cvsonly
			 );

if ($help) {
    die "Usage: cvsreport.pl [opts] [files]\n" .
	"    --help          Get this help\n" .
	"    --sync          Put files where they need to go.\n" .
	"                    All files, unless you specify which ones.\n".
	"    --full          Show main files not in a CVS repository\n".
	"    --diff          Show diffs of changed files.\n".
	"    --cvsonly       Don't consider files changed in live tree.\n";
}

unless (-d $ENV{'LJHOME'}) { 
    die "\$LJHOME not set.\n";
}


my $maind = $ENV{'LJHOME'};
my $cvs = "$maind/cvs/livejournal";
my $cvslocal = "$maind/cvs/local";
my @toplevel = qw(htdocs cgi-bin bin doc src);

my %status = ();   # $relfile -> $status

# checks if files aren't in CVS, are newer than CVS, or if CVS is newer
scan_main();

# checks to see if new CVS files aren't in the main tree yet
scan_cvs();

my @files = scalar(@ARGV) ? @ARGV : sort keys %status;
foreach my $file (@files) 
{
    next if ($file =~ /~$/);     # ignore emacs files
    my $status = $status{$file};
    if ($status eq "main -> ??") { 
	next if ($sync);
	next unless ($full);
    }
    my $showstatus = $status || ("-"x20);

    my ($sdir, $ddir);
    if ($status eq "main <- cvs") {
	($sdir, $ddir) = ($cvs, $maind);
    } elsif ($status eq "main <- local") {
	($sdir, $ddir) = ($cvslocal, $maind);
    } elsif ($status eq "main -> local") {
	($sdir, $ddir) = ($maind, $cvslocal);
    } elsif ($status eq "main -> cvs") {
	($sdir, $ddir) = ($maind, $cvs);
    } 

    if ($cvsonly && $sdir eq $maind) {
	next;
    }
    
    my $the_diff = "";
    if ($diff && $status ne "main -> ??" && $sdir && $ddir) {
	$the_diff = `diff -u $ddir/$file $sdir/$file`;
	unless ($the_diff)
	{
	    # no real change (just touched/copied?), so copy
	    # cvs one on top to fix times up.
	    if ($ddir ne $maind) {
		($sdir, $ddir) = ($ddir, $sdir);
	    }
	    install($sdir, $ddir, $file);
	    next;
	}    
    }

    printf "%-20s %s\n", $showstatus, $file;
    print $the_diff;
    
    if ($sync && $sdir && $ddir) {
	unless (install($sdir, $ddir, $file)) { print "   Error: $!\n"; }
    }
}

sub install
{
    my ($sdir, $ddir, $relfile) = @_;
    
    # check for directory existence
    my @dirs = split(m!/!, $relfile);
    pop @dirs;  # pop the file part.
    for (my $i=0; $i<scalar(@dirs); $i++) {
	my $sd = join("/", @dirs[0..$i]);
	my $fullsd = "$ddir/$sd";
	unless (-d $fullsd) {
	    mkdir $fullsd, 0755;
	}
    }

    return copy("$sdir/$relfile", "$ddir/$relfile");
}

# was using perl's File::Copy, but I want to preserve the file time.
sub copy
{
    my ($src, $dest) = @_;
    my $ret = system("cp", "-p", $src, $dest);
    return ($ret == 0);
}

sub scan_cvs
{
    foreach my $repo ("cvs", "local")
    {
	my $cdir = $repo eq "cvs" ? $cvs : $cvslocal;
	my @dirs = @toplevel;
	while (@dirs)
	{
	    my $dir = shift @dirs;
	    my $fulldir = "$cdir/$dir";
	    next unless (-e $fulldir);
	    opendir (MD, $fulldir) or die "Can't open $fulldir.";
	    while (my $file = readdir(MD)) {
		next if ($file =~ /CVS/);
		if (-d "$fulldir/$file") {
		    unless ($file eq "." || $file eq "..") {
			unshift @dirs, "$dir/$file";
		    }
		} elsif (-f "$fulldir/$file") {
		    my $relfile = "$dir/$file";
		    
		    my $mtime = mtime("$maind/$relfile");
		    my $ctime = mtime("$cdir/$relfile");
		    
		    my $status = "";
		    if (! $mtime && $ctime) {
			$status = "main <- $repo";
		    } 

		    $status{$relfile} = $status if ($status);
		    
		} else {
		    print "WHAT IS THIS? $dir/$file\n";
		}
	    }
	    close MD;
	}
    }
}

sub scan_main
{
    my @dirs = @toplevel;
    while (@dirs)
    {
	my $dir = shift @dirs;
	my $fulldir = "$maind/$dir";
	opendir (MD, $fulldir) or die "Can't open $fulldir.";
	while (my $file = readdir(MD)) {
	    if (-d "$fulldir/$file") {
		unless ($file eq "." || $file eq "..") {
		    unshift @dirs, "$dir/$file";
		}
	    } elsif (-f "$fulldir/$file") {
		my $relfile = "$dir/$file";

		my $mtime = mtime("$maind/$relfile");
		my $ctime = mtime("$cvs/$relfile");
		my $ltime = mtime("$cvslocal/$relfile");

		my $status = "";
		if ($mtime && ! $ctime && ! $ltime) {
		    $status = "main -> ??";
		} elsif ($mtime > $ctime && $mtime > $ltime) {
		    if ($ltime) {
			$status = "main -> local";
		    } else {
			$status = "main -> cvs";
		    }
		} elsif (! $ltime && $ctime > $mtime) {
		    $status = "main <- cvs";
		} elsif ($ltime && $ltime > $mtime) {
		    $status = "main <- local";
		}

		$status{$relfile} = $status if ($status);
		
	    } else {
		print "WHAT IS THIS? $dir/$file\n";
	    }
	}
        close MD;
    }

}

sub mtime
{
    my $file = shift;
    return (stat($file))[9];
}
