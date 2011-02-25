# Event that is fired when there is a new post in a journal.
# sarg1 = optional tag id to filter on

package LJ::Event::JournalNewEntry;
use strict;
use Scalar::Util qw(blessed);
use Class::Autouse qw(LJ::Entry);
use Carp qw(croak);
use base 'LJ::Event';

sub new {
    my ($class, $entry) = @_;
    croak 'Not an LJ::Entry' unless blessed $entry && $entry->isa("LJ::Entry");
    return $class->SUPER::new($entry->journal, $entry->ditemid);
}

sub is_common { 1 }

sub entry {
    my $self = shift;
    return LJ::Entry->new($self->u, ditemid => $self->arg1);
}

sub matches_filter {
    my ($self, $subscr) = @_;

    my $ditemid = $self->arg1;
    my $evtju = $self->event_journal;
    return 0 unless $evtju && $ditemid; # TODO: throw error?

    my $entry = LJ::Entry->new($evtju, ditemid => $ditemid);
    return 0 unless $entry && $entry->valid; # TODO: throw error?
    return 0 unless $entry->visible_to($subscr->owner);

    # filter by tag?
    my $stagid = $subscr->arg1;
    if ($stagid) {
        my $usertaginfo = LJ::Tags::get_usertags($entry->journal, {remote => $subscr->owner});

        if ($usertaginfo) {
            my %tagmap = (); # tagname => tagid
            while (my ($tagid, $taginfo) = each %$usertaginfo) {
                $tagmap{$taginfo->{name}} = $tagid;
            }

            return 0 unless grep { $tagmap{$_} == $stagid } $entry->tags;
        }
    }

    # all posts by friends
    return 1 if ! $subscr->journalid && LJ::is_friend($subscr->owner, $self->event_journal);

    # a post on a specific journal
    return LJ::u_equals($subscr->journal, $evtju);
}

sub content {
    my ($self, $target) = @_;
    my $entry = $self->entry;

    return undef unless $entry && $entry->valid;
    return undef unless $entry->visible_to($target);

    return $entry->event_html . $self->as_html_actions;
}

sub as_string {
    my $self = shift;
    my $entry = $self->entry;
    my $about = $entry->subject_text ? ' titled "' . $entry->subject_text . '"' : '';
    my $poster = $entry->poster->user;
    my $journal = $entry->journal->user;

    return "$poster has posted a new entry$about at " . $entry->url
        if $entry->journal->is_person;

    return "$poster has posted a new entry$about in $journal at " . $entry->url;
}

sub as_sms {
    my ($self, $u) = @_;
    my $lang = ($u && $u->prop('browselang')) || $LJ::DEFAULT_LANG;
    
    my $tinyurl;
    $tinyurl = LJ::API::BitLy->shorten( "http://m.livejournal.com/read/user/" 
        . $self->entry->journal->user . '/' . $self->entry->ditemid . '/' );
    undef $tinyurl if $tinyurl =~ /^500/;

    my $mlstrng = $self->entry->journal->is_comm ? 'notification.sms.journalnewentry_comm' : 'notification.sms.journalnewentry';
# [[poster]] has posted with a new entry. To view, send READ [[journal]] to read it. [[disclaimer]]
# [[poster]] has posted with a new entry in [[journal]]. To view, send READ [[journal]] to read it. [[disclaimer]]

    return LJ::Lang::get_text($lang, $mlstrng, undef, {
        poster  => $self->entry->poster->user,
        journal => $self->entry->journal->user,
        mobile_url => $tinyurl,
    });
}

sub as_alert {
    my $self = shift;
    my $u = shift;
    my $entry_url = $self->entry->url;
    return LJ::Lang::get_text($u->prop('browselang'),
        'esn.journal_new_entry.alert', undef,
            {
                who     => $self->entry->poster->ljuser_display(),
                journal => "<a href=\"$entry_url\">" . $self->entry->journal->display_username() . "</a>",
                openlink        => '<a href="$entry_url">',
                closelink       => '</a>',
            });
}

sub as_html {
    my ($self, $target) = @_;

    croak "No target passed to as_html" unless LJ::isu($target);

    my $journal = $self->u;
    my $entry = $self->entry;

    return sprintf("(Deleted entry in %s)", $journal->ljuser_display)
        unless $entry && $entry->valid;
    return "(You are not authorized to view this entry)"
        unless $self->entry->visible_to($target);

    my $ju = LJ::ljuser($journal);
    my $pu = LJ::ljuser($entry->poster);
    my $url = $entry->url;

    my $about = $entry->subject_text ? ' titled "' . $entry->subject_text . '"' : '';
    my $where = LJ::u_equals($journal, $entry->poster) ? "$pu" : "$pu in $ju";

    return "New <a href=\"$url\">entry</a>$about by $where.";
}

sub as_html_actions {
    my ($self) = @_;

    my $entry = $self->entry;
    my $url = $entry->url;
    my $reply_url = $entry->url(mode => 'reply');

    my $ret .= "<div class='actions'>";
    $ret .= " <a href='$reply_url'>Reply</a>";
    $ret .= " <a href='$url'>Link</a>";
    $ret .= "</div>";

    return $ret;
}

my @_ml_strings_en = (
    'esn.journal_new_entry.alert',                  # '[[who]] posted a new entry in [[journal]]!',
    'esn.journal_new_entry.posted_new_entry',       # '[[who]] posted a new entry in [[journal]]!',
    'esn.journal_new_entry.updated_their_journal',  # '[[who]] updated their journal!',
    'esn.hi',                                       # 'Hi [[username]],',
    'esn.journal_new_entry.about',                  # ' titled "[[title]]"',
    'esn.tags',                                     # 'The entry is tagged "[[tags]]"',
    'esn.journal_new_entry.head_comm',              # 'There is a new entry by [[poster]][[about]] in [[journal]]![[tags]]',
    'esn.journal_new_entry.head_user',              # '[[poster]] has posted a new entry[[about]].[[tags]]',
    'esn.you_can',                                  # 'You can:',
    'esn.view_entry',                               # '[[openlink]]View the entry[[closelink]]',
    'esn.read_recent_entries',                      # '[[openlink]]Read the recent entries in [[journal]][[closelink]]',
    'esn.join_community',                           # '[[openlink]]Join [[journal]] to read Members-only entries[[closelink]]',
    'esn.read_user_entries',                        # '[[openlink]]Read [[poster]]\'s recent entries[[closelink]]',
    'esn.add_friend'                                # '[[openlink]]Add [[journal]] to your Friends list[[closelink]]',
);

sub as_email_subject {
    my ($self, $u) = @_;

    # Use special subject for some special communities
    if ($self->entry->journal->is_comm) {
        my $subject = LJ::run_hook(
            'esn_new_journal_post_subject_' . $self->entry->journal->user,
            $u, $self->entry);
        return $subject if $subject;
    }

    # Precache text lines
    my $lang = $u->prop('browselang');
    LJ::Lang::get_text_multi($lang, undef, \@_ml_strings_en);

    if ($self->entry->journal->is_comm) {
        return LJ::Lang::get_text($lang, 'esn.journal_new_entry.posted_new_entry', undef,
            {
                who     => $self->entry->poster->display_username,
                journal => $self->entry->journal->display_username,
            });
    } else {
        return LJ::Lang::get_text($lang, 'esn.journal_new_entry.updated_their_journal', undef,
            {
                who     => $self->entry->journal->display_username,
            });
    }
}

sub _as_email {
    my ($self, $u, $is_html) = @_;

    my $username = $is_html ? $u->ljuser_display : $u->display_username;

    my $poster_text = $self->entry->poster->display_username;
    my $poster      = $is_html ? $self->entry->poster->ljuser_display : $poster_text;

    # $journal - html or plaintext version depends of $is_html
    # $journal_text - text version
    # $journal_user - text version, local journal user (ext_* if OpenId).

    my $journal_text = $self->entry->journal->display_username;
    my $journal = $is_html ? $self->entry->journal->ljuser_display : $journal_text;
    my $journal_user = $self->entry->journal->user;

    my $entry_url   = $self->entry->url;
    my $journal_url = $self->entry->journal->journal_base;

    my $email;

    my $lang = $u->prop('browselang');

    # Precache text lines
    LJ::Lang::get_text_multi($lang, undef, \@_ml_strings_en);

    my $tags = '';
    # add tag info for entries that have tags
    if ($self->entry->tags) {
        $tags = ' ' . LJ::Lang::get_text($lang, 'esn.tags', undef, { tags => join(', ', $self->entry->tags ) });
    }

    my $about = $self->entry->subject_text ?
        (LJ::Lang::get_text($lang, 'esn.journal_new_entry.about', undef, { title => $self->entry->subject_text })) : '';

    my $opts = {
        poster      => $poster,
        about       => $about,
        journal     => $journal,
        tags        => $tags,
        username    => $username,
        is_html     => $is_html,
    };

    # Try to run hook for special communities
    if ($self->entry->journal->is_comm) {
        $email = LJ::run_hook(
            'esn_new_journal_post_email_' . $self->entry->journal->user,
            $u, $self->entry, $opts);
    }

    unless ($email) {
        $email = LJ::Lang::get_text($lang, 'esn.hi', undef, $opts) . "\n\n";
        $email .= LJ::Lang::get_text($lang,
            $self->entry->journal->is_comm ? 'esn.journal_new_entry.head_comm' : 'esn.journal_new_entry.head_user',
            undef,
            $opts) . "\n\n";
    }

    # make hyperlinks for options
    # tags 'poster' and 'journal' cannot contain html <a> tags
    # when it used between [[openlink]] and [[closelink]] tags.
    my $vars = { poster  => $poster_text, journal => $journal_text, };
    my $show_join_option = $self->entry->journal->is_comm && !LJ::is_friend($self->entry->journal, $u);

    # Some special community (e.g. writersblock) don't want join option in esn.
    $show_join_option = 0 if $show_join_option && LJ::run_hook('esn_hide_join_option_for_' . $self->entry->journal->user);

    $email .= LJ::Lang::get_text($lang, 'esn.you_can', undef) .
        $self->format_options($is_html, $lang, $vars,
            {
                'esn.view_entry'            => [ 1, $entry_url ],
                'esn.read_recent_entries'   => [ $self->entry->journal->is_comm ? 2 : 0,
                                                    $journal_url ],
                'esn.join_community'        => [ $show_join_option ? 3 : 0,
                                                    "$LJ::SITEROOT/community/join.bml?comm=$journal_user" ],
                'esn.read_user_entries'     => [ ($self->entry->journal->is_comm) ? 0 : 4,
                                                    $journal_url ],
                'esn.add_friend'            => [ LJ::is_friend($u, $self->entry->journal)? 0 : 5,
                                                    "$LJ::SITEROOT/friends/add.bml?user=$journal_user" ],
            });

    return $email;
}

sub as_email_string {
    my ($self, $u) = @_;
    return unless $self->entry && $self->entry->valid;

    return _as_email($self, $u, 0);
}

sub as_email_html {
    my ($self, $u) = @_;
    return unless $self->entry && $self->entry->valid;

    return _as_email($self, $u, 1);
}

# returns list of (hashref of (tagid => name))
sub unsubscribed_tags {
    my ($class, $subscr) = @_;

    my $journal = $subscr->journal;
    return () unless $journal;

    my $usertags = LJ::Tags::get_usertags($journal, {remote => $subscr->owner});
    return () unless $usertags;

    my @tagids = sort { $usertags->{$a}->{name} cmp $usertags->{$b}->{name} } keys %$usertags;
    return grep { $_ } map {
        $subscr->owner->has_subscription(
                                         etypeid => $class->etypeid,
                                         arg1    => $_,
                                         journal => $journal
                                         ) ?
                                         undef : {$_ => $usertags->{$_}->{name}};
    } @tagids;
}

sub subscription_as_html {
    my ($class, $subscr, $field_num) = @_;

    my $journal = $subscr->journal;

    # are we filtering on a tag?
    my $arg1 = $subscr->arg1;
    my $usertags;

    if ($arg1 eq '?') {
        my @unsub_tags = $class->unsubscribed_tags($subscr);
        my %tagdropdown;

        foreach my $unsub_tag (@unsub_tags) {
            while (my ($tagid, $name) = each %$unsub_tag) {
                my $group = bless({
                    'userid' => $subscr->userid,
                    'journalid' => $subscr->journalid,
                    'etypeid' => $subscr->etypeid,
                    'arg1' => $tagid,
                    'arg2' => 0,
                }, 'LJ::Subscription::Group');

                $tagdropdown{$group->freeze} = $name;
            }
        }

        my @tagdropdown =
            map { $_ => $tagdropdown{$_} }
            sort { $tagdropdown{$a} cmp $tagdropdown{$b} }
            keys %tagdropdown;

        $usertags = LJ::html_select({
            name => 'event-'.$field_num,
        }, @tagdropdown);

    } elsif ($arg1) {
        $usertags = LJ::Tags::get_usertags($journal, {remote => $subscr->owner})->{$arg1}->{'name'};
    }

    if ($arg1) {
        return LJ::Lang::ml('event.journal_new_entry.tag.' . ($journal->is_comm ? 'community' : 'user'),
                {
                    user    => $journal->ljuser_display,
                    tags    => $usertags,
                });
    }

    return LJ::Lang::ml('event.journal_new_entry.friendlist') unless $journal;

    return LJ::Lang::ml('event.journal_new_entry.' . ($journal->is_comm ? 'community' : 'user'),
            {
                user    => $journal->ljuser_display,
            });
}

sub event_as_html {
    my ($class, $group, $field_num) = @_;

    my $ret = $class->subscription_as_html($group, $field_num);
    $ret .= LJ::html_hidden('event-'.$field_num => $group->freeze)
        unless $group->arg1 eq '?';

    return $ret;
}

sub is_subscription_visible_to {
    my ($self, $u) = @_;

    if ($self->arg1 eq '?') {
        my $journal = $self->u;
        my $usertags = LJ::Tags::get_usertags($journal, { 'remote' => $u });
        my @tagids = grep {
            !$u->has_subscription(
                etypeid => $self->etypeid,
                arg1    => $_,
                journal => $journal,
            );
        } (keys %$usertags);

        return 0 unless scalar(@tagids);
    }

    return 1;
}

sub is_tracking { 1 }
sub available_for_user { 1 }

# when was this entry made?
sub eventtime_unix {
    my $self = shift;
    my $entry = $self->entry;
    return $entry ? $entry->logtime_unix : $self->SUPER::eventtime_unix;
}

sub zero_journalid_subs_means { undef }

1;
