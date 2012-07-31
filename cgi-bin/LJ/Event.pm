=comment

LJ::Event module: the "event" part of the Event-Subscription-Notification (ESN)
subsystem. See comments in LJ::ESN for information about how ESN works.

ESN Event is a "value object" in the sense that it never gets stored in the DB
(it may be passed to workers, however). Event object is essentially a structure
with the following fields:

* event type (etypeid), which can be translated to a subclass of LJ::Event;
  LJ::Typemap is used to maintain this translation.
* journal in which the event happened (userid).
* two arguments, arg1 and arg2; meaning of these arguments is determined by
  the logic of specific LJ::Event subclass.

Note that Event is not a Subscription, so it doesn't have information about
which user is supposed to receive a Notification about it. Functions that
are supposed to return information about various Event-User relationships
(e.g. "can this user subscribe to this event?") receive an LJ::User object
as one of their parameters.

LJ::Event is an abstract class, only implementing functionality common to all
event types. There is a number of LJ::Event::* subclasses which implement
event-specific functionality.

Guide to subclasses:
* JournalNewEntry    -- a journal has a new entry in it
* JoutnalNewEntry    -- a journal has a new repost in it
* JournalNewComment  -- a journal has a new comment in it
  * CommunityEntryReply -- a user's community entry has received a comment
  * CommentReply        -- someone replied to a user's comment
* Befriended         -- one user added another as a friend
* Defriended         -- one user removed another from their friends list
* CommunityInvite    -- one user invited another to a community
* InvitedFriendJoins -- a person invited to LiveJournal by a user has created a journal
* NewUserpic         -- a user uploaded a userpic
* UserExpunged       -- a user has been purged from the servers
* Birthday           -- a user has upcoming birthday
* PollVote           -- a user voted in a poll
* UserMessageRecvd   -- a user has received a message from another
* UserMessageSent    -- a user has sent a message to another

In this module, "ExampleEvent" will be used for documentation purposes only.
(And we assume that $example_etypeid is its etypeid.) It is not an actually
existing event.

Please note that there are two possible uses for LJ::Event object:

* "Fire event" -- send Schwartz a notification that the event has occured.
* As a value object -- to store information about an event or a group of events.
  These objects do not necessarily represent valid events; for example, they
  may not have the "journal" field set.

=cut

package LJ::Event;
use strict;
no warnings 'uninitialized';

use Carp qw(confess);
use LJ::ESN;
use LJ::ModuleLoader;
use LJ::Subscription;
use LJ::Typemap;
use LJ::Text;

### COMMON FUNCTIONS ###

# create a new event structure based on its type, journal and arguments
#
# my $event = LJ::Event::ExampleEvent->new($u, $arg1, $arg2);
sub new {
    my ($class, $u, @args) = @_;
    confess("too many args")        if @args > 4;

    return bless {
        userid => LJ::want_userid($u),
        args   => \@args,
        user   => $u,
    }, $class;
}

# create a new event structure based on its type, journal and arguments
# difference from "new" is that all arguments are integers: etypeid for
# determining type, and userid for journalid for determining journal.
#
# my $event =
#     LJ::Event->new_from_raw_params($example_etypeid, $u->id, $arg1, $arg2, $arg3, $arg4);
sub new_from_raw_params {
    my (undef, $etypeid, $journalid, $arg1, $arg2, $arg3, $arg4) = @_;

    my $class   = LJ::Event->class($etypeid) or confess "Classname cannot be undefined/false";
    my $journal = LJ::load_userid($journalid);
    my $evt     = LJ::Event->new($journal, $arg1, $arg2, $arg3, $arg4);

    # bless into correct class
    bless $evt, $class;

    return $evt;
}

# return an array or an arrayref of event fields: etypeid, journalid, args
#
# my ($etypeid, $journalid, $arg1, $arg2) = $event->raw_params;
#
# my $params = $event->raw_params;
# my ($etypeid, $journalid, $arg1, $arg2) = @$params;
sub raw_params {
    my $self = shift;
    use Data::Dumper;
    my $ju = $self->event_journal or
        Carp::confess("Event $self has no journal: " . Dumper($self));
    my @params = map { $_ || 0 } (
        $self->etypeid,
        $ju->id,
        @{$self->{args}},
    );
    return wantarray ? @params : \@params;
}

# "getter" methods; all of these are final.
#
# my $journal = $event->event_journal;
# my $journal = $event->u;
# my $arg1    = $event->arg1;
sub event_journal { &u; }
sub userid        { $_[0]->{userid}; }

sub u {
    my ($self) = @_;
    $self->{'u'} ||= LJ::load_userid($self->{userid});
    return $self->{'u'};
}

sub arg1 {  $_[0]->{args}[0] }
sub arg2 {  $_[0]->{args}[1] }

# alias for LJ::ESN->process_fired_events
sub process_fired_events {
    my $class = shift;
    confess("Can't call in web context") if LJ::is_web_context();
    LJ::ESN->process_fired_events;
}

# returns a scalar indicating what a journal=0 wildcard means in a subscription
# of this type.
#
# valid values are nothing ("" or undef), "all", or "friends"
#
# this is a virtual function; base class function returns "" for nothing.
#
# warn "not notifying"
#     unless $sub->journal || $event->zero_journalid_subs_means;
sub zero_journalid_subs_means { "" }

# returns a boolean value indicating whether the inbox notification for this
# event should initially come already read.
#
# this is a virtual function; base class function returns 0 for "initially
# mark unread"
#
# $inbox->mark_read($notification) if $event->mark_read;
sub mark_read {
    my $self = shift;
    return 0;
}

# return the typemap for the Events classes
#
# my $tm = LJ::Event->typemap;
# my $class = $tm->typeid_to_class($etypeid);
sub typemap {
    return LJ::Typemap->new(
        table       => 'eventtypelist',
        classfield  => 'class',
        idfield     => 'etypeid',
    );
}

my (%classes, %etypeids);

# return the class name, given an etypeid
#
# my $class = LJ::Event->class($etypeid);
sub class {
    my ($class, $typeid) = @_;

    unless ($classes{$typeid}) {
        my $tm = $class->typemap
            or return undef;

        $typeid ||= $class->etypeid;

        $classes{$typeid} = $tm->typeid_to_class($typeid);
    }

    return $classes{$typeid};
}

# return etypeid for the class
#
# my $etypeid = LJ::Event::ExampleEvent->etypeid;
sub etypeid {
    my ($class_self) = @_;
    my $class = ref $class_self ? ref $class_self : $class_self;

    unless ($etypeids{$class}) {
        my $tm = $class->typemap
            or return undef;

        $etypeids{$class} = $tm->class_to_typeid($class);
    }

    return $etypeids{$class};
}

# return etypeid for the given class
#
# my $etypeid = LJ::Event->event_to_etypeid('ExampleEvent');
# my $etypeid = LJ::Event->event_to_etypeid('LJ::Event::ExampleEvent');
sub event_to_etypeid {
    my ($class, $evt_name) = @_;

    $evt_name = "LJ::Event::$evt_name" unless $evt_name =~ /^LJ::Event::/;

    return undef
        unless $class->typemap->class_to_typeid($evt_name);

    my $tm = $class->typemap
        or return undef;
    return $tm->class_to_typeid($evt_name);
}

# return an array listing all LJ::Event subclasses
#
# my @classes = LJ::Event->all_classes;
sub all_classes {
    my $class = shift;

    # return config'd classes if they exist, otherwise just return everything that has a mapping
    return @LJ::EVENT_TYPES if @LJ::EVENT_TYPES;

    confess "all_classes is a class method" unless $class;

    my $tm = $class->typemap
        or confess "Bad class $class";

    return $tm->all_classes;
}

# return string containing nicely-represented list of links to go with
# the notification (the "now that you're receiving this notification, you
# can" one)
#
# my $lang = 'en';
# my $mlvars = {
#     'aopts' => qq{ href="$LJ::SITEROOT"; },
# };
# my $urls = {
#     # key is an ML key (and $mlvars are used to expand it), value is an
#     # arrayref
#     #
#     # the first element of that arrayref is a sort order number; passing 0
#     # there prevents the element from showing.
#     #
#     # the second element is where the link should point.
#     'esn.smile' => [ 1, $LJ::SITEROOT ],
#     'esn.facepalm' => [ 0, $LJ::SITEROOT ],
# };
# my $extra = "additional blinky text";
# my $str = LJ::Event->format_options($is_html, $lang, $mlvars, $urls, $extra);
sub format_options {
    my ($self, $is_html, $lang, $vars, $urls, $extra) = @_;

    my ($tag_p, $tag_np, $tag_li, $tag_nli, $tag_ul, $tag_nul, $tag_br) = ('','','','','','',"\n");
 
    if ($is_html) {
        $tag_p  = '<p>';    $tag_np  = '</p>';
        $tag_li = '<li>';   $tag_nli = '</li>';
        $tag_ul = '<ul>';   $tag_nul = '</ul>';
    }

    my $options = $tag_br . $tag_br . $tag_ul;

    if ($is_html) {
        $vars->{'closelink'} = '</a>';
        $options .=
            join('',
                map {
                    my $key = $_;
                    $vars->{'openlink'} = '<a href="' . $urls->{$key}->[1] . '">';
                    $tag_li . LJ::Lang::get_text($lang, $key, undef, $vars) . $tag_nli;
                    }
                    sort { $urls->{$a}->[0] <=> $urls->{$b}->[0] }
                        grep { $urls->{$_}->[0] }
                            keys %$urls);
    } else {
        $vars->{'openlink'} = '';
        $vars->{'closelink'} = '';
        $options .=
            join('',
                map {
                    my $key = $_;
                    '  - ' . LJ::Lang::get_text($lang, $key, undef, $vars) . ":\n" .
                    '    ' . $urls->{$key}->[1] . "\n"
                    }
                    sort { $urls->{$a}->[0] <=> $urls->{$b}->[0] }
                        grep { $urls->{$_}->[0] }
                            keys %$urls);
        chomp($options);
    }

    $options .= $extra if $extra;

    $options .= $tag_nul . $tag_br; 

    return $options;
}

### FIRED EVENT FUNCTIONS ###

# return a boolean value specifying whether we should notify the user
# regardless of their account state -- for example, if they are suspended.
#
# this is a virtual function; base class function returns "do not notify",
# meaning that only visible users with their emails validated are notified.
#
# return unless $u->is_visible || $event->is_significant;
sub is_significant { 0 }

# return HTML code representing the event.
#
# this is a purely virtual function; base class function returns an empty
# string.
#
# my $html = $event->content;
sub content { '' }

# return a hashref representing information returned by the getinbox protocol
# and XML-RPC method.
#
# this is a virtual function; base class function returns a hashref containing
# information about event class only.
#
# my $hashref = $event->raw_info;
# print $hashref->{'type'};
sub raw_info {
    my $self = shift;

    my $subclass = ref $self;
    $subclass =~ s/LJ::Event:?:?//;

    return { type => $subclass };
}

# return a string representing a notification sent to the passed user notifying
# them that this event has happened.
#
# this is a virtual function; base class function returns a dummy string
# listing information about the event class and its arguments. it does not
# do anything trying to parse arguments.
#
# print $event->as_string($u);
sub as_string {
    my ($self, $u) = @_;

    confess "No target passed to Event->as_string" unless LJ::isu($u);

    my ($classname) = (ref $self) =~ /Event::(.+?)$/;
    return "Event $classname fired for user=$u->{user}, args=[@{$self->{args}}]";
}

# return HTML code representing a notification sent to the passed user notifying
# them that this event has happened.
#
# this is a virtual function; base class function returns whatever "as_string"
# method returns.
#
# print $event->as_html($u);
sub as_html {
    my ($self, $u) = @_;

    confess "No target passed to Event->as_string" unless LJ::isu($u);

    return $self->as_string;
}

# return a string representing an IM (Jabber) notification sent to the passed
# user notifying them that this event has happened.
#
# this is a virtual function; base class function returns whatever "as_string"
# method returns.
#
# $ljtalk->send($u, $event->as_im($u));
sub as_im {
    my ($self, $u) = @_;
    return $self->as_string($u);
}

# return a string representing an "Alerts" (Windows Live Messenger)
# notification sent to the passed user notifying them that this event has
# happened.
#
# this is a virtual function; base class function returns whatever "as_string"
# method returns.
#
# $wlm->send($u, $event->as_alert($u));
sub as_alert {
    my ($self, $u) = @_;
    return $self->as_string($u);
}

# return a string representing an email subject of an email notification sent
# to the passed user notifying them that this event has happened.
#
# this is a virtual function; base class function returns whatever "as_string"
# method returns.
#
# my $subject = $event->as_email_subject($u);
sub as_email_subject {
    my ($self, $u) = @_;
    return $self->as_string($u);
}

# return a string representing HTML content of an email notification sent
# to the passed user notifying them that this event has happened.
#
# this is a virtual function; base class function returns whatever
# "as_email_string" method returns.
#
# my $body_html = $event->as_email_html($u);
sub as_email_html {
    my ($self, $u) = @_;
    return $self->as_email_string($u);
}

# return a string representing plain text content of an email notification sent
# to the passed user notifying them that this event has happened.
#
# this is a virtual function; base class function returns whatever
# "as_string" method returns.
#
# my $body_text = $event->as_email_string($u);
sub as_email_string {
    my ($self, $u) = @_;
    return $self->as_string($u);
}

# return a string representing the "From:" header of an email notification sent
# to the passed user notifying them that this event has happened.
#
# this is a virtual function; base class function returns $LJ::SITENAMESHORT.
#
# my $from = $event->as_email_from_name($u);
sub as_email_from_name {
    my ($self, $u) = @_;
    return $LJ::SITENAMESHORT;
}

# return a hashref representing additional headers of an email notification sent
# to the passed user notifying them that this event has happened.
#
# this is a virtual function; base class function returns undef, which means
# "no additional headers".
#
# my $headers = $event->as_email_headers($u);
# print $headers->{'Message-ID'};
sub as_email_headers {
    my ($self, $u) = @_;
    return undef;
}

# return a boolean value indicating that email notifications of this event need
# a standard footer (ml(esn.email.html.footer)) appended to them.
#
# this is a virtual function; the base class function returns 1 for "yes".
#
# if ($evt->need_standard_footer) { $html .= BML::ml('esn.email.html.footer'); }
sub need_standard_footer { 1 }

# return a boolean value indicating that email notifications of this event need
# a promo appended to them.
#
# this is a virtual function; the base class function returns 1 for "yes".
sub show_promo { 1 }

# return a string representing an "SMS" (TxtLJ) notification sent to the passed
# user notifying them that this event has happened.
#
# this is a virtual function; base class function returns whatever "as_string"
# method returns, truncated to 160 chars with an EBCDIC ellipsis ('...') added.
#
# $txtlj->send($u, $event->as_sms($u));
sub as_sms {
    my ($self, $u, $opt) = @_;
    return LJ::Text->truncate_with_ellipsis(
        'str' => $self->as_string($u, $opt),
        'bytes' => 160,
        'ellipsis' => '...',
    );
}

sub as_push { warn "method 'as_push' has to be overriden in ".ref(shift)."!"; return '' }

sub as_push_payload { warn "method 'as_push_payload' has to be overriden in ".ref(shift)."!"; return ''}



# Returns a string representing a Schwartz role [queue] used to handle this event
# By default returns undef, which is ok for most cases.
sub schwartz_role {
    my $self = shift;
    my $class = ref $self || $self;

    return $LJ::SCHWARTZ_ROLE_FOR_ESN_CLASS{$class};
}

# insert a job for TheSchwartz to process this event.
#
# $event->fire;
sub fire {
    my $self = shift;
    return 0 if $LJ::DISABLED{'esn'};

    my $sclient = LJ::theschwartz( { role => $self->schwartz_role } );
    return 0 unless $sclient;

    my $job = $self->fire_job or
        return 0;

    my $h = $sclient->insert($job);
    return $h ? 1 : 0;
}

# returns a Schwartz Job object to process this event
#
# my $job = $event->fire_job;
sub fire_job {
    my $self = shift;
    return if $LJ::DISABLED{'esn'};

    if (my $val = $LJ::DEBUG{'firings'}) {
        if (ref $val eq "CODE") {
            $val->($self);
        } else {
            warn $self->as_string . "\n";
        }
    }

    return TheSchwartz::Job->new_from_array("LJ::Worker::FiredEvent", [ $self->raw_params ]);
}

# returns an array of subscriptions that MAY match this event; it is not
# necessary for all of them to match it -- it is needed to further filter
# them to remove ones that do not match.
#
# this is a virtual function; base class function only filters by etypeid,
# journal, and flags (must be active). it doesn't filter by
# arg1/arg2, whatever these might mean in a subclss.
#
# it may be senseful to override this in a subclass to allow for additional
# subscriptions to be triggered.
#
# my @subs = $event->subscriptions(
#     'cluster' => 1,    # optional, search the subs table on the given cluster
#     'limit'   => 5000, # optional, return no more than $limit subscriptions
# );
sub subscriptions {
    my ($self, %args) = @_;
    my $cid   = delete $args{'cluster'};
    my $limit = delete $args{'limit'};
    confess("Unknown options: " . join(', ', keys %args)) if %args;
    confess("Can't call in web context") if LJ::is_web_context();

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

    my $limit_remain = $limit;

    # SQL to match only on active subs
    my $and_enabled = "AND flags & " .
        LJ::Subscription->INACTIVE . " = 0";

    # TODO: gearman parallelize:
    foreach my $cid ($cid ? ($cid) : @LJ::CLUSTERS) {
        # we got enough subs
        last if $limit && $limit_remain <= 0;

        ## hack: use inactive server of user cluster to find subscriptions
        ## LJ::DBUtil wouldn't load in web-context
        ## inactive DB may be unavailable due to backup, or on dev servers
        ## TODO: check that LJ::get_cluster_master($cid) in other parts of code
        ## will return handle to 'active' db, not cached 'inactive' db handle
        my $udbh = '';
        if (not $LJ::DISABLED{'try_to_load_subscriptions_from_slave'}){
            $udbh = eval { 
                        require 'LJ/DBUtil.pm';
                        LJ::DBUtil->get_inactive_db($cid); # connect to slave 
                    };
        }
        $udbh ||= LJ::get_cluster_master($cid); # default (master) connect

        die "Can't connect to db" unless $udbh;

        # first we find exact matches (or all matches)
        my $journal_match = $allmatch ? "" : "AND journalid=?";

        my $limit_sql = ($limit && $limit_remain) ? "LIMIT $limit_remain" : '';
        my ($extra_condition, @extra_args) = $self->extra_params_for_finding_subscriptions();
        my $sql = "SELECT userid, subid, is_dirty, journalid, etypeid, " .
            "arg1, arg2, ntypeid, createtime, expiretime, flags  " .
            "FROM subs WHERE etypeid=? $journal_match $and_enabled $extra_condition " .
            $limit_sql;

        my $sth = $udbh->prepare($sql);
        my @args = ($self->etypeid);
        push @args, $self->u->id unless $allmatch;
        push @args, @extra_args;
        $sth->execute(@args);
        if ($sth->err) {
            warn "SQL: [$sql], args=[@args]\n";
            die $sth->errstr;
        }

        while (my $row = $sth->fetchrow_hashref) {
            my $sub = LJ::Subscription->new_from_row($row);
            next unless $sub->owner->clusterid == $cid;

            push @subs, $sub;
        }

        # then we find wildcard matches.
        if (@wildcards_from) {
            # FIXME: journals are only on one cluster! split jidlist based on cluster
            my $jidlist = join(",", @wildcards_from);

            my $sth = $udbh->prepare(qq{
                SELECT
                    userid, subid, is_dirty, journalid, etypeid,
                    arg1, arg2, ntypeid, createtime, expiretime, flags
                FROM subs
                USE INDEX(PRIMARY)
                WHERE etypeid=? AND journalid=0 $and_enabled
                    AND userid IN ($jidlist)
            });

            $sth->execute($self->etypeid);
            die $sth->errstr if $sth->err;

            while (my $row = $sth->fetchrow_hashref) {
                my $sub = LJ::Subscription->new_from_row($row);
                next unless $sub->owner->clusterid == $cid;

                push @subs, $sub;
            }
        }

        $limit_remain = $limit - @subs;
    }

    return @subs;
}

sub extra_params_for_finding_subscriptions {
    return '';
}

# returns a boolean value indicating whether the given subscription matches
# the event.
#
# this is a virtual function; base class function returns 1 for "yes".
#
# my @subs = grep { $event->matches_filter($_) } @subs;
sub matches_filter {
    my ($self, $subsc) = @_;
    return 1;
}

# returns a scalar value representing the time event happened.
#
# this is a virtual function; base class function returns undef for "unknown"
#
# my $time = $event->eventtime_unix;
# print scalar(localtime($time)) if defined $time;
sub eventtime_unix {
    return undef;
}

# Returns path to template file by event type for certain language, journal
# and e-mail section.
#
# @params:  section = [subject | body_html | body_text]
#           lang    = [ en | ru | ... ]
#
# @returns: filename or undef if template could not be found.
#
sub template_file_for {
    my $self = shift;
    my %opts = @_;

    return if LJ::conf_test($LJ::DISABLED{template_files});

    my $section      = $opts{section};
    my $lang         = $opts{lang} || 'default';
    my ($event_type) = (ref $self) =~ /\:([^:]+)$/; #
    my $journal_name = $self->event_journal->user;

    # all ESN e-mail templates are located in:
    #    $LJHOME/templates/ESN/$event_type/$language/$journal_name
    #
    # go though file paths until found existing one
    foreach my $file (
        "$event_type/$lang/$journal_name/$section.tmpl",
        "$event_type/$lang/default/$section.tmpl",
        "$event_type/default/$journal_name/$section.tmpl",
        "$event_type/default/default/$section.tmpl",
    ) {
        $file = "$ENV{LJHOME}/templates/ESN/$file"; # add common prefix
        return $file if -e $file;
    }
    return undef;
}

### VALUE OBJECT FUNCTIONS ###

# return a string with HTML code representing a subscription as shown to
# the user on a settings page.
#
# this is a virtual function; base class function returns a dummy string listing
# event class, journal, and arguments.
#
# my $html = LJ::Event::ExampleEvent->subscription_as_html(bless({
#     'journalid' => $journal->id,
#     'arg1' => $arg1,
#     'arg2' => $arg2,
# }, "LJ::Subscription"));
#
# my $html = LJ::Event::ExampleEvent->subscription_as_html(bless({
#     'journalid' => $journal->id,
#     'arg1' => $arg1,
#     'arg2' => $arg2,
# }, "LJ::Subscription::Group"));
sub subscription_as_html {
    my ($class, $subscr) = @_;

    confess "No subscription" unless $subscr;

    my $arg1 = $subscr->arg1;
    my $arg2 = $subscr->arg2;
    my $journalid = $subscr->journalid;

    my $user = $journalid ? LJ::ljuser(LJ::load_userid($journalid)) : "(wildcard)";

    return $class . " arg1: $arg1 arg2: $arg2 user: $user";
}

# return a boolean value indicating whether a user is able to subscribe to
# this event and receive notifications.
#
# this is a virtual function; base class function returns true, which means
# "yes, they can".
#
# @subs = grep { $_->available_for_user($u) } @subs;
sub available_for_user  {
    my ($self, $u) = @_;

    return 1;
}

# return a boolean indicating whether the subscription for this event is a
# "tracking" one, that is, it
#
# * counts towards user's quota of subscriptions
# * shows up on the bottom of the user's subscriptions list on the main
#   settings page
#
# this is a virtual function; base class function returns 1 for "yes"
#
# next unless $event->is_tracking;
sub is_tracking { 1 }

# return a boolean indicating whether the subscription for this event may
# be shown to the user. it may still not be shown if the calling page doesn't
# want it to be shown; returning true from here prevents the subscription
# from showing for good -- when this is done, LJ::Widget::SubscribeInterface
# will never show it, regardless of what is passed to it.
#
# this is a virtual function; base class function returns 1 for "yes"
#
# next unless $event->is_subscription_visible_to($u);
sub is_subscription_visible_to { 1 }

# return a string containing HTML code with information for the user about
# what they can do to have this subscription available (e.g. upgrade account).
#
# this is a virtual function; base class function calls a "disabled_esn_sub"
# hook for the user and returns whatever it returned or an empty string.
#
# print $event->get_disabled_pic;
sub get_disabled_pic {
    my ($self, $u) = @_;

    return LJ::run_hook("disabled_esn_sub", $u) || '';
}

# return a boolean indicating whether the checkbox corresponding to the
# given notification type may be shown to the user.
#
# this is a virtual function; base class function returns 1 for "yes".
#
# $checkbox = '' unless $event->is_subscription_ntype_visible_to($ntypeid, $u);
sub is_subscription_ntype_visible_to { 1 }

# return a boolean indicating whether the checkbox corresponding to the
# given notification type must be disabled.
#
# this is a virtual function; base class function checks whether the user
# is able to subscribe to this event, and whether the notification method
# is configured for them -- if one of these conditions not met, it returns
# 0 for "no"; otherwise, it returns 1 for "yes".
#
# overriding functions in subclasses are still expected to call the parent
# class function in order to avoid duplicating these checks.
#
# $disabled = $event->is_subscription_ntype_disabled_for($ntypeid, $u);
sub is_subscription_ntype_disabled_for {
    my ($self, $ntypeid, $u) = @_;

    return 1 unless $self->available_for_user($u);

    my $nclass = LJ::NotificationMethod->class($ntypeid);
    return 1 unless $nclass->configured_for_user($u);

    return 1 unless $nclass->is_subtype_enabled($self);

    return 0;
}

# assuming that the checkbox corresponding to the given notification type
# is disabled for the user, return a boolean value whether it is checked or not.
#
# this is a virtual function; base class function returns 0 for "no".
#
# $value = $disabled ?
#     $event->get_subscription_ntype_force($ntype, $u) : 
#     $sub->is_active;
sub get_subscription_ntype_force { 0 }

# returns a hashref with the information returned from these functions:
#
# * is_subscription_visible_to (the 'visible' key)
# * !available_for_user        (the 'disabled' key)
# * get_disabled_pic           (the 'disabled_pic' key)
#
# note that this function forces the event to be invisible in case user is
# unable to subscribe to this event and is unable to upgrade to it [that is, is
# an OpenID user].
#
# my $interface_info = $event->get_interface_status($u);
sub get_interface_status {
    my ($self, $u) = @_;

    my $available = $self->available_for_user($u);

    my $visible = $self->is_subscription_visible_to($u);
    $visible &&= ($available || !$u->is_identity);

    return {
        'visible' => $visible,
        'disabled' => !$available,
        'disabled_pic' => $self->get_disabled_pic($u),
    };
}

# returns a hashref with the information returned from these functions:
#
# * is_subscription_ntype_visible_to   (the 'visible' key)
# * is_subscription_ntype_disabled_for (the 'disabled' key)
# * get_subscription_ntype_force       (the 'force' key)
#
# my $interface_info = $event->get_ntype_interface_status($u);
sub get_ntype_interface_status {
    my ($self, $ntypeid, $u) = @_;

    return {
        'visible' => $self->is_subscription_ntype_visible_to($ntypeid, $u),
        'disabled' => $self->is_subscription_ntype_disabled_for($ntypeid, $u),
        'force' => $self->get_subscription_ntype_force($ntypeid, $u),
    };
}

# initialization code. do not touch this.
my @EVENTS = LJ::ModuleLoader->module_subclasses("LJ::Event");
foreach my $event (@EVENTS) {
    eval "use $event";
    confess "Error loading event module '$event': $@" if $@;
}

sub as_email_to {
    my ($self, $u) = @_;
    return $u->email_raw;
}

sub as_email_from {
    return $LJ::BOGUS_EMAIL;
}

sub go_through_clusters {1}

sub has_frame { 0 }

1;
