package LJ::RateLimit;

use strict;
use warnings;

use LJ::MemCache qw//;

our $RATE_DATAVER = 1;


# more anti-spammer rate limiting.  returns 1 if rate is okay, 0 if too fast.
#
# args:
#   1) u -> user that performs action
#   2) rate conditions
#      [
#       [ memcache key, [ [rate, period-of-time], [rate, period-of-time] ],
#       ...
#      ]
#   3) nowrite (optional): do not write to the ratelog; just check what's
#      already there.
sub check {
    my $class = shift;
    my $u     = shift;
    my @watch = @{ shift || [] };
    my $nowrite = shift;

    # we require memcache to do rate limiting efficiently
    return 1 unless @LJ::MEMCACHE_SERVERS;

    # return right away if the account is suspended
    return 0 if $u && $u->statusvis =~ /[SD]/;

    # allow some users to be very aggressive commenters and authors. i.e. our bots.
    return 1 if $u
                and grep { $u->username eq $_ } @LJ::NO_RATE_CHECK_USERS;


    my $ip  = LJ::get_remote_ip();
    my $now = time();
    foreach my $watch (@watch) {
        my ($key, $rates) = ($watch->[0], $watch->[1]);
        my $max_period = $rates->[0]->[1];

        my $log = LJ::MemCache::get($key);

        # parse the old log
        my @times = ();
        if ($log && length($log) % 4 == 1 && substr($log,0,1) eq $RATE_DATAVER) {
            my $ct = (length($log)-1) / 4;
            for (my $i=0; $i<$ct; $i++) {
                my $time = unpack("N", substr($log,$i*4+1,4));
                push @times, $time if $time > $now - $max_period;
            }
        }

        # add this event unless we're throttling based on spamreports
        push @times, $now unless $key =~ /^spamreports/;

        # check rates
        foreach my $rate (@$rates) {
            my ($allowed, $period) = ($rate->[0], $rate->[1]);
            my $events = scalar grep { $_ > $now-$period } @times;

            return 0 # RATE LIMIT EXCEEDED
                if $events > $allowed;
        }

        unless ($nowrite) {
            # build the new log
            my $newlog = $RATE_DATAVER;
            foreach (@times) {
                $newlog .= pack("N", $_);
            }
            LJ::MemCache::set($key, $newlog, $max_period);
        }
    }

    return 1;
}


1;
