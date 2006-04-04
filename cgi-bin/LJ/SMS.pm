package LJ::SMS;
use strict;
use IO::Socket::INET;

sub new {
    my ($class, %opts) = @_;
    my $self = bless {}, $class;
    foreach my $k (qw(from text to)) {
        $self->{$k} = delete $opts{$k};
    }
    die if %opts;
    return $self;
}

sub owner {
    my $self = shift;
    my $dbr = LJ::get_db_reader();
    my $from = $self->{from} or
        return undef;
    my $uid = $dbr->selectrow_array("SELECT userid FROM smsusermap WHERE number=?",
                                    undef, $from);
    return $uid ? LJ::load_userid($uid) : undef;
}

sub set_to {
    my ($self, $to) = @_;
    $self->{to} = $to;
}

sub send {
    my $self = shift;
    if ($LJ::IS_DEV_SERVER) {
        return $self->send_jabber_dev_server;
    }
}

sub send_jabber_dev_server {
    my $self = shift;

    my $sock = IO::Socket::INET->new(PeerAddr => "127.0.0.1:5223")
        or return 0;

    my $to = $self->{to} . '@' . $LJ::DOMAIN;
    my $msg = $self->{text};
    my $xml = qq{<message type='chat' to='$to' from='sms\@$LJ::DOMAIN'><x xmlns='jabber:x:event'><composing/></x><body>$msg</body><html xmlns='http://jabber.org/protocol/xhtml-im'><body xmlns='http://www.w3.org/1999/xhtml'><html>$msg</html></body></html></message>};
    print $sock ("send_xml $to " . LJ::eurl($xml) . "\n");
    return 1;
}

sub as_string {
    my $self = shift;
    return "from=$self->{from}, text=$self->{text}\n";
}

1;
