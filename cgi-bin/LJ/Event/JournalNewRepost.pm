package LJ::Event::JournalNewRepost;

#
# JournalNewRepost Event: Fired when a 'reposter' reposts 'entry' in 'journal'
#

use strict;
use Scalar::Util qw(blessed);
use Carp qw(croak);
use Class::Autouse qw(LJ::Entry);
use base 'LJ::Event';

use LJ::Event::JournalNewEntry;

############################################################################
# constructor & property overrides
#

sub new {
    my ($class, $entry) = @_;

    croak 'Not an LJ::Entry' unless blessed $entry && $entry->isa("LJ::Entry");
    return $class->SUPER::new( $entry->poster, 
                               $entry->journalid, 
                               $entry->ditemid);
}

sub is_common { 0 }

############################################################################
# canonical accessors into the meaning of this event's arguments
#  * poster:   user object who posted entry originally
#  * journal:  journal u object where entry was posted
#  * reposter: user who reposted entry
#  * entry:    entry object which was posted (from journal, ditemid)
#

# user who posted the entry
sub poster {
    my ($self) = @_;
    my $entry  = $self->entry;

    return $entry->poster;
}

sub posterid {
    my $self = shift;

    return $self->poster->userid;
}

# journal entry was posted in
sub journal {
    my ($self) = @_;
    my $entry  = $self->entry;

    return $entry->journal;
}

sub journalid {
    my ($self) = @_;
    my $entry  = $self->entry; 

    return $entry->journalid;
}

sub reposter {
    my ($self) = @_;
    return $self->u;
}

sub reposterid {
    my ($self) = @_;

    return $self->u->userid;
}

# entry which was posted
sub entry {
    my ($self) = @_;
    my $real_entry = $self->real_entry;

    return $real_entry->original_post;
}

sub real_entry {
    my ($self) = @_;
    return LJ::Entry->new($self->reposter, ditemid => $self->real_ditemid);
}

sub real_ditemid {
    my $self = shift;
    return $self->arg2;
}

############################################################################
# subscription matching logic
#

sub matches_filter {
    my ($self, $subscr) = @_;
 
    my $ditemid = $self->arg2;
    my $evtju   = $self->event_journal;
    return 0 unless $evtju && $ditemid; # TODO: throw error?

    my $entry = LJ::Entry->new($evtju, ditemid => $ditemid);
    return 0 unless $entry && $entry->valid; # TODO: throw error?
    return 0 unless $entry->visible_to($subscr->owner);

    # all posts by friends
    return 1 if ! $subscr->journalid && LJ::is_friend($subscr->owner, $self->event_journal);

    # a post on a specific journal
    return LJ::u_equals( $subscr->journal, $evtju );
}


############################################################################
# methods for rendering ->as_*
#

sub as_string {
    my ($self, $u) = @_;

    my $lang     = ($u && $u->prop('browselang')) || $LJ::DEFAULT_LANG;
    my $entry    = $self->entry;
    my $journal  = $self->journal;

    my $about = $entry->subject_text ? "\"" . $entry->subject_text . "\"" : '';

    my $ml_string = $journal->is_community ? 'notification.string.usernewrepost_comm' : 
                                             'notification.string.usernewrepost';

    return LJ::Lang::get_text($lang, $ml_string, undef,
                        {
                            reposter      => $self->reposter->display_username,
                            community     => $self->journal->display_username,
                            about         => $about,
                            poster        => $entry->poster->display_username,
                            url           => $entry->url,
                        });
}

sub as_sms {
    my ($self, $u, $opt) = @_;
    my $lang = ($u && $u->prop('browselang')) || $LJ::DEFAULT_LANG;

    my $entry    = $self->entry;
    my $journalu = $self->journal;
    my $ml_string = $journalu->is_community ? 'notification.sms.usernewrepost_comm' : 
                                              'notification.sms.usernewrepost';

    my $tinyurl = 'http://m.livejournal.com/read/user/'
         . $entry->journal->user . '/' . $entry->ditemid . '/';

    my $mparms = $opt->{mobile_url_extra_params};
    $tinyurl .= '?' . join('&', map {$_ . '=' . $mparms->{$_}} keys %$mparms) if $mparms;
    $tinyurl = LJ::Client::BitLy->shorten($tinyurl);
    undef $tinyurl if $tinyurl =~ /^500/;
            
    return LJ::Lang::get_text($lang, $ml_string, undef, {
        reposter   => $self->poster->display_username,
        community  => $entry->journal->display_username,
        poster     => $entry->poster->display_username,
        mobile_url => $tinyurl,
    });    
}

sub as_alert {
    my ($self, $u) = @_;

    my $lang  = ($u && $u->prop('browselang')) || $LJ::DEFAULT_LANG;
    my $entry = $self->entry;

    my $journal = $self->journal;

    my $ml_string = $journal->is_community ? 'esn.user_new_repost_community.alert' : 
                                             'esn.user_new_repost.alert';

    return LJ::Lang::get_text($lang, $ml_string, undef,
        {
            reposter    => $self->reposter->ljuser_display(),
            community   => $entry->journal->ljuser_display(),
            poster      => $entry->poster->ljuser_display(),
            url         => "<a href=\"" . $entry->url . "\"/>" . $entry->url. "</a>",
        });
}

sub as_html {
    my ($self, $u) = @_;
    
    my $lang    = ($u && $u->prop('browselang')) || $LJ::DEFAULT_LANG;
    my $entry   = $self->entry;
    my $journal = $self->journal;
    return "(Invalid entry)" unless $entry && $entry->valid;
    my $url = $entry->url;

    my $ml_string = $journal->is_community ? 'esn.user_new_repost_community.ashtml' :
                                             'esn.user_new_repost.ashtml';

    my $journal  = LJ::ljuser($self->journal);
    my $poster   = LJ::ljuser($self->poster);
    my $reposter = LJ::ljuser($self->reposter);
    my $entry    = $self->entry; 

    my $about = $entry->subject_text ? "\"" . $entry->subject_text . "\"" : '';

    return LJ::Lang::get_text($lang, $ml_string, undef, 
        {
            reposter  => $reposter,
            poster    => $poster,
            community => $journal,
            about     => $about,
        }); 
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

sub content {
    my ($self, $target) = @_;
    my $entry = $self->entry;

    return undef unless $entry && $entry->valid;
    return undef unless $entry->visible_to($target);

    return $entry->event_html . $self->as_html_actions;
}


sub as_email_subject {
    my ($self, $u) = @_;
    my $lang = ($u && $u->prop('browselang')) || $LJ::DEFAULT_LANG;

    my $entry    = $self->entry;
    my $reposter = $self->reposter;
    my $poster   = $self->poster;
    my $journal  = $self->journal;

    my $ml_string = $journal->is_community ? 'esn.journal_new_repost_community.subject' :
                                             'esn.journal_new_repost.subject';

    return LJ::Lang::get_text($lang, $ml_string, undef,
        {
            reposter    => $reposter->display_username,
            poster      => $poster->display_username,
            community   => $journal->display_username,    
        });
}

sub _as_email {
    my ($self, $u, $is_html) = @_;

    my $lang  = ($u && $u->prop('browselang')) || $LJ::DEFAULT_LANG;
    my $entry = $self->entry;

    my $is_community = $entry->journal->is_community;

    my $username = $is_html ? $u->ljuser_display :
                              $u->display_username;

    my $reposter = $self->reposter;
    my $reposter_name = $is_html ? $reposter->ljuser_display :
                                   $reposter->display_username;

    my $poster_text = $self->entry->poster->display_username;
    my $poster      = $is_html ? $entry->poster->ljuser_display :
                                 $poster_text;

    my $journal_text = $self->entry->journal->display_username;
    my $journal      = $is_html ? $entry->journal->ljuser_display :
                                  $journal_text;

    my $journal_user = $self->entry->journal->user;
    my $entry_url    = $self->entry->url;
    my $journal_url  = $self->reposter->journal_base;

    my $tags = '';
    # add tag info for entries that have tags
    if ($self->entry->tags) {
        $tags = ' ' . LJ::Lang::get_text($lang, 'esn.tags', undef,
                        {
                            tags => join(', ', $self->entry->tags )
                        });
    }

    my $about = '';
    if ($self->entry->subject_text) {
        $about = LJ::Lang::get_text($lang, 'esn.journal_new_entry.about', undef,
                {
                    title => $self->entry->subject_text 
                });
    }

    my $opts = {
        poster      => $poster,
        journal     => $journal,
        username    => $username,
        is_html     => $is_html,
    };

    my $email = LJ::Lang::get_text($lang, 'esn.hi', undef, $opts);

    $email .= $is_html ? '<br /><br />' : "\n\n";
    my $ml_head_string = $is_community ? 'esn.journal_new_repost.head_comm' :
                                         'esn.journal_new_repost.head_user';

    # make hyperlinks for options
    # tags 'poster' and 'journal' cannot contain html <a> tags
    # when it used between [[openlink]] and [[closelink]] tags.
    my $vars = { poster    => $poster_text, 
                 journal   => $reposter_name,
                 community => $journal, };

    $email .= LJ::Lang::get_text($lang, $ml_head_string, undef,
                {
                    reposter    => $reposter_name,
                    poster      => $reposter_name,
                    community   => $journal,
                    url         => $entry_url,
                    tags        => $tags,
                    about       => $about,
                });

    $email .= $is_html ? '<br /><br />' : "\n\n";

    my $show_join_option = $self->entry->journal->is_comm && !LJ::is_friend($self->entry->journal, $u);

    # Some special community (e.g. writersblock) don't want join option in esn.
    $show_join_option = 0 if $show_join_option && LJ::run_hook('esn_hide_join_option_for_' . $self->entry->journal->user);
    
    # make hyperlinks for options
    # tags 'poster' and 'journal' cannot contain html <a> tags
    # when it used between [[openlink]] and [[closelink]] tags.
    my $vars = { poster    => $reposter_name,
                 reposter  => $reposter_name,
                 journal   => $journal,
                 community => $journal, };


    $email .= LJ::Lang::get_text($lang, 'esn.you_can', undef) .
        $self->format_options($is_html, $lang, $vars,
            {
                'esn.view_entry'            => [ 1, $entry_url ],
                'esn.read_recent_entries'   => [ $self->entry->journal->is_comm ? 2 : 0,
                                                    $entry->journal->journal_base ],
                'esn.join_community'        => [ $show_join_option ? 3 : 0,
                                                    "$LJ::SITEROOT/community/join.bml?comm=$journal_user" ],
                'esn.read_user_entries'     => [ 1, $journal_url ],
                'esn.add_friend_reposter'   => [ LJ::is_friend($u, $self->reposter)? 0 : 5,
                                                    "$LJ::SITEROOT/friends/add.bml?user=" . $reposter->user  ],
            });

    return $email; 
}

sub as_email_string {
    my ($self, $u) = @_;
    return $self->_as_email($u, 0);
}

sub as_email_html {
    my ($self, $u) = @_;
    return $self->_as_email($u, 1);
}

sub subscriptions {
    my ($self, %args) = @_;
   
    my $entry = $self->real_entry;
    my $event = LJ::Event::JournalNewEntry->new($entry);
    my @entry_subs = $event->subscriptions(%args);

    my @subs;
    foreach my $subsc (@entry_subs) {
        my $row = { userid      => $subsc->{'userid'},
                    journalid   => $subsc->{'journalid'},
                    ntypeid     => $subsc->{'ntypeid'},
                  };

        push @subs, LJ::Subscription->new_from_row($row);
    }

    return @subs;
}

sub available_for_user { 1 }
sub is_tracking { 0 }
sub is_subscription_visible_to { 1 }

1;
