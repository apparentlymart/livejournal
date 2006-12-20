package LJ::M::ProfilePage;

use strict;
use warnings;

use Carp qw(croak);

sub new {
    my $class = shift;
    my $u = shift || die;
    my $self = bless {
        u => $u,
        max_friends_show => 500,
        max_friendof_show => 150,
    }, (ref $class || $class);
    $self->_init;
    return $self;
}

sub _init {
    my $self = shift;

    $self->{banned_userids} = {};
    if (my $uidlist = LJ::load_rel_user($self->{u}, 'B')) {
        $self->{banned_userids}{$_} = 1 foreach @$uidlist;
    }
}

sub max_friends_show { $_[0]{max_friends_show} }
sub max_friendof_show { $_[0]{max_friendof_show} }

sub should_hide_friendof {
    my ($self, $uid) = @_;
    return $self->{banned_userids}{$uid};
}

sub head_meta_tags {
    my $self = shift;
    my $u = $self->{u};
    my $jbase = $u->journal_base;
    my $ret;
    my $digest = Digest::SHA1::sha1_hex('mailto:' . $u->{'email'});
    $ret .= "<link rel='alternate' type='application/rss+xml' title='RSS' href='$jbase/data/rss' />\n";
    $ret .= "<link rel='alternate' type='application/atom+xml' title='Atom' href='$jbase/data/atom' />\n";
    $ret .= "<link rel='alternate' type='application/rdf+xml' title='FOAF' href='$jbase/data/foaf' />\n";
    $ret .= "<meta name=\"foaf:maker\" content=\"foaf:mbox_sha1sum '$digest'\" />\n";
    return $ret;
}

1;
