package LJ::Event::UserNewEntry;

#
# UserNewEntry Event: Fired when a 'poster' posts 'entry' in 'journal'
#

use strict;
use Scalar::Util qw(blessed);
use Carp qw(croak);
use Class::Autouse qw(LJ::Entry);
use base 'LJ::Event';

############################################################################
# constructor & property overrides
#

sub new {
    my ($class, $entry) = @_;
    croak 'Not an LJ::Entry' unless blessed $entry && $entry->isa("LJ::Entry");
    return $class->SUPER::new($entry->poster, $entry->journalid, $entry->ditemid);
}

sub is_common { 0 }

############################################################################
# canonical accessors into the meaning of this event's arguments
#  * poster:  user object who posted
#  * journal: journal u object where entry was posted
#  * entry:   entry object which was posted (from journal, ditemid)
#

# user who posted the entry
sub poster {
    my $self = shift;
    return $self->u;
}

sub posterid {
    my $self = shift;
    return $self->u->{userid};
}

# journal entry was posted in
sub journal {
    my $self = shift;
    return LJ::load_userid($self->arg1);
}

sub journalid {
    my $self = shift;
    return $self->arg1+0;
}

# entry which was posted
sub entry {
    my $self = shift;
    return LJ::Entry->new($self->journal, ditemid => $self->ditemid);
}

sub ditemid {
    my $self = shift;
    return $self->arg2;
}

############################################################################
# subscription matching logic
#

sub matches_filter {
    my ($self, $subscr) = @_;

    # does the entry actually exist?
    return 0 unless $self->journalid && $self->ditemid; # TODO: throw error?

    # construct the entry so we can determine visibility
    my $entry = $self->entry;
    return 0 unless $entry && $entry->valid; # TODO: throw error?
    return 0 unless $entry->visible_to($subscr->owner);

    # journalid of 0 means 'all friends', so if the poster is
    # a friend of the subscription owner, then they match
    return 1 if ! $subscr->journalid && LJ::is_friend($subscr->owner, $self->poster);

    # otherwise we have a journalid, see if it's the specific
    # journal that the subscription is watching
    return LJ::u_equals($subscr->journal, $self->poster);
}


############################################################################
# methods for rendering ->as_*
#

sub as_string {
    my $self = shift;
    my $entry = $self->entry;
    my $about = $entry->subject_text ? " titled '" . $entry->subject_text . "'" : '';
    return sprintf("User '%s' made a new entry $about at: " . $self->entry->url,
                   $self->poster->{name});
}

sub as_sms {
    my ($self, $u, $opt) = @_;
    my $lang = ($u && $u->prop('browselang')) || $LJ::DEFAULT_LANG;

    my $entry = $self->entry;
    my $mlstring = ($entry->posterid == $entry->journalid)? 'notification.sms.usernewentry':'notification.sms.usernewentry_comm';
    my $tinyurl = 'http://m.livejournal.com/read/user/'
         . $entry->journal->user . '/' . $entry->ditemid . '/';
    my $mparms = $opt->{mobile_url_extra_params};
    $tinyurl .= '?' . join('&', map {$_ . '=' . $mparms->{$_}} keys %$mparms) if $mparms;
    $tinyurl = LJ::Client::BitLy->shorten($tinyurl);
    undef $tinyurl if $tinyurl =~ /^500/;
            
# User '[[user]]' posted in their journal
# User '[[user]]' posted '[[journal]]'
    return LJ::Lang::get_text($lang, '.string', undef, {
        user       => $self->poster->{user},
        journal    => $entry->journal->{user},
        mobile_url => $tinyurl,
    });    
}

# esn.user_new_entry.in_their_journal.alert=User '[[user]]' posted in their journal
# esn.user_new_entry.in_user_journal.alert=User '[[user]]' posted in '[[journal]]'
sub as_alert {
    my $self = shift;
    my $u = shift;

    my $entry = $self->entry;

    return LJ::Lang::get_text($u->prop('browselang'),
        'esn.user_new_entry.' .
            ($entry->posterid == $entry->journalid ? 'in_their_journal' : 'in_user_journal' ) .
            'alert', undef,
        {
            who     => $entry->poster->ljuser_display(),
            journal => $entry->journal->ljuser_display(),
        });
}

sub as_html {
    my $self = shift;

    my $entry = $self->entry;
    return "(Invalid entry)" unless $entry && $entry->valid;
    my $url = $entry->url;

    my $ju = LJ::ljuser($self->journal);
    my $pu = LJ::ljuser($self->poster);

    return "User $pu has posted a new <a href=\"$url\">entry</a> in $ju.";
}

sub subscription_as_html {
    my ($class, $subscr) = @_;

    # journal is the 'watched journal' of the subscription
    #  * 0 means the subscription is for posts by any friend
    my $journal = $subscr->journal;

    # non-zero journal means the subscription refers to
    # posts made by a specific user

    return $journal ?
        LJ::Lang::ml('event.user_new_entry.user', { user => $journal->ljuser_display } ) : # $journaluser posts a new entry anywhere.
        LJ::Lang::ml('event.user_new_entry.any'); # "Any of my friends posts a new entry anywhere."
}

sub available_for_user { 0 }
sub is_tracking { 1 }
sub is_subscription_visible_to { 1 }

1;
