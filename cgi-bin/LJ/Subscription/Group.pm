package LJ::Subscription::Group;

use strict;

use Carp qw(cluck confess);

use constant GROUP_COLS => qw(userid journalid etypeid arg1 arg2);
use constant OTHER_COLS => qw(is_dirty ntypeid subid createtime expiretime flags);

my @group_cols = (GROUP_COLS);
my @other_cols = (OTHER_COLS);

sub freeze {
    my ($self) = @_;
    
    my %self = %$self;
    return join('-', map { $_ || 0 } @self{@group_cols});
}

sub thaw {
    my ($class, $frozen) = @_;

    my %self;
    @self{@group_cols} = split /-/, $frozen;

    return bless({
        %self,
        'subs' => {},
    }, $class);
}

sub group_from_sub {
    my ($class, $sub) = @_;

    my %sub = map { $_ => int $sub->{$_} } @group_cols;

    return bless({
        %sub,
        'subs' => {},
    }, $class);
}

sub insert_sub {
    my ($self, $sub) = @_;

    my $key = $sub->ntypeid;

    $self->{'subs'}->{$key} = $sub;
}

sub create_sub {
    my ($self, $ntypeid) = @_;

    my %sub = map { $_ => $self->{$_} } @group_cols;
    my $sub = bless({
        %sub,
        'ntypeid' => $ntypeid,
        'is_dirty' => 0,
        'createtime' => time,
        'expiretime' => 0,
        'flags' => 0,
    }, 'LJ::Subscription');

    return $self->insert_sub($sub);
}

sub ensure_inbox_created {
    my ($self) = @_;

    my $inbox_ntypeid = LJ::NotificationMethod::Inbox->ntypeid;
    return if $self->{'subs'}->{$inbox_ntypeid};

    my %sub = map { $_ => $self->{$_} } @group_cols;
    my $sub = bless({
        %sub,
        'ntypeid' => $inbox_ntypeid,
        'is_dirty' => 0,
        'createtime' => time,
        'expiretime' => 0,
        'flags' => LJ::Subscription::INACTIVE(),
    }, 'LJ::Subscription');

    $self->{'subs'}->{$inbox_ntypeid} = $sub;
}

sub find_sub {
    my ($self, $sub) = @_;

    my $key = $sub->ntypeid;

    return undef unless $self->{'subs'}->{$key};
    return bless($self->{'subs'}->{$key}, 'LJ::Subscription');
}

sub find_or_insert_sub {
    my ($self, $sub) = @_;

    my $key = $sub->ntypeid;

    $self->{'subs'}->{$key} = $sub unless $self->{'subs'}->{$key};
    return bless($self->{'subs'}->{$key}, 'LJ::Subscription');
}

sub find_or_insert_ntype {
    my ($self, $ntypeid) = @_;

    my %subprops = map { $_ => $self->{$_} } @group_cols;

    my $sub = bless({
        %subprops,
        'ntypeid' => $ntypeid,
        'createtime' => time,
        'expiretime' => 0,
        'flags' => LJ::Subscription::INACTIVE(),
    }, 'LJ::Subscription');

    return $self->find_or_insert_sub($sub);
}

sub custom_user_groups {
    my ($class, $u) = @_;

    
}

sub user_groups {
    my ($class, $u) = @_;

    my $group_cols = join(',', @group_cols);
    my $other_cols = join(',', @other_cols);

    $u = LJ::want_user($u);

    confess "cannot get a user" unless $u;

    my $dbr = $u->get_cluster_reader();

    confess "cannot get a database handle" unless $dbr;

    my $res = $dbr->selectall_hashref(qq{
        SELECT
            $group_cols, $other_cols
        FROM subs
        WHERE userid=?
        ORDER BY
            $group_cols
    }, Slice => {}, $u->id);

    my @ret;

    my $lastrow = undef;
    my $lastobj = undef;

    foreach my $row (@$res) {
        my $neednew = !defined $lastrow;

        unless ($neednew) {
            foreach my $col (@group_cols) {
                next if $lastrow->{$col} eq $row->{$col};

                $neednew = 1;
                last;
            }
        }

        if ($neednew) {
            my %newprops = map { $_ => $row->{$_} } @group_cols;

            $lastobj = $class->new(\%newprops);
            push @ret, $lastobj;
        }

        my %otherprops = map { $_ => $row->{$_} } @other_cols;
        $lastobj->push_ntype(\%otherprops);

        $lastrow = $row;
    }

    return \@ret;
}

sub new {
    my ($class, $props) = @_;

    confess "need a hashref here" unless ref $props eq 'HASH';

    my %newprops = map { delete $props->{$_} } @group_cols;
    $newprops{'ntypes'} = [];

    confess "unknown properties: " . join(', ', keys %$props)
        if scalar(%$props);

    return bless(\%newprops, $class);
}

sub push_ntype {
    my ($self, $props) = @_;

    confess "need a hashref here" unless ref $props eq 'HASH';

    my %newprops = map { delete $props->{$_} } @other_cols;

    confess "unknown properties: " . join(', ', keys %$props)
        if scalar(%$props);

    push @{$self->{'ntypes'}}, \%newprops;
}

# getters

sub arg1 {
    my ($self) = @_;
    return $self->{'arg1'};
}

sub arg2 {
    my ($self) = @_;
    return $self->{'arg2'};
}

sub journalid {
    my ($self) = @_;
    return $self->{'journalid'};
}

sub userid {
    my ($self) = @_;
    return $self->{'userid'};
}

sub etypeid {
    my ($self) = @_;
    return $self->{'etypeid'};
}

sub journal {
    my ($self) = @_;
    $self->{'journal'} ||= LJ::want_user($self->journalid);
    return $self->{'journal'};
}

sub owner {
    my ($self) = @_;
    return LJ::want_user($self->userid);
}

sub event_class {
    my ($self) = @_;

    my $evtclass = LJ::Event->class($self->etypeid);
    return $evtclass || undef;
}

sub as_html {
    my ($self) = @_;

    my $evtclass = $self->event_class || return undef;

    return $evtclass->subscription_as_html($self);
}

sub event_as_html {
    my ($self, $field_num) = @_;

    my $ret = '';

    my $evtclass = $self->event_class || return undef;
    if ($evtclass->can('event_as_html')) {
        return $evtclass->event_as_html($self, $field_num);
    }

    $ret .= LJ::html_hidden('event-'.$field_num => $self->freeze);
    $ret .= $self->as_html;
}

sub event {
    my ($self) = @_;

    unless ($self->{'event'}) {
        my $evt = LJ::Event->new($self->journal, $self->arg1, $self->arg2);
        bless $evt, $self->event_class;
        $self->{'event'} = $evt;
    }

    return $self->{'event'};
}

sub is_tracking {
    my ($self) = @_;

    my $evt = $self->event;

    return 0 unless $evt;
    return $evt->is_tracking($self->userid);
}

sub get_interface_status {
    my ($self, $u) = @_;

    my $evt = $self->event;

    return $evt->get_interface_status($u);
}

sub get_ntype_interface_status {
    my ($self, $ntypeid, $u) = @_;

    my $evt = $self->event;

    return $evt->get_ntype_interface_status($ntypeid, $u);
}

sub group {
    my ($self) = @_;
    return $self;
}

sub createtime {
    my ($self) = @_;

    my $inbox_ntypeid = LJ::NotificationMethod::Inbox->ntypeid;
    return $self->{'subs'}->{$inbox_ntypeid}->{'createtime'};
}

sub enabled {
    my ($self) = @_;

    my $u = LJ::want_user($self->userid);
    return $self->event->available_for_user($u);
}

sub active {
    my ($self) = @_;

    return 0 unless $self->enabled;

    my $ret = 0;
    $ret ||= $_->active foreach (values %{$self->{'subs'}});

    return $ret;
}

1;
