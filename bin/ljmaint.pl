#!/usr/bin/perl
#
# <LJDEP>
# lib: Fcntl::, cgi-bin/ljlib.pl
# file: bin/maint/taskinfo.txt, bin/maint/taskinfo-local.txt
# </LJDEP>

use strict;
use Fcntl ':flock'; 
use vars qw(%maint $VERBOSE);

unless (-d $ENV{'LJHOME'}) {
    die "\$LJHOME not set.\n";
}

require "$ENV{'LJHOME'}/cgi-bin/ljlib.pl";

my %maintinfo;
my $MAINT = "$LJ::HOME/bin/maint";
my $LOCKDIR = "$LJ::HOME/temp";

load_tasks();

$VERBOSE = 1;   # 0=quiet, 1=normal, 2=verbose

if (@ARGV)
{
    ## check the correctness of the taskinfo files
    if ($ARGV[0] eq "--check") {
        foreach my $task (keys %maintinfo)
        {
            my %loaded;
            my $source = $maintinfo{$task}->{'source'};
            unless (-e "$MAINT/$source") {
                print "$task references missing file $source\n";
                next;
            }
            unless ($loaded{$source}++) {
                require "$MAINT/$source";
            }
            unless (ref $maint{$task} eq "CODE") {
                print "$task is missing code in $source\n";
            }
        }
        exit 0;
    }

    if ($ARGV[0] =~ /^-v(.?)/) {
        if ($1 eq "") { $VERBOSE = 2; }
        else { $VERBOSE = $1; }
        shift @ARGV;
    }

    my @targv;
    my $hit_colon = 0;
    foreach my $arg (@ARGV)
    {
        if ($arg eq ';') {
            $hit_colon = 1;
            run_task(@targv);
            @targv = ();
            next;
        } 
        push @targv, $arg;
    }

    if ($hit_colon) {
        # new behavior: task1 arg1 arg2 ; task2 arg arg2 
        run_task(@targv);	
    } else {
        # old behavior: task1 task2 task3  (no args, ever)
        foreach my $task (@targv) {
            run_task($task);
        }
    }
}
else
{
    print "Available tasks: \n";
    foreach (sort keys %maintinfo) {
        print "  $_ - $maintinfo{$_}->{'des'}\n";
    }
}

sub run_task
{
    my $task = shift;
    return unless ($task);
    my @args = @_;

    print "Running task '$task':\n\n" if ($VERBOSE >= 1);
    unless ($maintinfo{$task}) {
        print "Unknown task '$task'\n";
        return;
    }

    my $lock_file = "$LOCKDIR/mainttask-$task";
    if (-e $lock_file) {
        open(LOCK, $lock_file);
        my $line = <LOCK>;
        if ($line =~ /(\d+)/) {
            my $start = $1;
            my $age = time() - $start;
            if ($age > 60*5) {
                print "Stale ljmaint lock file?  Existing for $age seconds: $lock_file\n";
                exit 1;
            }
        }
        close LOCK;
    }

    open (LOCK, ">$lock_file") or die "Couldn't write lock file: $lock_file: $!";
    if (flock (LOCK, LOCK_EX|LOCK_NB)) {
        seek(LOCK, 0, 0);  # go to beginning of file
        select(LOCK);
        $| = 1;
        select(STDOUT);
        print LOCK ("Started at: " . time() . " (" . scalar(localtime()) . ")\n");
        require "$MAINT/$maintinfo{$task}->{'source'}";
        $LJ::LJMAINT_VERBOSE = $VERBOSE;
        $maint{$task}->(@args);
        unlink $lock_file;
        flock(LOCK, LOCK_UN);
        close LOCK;
    } else {
        print "Task '$task' already running.  Quitting.\n" if ($VERBOSE >= 1);
    }
}

sub load_tasks
{
    foreach my $filename (qw(taskinfo.txt taskinfo-local.txt))
    {
        my $file = "$MAINT/$filename";
        open (F, $file) or next;
        my $source;
        while (my $l = <F>) {
            next if ($l =~ /^\#/);
            if ($l =~ /^(\S+):\s*/) {
                $source = $1; 
                next;
            }
            if ($l =~ /^\s*(\w+)\s*-\s*(.+?)\s*$/) {
                $maintinfo{$1}->{'des'} = $2;
                $maintinfo{$1}->{'source'} = $source;
            }
        }
        close (F);
    }
}

