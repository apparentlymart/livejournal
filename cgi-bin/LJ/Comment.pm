#
# LiveJournal comment object.
#
# Just framing right now, not much to see here!
#

package LJ::Comment;

use strict;
use Carp qw/ croak /;
use Class::Autouse qw(
                      LJ::Entry
                      );

require "$ENV{'LJHOME'}/cgi-bin/htmlcontrols.pl";
require "$ENV{'LJHOME'}/cgi-bin/talklib.pl";

# internal fields:
#
#    journalid:     journalid where the commend was
#                   posted,                          always present
#    jtalkid:       jtalkid identifying this comment
#                   within the journal_u,            always present
#
#    nodetype:      single-char nodetype identifier, loaded if _loaded_row
#    nodeid:        nodeid to which this comment
#                   applies (often an entry itemid), loaded if _loaded_row
#
#    parenttalkid:  talkid of parent comment,        loaded if _loaded_row
#    posterid:      userid of posting user           lazily loaded at access
#    datepost_unix: unixtime from the 'datepost'     loaded if _loaded_row
#    state:         comment state identifier,        loaded if _loaded_row

#    body:          text of comment,                 loaded if _loaded_text
#    body_orig:     text of comment w/o transcoding, present if unknown8bit

#    subject:       subject of comment,              loaded if _loaded_text
#    subject_orig   subject of comment w/o transcoding, present if unknown8bit

#    props:   hashref of props,                    loaded if _loaded_props

#    _loaded_text:   loaded talktext2 row
#    _loaded_row:    loaded talk2 row
#    _loaded_props:  loaded props

my %singletons = (); # journalid->jtalkid->singleton

sub reset_singletons {
    %singletons = ();
}

# <LJFUNC>
# name: LJ::Comment::new
# class: comment
# des: Gets a comment given journal_u entry and jtalkid.
# args: uuserid, opts
# des-uobj: A user id or $u to load the comment for.
# des-opts: Hash of optional keypairs.
#           jtalkid => talkid journal itemid (no anum)
# returns: A new LJ::Comment object.  undef on failure.
# </LJFUNC>
sub instance {
    my $class = shift;
    my $self  = bless {};

    my $uuserid = shift;
    my $n_arg   = scalar @_;
    croak("wrong number of arguments")
        unless $n_arg && ($n_arg % 2 == 0);

    my %opts = @_;

    $self->{journalid} = LJ::want_userid($uuserid) or
        croak("invalid journalid parameter");

    $self->{jtalkid} = int(delete $opts{jtalkid});

    if (my $dtalkid = int(delete $opts{dtalkid})) {
        $self->{jtalkid} = $dtalkid >> 8;
    }

    my $journalid = $self->{journalid};
    my $jtalkid   = $self->{jtalkid};

    # do we have a singleton for this comment?
    $singletons{$journalid} ||= {};
    return $singletons{$journalid}->{$jtalkid}
        if $singletons{$journalid}->{$jtalkid};

    # save the singleton if it doesn't exist
    $singletons{$journalid}->{$jtalkid} = $self;

    croak("need to supply jtalkid") unless $self->{jtalkid};
    croak("unknown parameters: " . join(", ", keys %opts))
        if %opts;
    return $self;
}
*new = \&instance;

sub absorb_row {
    my ($self, %row) = @_;

    $self->{$_} = $row{$_} foreach (qw(nodetype nodeid parenttalkid posterid datepost state));
    $self->{_loaded_row} = 1;
}

sub url {
    my $self    = shift;

    my $dtalkid = $self->dtalkid;
    my $entry   = $self->entry;
    my $url     = $entry->url;

    return "$url?thread=$dtalkid#t$dtalkid";
}

sub reply_url {
    my $self    = shift;

    my $dtalkid = $self->dtalkid;
    my $entry   = $self->entry;
    my $url     = $entry->url;

    return "$url?replyto=$dtalkid";
}

sub thread_url {
    my $self    = shift;

    my $dtalkid = $self->dtalkid;
    my $entry   = $self->entry;
    my $url     = $entry->url;

    return "$url?thread=$dtalkid";
}

sub unscreen_url {
    my $self    = shift;

    my $dtalkid = $self->dtalkid;
    my $entry   = $self->entry;
    my $journal = $entry->journal->{user};

    return
        "$LJ::SITEROOT/talkscreen.bml" .
        "?mode=unscreen&journal=$journal" .
        "&talkid=$dtalkid";
}

sub delete_url {
    my $self    = shift;

    my $dtalkid = $self->dtalkid;
    my $entry   = $self->entry;
    my $journal = $entry->journal->{user};

    return
        "$LJ::SITEROOT/delcomment.bml" .
        "?journal=$journal&id=$dtalkid";
}

# return LJ::User of journal comment is in
sub journal {
    my $self = shift;
    return LJ::load_userid($self->{journalid});
}

sub journalid {
    my $self = shift;
    return $self->{journalid};
}

# return LJ::Entry of entry comment is in, or undef if it's not
# a nodetype of L
sub entry {
    my $self = shift;
    __PACKAGE__->preload_rows([ $self->unloaded_singletons ]);
    return undef unless $self->{nodetype} eq "L";
    return LJ::Entry->new($self->journal, jitemid => $self->{nodeid});
}

sub jtalkid {
    my $self = shift;
    return $self->{jtalkid};
}

sub dtalkid {
    my $self = shift;
    my $entry = $self->entry;
    return ($self->jtalkid * 256) + $entry->anum;
}

sub parenttalkid {
    my $self = shift;
    __PACKAGE__->preload_rows([ $self->unloaded_singletons ]);
    return $self->{parenttalkid};
}

# returns a LJ::Comment object for the parent
sub parent {
    my $self = shift;
    my $ptalkid = $self->parenttalkid or return undef;

    return LJ::Comment->new($self->journal, jtalkid => $ptalkid);
}

# returns true if entry currently exists.  (it's possible for a given
# $u, to make a fake jitemid and that'd be a valid skeleton LJ::Entry
# object, even though that jitemid hasn't been created yet, or was
# previously deleted)
sub valid {
    my $self = shift;
    my $u = $self->journal;
    return 0 unless $u && $u->{clusterid};
    __PACKAGE__->preload_rows([ $self->unloaded_singletons ]);
    return $self->{_loaded_row};
}

# when was this comment left?
sub unixtime {
    my $self = shift;
    __PACKAGE__->preload_rows([ $self->unloaded_singletons ]);
    return LJ::mysqldate_to_time($self->{datepost}, 0);
}

# returns LJ::User object for the poster of this entry, or undef for anonymous
sub poster {
    my $self = shift;
    return LJ::load_userid($self->posterid);
}

sub posterid {
    my $self = shift;
    __PACKAGE__->preload_rows([ $self->unloaded_singletons ]);
    return $self->{posterid};
}

# returns an arrayref of unloaded comment singletons
sub unloaded_singletons {
    my $self = shift;
    my @singletons;
    push @singletons, values %{$singletons{$_}} foreach keys %singletons;
    return grep { ! $_->{_loaded_row} } @singletons;
}

# class method:
sub preload_rows {
    my ($class, $obj_list) = @_;

    my @to_load = 
        (map  { [ $_->journal, $_->jtalkid ] } 
         grep { ! $_->{_loaded_row} } @$obj_list);

    # already loaded?
    return 1 unless @to_load;

    # args: ([ journalid, jtalkid ], ...)
    my @rows = LJ::Talk::get_talk2_row_multi(@to_load);

    # make a mapping of journalid-jtalkid => $row
    my %row_map = map { join("-", $_->{journalid}, $_->{jtalkid}) => $_ } @rows;

    foreach my $obj (@$obj_list) {
        my $u = $obj->journal;

        my $row = $row_map{join("-", $u->id, $obj->jtalkid)};
        for my $f (qw(nodetype nodeid parenttalkid posterid datepost state)) {
            $obj->{$f} = $row->{$f};
        }
        $obj->{_loaded_row} = 1;
    }

    return 1;
}

# class method:
sub preload_props {
    my ($class, $entlist) = @_;
    foreach my $en (@$entlist) {
        next if $en->{_loaded_props};
        $en->_load_props;
    }
}

# returns true if loaded, zero if not.
# also sets _loaded_text and subject and event.
sub _load_text {
    my $self = shift;
    return 1 if $self->{_loaded_text};

    my $entry  = $self->entry;
    my $entryu = $entry->journal;

    my $ret  = LJ::get_talktext2($entryu, $self->jtalkid);
    my $tt = $ret->{$self->jtalkid};
    return 0 unless $tt && ref $tt;

    # raw subject and body
    $self->{subject} = $tt->[0];
    $self->{body}    = $tt->[1];

    if ($self->prop("unknown8bit")) {
        # save the old ones away, so we can get back at them if we really need to
        $self->{subject_orig} = $self->{subject};
        $self->{body_orig}    = $self->{body};

        # FIXME: really convert all the props?  what if we binary-pack some in the future?
        LJ::item_toutf8($self->journal, \$self->{subject}, \$self->{body}, $self->{props});
    }

    $self->{_loaded_text} = 1;
    return 1;
}

sub prop {
    my ($self, $prop) = @_;
    $self->_load_props unless $self->{_loaded_props};
    return $self->{props}{$prop};
}

sub props {
    my ($self, $prop) = @_;
    $self->_load_props unless $self->{_loaded_props};
    return $self->{props} || {};
}

sub _load_props {
    my $self = shift;
    return 1 if $self->{_loaded_props};

    my $props = {};
    LJ::load_talk_props2($self->{journalid}, [ $self->{jtalkid} ], $props);
    $self->{props} = $props->{ $self->{jtalkid} };

    $self->{_loaded_props} = 1;
    return 1;
}

# raw utf8 text, with no HTML cleaning
sub subject_raw {
    my $self = shift;
    $self->_load_text  unless $self->{_loaded_text};
    return $self->{subject};
}

# raw text as user sent us, without transcoding while correcting for unknown8bit
sub subject_orig {
    my $self = shift;
    $self->_load_text unless $self->{_loaded_text};
    return $self->{subject_orig} || $self->{subject};
}

# raw utf8 text, with no HTML cleaning
sub body_raw {
    my $self = shift;
    $self->_load_text unless $self->{_loaded_text};
    return $self->{body};
}

# raw text as user sent us, without transcoding while correcting for unknown8bit
sub body_orig {
    my $self = shift;
    $self->_load_text unless $self->{_loaded_text};
    return $self->{body_orig} || $self->{body};
}

# comment body, cleaned
sub body_html {
    my $self = shift;

    my $opts;
    $opts->{preformatted} = $self->prop("opt_preformatted");
    $opts->{anon_comment} = $self->poster ? 0 : 1;

    my $body = $self->body_raw;
    LJ::CleanHTML::clean_comment(\$body, $opts) if $body;
    return $body;
}

# comment body, plaintext
sub body_text {
    my $self = shift;

    my $body = $self->body_html;
    return LJ::strip_html($body);
}

sub subject_html {
    my $self = shift;
    $self->_load_text unless $self->{_loaded_text};
    return LJ::ehtml($self->{subject});
}

sub subject_text {
    my $self = shift;
    my $subject = $self->subject_raw;
    return LJ::ehtml($subject);
}

sub body_for_html_email {
    my $self = shift;
    my $u = shift;

    return _encode_for_email($u, $self->body_html);
}

sub body_for_text_email {
    my $self = shift;
    my $u = shift;

    return _encode_for_email($u, $self->body_raw);
}

sub subject_for_html_email {
    my $self = shift;
    my $u = shift;

    return _encode_for_email($u, $self->subject_html);
}

sub subject_for_text_email {
    my $self = shift;
    my $u = shift;

    return _encode_for_email($u, $self->subject_raw);
}


# Encode email strings if user has selected mail encoding
sub _encode_for_email {
    my $u = shift;
    my $string = shift;
    my $enc = $u->mailencoding;

    return $string unless $enc;
    return Unicode::MapUTF8::from_utf8({-string=>$string, -charset=>$enc});
}

sub is_active {
    my $self = shift;
    __PACKAGE__->preload_rows([ $self->unloaded_singletons] );
    return $self->{state} eq 'A' ? 1 : 0;
}

sub is_screened {
    my $self = shift;
    __PACKAGE__->preload_rows([ $self->unloaded_singletons ]);
    return $self->{state} eq 'S' ? 1 : 0;
}

sub is_deleted {
    my $self = shift;
    __PACKAGE__->preload_rows([ $self->unloaded_singletons ]);
    return $self->{state} eq 'D' ? 1 : 0;
}

sub is_frozen {
    my $self = shift;
    __PACKAGE__->preload_rows([ $self->unloaded_singletons ]);
    return $self->{state} eq 'F' ? 1 : 0;
}

sub visible_to {
    my ($self, $u) = @_;

    return 0 unless $self->entry && $self->entry->visible_to($u);

    # if screened and user doesn't own this journal
    return 0 if $self->is_screened && ! LJ::can_manage($u, $self->journal);

    # comments from suspended users aren't visible
    return 0 if $self->poster && $self->poster->{statusvis} eq 'S';

    return 1;
}

sub remote_can_delete {
    my $self = shift;

    my $remote = LJ::User->remote;
    return $self->targetu_can_delete($remote);
}

sub user_can_delete {
    my $self = shift;
    my $targetu = shift;
    return 0 unless LJ::isu($targetu);

    my $journalu = $self->journal;
    my $posteru  = $self->poster;
    my $poster   = $posteru ? $posteru->{user} : undef;

    return LJ::Talk::can_delete($targetu, $journalu, $posteru, $poster);
}

# returns comment action buttons (screen, freeze, delete, etc...)
sub manage_buttons {
    my $self = shift;
    my $dtalkid = $self->dtalkid;
    my $journal = $self->journal;
    my $jargent = "journal=$journal->{'user'}&amp;";

    my $remote = LJ::get_remote() or return '';

    my $managebtns = '';

    return '' unless $self->poster && $self->entry->poster;

    if (LJ::Talk::can_delete($remote, $self->journal, $self->entry->poster, $self->poster->{user})) {
        $managebtns .= "<a href='$LJ::SITEROOT/delcomment.bml?${jargent}id=$dtalkid'>" . LJ::img("btn_del", "", { 'align' => 'absmiddle', 'hspace' => 2, 'vspace' => }) . "</a>";
    }

    if (LJ::Talk::can_freeze($remote, $self->journal, $self->entry->poster, $self->poster->{user})) {
        unless ($self->is_frozen) {
            $managebtns .= "<a href='$LJ::SITEROOT/talkscreen.bml?mode=freeze&amp;${jargent}talkid=$dtalkid'>" . LJ::img("btn_freeze", "", { align => 'absmiddle', hspace => 2, vspace => }) . "</a>";
        } else {
            $managebtns .= "<a href='$LJ::SITEROOT/talkscreen.bml?mode=unfreeze&amp;${jargent}talkid=$dtalkid'>" . LJ::img("btn_unfreeze", "", { align => 'absmiddle', hspace => 2, vspace => }) . "</a>";
        }
    }

    if (LJ::Talk::can_screen($remote, $self->journal, $self->entry->poster, $self->poster->{user})) {
        unless ($self->is_screened) {
            $managebtns .= "<a href='$LJ::SITEROOT/talkscreen.bml?mode=screen&amp;${jargent}talkid=$dtalkid'>" . LJ::img("btn_scr", "", { 'align' => 'absmiddle', 'hspace' => 2, 'vspace' => }) . "</a>";
        } else {
            $managebtns .= "<a href='$LJ::SITEROOT/talkscreen.bml?mode=unscreen&amp;${jargent}talkid=$dtalkid'>" . LJ::img("btn_unscr", "", { 'align' => 'absmiddle', 'hspace' => 2, 'vspace' => }) . "</a>";
        }
    }

    return $managebtns;
}

# returns info for javscript comment management
sub info {
    my $self = shift;
    my $remote = LJ::get_remote() or return;

    my %LJ_cmtinfo;
    $LJ_cmtinfo{'canAdmin'} = LJ::can_manage($remote, $self->journal);
    $LJ_cmtinfo{'journal'} = $self->journal->{user};
    $LJ_cmtinfo{'remote'} = $remote->{user};

    return \%LJ_cmtinfo;
}

sub indent {
    return LJ::Talk::Post::indent(@_);
}

sub blockquote {
    return LJ::Talk::Post::blockquote(@_);
}

# used for comment email notification headers
sub email_messageid {
    my $self = shift;
    return "<" . join("-", "comment", $self->journal->id, $self->dtalkid) . "\@$LJ::DOMAIN>";
}

sub format_text_mail {
    my $self = shift;
    my $targetu = shift;
    croak "invalid targetu passed to format_text_mail"
        unless LJ::isu($targetu);

    # targetu: passed
    # comment: $self
    # parent:  $self->parent
    # talkurl: $self->url
    # item:    $self->entry

    my $parent  = $self->parent;
    my $entry   = $self->entry;
    my $posteru = $self->poster;

    $Text::Wrap::columns = 76;

    my $who = "Somebody";
    if ($posteru) {
        $who = $posteru->{name} . " (" . $posteru->{user} . ")";
    }

    my $text = "";
    if (LJ::u_equals($targetu, $self->poster)) {
        # ->parent returns undef/0 if parent is an entry.
        if (! $parent) {
            # parent is journal entry
            my $parentu = $entry->journal;

            $who = $parentu->{name} . " (" . $parentu->{user} . ")";
            $text .= "You left a comment in a post by $who.  ";
            $text .= "The entry you replied to was:";
        } else {
            $text .= "You left a comment in reply to another comment.  ";
            $text .= "The comment you replied to was:";
        }
    } elsif (LJ::u_equals($targetu, $entry->journal)) {
        # ->parent returns undef/0 if parent is an entry.
        if (! $parent) {
            $text .= "$who replied to your $LJ::SITENAMESHORT post in which you said:";
        } else {
            $text .= "$who replied to another comment somebody left in your $LJ::SITENAMESHORT post.  ";
            $text .= "The comment they replied to was:";
        }
    } else {
        if ($parent) {
            my $pwho = $parent->poster ? $parent->poster->user : "somebody else";
            $text .= "$who replied to a $LJ::SITENAMESHORT comment in which $pwho said:";
        } else {
            my $pwho = $entry->poster->user;
            $text .= "$who replied to a $LJ::SITENAMESHORT post in which $pwho said:";
        }
    }
    $text .= "\n\n";
    $text .= indent($parent ? $parent->body_for_text_email($targetu)
                            : $entry->event_for_text_email($targetu), ">") . "\n\n";
    $text .= (LJ::u_equals($targetu, $posteru) ? 'Your' : 'Their') . " reply was:\n\n";
    if (my $subj = $self->subject_for_text_email($targetu)) {
        $text .= Text::Wrap::wrap("  Subject: ", "", $subj) . "\n\n";
    }
    $text .= indent($self->body_for_text_email($targetu));
    $text .= "\n\n";

    my $can_unscreen = $self->is_screened &&
                       LJ::Talk::can_unscreen($targetu, $entry->journal, $entry->poster,
                                              $posteru ? $posteru->{user} : undef);

    if ($self->is_screened) {
        $text .= "This comment was screened.  ";
        $text .= $can_unscreen ?
                 "You must respond to it or unscreen it before others can see it.\n\n" :
                 "Someone else must unscreen it before you can reply to it.\n\n";
    }

    my $opts = "";
    $opts .= "Options:\n\n";
    $opts .= "  - View the discussion:\n";
    $opts .= "    " . $self->thread_url . "\n";
    $opts .= "  - View all comments on the entry:\n";
    $opts .= "    " . $entry->url . "\n";
    $opts .= "  - Reply to the comment:\n";
    $opts .= "    " . $self->reply_url . "\n";
    if ($can_unscreen) {
        $opts .= "  - Unscreen the comment:\n";
        $opts .= "    " . $self->unscreen_url . "\n";
    }
    if ($self->user_can_delete($targetu)) {
        $opts .= "  - Delete the comment:\n";
        $opts .= "    " . $self->delete_url . "\n";
    }

    return Text::Wrap::wrap("", "", $text) . "\n" . $opts;
}

sub format_html_mail {
    my $self = shift;
    my $targetu = shift;
    croak "invalid targetu passed to format_html_mail"
        unless LJ::isu($targetu);

    # targetu: passed
    # comment: $self
    # parent:  $self->parent
    # talkurl: $self->url
    # item:    $self->entry

    my $parent  = $self->parent;
    my $entry   = $self->entry;
    my $posteru = $self->poster;
    my $talkurl = $entry->url;

    my $who = "Somebody";
    if ($posteru) {
        my $profile_url = $posteru->profile_url;
        $who = LJ::ehtml($posteru->{name}) .
            " (<a href=\"$profile_url\">$posteru->{user}</a>)";
    }

    # find desired mail encoding for the target user
    LJ::load_codes({ "encoding" => \%LJ::CACHE_ENCODINGS } )
        unless %LJ::CACHE_ENCODINGS;

    my $encprop  = $targetu->mailencoding;
    my $encoding = $encprop ? $LJ::CACHE_ENCODINGS{$encprop} : "UTF-8";

    my $html = "";
    $html .= "<head><meta http-equiv=\"Content-Type\" content=\"text/html; charset=$encoding\" /></head>\n<body>\n";

    my $intro;
    my $parentu = $entry->journal;
    my $profile_url = $parentu->profile_url;
    my $entry_url   = $entry->url;

    my $pwho = 'you';

    if (! $parent && ! LJ::u_equals($parentu, $targetu)) {
        my $p_profile_url = $entry->poster->profile_url;
        $pwho = LJ::ehtml($entry->poster->{name}) .
            " (<a href=\"$p_profile_url\">" . $entry->poster->{user} . "</a>)";
    } elsif ($parent) {
        my $threadu = $parent->poster;
        if ($threadu && ! LJ::u_equals($threadu, $targetu)) {
            $pwho = LJ::ehtml($threadu->{name}) .
                " (<a href=\"$profile_url\">" . $threadu->{user} . "</a>)";
        }
    }

    if (LJ::u_equals($targetu, $self->poster)) {
        # ->parent returns undef/0 if parent is an entry.
        if (! $parent) {
            $who = LJ::ehtml($parentu->{name}) .
                " (<a href=\"$profile_url\">$parentu->{user}</a>)";
            $intro = "You replied to <a href=\"$talkurl\">a $LJ::SITENAMESHORT post</a> in which $pwho said:";
        } else {
            $intro = "You replied to a comment $pwho left in ";
            $intro .= "<a href=\"$talkurl\">a $LJ::SITENAMESHORT post</a>.  ";
            $intro .= "The comment you replied to was:";
        }
    } elsif (LJ::u_equals($targetu, $entry->journal)) {
        if (! $parent) {
            $intro = "$who replied to <a href=\"$talkurl\">your $LJ::SITENAMESHORT post</a> in which $pwho said:";
        } else {
            $intro = "$who replied to another comment $pwho left in ";
            $intro .= "<a href=\"$talkurl\">your $LJ::SITENAMESHORT post</a>.  ";
            $intro .= "The comment they replied to was:";
        }
    } else {
        $intro = "$who replied to <a href=\"$talkurl\">a $LJ::SITENAMESHORT " .
            ($parent ? "comment" : "post") . "</a> ";
        $intro .= "in which $pwho said:";
    }

    my $pichtml;
    my $pic_kw = $self->prop('picture_keyword');

    if ($posteru && $posteru->{defaultpicid} || $pic_kw) {
        my $pic = $pic_kw ? LJ::get_pic_from_keyword($posteru, $pic_kw) : undef;
        my $picid = $pic ? $pic->{picid} : $posteru->{defaultpicid};
        unless ($pic) {
            my %pics;
            LJ::load_userpics(\%pics, [ $posteru, $posteru->{defaultpicid} ]);
            $pic = $pics{$picid};
            # load_userpics doesn't return picid, but we rely on it above
            $picid = $picid;
        }
        if ($pic) {
            $pichtml = "<img src=\"$LJ::USERPIC_ROOT/$picid/$pic->{userid}\" align='absmiddle' ".
                "width='$pic->{width}' height='$pic->{height}' ".
                "hspace='1' vspace='2' alt='' /> ";
        }
    }

    if ($pichtml) {
        $html .= "<table><tr valign='top'><td>$pichtml</td><td width='100%'>$intro</td></tr></table>\n";
    } else {
        $html .= "<table><tr valign='top'><td width='100%'>$intro</td></tr></table>\n";
    }

    $html .= blockquote($parent ? $parent->body_for_html_email($targetu)
                                : $entry->event_for_html_email($targetu));

    $html .= "\n\n" . (LJ::u_equals($targetu, $posteru) ? 'Your' : 'Their') . " reply was:\n\n";
    my $pics = LJ::Talk::get_subjecticons();
    my $icon = LJ::Talk::show_image($pics, $self->prop('subjecticon'));

    my $heading;
    if ($self->subject_raw) {
        $heading = "<b>Subject:</b> " . $self->subject_for_html_email($targetu);
    }
    $heading .= $icon;
    $heading .= "<br />" if $heading;
    # this needs to be one string so blockquote handles it properly.
    $html .= blockquote("$heading" . $self->body_for_html_email($targetu));

    my $can_unscreen = $self->is_screened &&
                       LJ::Talk::can_unscreen($targetu, $entry->journal, $entry->poster,
                                              $posteru ? $posteru->{user} : undef);

    if ($self->is_screened) {
        $html .= "<p>This comment was screened.  ";
        $html .= $can_unscreen ?
                 "You must respond to it or unscreen it before others can see it.</p>\n" :
                 "Someone else must unscreen it before you can reply to it.</p>\n";
    }

    $html .= "<p>From here, you can:\n";
    $html .= "<ul><li><a href=\"" . $self->thread_url . "\">View the thread</a> starting from this comment</li>\n";
    $html .= "<li><a href=\"$talkurl\">View all comments</a> to this entry</li>\n";
    $html .= "<li><a href=\"" . $self->reply_url . "\">Reply</a> at the webpage</li>\n";
    if ($can_unscreen) {
        $html .= "<li><a href=\"" . $self->unscreen_url . "\">Unscreen the comment</a></li>";
    }
    if ($self->user_can_delete($targetu)) {
        $html .= "<li><a href=\"" . $self->delete_url . "\">Delete the comment</a></li>";
    }
   $html .= "</ul></p>";

    my $want_form = $self->is_active || $can_unscreen;  # this should probably be a preference, or maybe just always off.
    if ($want_form) {
        $html .= "If your mail client supports it, you can also reply here:\n";
        $html .= "<blockquote><form method='post' target='ljreply' action=\"$LJ::SITEROOT/talkpost_do.bml\">\n";

        $html .= LJ::html_hidden
            ( usertype     =>  "user",
              parenttalkid =>  $self->jtalkid,
              itemid       =>  $entry->ditemid,
              journal      =>  $entry->journal->{user},
              userpost     =>  $targetu->{user},
              ecphash      =>  LJ::Talk::ecphash($entry->jitemid, $self->jtalkid, $targetu->password)
              );

        $html .= "<input type='hidden' name='encoding' value='$encoding' />" unless $encoding eq "UTF-8";
        my $newsub = $self->subject_for_html_email($targetu);
        unless (!$newsub || $newsub =~ /^Re:/) { $newsub = "Re: $newsub"; }
        $html .= "<b>Subject: </b> <input name='subject' size='40' value=\"" . LJ::ehtml($newsub) . "\" />";
        $html .= "<p><b>Message</b><br /><textarea rows='10' cols='50' wrap='soft' name='body'></textarea>";
        $html .= "<br /><input type='submit' value=\"Post Reply\" />";
        $html .= "</form></blockquote>\n";
    }
    $html .= "</body>\n";

    return $html;
}

1;
