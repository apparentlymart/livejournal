#!/usr/bin/perl
#
# finger server.
#
# accepts two optional arguments, host and port.
# doesn't daemonize.
#
#
# <LJDEP>
# lib: Socket::, Text::Wrap, cgi-bin/ljlib.pl
# </LJDEP>

my $bindhost = shift @ARGV;
my $port = shift @ARGV;

unless ($bindhost) {
    $bindhost = "0.0.0.0";
}

require "$ENV{'LJHOME'}/cgi-bin/ljlib.pl";
&connect_db();

use Socket;
use Text::Wrap;

$SIG{'INT'} = sub {
    print "Interrupt caught!\n";
    close FH;
    close CL;
    exit;
};

my $proto = getprotobyname('tcp');
socket(FH, PF_INET, SOCK_STREAM, $proto) || die $!;

$port ||= 79;
my $localaddr = inet_aton($bindhost);
my $sin = sockaddr_in($port, $localaddr);

bind (FH, $sin) || die $!;

listen(FH, 10);

my $SERVE = 1;
while ($SERVE)
{
    accept(CL, FH) || die $!;
    &connect_db();
    my $line = <CL>;
    chomp $line;
    $line =~ s/\0//g;
    $line =~ s/\s//g;

    if ($line eq "") {
	print CL "Welcome to the $LJ::SITENAME finger server!

You can make queries in the following form:

   \@$LJ::DOMAIN              - this help message
   user\@$LJ::DOMAIN          - their userinfo
";
	close CL;
	next;
    }

    if ($line =~ /^(\w{1,15})$/) {
	# userinfo!
	my $user = $1;
	my $quser = $dbh->quote($user);
	my $sth = $dbh->prepare("SELECT user, has_bio, paidfeatures, userid, name, email, bdate, timeupdate, lastitemid, allow_infoshow FROM user WHERE user=$quser");
	$sth->execute;
	my $u = $sth->fetchrow_hashref;
	unless ($u) {
	    print CL "\nUnknown user ($user)\n";
	    close CL;
	    next;
	}

	my $bio;
	if ($u->{'has_bio'} eq "Y") {
	    $sth = $dbh->prepare("SELECT bio FROM userbio WHERE userid=$u->{'userid'}");
	    $sth->execute;
	    ($bio) = $sth->fetchrow_array;
	}
	delete $u->{'has_bio'};

	if ($u->{'allow_infoshow'} eq "Y") {
	    &load_user_props($u, "opt_whatemailshow", "country", "state", "city", "zip", "aolim", "icq", "url", "urlname", "gender", "yahoo", "msn");
	} else {
	    $u->{'opt_whatemailshow'} = "N";
	}
	delete $u->{'allow_infoshow'};

	if ($u->{'opt_whatemailshow'} eq "L") {
	    delete $u->{'email'};
	} 
	if ($LJ::USER_EMAIL && ($u->{'paidfeatures'} eq "on" || $u->{'paidfeatures'} eq "paid")) {
	    if ($u->{'email'}) { $u->{'email'} .= ", "; }
	    $u->{'email'} .= "$user\@$LJ::USER_DOMAIN";
	}
	if ($u->{'opt_whatemailshow'} eq "N") {
	    delete $u->{'email'};
	} 
	delete $u->{'opt_whatemailshow'};

	my $max = 1;
	foreach (keys %$u) {
	    if (length($_) > $max) { $max = length($_); }
	}
	$max++;

	print CL "\nUserinfo for $user...\n\n";
	foreach my $k (sort keys %$u) {
	    printf CL "%${max}s : %s\n", $k, $u->{$k};
	}
	
	if ($bio) {
	    $bio =~ s/^\s+//;
	    $bio =~ s/\s+$//;
	    print CL "\nBio:\n\n";
	    $Text::Wrap::columns = 77;
	    print CL Text::Wrap::wrap("   ", "   ", $bio);
	}
	print CL "\n\n";
	
	close CL;
	next;
	
    }

    print CL "Unsupported/unimplemented query type: $line\n";
    print CL "length: ", length($line), "\n";
    close CL;
    next;
}
