#!/usr/bin/perl

use strict;
use Test::More 'no_plan';
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';

use LJ::Event::Befriended;
use LJ::NotificationMethod::Email;


my $u;
my $valid_u = sub {
    $u = LJ::load_user("system");
    ok(LJ::isu($u), "valid user loaded");
    return $u;
};


# override LJ::send_mail to set $ERV
# (email return value)
my $EMAIL_RV = 1;

sub LJ::send_mail {
    my $opts = shift
        or die "No opts";

    my $email = qq {
      To: $opts->{to}
      From: $opts->{from} ($opts->{fromname})
      Subject: $opts->{subject}
      HTML Body: "$opts->{html}"
      Plaintext Body: "$opts->{body}"
      };

    my $filename = "$ENV{LJHOME}/t/temp/nm-email.txt";

    open(EMAILFILE, ">$filename")
        or die "Could not open $filename for writing";
    print EMAILFILE $email;
    close(EMAILFILE);

    # check for correct fields
    is($opts->{to}, $u->{email}, "Email address");
    is($opts->{from}, $LJ::BOGUS_EMAIL, "From address");
    like($opts->{body}, qr/the user .+ has added .+ as a friend/i, "Body");

    return $EMAIL_RV;
}

# less duplication of this so we can revalidate
my $meth;
my $valid_meth = sub {
    $meth = eval { LJ::NotificationMethod::Email->new($u) };
    ok(ref $meth && ! $@, "valid Email method instantiated");
    return $meth;
};

# constructor tests
{
    $valid_u->();
    $valid_meth->();

    $meth = eval { LJ::NotificationMethod::Email->new() };
    like($@, qr/invalid user/, "empty list passed to constructor");

    $meth = eval { LJ::NotificationMethod::Email->new() };
    like($@, qr/invalid user/, "undef passed to constructor");

    $meth = eval { LJ::NotificationMethod::Email->new() };
    like($@, qr/invalid user/, "non-user passed to constructor");

    # test valid case
    $valid_meth->();
}

# accessor/setter tests
{
    my $mu;

    $valid_u->();
    $valid_meth->();

    # now we have valid from prev test
    $mu = eval { $meth->{u} };
    is($mu, $u, "member u is constructed u");

    $mu = eval { $meth->u };
    is_deeply($mu, $u, "gotten u is constructed u");

    $mu = eval { $meth->u('foo') };
    like($@, qr/invalid 'u'/, "setting non-ref");

    $mu = eval { $meth->u($u, 'bar') };
    like($@, qr/superfluous/, "superfluous args");

    # clear out $u
    %$u = ();
    LJ::start_request();
    $mu = eval { $meth->u };
    ok(! %$u, "cleared 'u'");

    $u = LJ::load_user("system");
    ok(LJ::isu($u), "new 'u' loaded");

    $mu = eval { $meth->u($u) };
    is_deeply($mu, $u, "set new 'u' in object");
}

# notify
{
    $valid_u->();
    $valid_meth->();

    my $ev;

    my $fromu = $u; # yeah, you can friend yourself
    $ev = LJ::Event::Befriended->new($u, $fromu);
    ok(ref $ev && ! $@, "created LJ::Event::Befriended object");

    # failures
    eval { LJ::NotificationMethod::Email::notify() };
    like($@, qr/'notify'.+?object method/, "notify class method");

    eval { $meth->notify };
    like($@, qr/requires one or more/, "notify no events");

    eval { $meth->notify(undef) };
    like($@, qr/invalid event/, "notify undef event");

    eval { $meth->notify($ev, undef, $ev) };
    like($@, qr/invalid event/, "undef event with noise");

    my $str = $ev->as_string;
    $meth->notify($ev);
}
