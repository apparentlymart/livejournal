#!/usr/bin/perl
#
# LiveJournal 404 handler.
#
# Tasks:
#   - uses redirect.dat to forward people onto new URLs
#   - makes graphviz files for AT&T's webdot server (see note below)
#

use FCGI;
require "$ENV{'LJHOME'}/cgi-bin/ljlib.pl";

my %redir;
open (REDIR, "$ENV{'LJHOME'}/cgi-bin/redirect.dat");
while (<REDIR>) {
    next unless (/^(\S+)\s+(\S+)/);
    my ($src, $dest) = ($1, $2);
    $redir{$src} = $dest;
}

my $REQ_COUNT = 0;
my $REQ_MAX = 500;

my $CONTINUE = 1;
my $SERVING = 0;

$SIG{'TERM'} = sub {
    if ($SERVING) {
	$CONTINUE = 0;  # when next request finishes, end.
    } else {
	exit;
    }
};

 REQUEST:
    while((($SERVING=0) || 1) &&      # set serving to 0
          $CONTINUE &&                # stop if got signal earlier
          ++$REQ_COUNT <= $REQ_MAX && # go until time to restart
	FCGI::accept() >= 0)
{
    $SERVING = 1;

    my $dbs = LJ::get_dbs();
    my $dbh = $dbs->{'dbh'};
    my $dbr = $dbs->{'reader'};

    my $req_path = $ENV{'REQUEST_URI'};

    ### AT&T's webdot server only accepts URLs without question marks
    ### in them, so we make them here now.  great place, eh?
    if ($req_path =~ m!^/friends/graph/(\w+)\.dot$!) 
    {
	print "Status: 200 OK\n";
	print "Content-type: text/plain\n\n";
	print LJ::make_graphviz_dot_file($dbh, $1);
	next REQUEST;	
    }

    my $req_args;
    if ($req_path =~ s/\?.*$//) {
	$req_args = $&;
    }
    $req_path =~ s!/$!!;

    if ($redir{$req_path}) {
	my $new = $redir{$req_path} . $req_args;
	print "Status: 301 Moved Permanently\n";
	print "Location: $new\n";
	print "Content-type: text/html\n\n";
	print "This page is now available <A HREF=\"$new\">here</A>.";

	open (FLOG, ">>$ENV{'LJHOME'}/logs/404.log");
	print FLOG join("\t", "warning", $req_path, $ENV{'HTTP_REFERER'}),"\n";
	close FLOG;

	next REQUEST;
    }

    print "Content-type: text/html\n";
    print "Cache-Control: private, proxy-revalidate\n";
    print "Status: 404 Not Found\n";
    print "\n";
    print "<H1>Not Found</H1>The requested URL ", LJ::ehtml($ENV{'REQUEST_URI'}),
          " was not found on this server.\n";
    next REQUEST;
}


