#!/usr/bin/perl
#

use strict;
use File::Find;

require "$ENV{'LJHOME'}/cgi-bin/ljlib.pl";

my $dir = "$ENV{'LJHOME'}/htdocs/userpics";

my $db = LJ::get_db_reader();
my $deleted = 0;

my @files;
my $flush = sub {
    my %owner;
    my @ids;
    foreach my $f (@files) {
	if ($f->[0] =~ /\d+/) {
	    push @ids, $&;
	}
    }
    my $in = join(',', @ids);
    #print "Checking: $in\n";
    my $sth = $db->prepare("SELECT picid, userid FROM userpic WHERE picid IN ($in)");
    $sth->execute;
    while (my ($pid, $uid) = $sth->fetchrow_array) {
	$owner{$pid} = $uid;
    }
    
    # delete ones that are gone
    my @del;
    foreach my $f (@files) {
	next unless $f->[0] =~ /\d+/;
	my $pid = $&;
	next if $owner{$pid};
	push @del, $f->[1];

	my $symlink = $f->[1];
	if ($symlink =~ s/\-\d+//) {
	    push @del, $symlink;
	}
    }

    @files = ();
    return unless @del;

    my $to_del = scalar @del;
    $deleted += $to_del;
    print "Deleting: $to_del (total: $deleted)\n";
    unlink @del;
    sleep 1;
};

my $add = sub {
    push @files, [ $_[0], $_[1] ];
    if (@files > 100) { $flush->(); }
};

sub wanted {
    return unless -f;
    $add->($_, $File::Find::name);
}

find({
    'wanted' => \&wanted,
}, $dir);

