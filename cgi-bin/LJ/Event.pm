package LJ::Event;
use strict;
use Carp qw(croak);
use Class::Autouse qw(
                      LJ::Subscription
                      LJ::Typemap
                      LJ::Event::JournalNewEntry
                      LJ::Event::UserNewEntry
                      LJ::Event::JournalNewComment
                      LJ::Event::UserNewComment
                      LJ::Event::Befriended
                      );

# Guide to subclasses:
#    LJ::Event::JournalNewEntry -- a journal (user/community) has a new entry in it
#                                  ($ju,$ditemid,undef)
#    LJ::Event::UserNewEntry    -- a user posted a new entry in some journal
#                                  ($u,$journalid,$ditemid)
#    LJ::Event::JournalNewComment -- a journal has a new comment in it
#                                  ($ju,$jtalkid)   # TODO: should probably be ($ju,$jitemid,$jtalkid)
#    LJ::Event::UserNewComment    -- a user left a new comment somewhere
#                                  ($u,$journalid,$jtalkid)
#    LJ::Event::Befriended        -- user $fromuserid added $u as a friend
#                                  ($u,$fromuserid)

# make sure all the config'd classes are mapped
if(@LJ::EVENT_TYPES) {
    my $tm = __PACKAGE__->typemap or die "Could not make typemap.";
    $tm->map_classes(@LJ::EVENT_TYPES);
}

sub new {
    my ($class, $u, @args) = @_;
    croak("too many args") if @args > 2;
    croak("args must be numeric") if grep { /\D/ } @args;

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


# Override this.  by default, events are rare, so subscriptions to
# them are tracked in target's "has_subscription" table.
# for common events, change this to '1' in subclasses and events
# will always fire without consulting the "has_subscription" table
sub is_common {
    0;
}

# Override this with a very short description of the type of event
sub title {
    return 'New Event';
}

sub as_string {
    my $self = shift;
    my $u    = $self->u;
    my ($classname) = (ref $self) =~ /Event::(.+?)$/;
    return "Event $classname fired for user=$u->{user}, args=[@{$self->{args}}]";
}

sub as_sms {
    my $self = shift;
    my $str = $self->as_string;
    return $str if length $str <= 160;
    return substr($str, 0, 157) . "...";
}

sub journal_sub_title { undef }
sub journal_sub_type  { undef }
sub arg1_sub_title    { undef }
sub arg1_sub_type     { undef }
sub arg2_sub_title    { undef }
sub arg2_sub_type     { undef }


############################################################################
#            Don't override
############################################################################

sub u    {  $_[0]->{u} }
sub arg1 {  $_[0]->{args}[0] }
sub arg2 {  $_[0]->{args}[1] }


# class method
sub process_fired_events {
    my $class = shift;

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

    # TODO: change this to log to 'TheSchwartz'
    $u->cmd_buffer_add("fired_event", {
        etypeid => $self->etypeid,
        arg1    => $self->{args}[0],
        arg2    => $self->{args}[1],
    });
}

# called outside of web context where things can go slow.
sub process_firing {
    my $self = shift;
    croak("Can't call in web context") if LJ::is_web_context();

    foreach my $subsc ($self->subscriptions) {
        next unless $self->matches($subsc);
        $subsc->process($self);
    }
}

sub subscriptions {
    my $self = shift;
    my $cid  = shift;  # optional.
    croak("Can't call in web context") if LJ::is_web_context();

    # allsubs
    my @subs;

    my $zeromeans = $self->zero_journalid_subs_means;

    my @wildcards_from;
    if ($zeromeans eq "friends") {
        # find friendofs, add to @wildcards_from
    }

    # TODO: gearman parallelize:
    foreach my $cid ($cid ? ($cid) : @LJ::CLUSTERS) {
        my $udbh = LJ::get_cluster_master($cid)
            or die;

        # first we find exact matches
        my $args = "";
        my $sth = $udbh->prepare("SELECT userid, subid FROM subs WHERE etypeid=? AND journalid=? $args");
        $sth->execute($self->etypeid, $self->u->{userid});
        while (my ($uid, $subid) = $sth->fetchrow_array) {
            # TODO: convert to using new_from_row, more efficient
            push @subs, LJ::Subscription->new_by_id(LJ::load_userid($uid), $subid);
        }

        # then we find wildcard matches.
        if (@wildcards_from) {
            my $jidlist = join(",", @wildcards_from);
            my $sth = $udbh->prepare("SELECT userid, subid FROM subs WHERE etypeid=? AND journalid IN ($jidlist) $args");

        }

    }

    return @subs;
}

# valid values are nothing ("" or undef), or "friends"
sub zero_journalid_subs_means { "friends" }

# INSTANCE METHOD: SHOULD OVERRIDE, calling SUPER::matches->() && ....
sub matches {
    my ($self, $subsc) = @_;
    return
        $self->{etypeid}   == $subsc->{etypeid} &&
        $self->{journalid} == $subsc->{journalid};   # TODO: this is wrong, because journalid of zero could mean a friend. ambye just
    # make this always return true and people can override and not call super?

    # MAYBE: rename matches_filter?  to imply we never give wrong etypeid/subid at least?  and journalid of zero DOES mean
    # it already matched a friend/etc.
}

# instance method
sub should_enqueue {
    my $self = shift;
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

package LJ::Event::ForTest2;
use base 'LJ::Event';

1;
