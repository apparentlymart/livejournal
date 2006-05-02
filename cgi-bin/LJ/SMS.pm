package LJ::SMS;
use strict;
use IO::Socket::INET;
use Carp qw(croak);

sub new {
    my ($class, %opts) = @_;
    my $self = bless {}, $class;

    # smsusermap, pass in from/to as u/number
    foreach my $k (qw(from to)) {
        $self->{$k} = delete $opts{$k};
        if (LJ::isu($self->{$k})) {
            my $u = $self->{$k};
            $self->{$k} = $u->sms_number
                or croak("'$k' user has no mapped number");
        }
    }
    $self->{text} = delete $opts{text};
    die if %opts;
    return $self;
}

sub to {
    return $_[0]{to};
}

sub text {
    return $_[0]{text};
}

sub owner {
    my $self = shift;
    my $from = shift || $self->{from}
        or return undef;

    my $dbr = LJ::get_db_reader();
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
    if (my $cv = $LJ::_T_SMS_SEND) {
        $cv->($self);
        return;
    }
    if ($LJ::IS_DEV_SERVER) {
        return $self->send_jabber_dev_server;
    }

    warn "LJ::SMS->send() not implemented yet";
}

sub send_jabber_dev_server {
    my $self = shift;

    my $sock = IO::Socket::INET->new(PeerAddr => "127.0.0.1:5224")
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

# is sms sending configured?
sub configured {
    my $class = shift;

    # FIXME: once non-dev implementation, add those
    #        configuration vars here
    return $LJ::IS_DEV_SERVER ? 1 : 0;
}

sub configured_for_user {
    my $class = shift;
    my $u = shift;

    # FIXME: for now just check to see if the user has
    #        a uid -> number mapping in smsusermap
    return $class->number($u) ? 1 : 0;
}

1;
