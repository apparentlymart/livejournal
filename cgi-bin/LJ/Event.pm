package LJ::Event;
use strict;
use Carp qw(croak);
use Class::Autouse qw(
                      LJ::ESN
                      LJ::Subscription
                      LJ::Typemap
                      LJ::Event::JournalNewEntry
                      LJ::Event::UserNewEntry
                      LJ::Event::JournalNewComment
                      LJ::Event::UserNewComment
                      LJ::Event::Befriended
                      LJ::Event::CommunityInvite
                      LJ::Event::CommunityJoinRequest
                      LJ::Event::OfficialPost
                      LJ::Event::NewUserpic
                      LJ::Event::InvitedFriendJoins
                      );

# Guide to subclasses:
#    LJ::Event::JournalNewEntry     -- a journal (user/community) has a new entry in it
#                                   ($ju,$ditemid,undef)
#    LJ::Event::UserNewEntry       -- a user posted a new entry in some journal
#                                   ($u,$journalid,$ditemid)
#    LJ::Event::JournalNewComment  -- a journal has a new comment in it
#                                   ($ju,$jtalkid)   # TODO: should probably be ($ju,$jitemid,$jtalkid)
#    LJ::Event::UserNewComment     -- a user left a new comment somewhere
#                                   ($u,$journalid,$jtalkid)
#    LJ::Event::Befriended         -- user $fromuserid added $u as a friend
#                                   ($u,$fromuserid)
#    LJ::Event::CommunityInvite    -- user $fromuserid invited $u to join $commid community)
#                                   ($u,$fromuserid, $commid)
#    LJ::Event::InvitedFriendJoins -- user $u1 was invited to join by $u2 and created a journal
#                                   ($u1, $u2)
#    LJ::Event::NewUserpic         -- user $u uploaded userpic $up
#                                   ($u,$up)

sub new {
    my ($class, $u, @args) = @_;
    croak("too many args")        if @args > 2;
    croak("args must be numeric") if grep { /\D/ } @args;
    croak("u isn't a user")       unless LJ::isu($u);

    return bless {
        u => $u,
        args => \@args,
    }, $class;
}

# Class method
sub new_from_raw_params {
    my (undef, $etypeid, $journalid, $arg1, $arg2) = @_;

    my $class = LJ::Event->class($etypeid) or die "Classname cannot be undefined/false";
    my $evt   = LJ::Event->new(LJ::load_userid($journalid),
                               $arg1, $arg2);

    # bless into correct class
    bless $evt, $class;

    return $evt;
}

sub raw_params {
    my $self = shift;
    use Data::Dumper;
    my $ju = $self->event_journal or
        Carp::confess("Event $self has no journal: " . Dumper($self));
    my @params = map { $_+0 } ($self->etypeid,
                               $ju->{userid},
                               $self->{args}[0],
                               $self->{args}[1]);
    return wantarray ? @params : \@params;
}

# Override this.  by default, events are rare, so subscriptions to
# them are tracked in target's "has_subscription" table.
# for common events, change this to '1' in subclasses and events
# will always fire without consulting the "has_subscription" table
sub is_common {
    0;
}

# Override this with HTML containing the actual event
sub content { '' }

sub as_string {
    my $self = shift;
    my $u    = $self->u;
    my ($classname) = (ref $self) =~ /Event::(.+?)$/;
    return "Event $classname fired for user=$u->{user}, args=[@{$self->{args}}]";
}

# default is just return the string, override if subclass
# actually can generate pretty content
sub as_html {
    my $self = shift;
    return $self->as_string;
}

# plaintext email subject
sub as_email_subject {
    my $self = shift;
    return $self->as_string;
}

# contents for HTML email
sub as_email_html {
    my $self = shift;
    return $self->as_html;
}

# contents for plaintext email
sub as_email_string {
    my $self = shift;
    return $self->as_string;
}

# class method, takes a subscription
sub subscription_as_html {
    my ($class, $subscr) = @_;

    croak "No subscription" unless $subscr;

    my $arg1 = $subscr->arg1;
    my $arg2 = $subscr->arg2;
    my $journalid = $subscr->journalid;

    my $user = $journalid ? LJ::ljuser(LJ::load_userid($journalid)) : "(wildcard)";

    return $class . " arg1: $arg1 arg2: $arg2 user: $user";
}

sub as_sms {
    my $self = shift;
    my $str = $self->as_string;
    return $str if length $str <= 160;
    return substr($str, 0, 157) . "...";
}

# override in subclasses
sub subscription_applicable {
    my ($class, $subscr) = @_;

    return 1;
}

############################################################################
#            Don't override
############################################################################

sub event_journal { &u; }
sub u    {  $_[0]->{u} }
sub arg1 {  $_[0]->{args}[0] }
sub arg2 {  $_[0]->{args}[1] }


# class method
sub process_fired_events {
    my $class = shift;
    croak("Can't call in web context") if LJ::is_web_context();
    LJ::ESN->process_fired_events;
}

# instance method.
# fire either logs the event to the delayed work system to be
# processed later, or does nothing, if it's a rare event and there
# are no subscriptions for the event.
sub fire {
    my $self = shift;
    my $u = $self->{u};
    return 0 if $LJ::DISABLED{'esn'};

    if (my $val = $LJ::DEBUG{'firings'}) {
        if (ref $val eq "CODE") {
            $val->($self);
        }
        warn $self->as_string . "\n";
    }

    return unless $self->should_enqueue;

    my $sclient = LJ::theschwartz();
    return 0 unless $sclient;

    my $h = $sclient->insert("LJ::Worker::FiredEvent", [ $self->raw_params ]);
    return $h ? 1 : 0;
}

sub subscriptions {
    my ($self, %args) = @_;
    my $cid   = delete $args{'cluster'};  # optional
    my $limit = delete $args{'limit'};    # optional
    croak("Unknown options: " . join(', ', keys %args)) if %args;
    croak("Can't call in web context") if LJ::is_web_context();

    # allsubs
    my @subs;

    my $allmatch = 0;
    my $zeromeans = $self->zero_journalid_subs_means;

    my @wildcards_from;
    if ($zeromeans eq 'friends') {
        # find friendofs, add to @wildcards_from
        @wildcards_from = LJ::get_friendofs($self->u);
    } elsif ($zeromeans eq 'all') {
        $allmatch = 1;
    }

    # TODO: gearman parallelize:
    foreach my $cid ($cid ? ($cid) : @LJ::CLUSTERS) {
        my $udbh = LJ::get_cluster_master($cid)
            or die;

        # first we find exact matches (or all matches)
        my $journal_match = $allmatch ? "" : "AND journalid=?";
        my $sth = $udbh->prepare
            ("SELECT userid, subid FROM subs WHERE etypeid=? $journal_match");

        my @args = $self->etypeid;
        push @args, $self->{u}->{userid} unless $allmatch;
        $sth->execute(@args);

        while (my ($uid, $subid) = $sth->fetchrow_array) {
            # TODO: convert to using new_from_row, more efficient
            push @subs, LJ::Subscription->new_by_id(LJ::load_userid($uid), $subid);
        }

        # then we find wildcard matches.
        if (@wildcards_from) {
            my $jidlist = join(",", @wildcards_from);
            my $sth = $udbh->prepare
                ("SELECT userid, subid FROM subs " .
                 "WHERE etypeid=? AND journalid=0 AND userid IN ($jidlist)");
            $sth->execute($self->etypeid);
            die $sth->errstr if $sth->err;

            while (my ($uid, $subid) = $sth->fetchrow_array) {
                # TODO: convert to using new_from_row, more efficient
                push @subs, LJ::Subscription->new_by_id(LJ::load_userid($uid), $subid);
            }
        }
    }

    return grep { $_->active } @subs;
}

# valid values are nothing ("" or undef), or "friends"
sub zero_journalid_subs_means { "friends" }

# INSTANCE METHOD: SHOULD OVERRIDE if the subscriptions support filtering
sub matches_filter {
    my ($self, $subsc) = @_;
    return 1;
}

# instance method. Override if possible.
# returns when the event happened, or undef if unknown
sub eventtime_unix {
    return undef;
}

# instance method
sub should_enqueue {
    my $self = shift;
    return 1;  # for now.
    return $self->is_common || $self->has_subscriptions;
}

# instance method
sub has_subscriptions {
    my $self = shift;
    return 1; # FIXME: consult "has_subs" table
}


# get the typemap for the subscriptions classes (class/instance method)
sub typemap {
    return LJ::Typemap->new(
        table       => 'eventtypelist',
        classfield  => 'class',
        idfield     => 'etypeid',
    );
}

# returns the class name, given an etypid
sub class {
    my ($class, $typeid) = @_;
    my $tm = $class->typemap
        or return undef;

    return $tm->typeid_to_class($typeid);
}

# returns the eventtypeid for this site.
# don't override this in subclasses.
sub etypeid {
    my ($class_self) = @_;
    my $class = ref $class_self ? ref $class_self : $class_self;

    my $tm = $class->typemap
        or return undef;

    return $tm->class_to_typeid($class);
}

# Class method
sub event_to_etypeid {
    my ($class, $evt_name) = @_;
    $evt_name = "LJ::Event::$evt_name" unless $evt_name =~ /^LJ::Event::/;
    my $tm = $class->typemap
        or return undef;
    return $tm->class_to_typeid($evt_name);
}

# this returns a list of all possible event classes
# class method
sub all_classes {
    my $class = shift;

    # return config'd classes if they exist, otherwise just return everything that has a mapping
    return @LJ::EVENT_TYPES if @LJ::EVENT_TYPES;

    croak "all_classes is a class method" unless $class;

    my $tm = $class->typemap
        or croak "Bad class $class";

    return $tm->all_classes;
}

1;
