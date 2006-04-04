package DJabberd::RosterStorage::FakeSMS;
use strict;
use base 'DJabberd::RosterStorage';

sub blocking { 0 }

sub get_roster {
    my ($self, $cb, $conn, $jid) = @_;

    my $user = $jid->node;
    my $roster = DJabberd::Roster->new;

    my $ri = DJabberd::RosterItem->new(
                                       jid => "sms\@" . $LJ::DOMAIN,
                                       name => "SMS to/from $LJ::SITENAMESHORT",
                                       );
    $ri->add_group("SMS Test");
    $roster->add($ri);
    $cb->set_roster($roster);
}

1;
