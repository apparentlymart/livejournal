package DJabberd::Delivery::FakeSMS;
use strict;
use warnings;
use base 'DJabberd::Delivery';
use LWP::Simple;
use LWP::UserAgent;
use HTTP::Request::Common;

my $ua = LWP::UserAgent->new;

sub deliver {
    my ($self, $conn, $cb, $stanza) = @_;
    warn "fake sms delivery attempt.......\n";
    my $to = $stanza->to_jid                or return $cb->declined;
    return $cb->declined unless $to->node eq "sms";
    warn "fakesms delivery!\n";

    my $from = $stanza->from;
    $from =~ s/\@.+//;
    my $msg_xml = $stanza->as_xml;
    return $cb->declined unless $msg_xml =~ m!<body>(.+?)</body>!;
    my $msg = $1;

    warn "****** FROM: $from\n";
    warn "****** Message: $msg\n";

    my $res = $ua->request(POST "$LJ::SITEROOT/misc/fakesms.bml", [from => $from, message => $msg]);
    if ($res->is_success) {
        warn " ... delivered!\n";
    } else {
        warn " ... failure.\n";
    }

    $cb->delivered;
}

1;
