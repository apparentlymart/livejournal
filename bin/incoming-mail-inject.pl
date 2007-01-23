#!/usr/bin/perl
use strict;

BEGIN {
    $ENV{LJHOME} ||= "/home/lj";
}
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';
use LJ::IncomingEmailHandle;

my $sclient = LJ::theschwartz() or die "No schwartz config.\n";

my $tempfail = sub {
    my $msg = shift;
    warn "Failure: $msg\n" if $msg;
    # makes postfix do temporary failure:
    exit(75);
};

# below this size, we put in database directly.  if over,
# we put in mogile.
sub IN_MEMORY_THRES () {
    return
        $ENV{T_MAILINJECT_THRES_SIZE} ||
        768 * 1024;
}

my $buf;
my $msg = '';  # in-memory message
my $rv;
my $len = 0;
my $ieh;
eval {
    while ($rv = sysread(STDIN, $buf, 1024*64)) {
        $len += $rv;
        if ($ieh) {
            $ieh->append($buf);
        } else {
            $msg .= $buf;
        }

        if ($len > IN_MEMORY_THRES && ! $ieh) {
            # allocate a mogile filehandle once we cross the line of
            # what's too big to store in memory and in a schwartz arg
            $ieh = LJ::IncomingEmailHandle->new;
            $ieh->append($msg);
            undef $msg;  # no longer used.
        }
    }
    $tempfail->("Error reading: $!") unless defined $rv;

    if ($ieh) {
        $ieh->closetemp;
        $tempfail->("Size doesn't match") unless $ieh->tempsize == $len;
        $ieh->insert_into_mogile;
    }
};
$tempfail->($@) if $@;

my $h = $sclient->insert(TheSchwartz::Job->new(funcname => "LJ::Worker::IncomingEmail",
                                               arg      => ($ieh ? $ieh->id : $msg)));
warn "handle = $h\n";
exit 0 if $h;
exit(75);  # temporary error


