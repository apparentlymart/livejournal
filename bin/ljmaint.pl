#!/usr/bin/perl
#

use strict;
use Fcntl ':flock'; 

require '/home/lj/cgi-bin/ljlib.pl';

my $BIN = "/home/lj/bin";
my $MAINT = "$BIN/maint";
my $TEMP = "/home/lj/temp";
my $LOGDIR = "/home/lj/logs";

my %maint;
load_tasks();

my $VERBOSE=1;   # 0=quiet, 1=normal, 2=verbose
if (@ARGV)
{
    if ($ARGV[0] =~ /^-v(.?)/) {
	if ($1 eq "") { $VERBOSE = 2; }
	else { $VERBOSE = $1; }
	shift @ARGV;
    }
    
    foreach my $task (@ARGV)
    {
	print "Running task '$task':\n\n" if ($VERBOSE >= 1);
	open (LOCK, ">$TEMP/mainttask-$task");
	if (flock (LOCK, LOCK_EX|LOCK_NB)) {
	    if (ref $maint{$task} eq "CODE") {
		&{ $maint{$task} };
	    } else {
		if ($maint{$task}->{'source'}) {
		    require "$MAINT/$maint{$task}->{'source'}";
		}
		&{ $maint{$task}->{'sub'} }();
	    }
	    unlink "$TEMP/mainttask-$task";
	    flock(LOCK, LOCK_UN);
	    close LOCK;
	} else {
	    print "Task '$task' already running.  Quitting.\n" if ($VERBOSE >= 1);
	}
    }
}
else
{
    print "Known tasks: \n";
    foreach (sort keys %maint)
    {
	my $des;
	if (ref $maint{$_} eq "HASH") {
	    $des = $maint{$_}->{'des'} ? " - $maint{$_}->{'des'}" : "";
	}
	print "  $_$des\n";
    }
}

sub load_tasks
{
    opendir (MAINTD, "$MAINT") or die "Can't open bin/maint.\n";
    while (my $filename = readdir(MAINTD))
    {
	my $file = "$MAINT/$filename";
	next if ($filename =~ /~$/ || 
		 $filename =~ /^#.+#$/ || 
		 $filename =~ /^\.\#/ || 
		 ! -f $file);

	my $open = 0;
	open (F, $file);
	print "opened: $file\n";
	while (my $l = <F>)
	{
	    next unless ($l =~ /^\#/);
	    if ($l =~ m!<maint>!)  { $open = 1; next; }
	    if ($l =~ m!</maint>!) { last; }
	    if ($l =~ /^#\s*(\w+)\s*:\s*(.+?)\s*$/) {
		$maint{$1}->{'des'} = $2;
		$maint{$1}->{'source'} = $filename;
		print "maint{$1} = $filename\n";
	    }
	}
	close (F);
    }
}

sub old_tasks
{
    $maint{'sleep_5'} = {
	'sub' => sub { print "Start.\n"; sleep 5; print "Stop.\n"; }
    };

    $maint{'clean_intdups'} = {
	'source' => 'interests.pl',
	'des' => 'Remove duplicate interests (rare, but it happens)',
    };

    $maint{'create_temp_dirs'} = {
	'source' => 'temp.pl',
	'des' => 'Create tree of temporary directories.',
    };
    
    $maint{'clean_intcounts'} = {
	'source' => 'interests.pl',
	'des' => 'Migration tool.  Used to define intcount when it was null.',
    };

    $maint{'expiring'} = {
	'source' => 'expiring.pl',
	'des' => 'Expire un-renewed paid accounts, and remind users with accounts soon to expire.',
    };

    $maint{'gen_robotstxt'} = {
	'source' => 'robots.pl',
	'des' => 'Generates the robots.txt file for people don\'t want to be indexed.',
    };

    $maint{'clean_oldusers'} = {
	'source' => 'clean_oldusers.pl',
	'des' => 'Remove users that have stale/invalid accounts.',
    };

    $maint{'stats_makemarkers'} = {
	'source' => 'xplanet.pl',
	'des' => 'Make the markers.txt file to feed to xplanet',
    };

    $maint{'stats_friends'} = {
	'source' => 'statsfriends.pl',
	'des' => 'Make the text file listing all friend relationships.',
    };

    $maint{'clean_cities'} = {
	'source' => 'clean_cities.pl',
	'des' => '[old?] takes weirdly formatted city names and fixes/deletes them',
    };

    $maint{'clean_caches'} = {
	'source' => 'clean_caches.pl',
	'des' => 'removes old cache files',
    };
    
    $maint{'db_batchdelete'} = {
	'source' => 'batchdelete.pl',
	'des' => 'Delete stuff from the database en masse.',
    };
    
    $maint{'xfers_do'} = {
	'source' => 'xfers.pl',
	'des' => "FTPs/SCPs people's journals to their webservers.",
    };
	 
    $maint{'pay_mail'} = {
	'source' => 'pay.pl',
	'des' => 'Sends out the email thanking people for their payment',
    };
    
    $maint{'pay_updateaccounts'} = {
	'source' => 'pay.pl',
	'des' => "Sets people's accounts to 'paid' if it's not already.",
    };

    $maint{'build_randomuserset'} = {
	'source' => 'stats.pl',
	'des' => "Sets people's accounts to 'paid' if it's not already.",
    };
    
    $maint{'syncweb'} = {
	'source' => 'syncweb.pl',
	'des' => "rsync files from master server.",
    };

    $maint{'syncmodules'} = {
	'source' => 'syncweb.pl',
	'des' => "Install new local perl modules if needed, on master or slaves.",
    };

    $maint{'genstats'} = {
	'source' => 'stats.pl',
	'des' => 'Generates the nightly statistics',
    };

    $maint{'genstats_weekly'} = {
	'source' => 'stats.pl',
	'des' => 'Generates the weekly statistics',
    };
    
    $maint{'genstatspics'} = {
	'source' => 'statspics.pl',
	'des' => 'Makes a bunch of graphs to show on the statistics page.',
    };
    
    $maint{'sendicqs'} = {
	'source' => 'icq.pl',
	'des' => '[OLD/BROKEN] send crap via icq gateway.',
    };

    $maint{'bdaymail'} = {
	'source' => 'bday.pl',
	'des' => 'Sends people happy birthday email.',
    };
    
    $maint{'makealiases'} = {
	'source' => 'aliases.pl',
	'des' => "Rebuilds the postfix /etc/postfix/virtual file for paid users.",
    };

    $maint{'makemoodindexes'} = {
	'source' => 'moods.pl',
	'des' => 'Generate the index.html files in all the mood directories.',
    };

    $maint{'dirsync'} = {
	'source' => 'dirsync.pl',
	'des' => 'Sync the public docroots from the devftp area.',
    };
    

$maint{'rotatelogs'} = sub
{
  unless ($> == 0) {
    print "Only root can rotate logs\n";
    return 0;
  }

  my $host = `hostname`;
  unless ($host =~ /^lj-(\w+)\.livejournal\.com$/) {
      print "Can't detect what LJ host this is.\n";
      return 0;
  }
  $host = $1;
  print "Host = $host\n";

  print "Rotating logs...\n";
  system("$BIN/rotate $LOGDIR/access-$host $LOGDIR/error-$host $LOGDIR/uaccess-$host $LOGDIR/uerror-$host");
  print "Gracefully restarting apache...\n";
  system("/usr/local/apache/bin/apachectl", "graceful");
  print "Done.\n";
};

$maint{'apgrace'} = sub
{
  unless ($> == 0) {
    print "Only root can restart apache\n";
    return 0;
  }

  print "Gracefully restarting apache...\n";
  system("/usr/local/apache/bin/apachectl", "graceful");
  print "Done.\n";
};

$maint{'apgraceslaves'} = sub
{
  unless ($> == 0) {
    print "Only root can restart apache\n";
    return 0;
  }

  my $host = `hostname`;
  if ($host =~ /lj-kenny/) {
      print "I am kenny.  I'm not restarting.\n";
      return;
  }

  print "Gracefully restarting apache...\n";
  system("/usr/local/apache/bin/apachectl", "graceful");
  print "Done.\n";
};

$maint{'apreset'} = sub
{
  unless ($> == 0) {
    print "Only root can restart apache\n";
    return 0;
  }

  print "Restarting apache...\n";
  system("/usr/local/apache/bin/apachectl", "restart");
  print "Done.\n";
};

$maint{'hupcaches'} = sub
{
    if ($> == 0) {
	print "Don't run this as root.\n";
	return 0;
    }
    foreach my $proc (qw(404notfound.cgi users customview.cgi bmlp.pl log.cgi))
    {
	print "$proc...";
	print `$BIN/hkill 404notfound.cgi | wc -l`;
    }
};

$maint{'restartapps'} = sub
{
    if ($> == 0) {
	print "Don't run this as root.\n";
	return 0;
    }
    my $pid;
    if ($pid = fork) 
    {
	print "Started.\n";
	return 1;
    }

    foreach my $proc (qw(404notfound.cgi users customview.cgi)) {
	system("$BIN/pkill", $proc);
    }
};

$maint{'load'} = sub
{
    print ((`w`)[0]);
   
};

$maint{'date'} = sub
{
    print ((`date`)[0]);
   
};

$maint{'exposeconf'} = sub
{
    print "-I- Copying configuration files to /misc/conf\n";
    my @files = qw(
		   /usr/src/sys/i386/conf/KENNYSMP   kernel-config.txt
		   /etc/postfix/main.cf              postfix-main.cf.txt
		   /etc/postfix/master.cf            postfix-master.cf.txt
		   );
		   
    while (@files) {
	my $src = shift @files;
	my $dest = shift @files;
	print "$src -> $dest\n";
	system("cp", $src, "/home/lj/htdocs/misc/conf/$dest");
    }
    print "done.\n";
};

} # end sub
