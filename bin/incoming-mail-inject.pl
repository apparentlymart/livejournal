#!/usr/bin/perl
use strict;
BEGIN {
    $ENV{LJHOME} ||= "/home/lj";
}
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';

my $rand = rand();

# makes postfix do temporary failure:
#exit(75);

use constant IN_MEMORY_THRES => 768 * 1024;  # below this size, we put in database directly.

open (my $fh, ">/home/lj/mail/last-email.txt");

my $msg = '';  # in-memory message
my $mogfh;
while (<>) {
    print $fh $_;
    if ($msg < IN_MEMORY_THRES) {
        $msg .= $_;
    } else {
        # allocate a file in mogilefs
        $mogfh = 1;  # TODO: filehandle object
    }
}

if ($mogfh) {
    warn "Not implemented (to MogileFS)\n";
    exit(75);
}

my $sclient = LJ::theschwartz() or die "No schwartz config.\n";

my $h = $sclient->insert(TheSchwartz::Job->new(funcname => "LJ::Worker::IncomingEmail",
                                               arg      => $msg));
print "handle = $h\n";
exit 0 if $h;
exit(75);  # temporary error


