package LJ::Talk;
use strict;

use Captcha::reCAPTCHA;
use Carp qw(croak);
use MIME::Words;

use LJ::Comment;
use LJ::Constants;
use LJ::Event::JournalNewComment;
use LJ::EventLogRecord::NewComment;
use LJ::OpenID;
use LJ::RateLimit qw//;
use LJ::Share;
use LJ::Talk::Author;
use LJ::TimeUtil;
use LJ::Pay::Wallet;
use LJ::GeoLocation;
use LJ::DelayedEntry;

use constant {
    PACK_FORMAT => "NNNNC",
    PACK_MULTI  => "C(NNNNC)*",
}; ## $talkid, $parenttalkid, $poster, $time, $state 

# dataversion for rate limit logging
our $RATE_DATAVER = "1";

sub get_subjecticons
{
    my %subjecticon;
    $subjecticon{'types'} = [ 'sm', 'md' ];
    $subjecticon{'lists'}->{'md'} = [
            { img => "md01_alien.gif",          w => 32,        h => 32 },
            { img => "md02_skull.gif",          w => 32,        h => 32 },
            { img => "md05_sick.gif",           w => 25,        h => 25 },
            { img => "md06_radioactive.gif",    w => 20,        h => 20 },
            { img => "md07_cool.gif",           w => 20,        h => 20 },
            { img => "md08_bulb.gif",           w => 17,        h => 23 },
            { img => "md09_thumbdown.gif",      w => 25,        h => 19 },
            { img => "md10_thumbup.gif",        w => 25,        h => 19 }
    ];
    $subjecticon{'lists'}->{'sm'} = [
            { img => "sm01_smiley.gif",         w => 15,        h => 15 },
            { img => "sm02_wink.gif",           w => 15,        h => 15 },
            { img => "sm03_blush.gif",          w => 15,        h => 15 },
            { img => "sm04_shock.gif",          w => 15,        h => 15 },
            { img => "sm05_sad.gif",            w => 15,        h => 15 },
            { img => "sm06_angry.gif",          w => 15,        h => 15 },
            { img => "sm07_check.gif",          w => 15,        h => 15 },
            { img => "sm08_star.gif",           w => 20,        h => 18 },
            { img => "sm09_mail.gif",           w => 14,        h => 10 },
            { img => "sm10_eyes.gif",           w => 24,        h => 12 }
    ];

    # assemble ->{'id'} portion of hash.  the part of the imagename before the _
    foreach (keys %{$subjecticon{'lists'}}) {
            foreach my $pic (@{$subjecticon{'lists'}->{$_}}) {
            next unless ($pic->{'img'} =~ /^(\D{2}\d{2})\_.+$/);
            $subjecticon{'pic'}->{$1} = $pic;
            $pic->{'id'} = $1;
            }
    }

    return \%subjecticon;
}

# entryid-commentid-emailrecipientpassword hash
sub ecphash {
    my ($itemid, $talkid, $password) = @_;
    return "ecph-" . Digest::MD5::md5_hex($itemid . $talkid . $password);
}

# Returns talkurl with GET args added (don't pass #anchors to this :-)
sub talkargs {
    my $talkurl = shift;
    my $args = join("&", grep {$_} @_);
    my $sep;
    $sep = ($talkurl =~ /\?/ ? "&" : "?") if $args;
    return "$talkurl$sep$args";
}

# Returns HTML to display an image, given the image id as an argument.
sub show_image
{
    my $pics = shift;
    my $id = shift;
    my $extra = shift;
    return unless defined $pics->{'pic'}->{$id};
    my $p = $pics->{'pic'}->{$id};
    my $pfx = "$LJ::IMGPREFIX/talk";
    return "<img src='$pfx/$p->{'img'}' border='0' ".
        "width='$p->{'w'}' height='$p->{'h'}' valign='middle' $extra />";
}

# Returns 'none' icon.
sub show_none_image
{
    my $extra = shift;
    my $img = 'none.gif';
    my $w = 15;
    my $h = 15;
    my $pfx = "$LJ::IMGPREFIX/talk";
    return "<img src='$pfx/$img' border='0' ".
        "width='$w' height='$h' valign='middle' $extra />";
}

sub link_bar
{
    my $opts = shift;
    my ($u, $up, $remote, $headref, $itemid) =
        map { $opts->{$_} } qw(u up remote headref itemid);
    my $ret;

    my @linkele;

    my $mlink = sub {
        my ($url, $piccode, $class) = @_;
        unless ( LJ::is_enabled('comment_controller') ) {
            return ("<a href=\"$url\">" .
                    LJ::img($piccode, "", { 'align' => 'absmiddle' }) .
                    "</a>");
        } else {
            my $title = LJ::Lang::ml('talk.'. $class);
            return sprintf
                '<a href="%s" rel="nofollow" title="%s" class="b-controls b-controls-%s"><i class="b-controls-bg"></i>%s</a>',
                $url, $title, $class, $title;
        }
    };

    my $jarg = "journal=$u->{'user'}&";
    my $jargent = "journal=$u->{'user'}&amp;";

    my $entry;
    if ($opts->{delayedid}) {
        $entry = LJ::DelayedEntry->get_entry_by_id($u, $opts->{delayedid});
    } else {
        $entry = LJ::Entry->new($u, ditemid => $itemid);
    }

    my $itemlnk = $entry->is_delayed ? "delayedid=" . $opts->{delayedid} :
                                       "itemid=$itemid";

    # << Previous
    push @linkele, $mlink->("$LJ::SITEROOT/go.bml?${jargent}$itemlnk&amp;dir=prev", "prev_entry", 'prev');
    $$headref .= "<link href='$LJ::SITEROOT/go.bml?${jargent}$itemlnk&amp;dir=prev' rel='Previous' />\n";

    # memories
    unless ($LJ::DISABLED{'memories'} || $entry->is_delayed) {
        push @linkele, $mlink->("$LJ::SITEROOT/tools/memadd.bml?${jargent}itemid=$itemid", "memadd", 'memadd');
    }

    # edit entry - if we have a remote, and that person can manage
    # the account in question, OR, they posted the entry, and have
    # access to the community in question
    if (defined $remote && ($remote && $remote->can_manage($u) ||
                            (LJ::u_equals($remote, $up) && LJ::can_use_journal($up->{userid}, $u->{user}, {}))))
    {
        if ($entry->is_delayed) {
            push @linkele, $mlink->("$LJ::SITEROOT/editjournal.bml?${jargent}delayedid=" . $entry->delayedid, "editentry", 'edit');
        } else {
            push @linkele, $mlink->("$LJ::SITEROOT/editjournal.bml?${jargent}itemid=$itemid", "editentry", 'edit');
        }
    }

    # edit tags
    unless ($LJ::DISABLED{tags}) {
        if (defined $remote && LJ::Tags::can_add_entry_tags($remote, $entry)) {
            if ($entry->is_delayed) {
                push @linkele, $mlink->("$LJ::SITEROOT/edittags.bml?${jargent}delayedid=" . $entry->delayedid, "edittags", 'edittags');
            } else {
                push @linkele, $mlink->("$LJ::SITEROOT/edittags.bml?${jargent}itemid=$itemid", "edittags", 'edittags');
            }
        }
    }

    if ( LJ::is_enabled('sharing') && $entry->is_public && !$entry->is_delayed ) {
        LJ::Share->request_resources;
        push @linkele, $mlink->( '#', 'share', 'share')
                     . LJ::Share->render_js( { 'entry' => $entry } );
    }

    if ($remote && $remote->can_use_esn && !$entry->is_delayed) {
        my $img_key = $remote->has_subscription(journal => $u, event => "JournalNewComment", arg1 => $itemid, require_active => 1) ?
            "track_active" : "track";
        push @linkele, $mlink->("$LJ::SITEROOT/manage/subscriptions/entry.bml?${jargent}itemid=$itemid", $img_key, 'track');
    }

    if (!$entry->is_delayed && $remote && $remote->can_see_content_flag_button( content => $entry )) {
        my $flag_url = LJ::ContentFlag->adult_flag_url($entry);
        push @linkele, $mlink->($flag_url, 'flag', 'flag');
    }

    ## Next
    push @linkele, $mlink->("$LJ::SITEROOT/go.bml?${jargent}$itemlnk&amp;dir=next", "next_entry", 'next');
    $$headref .= "<link href='$LJ::SITEROOT/go.bml?${jargent}$itemlnk&amp;dir=next' rel='Next' />\n";

    if ( LJ::is_enabled('comment_controller') ) {
        return \@linkele;
    }

    if (@linkele) {
        $ret .= BML::fill_template("standout", {
            'DATA' => "<table><tr><td valign='middle'>" .
                join("&nbsp;&nbsp;", @linkele) .
                "</td></tr></table>",
            });
    }

    return $ret;
}

sub init
{
    my ($form) = @_;
    my $init = {};  # structure to return

    my $journal = $form->{'journal'};
    my $ju = undef;
    my $item = undef;        # hashref; journal item conversation is in

    # defaults, to be changed later:
    $init->{'itemid'} = $form->{'itemid'}+0;
    $init->{'ditemid'} = $init->{'itemid'};
    $init->{'thread'} = $form->{'thread'}+0;
    $init->{'dthread'} = $init->{'thread'};
    $init->{'clustered'} = 0;
    $init->{'replyto'} = $form->{'replyto'}+0;
    $init->{'style'} = $form->{'style'} ? "mine" : undef;

    if ($journal) {
        # they specified a journal argument, which indicates new style.
        $ju = LJ::load_user($journal);
        return { 'error' => BML::ml('talk.error.nosuchjournal')} unless $ju;
        return { 'error' => BML::ml('talk.error.purged')} if $ju->is_expunged;

        $init->{'clustered'} = 1;
        foreach (qw(itemid replyto)) {
            next unless $init->{$_};
            $init->{'anum'} = $init->{$_} % 256;
            $init->{$_} = int($init->{$_} / 256);
            last;
        }
        $init->{'thread'} = int($init->{'thread'} / 256)
            if $init->{'thread'};
    } else {
        # perhaps it's an old URL for a user that's since been clustered.
        # look up the itemid and see what user it belongs to.
        if ($form->{'itemid'}) {
            my $itemid = $form->{'itemid'}+0;
            my $newinfo = LJ::get_newids('L', $itemid);
            if ($newinfo) {
                $ju = LJ::load_userid($newinfo->[0]);
                return { 'error' => BML::ml('talk.error.nosuchjournal')} unless $ju;
                $init->{'clustered'} = 1;
                $init->{'itemid'} = $newinfo->[1];
                $init->{'oldurl'} = 1;
                if ($form->{'thread'}) {
                    my $tinfo = LJ::get_newids('T', $init->{'thread'});
                    $init->{'thread'} = $tinfo->[1] if $tinfo;
                }
            } else {
                return { 'error' => BML::ml('talk.error.noentry') };
            }
        } elsif ($form->{'replyto'}) {
            my $replyto = $form->{'replyto'}+0;
            my $newinfo = LJ::get_newids('T', $replyto);
            if ($newinfo) {
                $ju = LJ::load_userid($newinfo->[0]);
                return { 'error' => BML::ml('talk.error.nosuchjournal')} unless $ju;
                $init->{'replyto'} = $newinfo->[1];
                $init->{'oldurl'} = 1;
            } else {
                return { 'error' => BML::ml('talk.error.noentry') };
            }
        }
    }

    $init->{'journalu'} = $ju;
    return $init;
}

# $u, $itemid
sub get_journal_item
{
    my ($u, $itemid) = @_;
    return unless $u && $itemid;

    my $uid = $u->{'userid'}+0;
    $itemid += 0;

    my $item = LJ::get_log2_row($u, $itemid);
    return undef unless $item;

    $item->{'alldatepart'} = LJ::TimeUtil->alldatepart_s2($item->{'eventtime'});

    $item->{'itemid'} = $item->{'jitemid'};    # support old & new keys
    $item->{'ownerid'} = $item->{'journalid'}; # support old & news keys

    my $lt = LJ::get_logtext2($u, $itemid);
    my $v = $lt->{$itemid};
    $item->{'subject'} = $v->[0];
    $item->{'event'} = $v->[1];

    ### load the log properties
    my %logprops = ();
    LJ::load_log_props2($u->{'userid'}, [ $itemid ], \%logprops);
    $item->{'props'} = $logprops{$itemid} || {};

    if ($LJ::UNICODE && $logprops{$itemid}->{'unknown8bit'}) {
        LJ::item_toutf8($u, \$item->{'subject'}, \$item->{'event'},
                        $item->{'logprops'}->{$itemid});
    }
    return $item;
}

sub check_viewable
{
    my ($remote, $item, $form, $errref) = @_;
    # note $form no longer used

    my $err = sub {
        $$errref = "<?h1 <?_ml Error _ml?> h1?><?p $_[0] p?>";
        return 0;
    };

    unless (LJ::can_view($remote, $item)) {
        if (defined $remote) {
             LJ::Request->pnotes ('error' => 'private');
             LJ::Request->pnotes ('remote' => LJ::get_remote());
             BML::return_error_status(403);
             return;
            return $err->(BML::ml('talk.error.notauthorised'));
        } else {
            my $redir = LJ::eurl( LJ::Request->current_page_url );
            return $err->(BML::redirect("$LJ::SITEROOT/?returnto=$redir&errmsg=notloggedin"));
        }
    }

    return 1;
}

# <LJFUNC>
# name: LJ::Talk::can_delete
# des: Determines if a user can delete a comment or entry: You can
#       delete anything you've posted.  You can delete anything posted in something
#       you own (i.e. a comment in your journal, a comment to an entry you made in
#       a community).  You can also delete any item in an account you have the
#       "A"dministration edge for.
# args: remote, u, up, userpost
# des-remote: User object we're checking access of.  From [func[LJ::get_remote]].
# des-u: Username or object of the account the thing is located in.
# des-up: Username or object of person who owns the parent of the thing.  (I.e. the poster
#           of the entry a comment is in.)
# des-userpost: Username (<strong>not</strong> object) of person who posted the item.
# returns: Boolean indicating whether remote is allowed to delete the thing
#           specified by the other options.
# </LJFUNC>
sub can_delete {
    my ($remote, $u, $up, $userpost) = @_; # remote, journal, posting user, commenting user
    return 0 unless $remote;
    return 1 if $remote->{'user'} eq $userpost ||
                $remote->{'user'} eq (ref $u ? $u->{'user'} : $u) ||
                $remote->{'user'} eq (ref $up ? $up->{'user'} : $up) ||
                $remote->can_manage($u) ||
                $remote->can_sweep($u);
    return 0;
}

sub can_screen {
    my ($remote, $u, $up, $userpost) = @_;
    return 0 unless $remote;
    return 1 if $remote->{'user'} eq $u->{'user'} ||
                $remote->{'user'} eq (ref $up ? $up->{'user'} : $up) ||
                $remote->can_manage($u) || $remote->can_moderate($u) || $remote->can_sweep($u);
    return 0;
}

sub can_unscreen {
    my ($remote, $u, $up, $userpost) = @_;
    return 0 unless $remote;
    return 0 if !($remote->can_manage($u) || $remote->can_moderate($u)) && $remote->can_moderate($u);
    return 1 if $remote->can_sweep($u);
    return LJ::Talk::can_screen($remote, $u, $up, $userpost);
}

sub can_view_screened {
    my ($remote, $u, $up, $userpost) = @_;
    return 0 unless $remote;
    return 0 if $remote->can_moderate($u) and not $remote->can_manage($u);
    return 1 if $remote->can_sweep($u);
    return LJ::Talk::can_delete($remote, $u, $up, $userpost);
}

sub can_freeze {
    my ($remote, $u, $up, $userpost) = @_;
    return LJ::Talk::can_screen($remote, $u, $up, $userpost);
}

sub can_unfreeze {
    my ($remote, $u, $up, $userpost) = @_;
    return 0 unless $remote;
    return 1 if $remote->can_moderate($u);
    return LJ::Talk::can_unscreen($remote, $u, $up, $userpost);
}

sub can_mark_spam {
    my ($remote, $u, $up, $userpost) = @_;
    return 0 if $LJ::DISABLED{'spam_button'};
    return 0 unless $remote;
    return 1 if $remote->{'user'} eq (ref $up ? $up->{'user'} : $up);
    return $remote->can_manage($u);
}

sub can_unmark_spam {
    my ($remote, $u, $up, $userpost) = @_;
    return 0 if $LJ::DISABLED{'spam_button'};
    return 0 unless $remote;
    return 1 if $remote->can_moderate($u);
    return LJ::Talk::can_mark_spam($remote, $u, $up, $userpost);
}

sub can_marked_as_spam {
    my ($remote, $u, $up, $userpost) = @_;
    return 0 if $LJ::DISABLED{'spam_button'};
    return 0 unless $remote;    ## Viewer is anonymous
    if ($userpost) {
        my $comment_owner = LJ::load_user(ref($userpost) ? $userpost->{'user'} : $userpost);
        return 0 if $comment_owner && $remote->{'user'} eq $comment_owner->{'user'}; ## Remote user is owner of this comment
        return 0 if $comment_owner && LJ::Talk::can_unmark_spam($comment_owner, $u); ## Poster is a maintainer too
    }
    return LJ::Talk::can_mark_spam($remote, $u, $up);
}

# <LJFUNC>
# name: LJ::Talk::screening_level
# des: Determines the screening level of a particular post given the relevant information.
# args: journalu, jitemid
# des-journalu: User object of the journal the post is in.
# des-jitemid: Itemid of the post.
# returns: Single character that indicates the screening level.  Undef means don't screen
#          anything, 'A' means screen All, 'R' means screen Anonymous (no-remotes), 'F' means
#          screen non-friends.
# </LJFUNC>
sub screening_level {
    my ($journalu, $jitemid) = @_;
    die 'LJ::screening_level needs a user object.' unless ref $journalu;
    $jitemid += 0;
    die 'LJ::screening_level passed invalid jitemid.' unless $jitemid;

    # load the logprops for this entry
    my %props;
    LJ::load_log_props2($journalu->{userid}, [ $jitemid ], \%props);

    # determine if userprop was overriden
    my $val = $props{$jitemid}{opt_screening};
    return if $val eq 'N'; # N means None, so return undef
    return $val if $val;

    # now return userprop, as it's our last chance
    LJ::load_user_props($journalu, 'opt_whoscreened');
    return if $journalu->{opt_whoscreened} eq 'N';
    $journalu->{opt_whoscreened} = 'R' 
        if $journalu->{opt_whoscreened} eq 'L';
    return $journalu->{opt_whoscreened} || 'R';
}

sub update_commentalter {
    my ($u, $itemid) = @_;
    LJ::set_logprop($u, $itemid, { 'commentalter' => time() });
}

sub update_journals_commentalter {
    my $u = shift;

    # journal data consists of two types: posts and comments.
    # last post time is stored in 'userusage' table.
    # last comment add/update/delete/whateverchange time - here:
    $u->set_prop("comment_alter_time", time());
}

# <LJFUNC>
# name: LJ::Talk::get_comments_in_thread
# class: web
# des: Gets a list of comment ids that are contained within a thread, including the
#      comment at the top of the thread.  You can also limit this to only return comments
#      of a certain state.
# args: u, jitemid, jtalkid, onlystate, screenedref
# des-u: user object of user to get comments from
# des-jitemid: journal itemid to get comments from
# des-jtalkid: journal talkid of comment to use as top of tree
# des-onlystate: if specified, return only comments of this state (e.g. A, F, S...)
# des-screenedref: if provided and an array reference, will push on a list of comment
#                   ids that are being returned and are screened (mostly for use in deletion so you can
#                   unscreen the comments)
# returns: undef on error, array reference of jtalkids on success
# </LJFUNC>
sub get_comments_in_thread {
    my ($u, $jitemid, $jtalkid, $onlystate, $screened_ref) = @_;
    $u = LJ::want_user($u);
    $jitemid += 0;
    $jtalkid += 0;
    $onlystate = uc $onlystate;
    return undef unless $u && $jitemid && $jtalkid &&
                        (!$onlystate || $onlystate =~ /^\w$/);

    # get all comments to post
    my $comments = LJ::Talk::get_talk_data($u, 'L', $jitemid) || {};

    # see if our comment exists
    return undef unless $comments->{$jtalkid};

    # create relationship hashref and count screened comments in post
    my %parentids;
    $parentids{$_} = $comments->{$_}{parenttalkid} foreach keys %$comments;

    # now walk and find what to update
    my %to_act;
    foreach my $id (keys %$comments) {
        my $act = ($id == $jtalkid);
        my $walk = $id;
        while ($parentids{$walk}) {
            if ($parentids{$walk} == $jtalkid) {
                # we hit the one we want to act on
                $act = 1;
                last;
            }
            last if $parentids{$walk} == $walk;

            # no match, so move up a level
            $walk = $parentids{$walk};
        }

        # set it as being acted on
        $to_act{$id} = 1 if $act && (!$onlystate || $comments->{$id}{state} eq $onlystate);

        # push it onto the list of screened comments? (if the caller is doing a delete, they need
        # a list of screened comments in order to unscreen them)
        push @$screened_ref, $id if ref $screened_ref &&             # if they gave us a ref
                                    $to_act{$id} &&                  # and we're acting on this comment
                                    $comments->{$id}{state} eq 'S';  # and this is a screened comment
    }

    # return list from %to_act
    return [ keys %to_act ];
}

# <LJFUNC>
# name: LJ::Talk::delete_thread
# class: web
# des: Deletes an entire thread of comments.
# args: u, jitemid, jtalkid
# des-u: Userid or user object to delete thread from.
# des-jitemid: Journal itemid of item to delete comments from.
# des-jtalkid: Journal talkid of comment at top of thread to delete.
# returns: 1 on success; undef on error
# </LJFUNC>
sub delete_thread {
    my ($u, $jitemid, $jtalkid) = @_;

    # get comments and delete 'em
    my @screened;
    my $ids = LJ::Talk::get_comments_in_thread($u, $jitemid, $jtalkid, undef, \@screened);
    LJ::Talk::unscreen_comment($u, $jitemid, @screened) if @screened; # if needed only!
    my ($num, $numspam) = LJ::delete_comments($u, "L", $jitemid, @$ids);
    LJ::replycount_do($u, $jitemid, "decr", $num);
    LJ::replyspamcount_do($u, $jitemid, "decr", $numspam);
    LJ::Talk::update_commentalter($u, $jitemid);
    LJ::Talk::update_journals_commentalter($u);
    return 1;
}

# <LJFUNC>
# name: LJ::Talk::delete_author
# class: web
# des: Deletes all comments of one author for one entry.
# args: u, jitemid, posterid
# des-u: Userid or user object to delete thread from.
# des-jitemid: Journal itemid of item to delete comments from.
# des-posterid: Userid of author.
# returns: 1 on success; undef on error
# </LJFUNC>
sub delete_author {
    my ($u, $jitemid, $posterid) = @_;

    # get all comments to post
    my $comments = LJ::Talk::get_talk_data($u, 'L', $jitemid) || {};

    my @screened;
    my @ids;
    foreach my $id (keys %$comments) {
        next unless $comments->{$id}{posterid} eq $posterid;
        next if $comments->{$id}{state} eq 'D';
        push @ids, $id;
        push @screened, $id if $comments->{$id}{state} eq 'S';
    }

    LJ::Talk::unscreen_comment($u, $jitemid, @screened) if @screened; # if needed only!
    my ($num, $numspam) = LJ::delete_comments($u, "L", $jitemid, @ids);
    LJ::replycount_do($u, $jitemid, "decr", $num);
    LJ::replyspamcount_do($u, $jitemid, "decr", $numspam);
    LJ::Talk::update_commentalter($u, $jitemid);
    LJ::Talk::update_journals_commentalter($u);
    return 1;
}

# <LJFUNC>
# name: LJ::Talk::delete_comment
# class: web
# des: Deletes a single comment.
# args: u, jitemid, jtalkid, state?
# des-u: Userid or user object to delete comment from.
# des-jitemid: Journal itemid of item to delete comment from.
# des-jtalkid: Journal talkid of the comment to delete.
# des-state: Optional. If you know it, provide the state
#            of the comment being deleted, else we load it.
# returns: 1 on success; undef on error
# </LJFUNC>
sub delete_comment {
    my ($u, $jitemid, $jtalkid, $state) = @_;
    return undef unless $u && $jitemid && $jtalkid;

    unless ($state) {
        my $td = LJ::Talk::get_talk_data($u, 'L', $jitemid);
        return undef unless $td;

        $state = $td->{$jtalkid}->{state};
    }
    return undef unless $state;

    # if it's screened, unscreen it first to properly adjust logprops
    LJ::Talk::unscreen_comment($u, $jitemid, $jtalkid)
        if $state eq 'S';

    # now do the deletion
    my ($num, $numspam) = LJ::delete_comments($u, "L", $jitemid, $jtalkid);
    LJ::replycount_do($u, $jitemid, "decr", $num);
    LJ::replyspamcount_do($u, $jitemid, "decr", $numspam);
    LJ::Talk::update_commentalter($u, $jitemid);
    LJ::Talk::update_journals_commentalter($u);

    # done
    return 1;
}

# <LJFUNC>
# name: LJ::Talk::freeze_thread
# class: web
# des: Freezes an entire thread of comments.
# args: u, jitemid, jtalkid
# des-u: Userid or user object to freeze thread from.
# des-jitemid: Journal itemid of item to freeze comments from.
# des-jtalkid: Journal talkid of comment at top of thread to freeze.
# returns: 1 on success; undef on error
# </LJFUNC>
sub freeze_thread {
    my ($u, $jitemid, $jtalkid) = @_;

    # now we need to update the states
    my $ids = LJ::Talk::get_comments_in_thread($u, $jitemid, $jtalkid, 'A');
    LJ::Talk::freeze_comments($u, "L", $jitemid, 0, $ids);
    return 1;
}

# <LJFUNC>
# name: LJ::Talk::unfreeze_thread
# class: web
# des: unfreezes an entire thread of comments.
# args: u, jitemid, jtalkid
# des-u: Userid or user object to unfreeze thread from.
# des-jitemid: Journal itemid of item to unfreeze comments from.
# des-jtalkid: Journal talkid of comment at top of thread to unfreeze.
# returns: 1 on success; undef on error
# </LJFUNC>
sub unfreeze_thread {
    my ($u, $jitemid, $jtalkid) = @_;

    # now we need to update the states
    my $ids = LJ::Talk::get_comments_in_thread($u, $jitemid, $jtalkid, 'F');
    LJ::Talk::freeze_comments($u, "L", $jitemid, 1, $ids);
    return 1;
}

# <LJFUNC>
# name: LJ::Talk::freeze_comments
# class: web
# des: Freezes comments.  This is the internal helper function called by
#      freeze_thread/unfreeze_thread.  Use those if you wish to freeze or
#      unfreeze a thread.  This function just freezes specific comments.
# args: u, nodetype, nodeid, unfreeze, ids
# des-u: Userid or object of user to manipulate comments in.
# des-nodetype: Nodetype of the thing containing the specified ids.  Typically "L".
# des-nodeid: Id of the node to manipulate comments from.
# des-unfreeze: If 1, unfreeze instead of freeze.
# des-ids: Array reference containing jtalkids to manipulate.
# returns: 1 on success; undef on error
# </LJFUNC>
sub freeze_comments {
    my ($u, $nodetype, $nodeid, $unfreeze, $ids) = @_;
    $u = LJ::want_user($u);
    $nodeid += 0;
    $unfreeze = $unfreeze ? 1 : 0;
    return undef unless LJ::isu($u) && $nodetype =~ /^\w$/ && $nodeid && @$ids;

    # get database and quote things
    return undef unless $u->writer;
    my $quserid = $u->{userid}+0;
    my $qnodetype = $u->quote($nodetype);
    my $qnodeid = $nodeid+0;

    # now perform action
    my @batch = map { int $_ } @$ids;
    my $in = join(',', @batch);
    my $newstate = $unfreeze ? 'A' : 'F';
    LJ::run_hooks('report_cmt_update', $quserid, \@batch);
    my $res = $u->talk2_do(nodetype => $nodetype, nodeid => $nodeid,
                           sql =>   "UPDATE talk2 SET state = '$newstate' " .
                                    "WHERE journalid = $quserid AND nodetype = $qnodetype " .
                                    "AND nodeid = $qnodeid AND jtalkid IN ($in)");

    # invalidate memcache for this comment
    LJ::Talk::invalidate_comment_cache($u->id, $nodeid, @$ids);

    
    # set time of comments modification in the journal
    LJ::Talk::update_journals_commentalter($u);

    LJ::run_hooks('freeze_comment', $unfreeze, $u, $nodeid, [@batch]); # jitemid, [jtalkid]

    return undef unless $res;
    return 1;
}

sub screen_comment {
    my $u = shift;
    return undef unless LJ::isu($u);
    my $itemid = shift(@_) + 0;
    my @jtalkids = @_;

    my @batch = map { int $_ } @jtalkids;
    my $in = join(',', @batch);
    return unless $in;

    my $userid = $u->{'userid'} + 0;

    LJ::run_hooks('report_cmt_update', $userid, \@batch);
    my $updated = $u->talk2_do(nodetype => "L", nodeid => $itemid,
                               sql =>   "UPDATE talk2 SET state='S' ".
                                        "WHERE journalid=$userid AND jtalkid IN ($in) ".
                                        "AND nodetype='L' AND nodeid=$itemid ".
                                        "AND state NOT IN ('S','D')");
    return undef unless $updated;

    # invalidate memcache for this comment
    LJ::Talk::invalidate_comment_cache($u->id, $itemid, @jtalkids);


    if ($updated > 0) {
        LJ::replycount_do($u, $itemid, "decr", $updated);
        LJ::set_logprop($u, $itemid, { 'hasscreened' => 1 });
    }

    LJ::Talk::update_commentalter($u, $itemid);
    LJ::Talk::update_journals_commentalter($u);

    LJ::run_hooks('screen_comment', $userid, $itemid, [@batch]); # jitemid, [jtalkid]

    return;
}

sub unscreen_comment {
    my $u = shift;
    return undef unless LJ::isu($u);
    my $itemid = shift(@_) + 0;
    my @jtalkids = @_;

    my @batch = map { int $_ } @jtalkids;
    my $in = join(',', @batch);
    return unless $in;

    my $userid = $u->{'userid'} + 0;
    my $prop = LJ::get_prop("log", "hasscreened");

    LJ::run_hooks('report_cmt_update', $userid, \@batch);
    my $updated = $u->talk2_do(nodetype => "L", nodeid => $itemid,
                               sql =>   "UPDATE talk2 SET state='A' ".
                                        "WHERE journalid=$userid AND jtalkid IN ($in) ".
                                        "AND nodetype='L' AND nodeid=$itemid ".
                                        "AND state='S'");
    return undef unless $updated;

    # invalidate memcache for this comment
    LJ::Talk::invalidate_comment_cache($u->id, $itemid, @jtalkids);

    if ($updated > 0) {
        LJ::replycount_do($u, $itemid, "incr", $updated);
        my $dbcm = LJ::get_cluster_master($u);
        my $hasscreened = $dbcm->selectrow_array("SELECT COUNT(*) FROM talk2 " .
                                                 "WHERE journalid=$userid AND nodeid=$itemid AND nodetype='L' AND state='S'");
        LJ::set_logprop($u, $itemid, { 'hasscreened' => 0 }) unless $hasscreened;
    }
    
    LJ::run_hooks('unscreen_comment', $userid, $itemid, $in);

    LJ::Talk::update_commentalter($u, $itemid);
    LJ::Talk::update_journals_commentalter($u);

    return;
}

sub spam_comment {
    my $u = shift;
    return undef unless LJ::isu($u);
    my $itemid = shift(@_) + 0;
    my @jtalkids = @_;

    my @batch = map { int $_ } @jtalkids;
    my $in = join(',', @batch);
    return unless $in;

    my $userid = $u->{'userid'} + 0;

    LJ::run_hooks('report_cmt_update', $userid, \@batch);
    my $updated = $u->talk2_do(nodetype => "L", nodeid => $itemid,
                               sql =>   "UPDATE talk2 SET state='B' ".
                                        "WHERE journalid=$userid AND jtalkid IN ($in) ".
                                        "AND nodetype='L' AND nodeid=$itemid ".
                                        "AND state NOT IN ('B','D')");
    return undef unless $updated;
    
    my $entry = LJ::Entry->new($u, jitemid => $itemid);
    my $spam_counter = $entry->prop('spam_counter') || 0;
    $entry->set_prop('spam_counter', $spam_counter + 1);

    # invalidate memcache for this comment
    LJ::Talk::invalidate_comment_cache($u->id, $itemid, @jtalkids);


    if ($updated > 0) {
        LJ::replycount_do($u, $itemid, "decr", $updated);
        LJ::set_logprop($u, $itemid, { 'hasspamed' => 1 });
    }

    LJ::Talk::update_commentalter($u, $itemid);
    LJ::Talk::update_journals_commentalter($u);

    return;
}

sub unspam_comment {
    my $u = shift;
    return undef unless LJ::isu($u);
    my $itemid = shift(@_) + 0;
    my @jtalkids = @_;
    
    my $new_state = 'A';    
    my $screening = LJ::Talk::screening_level( $u, $itemid ); 
    if ($screening eq 'A') {
        $new_state = 'S';
    }

    my @batch = map { int $_ } @jtalkids;
    my $in = join(',', @batch);
    return unless $in;

    my $userid = $u->{'userid'} + 0;
    my $prop = LJ::get_prop("log", "hasspamed");

    LJ::run_hooks('report_cmt_update', $userid, \@batch);
    my $updated = $u->talk2_do(nodetype => "L", nodeid => $itemid,
                               sql =>   "UPDATE talk2 SET state='$new_state' ".
                                        "WHERE journalid=$userid AND jtalkid IN ($in) ".
                                        "AND nodetype='L' AND nodeid=$itemid ".
                                        "AND state='B'");
    return undef unless $updated;
    
    my $entry = LJ::Entry->new($u, jitemid => $itemid);
    my $spam_counter = $entry->prop('spam_counter') || 0;

    # invalidate memcache for this comment
    LJ::Talk::invalidate_comment_cache($u->id, $itemid, @jtalkids);

    if ($updated > 0) {
        if ($spam_counter >= $updated) {
            $spam_counter = $spam_counter - $updated;
            $entry->set_prop('spam_counter', $spam_counter);
        }
        LJ::replycount_do($u, $itemid, "incr", $updated)
            if $new_state eq 'A';
        my $dbcm = LJ::get_cluster_master($u);
        my $hasspamed = $dbcm->selectrow_array("SELECT COUNT(*) FROM talk2 " .
                                                 "WHERE journalid=$userid AND nodeid=$itemid AND nodetype='L' AND state='B'");
        LJ::set_logprop($u, $itemid, { 'hasspamed' => 0 }) unless $hasspamed;
    }
    
    LJ::Talk::update_commentalter($u, $itemid);
    LJ::Talk::update_journals_commentalter($u);

    return $spam_counter;
}

sub get_talk_data {
    my ($u, $nodetype, $nodeid, $opts) = @_;
    return undef unless LJ::isu($u);
    return undef unless $nodetype =~ /^\w$/;
    return undef unless $nodeid =~ /^\d+$/;
    my $uid = $u->id;

    ## call normally if no gearman/not wanted
    
    ## Do no try to connect to Gearman if there is no need.
    return get_talk_data_do($uid, $nodetype, $nodeid, $opts)
        unless LJ::conf_test($LJ::LOADCOMMENTS_USING_GEARMAN, $u->id);

    my $gc = LJ::gearman_client();
    return get_talk_data_do($uid, $nodetype, $nodeid, $opts)
        unless $gc;

    # invoke gearman
    my $result;
    my @a = ($uid, $nodetype, $nodeid, $opts);
    my $args = Storable::nfreeze(\@a);
    my $task = Gearman::Task->new("get_talk_data", \$args,
                                  {
                                      uniq => join("-", $uid, $nodetype, $nodeid),
                                      on_complete => sub {
                                          my $res = shift;
                                          return unless $res;
                                          $result = Storable::thaw($$res);
                                      }
                                  });

    my $ts = $gc->new_task_set();
    $ts->add_task($task);
    $ts->wait(timeout => 30); # 30 sec timeout

    return $result;
}


sub make_comment_singleton {
    my ($jtalkid, $row, $u, $nodeid) = @_;

    # at this point we have data for this comment loaded in memory
    # -- instantiate an LJ::Comment object as a singleton and absorb
    #    that data into the object
    my $comment = LJ::Comment->new($u, jtalkid => $jtalkid);
    # add important info to row
    $row->{'nodetype'} = 'L';
    $row->{'nodeid'}   = $nodeid;
    $comment->absorb_row($row);

    return 1;
}

# retrieves data from the talk2 table (but preferably memcache)
# returns a hashref (key -> { 'talkid', 'posterid', 'datepost', 'datepost_unix',
#                             'parenttalkid', 'state' } , or undef on failure
# opts -> {
#           init_comobject    => [1|0], # by default 0, init or not comment objects
#           }
sub get_talk_data_do
{
    my ($uid, $nodetype, $nodeid, $opts) = @_;
    my $u = LJ::want_user($uid);
    return undef unless LJ::isu($u);
    return undef unless $nodetype =~ /^\w$/;
    return undef unless $nodeid =~ /^\d+$/;

    my $init_comobj = 1;
       $init_comobj = $opts->{init_comobj} if exists $opts->{init_comobj};
    
    my $ret = {};

    # check for data in memcache
    my $DATAVER = "3";  # single character
    my $RECORD_SIZE = 17;

    my $memkey = [$u->{'userid'}, "talk2:$u->{'userid'}:$nodetype:$nodeid"];

    my $lockkey = $memkey->[1];
    my $packed = LJ::MemCache::get($memkey);

    # we check the replycount in memcache, the value we count, and then fix it up
    # if it seems necessary.
    my $rp_memkey = $nodetype eq "L" ? LJ::Entry::reply_count_memkey($u, $nodeid) : undef;
    my $rp_count = $rp_memkey ? LJ::MemCache::get($rp_memkey) : 0;

    # hook for tests to count memcache gets
    if ($LJ::_T_GET_TALK_DATA_MEMCACHE) {
        $LJ::_T_GET_TALK_DATA_MEMCACHE->();
    }

    my $rp_ourcount = 0;
    my $fixup_rp = sub {
        return unless $nodetype eq "L";
        return if $rp_count == $rp_ourcount;
        return unless @LJ::MEMCACHE_SERVERS;
        return unless $u->writer;

        if (LJ::conf_test($LJ::FIXUP_USING_GEARMAN, $u) and my $gc = LJ::gearman_client()) {
            $gc->dispatch_background("fixup_logitem_replycount",
                                     Storable::nfreeze([ $u->id, $nodeid ]), {
                                         uniq => "-",
                                     });
        } else {
            LJ::Talk::fixup_logitem_replycount($u, $nodeid);
        }
    };


    # This is a bit tricky.  Since we just loaded and instantiated all comment singletons for this
    # entry (journalid, jitemid) we'll instantiate a skeleton LJ::Entry object (probably a singleton
    # used later in this request anyway) and let it know that its comments are already loaded
    my $set_entry_cache = sub {
        return 1 unless $nodetype eq 'L';

        my $entry = LJ::Entry->new($u, jitemid => $nodeid);

        # find all singletons that LJ::Comment knows about, then grep for the ones we've set in
        # this get_talk_data call (ones for this userid / nodeid)
        my @comments_for_entry =
            grep { $_->journalid == $u->{userid} && $_->nodeid == $nodeid } LJ::Comment->all_singletons;

        $entry->set_comment_list(@comments_for_entry);
    };

    my $memcache_good = sub {
        return $packed && substr($packed,0,1) eq $DATAVER &&
            length($packed) % $RECORD_SIZE == 1;
    };

    my $memcache_decode = sub {
        my $n = (length($packed) - 1) / $RECORD_SIZE * 5;
        my @data = unpack LJ::Talk::PACK_MULTI, $packed;

        for (my $i = 1; $i < $n; $i += 5 ) {
            my ($talkid, $par, $poster, $time) = @data[$i .. ($i + 3)];
            my $state = chr $data[$i + 4];

            $ret->{$talkid} = {
                talkid        => $talkid,
                state         => $state,
                posterid      => $poster,
                datepost_unix => $time,
                parenttalkid  => $par,
            };

            # instantiate comment singleton
            make_comment_singleton($talkid, $ret->{$talkid}, $u, $nodeid) if $init_comobj and $nodetype eq 'L';

            # comments are counted if they're 'A'pproved or 'F'rozen
            $rp_ourcount++ if $state eq "A" || $state eq "F";
        }

        $fixup_rp->();

        # set cache in LJ::Entry object for this set of comments
        $set_entry_cache->();

        ## increase profiling counter
        ## may be safely removed
        LJ::MemCache::add("talk2fromMemc", 0);
        LJ::MemCache::incr("talk2fromMemc");

        return $ret;
    };

    return $memcache_decode->() if $memcache_good->();

    # get time of last modification of comments in this journal.
    # if comments in journal were not updated for a some time, we could
    # load them from any server in cluster: master or slave
    my $dbcr = undef;
    my $comments_updated = $u->prop("comment_alter_time");
    if (LJ::is_web_context()
        and not LJ::did_post()
        and $LJ::USER_CLUSTER_MAX_SECONDS_BEHIND_MASTER
        and $comments_updated
        and time() - $comments_updated > $LJ::USER_CLUSTER_MAX_SECONDS_BEHIND_MASTER
    ){
        # try to load comments from Slave
        $dbcr = LJ::get_cluster_reader($u);

        ## increase profiling counter
        ## may be safely removed
        LJ::MemCache::add("talk2fromSlave", 0);
        LJ::MemCache::incr("talk2fromSlave");

    } else {
        $dbcr = LJ::get_cluster_def_reader($u);
    }
    return undef unless $dbcr;

    my $lock = $dbcr->selectrow_array("SELECT GET_LOCK(?,10)", undef, $lockkey);
    return undef unless $lock;

    # it's quite likely (for a popular post) that the memcache was
    # already populated while we were waiting for the lock
    $packed = LJ::MemCache::get($memkey);
    if ($memcache_good->()) {
        $dbcr->selectrow_array("SELECT RELEASE_LOCK(?)", undef, $lockkey);
        $memcache_decode->();
        return $ret;
    }

    ## increase profiling counter
    ## may be safely removed
    LJ::MemCache::add("talk2fromDB", 0);
    LJ::MemCache::incr("talk2fromDB");

    my $memval = $DATAVER;
    my $sth = $dbcr->prepare("SELECT t.jtalkid AS 'talkid', t.posterid, ".
                             "t.datepost, UNIX_TIMESTAMP(t.datepost) as 'datepost_unix', ".
                             "t.parenttalkid, t.state ".
                             "FROM talk2 t ".
                             "WHERE t.journalid=? AND t.nodetype=? AND t.nodeid=?");
    $sth->execute($u->{'userid'}, $nodetype, $nodeid);
    die $dbcr->errstr if $dbcr->err;
    while (my $r = $sth->fetchrow_hashref) {
        $ret->{$r->{'talkid'}} = $r;

        {
            # make a new $r-type hash which also contains nodetype and nodeid
            # -- they're not in $r because they were known and specified in the query
            my %row_arg = %$r;
            $row_arg{nodeid}   = $nodeid;
            $row_arg{nodetype} = $nodetype;

            # instantiate comment singleton
            make_comment_singleton($r->{talkid}, \%row_arg, $u, $nodeid) if $init_comobj and $nodetype eq 'L';

            # set talk2row memcache key for this bit of data
            LJ::Talk::add_talk2row_memcache($u->id, $r->{talkid}, \%row_arg);
        }

        $memval .= pack(LJ::Talk::PACK_FORMAT,
                        $r->{'talkid'},
                        $r->{'parenttalkid'},
                        $r->{'posterid'},
                        $r->{'datepost_unix'},
                        ord($r->{'state'}));

        $rp_ourcount++ if $r->{'state'} eq "A";
    }
    LJ::MemCache::set($memkey, $memval, 3600); # LJSV-748, using LJ::MemCache::append(...) in some (rare) cases 
                                               # can produce comment lose. This is a workaround. Real solution is more complicated.
    $dbcr->selectrow_array("SELECT RELEASE_LOCK(?)", undef, $lockkey);

    $fixup_rp->();

    # set cache in LJ::Entry object for this set of comments
    $set_entry_cache->();

    return $ret;
}

sub fixup_logitem_replycount {
    my ($u, $jitemid) = @_;

    # attempt to get a database lock to make sure that nobody else is in this section
    # at the same time we are
    my $nodetype = "L";  # this is only for logitem comment counts

    my $rp_memkey = LJ::Entry::reply_count_memkey($u, $jitemid);
    my $rp_count = LJ::MemCache::get($rp_memkey) || 0;
    my $fix_key = "rp_fixed:$u->{userid}:$nodetype:$jitemid:$rp_count";

    my $db_key = "rp:fix:$u->{userid}:$nodetype:$jitemid";
    my $got_lock = $u->selectrow_array("SELECT GET_LOCK(?, 1)", undef, $db_key);
    return unless $got_lock;

    # setup an unlock handler
    my $unlock = sub {
        $u->do("SELECT RELEASE_LOCK(?)", undef, $db_key);
        return undef;
    };

    # check memcache to see if someone has previously fixed this entry in this journal
    # with this reply count
    my $was_fixed = LJ::MemCache::get($fix_key);
    return $unlock->() if $was_fixed;

    # if we're doing innodb, begin a transaction, else lock tables
    my $sharedmode = "";
    if ($u->is_innodb) {
        $sharedmode = "LOCK IN SHARE MODE";
        $u->begin_work;
    } else {
        $u->do("LOCK TABLES log2 WRITE, talk2 READ, logbackup WRITE");
    }

    # get count and then update.  this should be totally safe because we've either
    # locked the tables or we're in a transaction.
    my $ct = $u->selectrow_array("SELECT COUNT(*) FROM talk2 FORCE INDEX (nodetype) WHERE ".
                                 "journalid=? AND nodetype='L' AND nodeid=? ".
                                 "AND state IN ('A','F') $sharedmode",
                                 undef, $u->{'userid'}, $jitemid);
    LJ::run_hooks('report_entry_update', $u->{'userid'}, $jitemid);
    $u->do("UPDATE log2 SET replycount=? WHERE journalid=? AND jitemid=?",
           undef, int($ct), $u->{'userid'}, $jitemid);
    print STDERR "Fixing replycount for $u->{'userid'}/$jitemid from $rp_count to $ct\n"
        if $LJ::DEBUG{'replycount_fix'};

    # now, commit or unlock as appropriate
    if ($u->is_innodb) {
        $u->commit;
    } else {
        $u->do("UNLOCK TABLES");
    }

    # mark it as fixed in memcache, so we don't do this again
    LJ::MemCache::add($fix_key, 1, 60);
    $unlock->();
    LJ::MemCache::set($rp_memkey, int($ct));
}

# LJ::Talk::load_comments_tree($u, $remote, $nodetype, $nodeid, $opts)
#
# nodetype: "L" (for log) ... nothing else has been used
# noteid: the jitemid for log.
# opts keys:
#   thread -- jtalkid to thread from ($init->{'thread'} or int($GET{'thread'} / 256))
#   page -- $GET{'page'}
#   page_size
#   view -- $GET{'view'} (picks page containing view's ditemid)
#   viewall
#   showspam
#   flat -- boolean:  if set, threading isn't done, and it's just a flat chrono view
#   up -- [optional] hashref of user object who posted the thing being replied to
#         only used to make things visible which would otherwise be screened?
#   out_error -- set by us if there's an error code:
#        nodb:  database unavailable
#        noposts:  no posts to load
#   out_pages:  number of pages
#   out_page:  page number being viewed
#   out_itemfirst:  first comment number on page (1-based, not db numbers)
#   out_itemlast:  last comment number on page (1-based, not db numbers)
#   out_pagesize:  size of each page
#   out_items:  number of total top level items
#
#   init_comobj -- init or not LJ::Comment object for every loaded raw data of a comment.
#                  by default it is On (true), but in this case it produces a huge overhead:
#                       LJ::Comment class stores in memory all comment instances and when load 
#                       property for any of a comment LJ::Comment loads all properties for ALL inited comments.
#                  (!) provide 'init_comobj => 0' wherever it is possible
#   strict_page_size -- under some circumstances page size (defined in 'page_size' option') may be changed.
#                       To disable this unexpected changes set this option to true value.
#
# returns:
#   ( $posts, $top_replies, $children ), where
#
#   $posts       - hashref {
#                      talkid => {
#                          talkid        => integer (jtalkid),
#                          parenttalkid  => integer (zero for top-level),
#                          posterid      => integer (zero for anon),
#                          datepost_unix => integer unix timestamp  1295268144,
#                          datepost      => string 'YYYY-MM-DD hh:mm:ss',
#                          state         => char ("A"=approved, "S"=screened, "D"=deleted stub, "B"=spam)
#                          has_children  => boolean - true, if comment has children (need for 'flat' mode)
#                          children      => arrayref of hashrefs like this,
#                          _show         => boolean (if item is to be ideally shown, 0 - if deleted or screened),
#                     }
#                 }
#   $top_replies - arrayref [ comment ids on the top level at the same page, ... ]
#   $children    - hashref { talkid => [ list of childred ids ] }
sub load_comments_tree
{
    my ($u, $remote, $nodetype, $nodeid, $opts) = @_;

    my $n = $u->{'clusterid'};
    my $viewall = $opts->{viewall};
    my $spambutton = LJ::is_enabled('spam_button');
    my $showspam   = $opts->{'showspam'};

    my $gtd_opts = { init_comobj => $opts->{init_comobj} };
    my $posts = get_talk_data($u, $nodetype, $nodeid, $gtd_opts);  # hashref, talkid -> talk2 row, or undef

    unless ($posts) {
        $opts->{'out_error'} = "nodb";
        return;
    }

    if ( $spambutton and $showspam ) {
        while ( my ($commentid, $comment) = each %$posts ) {
            if ( $comment->{state} eq 'B' ) {
                $comment->{parenttalkid} = 0;
                next;
            }
            delete $posts->{$commentid};
        }
    }
    
    my %children; # talkid -> [ childenids+ ]
    my %has_children; # talkid -> 1 or undef

    my $uposterid = $opts->{'up'} ? $opts->{'up'}->{'userid'} : 0;
    my $remote_userid = -1;
    my $journalid = $u->{'userid'};
    my ($can_manage, $can_sweep);

    if ( $remote ) {
        $can_manage = $remote->can_manage($u);
        $can_sweep = $remote->can_sweep($u);
        $remote_userid = $remote->{'userid'};
    }

    my $post_count = 0;
    my $flat = $opts->{'flat'};

    {
        my %showable_children;  # $id -> $count

        foreach my $post (@$posts{ sort { $b <=> $a } keys %$posts }) {
            my ($talkid, $parenttalkid, $state, $posterid) = @$post{ qw{ talkid parenttalkid state posterid } };

            $has_children{$parenttalkid} = 1;
            $post->{'has_children'} = $has_children{$talkid};

            # kill the threading in flat mode
            if ( $flat ) {
                $post->{'parenttalkid_actual'} = $parenttalkid;
                $post->{'parenttalkid'} = 0;
                $parenttalkid = 0;
            }

            # see if we should ideally show it or not.  even if it's
            # zero, we'll still show it if it has any children (but we won't show content)
            my $should_show = $state eq 'D'? 0 : 1;

            unless ( $viewall ) {
                $should_show = 0 if
                    $state eq 'S' && !($remote && ($remote_userid == $journalid ||
                                                   $remote_userid == $uposterid ||
                                                   $remote_userid == $posterid  ||
                                                   $can_manage || $can_sweep));
            }

            if ( $spambutton and not $showspam ) {
                $should_show = 0 if $state eq 'B' && !($remote && $remote_userid == $posterid);
            }

            $post->{'_show'} = $should_show;
            $post_count += $should_show;

            # make any post top-level if it says it has a parent but it isn't
            # loaded yet which means either a) row in database is gone, or b)
            # somebody maliciously/accidentally made their parent be a future
            # post, which could result in an infinite loop, which we don't want.
            if ( $parenttalkid && ! $posts->{$parenttalkid} ) {
                $post->{'parenttalkid'} = 0;
                $parenttalkid = 0;
            }

            $post->{'children'} = [ @$posts{ @{ $children{$talkid} || [] } } ];

            # increment the parent post's number of showable children,
            # which is our showability plus all those of our children
            # which were already computed, since we're working new to old
            # and children are always newer.
            # then, if we or our children are showable, add us to the child list
            my $sum = $should_show + $showable_children{$talkid};
            if ( $sum ) {
                $showable_children{$parenttalkid} += $sum;
                unshift @{ $children{$parenttalkid} }, $talkid;
            }
        }
    }

    # with a wrong thread number, silently default to the whole page
    my $thread = $opts->{'thread'}+0;
    $thread = 0 unless $posts->{$thread};

    unless ($thread || $children{$thread}) {
        $opts->{'out_error'} = "noposts";
        return;
    }

    my $page_size = $opts->{page_size} || $LJ::TALK_PAGE_SIZE || 25;
    my $threading_point = $LJ::TALK_THREAD_POINT || 50;

    # we let the page size initially get bigger than normal for awhile,
    # but if it passes threading_point, then everything's in page_size
    # chunks:
    unless ($opts->{strict_page_size}){ ## strict_page_size -- disables recalculation of the page size.
        $page_size = $threading_point if $post_count < $threading_point;
    }

    my $top_replies = $thread ? 1 : scalar(@{$children{$thread}});
    my $pages = int($top_replies / $page_size);
    if ($top_replies % $page_size) { $pages++; }

    my @top_replies = $thread ? ($thread) : @{$children{$thread}};
    my $page_from_view = 0;
    if ($opts->{'view'} && !$opts->{'page'}) {
        # find top-level comment that this comment is under
        my $viewid = int($opts->{'view'} / 256);
        while ($posts->{$viewid} && $posts->{$viewid}->{'parenttalkid'}) {
            $viewid = $posts->{$viewid}->{'parenttalkid'};
        }
        for (my $ti = 0; $ti < @top_replies; ++$ti) {
            if ($posts->{$top_replies[$ti]}->{'talkid'} == $viewid) {
                $page_from_view = int($ti/$page_size)+1;
                last;
            }
        }
    }
    my $page = int($opts->{'page'}) || $page_from_view || 1;
    $page = $page < 1 ? 1 : $page > $pages ? $pages : $page;

    my $itemfirst = $page_size * ($page-1) + 1;
    my $itemlast = $page == $pages ? $top_replies : ($page_size * $page);

    @top_replies = @top_replies[$itemfirst-1 .. $itemlast-1];

    $opts->{'out_pages'} = $pages;
    $opts->{'out_page'} = $page;
    $opts->{'out_itemfirst'} = $itemfirst;
    $opts->{'out_itemlast'} = $itemlast;
    $opts->{'out_pagesize'} = $page_size;
    $opts->{'out_items'} = $top_replies;

    return ( $posts, \@top_replies, \%children );
}

# LJ::Talk::load_comments($u, $remote, $nodetype, $nodeid, $opts)
#
# nodetype: "L" (for log) ... nothing else has been used
# noteid: the jitemid for log.
# opts keys:
#   thread -- jtalkid to thread from ($init->{'thread'} or int($GET{'thread'} / 256))
#   page -- $GET{'page'}
#   view -- $GET{'view'} (picks page containing view's ditemid)
#   flat -- boolean:  if set, threading isn't done, and it's just a flat chrono view
#   up -- [optional] hashref of user object who posted the thing being replied to
#         only used to make things visible which would otherwise be screened?
#   show_parents : boolean, if thread is specified, then also show it's parents.
#   out_error -- set by us if there's an error code:
#        nodb:  database unavailable
#        noposts:  no posts to load
#   out_pages:  number of pages
#   out_page:  page number being viewed
#   out_itemfirst:  first comment number on page (1-based, not db numbers)
#   out_itemlast:  last comment number on page (1-based, not db numbers)
#   out_pagesize:  size of each page
#   out_items:  number of total top level items
#
#   userpicref -- hashref to load userpics into, or undef to
#                 not load them.
#   userref -- hashref to load users into, keyed by userid
#   init_comobj -- init or not LJ::Comment object for every loaded raw data of a comment.
#                  by default it is On (true), but in this case it produces a huge overhead:
#                       LJ::Comment class stores in memory all comment instances and when load
#                       property for any of a comment LJ::Comment loads all properties for ALL inited comments.
#                  (!) provide 'init_comobj => 0' wherever it is possible
#   strict_page_size -- under some circumstances page size (defined in 'page_size' option') may be changed.
#                       To disable this unexpected changes set this option to true value.
#
# returns:
#   array of hashrefs containing keys:
#      - talkid (jtalkid)
#      - posterid (or zero for anon)
#      - userpost (string, or blank if anon)
#      - upost    ($u object, or undef if anon)
#      - datepost (mysql format)
#      - parenttalkid (or zero for top-level)
#      - parenttalkid_actual (set when the $flat mode is set, in which case parenttalkid is always faked to be 0)
#      - state ("A"=approved, "S"=screened, "D"=deleted stub)
#      - userpic number
#      - picid   (if userpicref AND userref were given)
#      - subject
#      - body
#      - props => { propname => value, ... }
#      - children => [ hashrefs like these ]
#      - _loaded => 1 (if fully loaded, subject & body)
#        unknown items will never be _loaded
#      - _show => {0|1}, if item is to be ideally shown (0 if deleted or screened)
sub load_comments
{
    my ($u, $remote, $nodetype, $nodeid, $opts) = @_;

    # paranoic code
    $opts->{'out_error'} = undef;

    my ($posts, $top_replies, $children) = load_comments_tree($u, $remote, $nodetype, $nodeid, $opts);

    if ($opts->{'out_error'}) {
        return;
    }

    # TODO: remove this
    my $page_size = $opts->{'out_pagesize'};

    my %users_to_load;  # userid -> 1
    my %posts_to_load;  # talkid -> 1

    map { $posts_to_load{$_} = 1 } @$top_replies;

    # mark child posts of the top-level to load, deeper
    # and deeper until we've hit the page size.  if too many loaded,
    # just mark that we'll load the subjects;
    my @check_for_children = keys %posts_to_load;

    unless ($opts->{expand_strategy}) {
        # the default strategy is to show first replies to top-level
        # comments
        foreach my $itemid (@$top_replies) {
            next unless $children->{$itemid};
            $posts_to_load{$children->{$itemid}->[0]} = 1;
        }
    }

    # 'by_level' strategy means that all comments up to the selected
    # level are expanded
    if ($opts->{expand_strategy} eq 'by_level' and $opts->{expand_level} > 1) {
        my $expand = sub {
            my ($fun, $cur_level, $item_ids) = @_;
            next if $cur_level >= $opts->{expand_level};

            foreach my $itemid (@$item_ids){
                $posts_to_load{$itemid} = 1;
                next unless $children->{$itemid};

                ## expand next level it there are comments
                $fun->($fun, $cur_level+1, $children->{$itemid});
            }
        };

        ## go through first level
        foreach my $itemid (@$top_replies){
            next unless $children->{$itemid};
            ## expand next (second) level
            $expand->($expand, 2, $children->{$itemid});
        }
    }

    # 'detailed' strategy means that all top-level and second level
    # comments are expanded; as for the third level comments,
    # we only expand five first replies to every first reply to
    # any top-level comment (yeah, this is tricky, watch me)
    if ($opts->{'expand_strategy'} eq 'detailed') {
        foreach my $itemid_l1 (@$top_replies) {
            next unless $children->{$itemid_l1};

            my $counter_l2 = 1;
            foreach my $itemid_l2 (@{$children->{$itemid_l1}}) {
                # we're handling a second-level comment here

                # the comment itself is always shown
                $posts_to_load{$itemid_l2} = 1;

                # if it's not the first reply, children can be hidden,
                # so we don't care
                next if $counter_l2 > 1;

                # if there is no children at all, we don't care either
                next unless $children->{$itemid_l2};

                # well, let's handle children now
                # we're copying a list here deliberately, so that
                # later on, we can splice() to modify the copy
                my @children = @{$children->{$itemid_l2}};
                map { $posts_to_load{$_} = 1 } splice(@children, 0, 5);

                $counter_l2++;
            }
        }
    }

    # load first level and 3 first replies(or replies to replies)
    if ($opts->{'expand_strategy'} eq 'mobile') {
        undef @check_for_children;
        foreach my $first_itemid (@$top_replies) {
            next unless $children->{$first_itemid};
            my @childrens = @{ $children->{$first_itemid} };
            my $load = $opts->{'expand_child'} || 3;
            while( @childrens && $load > 0 ){
                if ( @childrens >= $load ){
                    map { $posts_to_load{$_} = 1 }  splice(@childrens, 0, $load);
                    last;
                }else{
                    map { $posts_to_load{$_} = 1 }  @childrens;
                    $load -= @childrens;
                    @childrens = map { $children->{$_} ? @{$children->{$_}} : () } @childrens;
                }
            }
        }        
    }
    
    my $thread = $opts->{'thread'}+0;
    my $visible_parents = int $opts->{'visible_parents'};

    if ( $thread and $visible_parents ) {
        my $parents = $opts->{'parents_counter'};
        my $go_up_to = $opts->{'parents_talkid'};
        my $real_thread;

        while (my $parent_thread = $posts->{$thread}->{'parenttalkid'}) {
            $children->{$parent_thread} = [ $thread ];
            $posts->{$parent_thread}->{'children'} = [ $posts->{$thread} ];
            $posts->{$parent_thread}->{'_collapsed'} = 1;
            $posts_to_load{$parent_thread} = 1 if $visible_parents;
            $real_thread = $parent_thread if $visible_parents == 1;
            $thread = $parent_thread;
            $$go_up_to = $thread if ref $go_up_to and $thread;
            if ( defined $visible_parents ) {
                --$visible_parents if $visible_parents;
                $$parents += 1     if ref $parents and $thread;
            }
        }

        $$parents -= $LJ::S1_FOLDED_PARENTS if $$parents;
        $top_replies = [ $real_thread || $thread ];
    }

    my $max_subjects = $LJ::TALK_MAX_SUBJECTS;

    my %subjects_to_load;
    my $subjcounter = 0;

    while (@check_for_children) {
        my $cfc = shift @check_for_children;
        $users_to_load{$posts->{$cfc}->{'posterid'}} ||= 0.5;  # only care about username
        next unless defined $children->{$cfc};

        foreach my $child (@{$children->{$cfc}}) {
            if ( keys %posts_to_load < $page_size or $opts->{'expand_all'} ) {
                $posts_to_load{$child} = 1;
            } elsif ( ++$subjcounter < $max_subjects ) {
                $subjects_to_load{$child} = 1;
            }

            push @check_for_children, $child;
        }
    }

    # load text of posts
    my ($posts_loaded, $subjects_loaded);
    my $no_subject = LJ::is_enabled('new_comments')? '' : '...';

    $posts_loaded = LJ::get_talktext2($u, keys %posts_to_load);
    $subjects_loaded = LJ::get_talktext2($u, { onlysubjects => 1 }, keys %subjects_to_load, keys %posts_to_load);

    foreach my $talkid (keys %posts_to_load) {
        my $post = $posts->{$talkid};
        next unless $post->{'_show'};
        $post->{'_loaded'} = 1;
        $post->{'subject'} = $posts_loaded->{$talkid}->[0];
        $post->{'body'} = $posts_loaded->{$talkid}->[1];
        $users_to_load{$post->{'posterid'}} = 1;
    }

    while (my ($talkid, $post) = each %$posts) {
        next unless $post->{'_show'};
        $post->{'subject'} = $subjects_loaded->{$talkid}?
            $subjects_loaded->{$talkid}->[0]:
            $no_subject;
    } 

    # load meta-data
    {
        my %props;
        LJ::load_talk_props2($u->{'userid'}, [ keys %posts_to_load ] , \%props);
        foreach (keys %props) {
            next unless $posts->{$_}->{'_show'};
            $posts->{$_}->{'props'} = $props{$_};
        }
    }

    if ($LJ::UNICODE) {
        foreach (keys %posts_to_load) {
            if ($posts->{$_}->{'props'}->{'unknown8bit'}) {
                LJ::item_toutf8($u, \$posts->{$_}->{'subject'},
                                \$posts->{$_}->{'body'},
                                {});
              }
        }
    }

    # load users who posted
    delete $users_to_load{0};
    my %up = ();
    if (%users_to_load) {
        LJ::load_userids_multiple([ map { $_, \$up{$_} } keys %users_to_load ]);
        LJ::load_user_props_multi([values %up], [qw{ custom_usericon custom_usericon_individual }]);
 
        # fill in the 'userpost' member on each post being shown
        while (my ($id, $post) = each %$posts) {
            my $up = $up{$post->{'posterid'}};
            next unless $up;
            $post->{'upost'}    = $up;
            $post->{'userpost'} = $up->{'user'};
        }
    }

    ## Fix: if authors of comments deleted their journals, 
    ## and choosed to delete their content in other journals,
    ## then show their comments as deleted.
    ## Note: only posts with loaded users (posts that will be shown) are processed here.
    if (!$LJ::JOURNALS_WITH_PROTECTED_CONTENT{ $u->{'user'} }) {
        foreach my $post (values %$posts) {
            my $up = $up{ $post->{'posterid'} };
            if ( $up and $up->{'statusvis'} eq 'D' ) {
                my ($purge_comments, undef) = split /:/, $up->prop("purge_external_content");
                if ($purge_comments) {
                    delete @$post{qw/ _loaded subject body /};
                    $post->{'status'} = 'D';
                }
            }
        }
    } 

    # optionally give them back user refs
    if (ref($opts->{'userref'}) eq "HASH") {
        my %userpics = ();
        # copy into their ref the users we've already loaded above.
        while (my ($k, $v) = each %up) {
            $opts->{'userref'}->{$k} = $v;
        }

        # optionally load userpics
        if (ref($opts->{'userpicref'}) eq "HASH") {
            my @load_pic;
            foreach my $talkid (keys %posts_to_load) {
                my $post = $posts->{$talkid};
                my $kw;
                if ($post->{'props'} && $post->{'props'}->{'picture_keyword'}) {
                    $kw = $post->{'props'}->{'picture_keyword'};
                }
                my $pu = $opts->{'userref'}->{$post->{'posterid'}};
                my $id = LJ::get_picid_from_keyword($pu, $kw);
                $post->{'picid'} = $id;
                push @load_pic, [ $pu, $id ];
            }
            LJ::load_userpics($opts->{'userpicref'}, \@load_pic);
        }
    }
    return map { $posts->{$_} } @$top_replies;
}

# XXX these strings should be in talk, but moving them means we have
# to retranslate.  so for now we're just gonna put it off.
my $SC = '/talkpost_do.bml';

sub resources_for_talkform {
    LJ::need_res('stc/display_none.css');
    LJ::need_res(qw(
        js/jquery/jquery.lj.subjecticons.js
        js/jquery/jquery.lj.commentator.js
        js/jquery/jquery.lj.quotescreator.js
    ));
    LJ::need_res(qw(
        js/jquery/jquery.lj.authtype.js
        js/jquery/jquery.lj.userpicker.js
        js/jquery/jquery.lj.commentform.js
        js/jquery/jquery.easing.js
    ));
    LJ::need_res( {condition => 'IE'}, 'js/jquery/jquery.ie6multipleclass.min.js');
    LJ::need_string(qw(/talkpost_do.bml.quote.info.message));
}

sub talkform {

    # Takes a hashref with the following keys / values:
    # remote:      optional remote u object
    # journalu:    prequired journal u object
    # parpost:     parent post object
    # replyto:     init->replyto
    # ditemid:     init->ditemid
    # stylemine:   user using style=mine or not
    # form:        optional full form hashref
    # do_captcha:  optional toggle for creating a captcha challenge
    # require_tos: optional toggle to include TOS requirement form
    # errors:      optional error arrayref
    # text_hint:   hint before message textarea
    # embedable_form: use embedable template to draw form
    #
    my $opts = shift;
    return "Invalid talkform values." unless ref $opts eq 'HASH';

    my ( $remote, $journalu, $parpost, $form ) =
        map { $opts->{$_} } qw(remote journalu parpost form);

    my $editid = $form->{'edit'} || 0;

    # early bail if the user can't be making comments yet
    return $LJ::UNDERAGE_ERROR
        if $remote && $remote->underage;

    # once we clean out talkpost.bml, this will need to be changed.
    BML::set_language_scope('/talkpost.bml');

    # make sure journal isn't locked
    return
        "Sorry, this journal is locked and comments cannot be posted to it or edited at this time."
        if $journalu->{statusvis} eq 'L';

    # check max comments only if posting a new comment (not when editing)
    unless ($editid) {
        my $jitemid = int( $opts->{'ditemid'} / 256 );
        return
            "Sorry, this entry already has the maximum number of comments allowed."
            if LJ::Talk::Post::over_maxcomments( $journalu, $jitemid );
    }

    my $entry = LJ::Entry->new( $journalu, ditemid => $opts->{ditemid} );

    my $is_person = $remote && $remote->is_person;
    my $personal  = $journalu->is_person? 1 : 0;
    my $is_friend = LJ::is_friend( $journalu, $remote );
    my $remote_can_comment = $entry->registered_can_comment
        || ( $remote and $is_friend );

    #return "You cannot edit this comment."
    #    if $editid && !$is_person;

    my $filename = $opts->{embedable_form} 
        ? "$ENV{'LJHOME'}/templates/CommentForm/FormEmbedable.tmpl"
        : "$ENV{'LJHOME'}/templates/CommentForm/Form.tmpl";

    my $template = LJ::HTML::Template->new(
        { use_expr => 1 },    # force HTML::Template::Pro with Expr support
        filename          => $filename,
        die_on_bad_params => 0,
        strict            => 0,
        )
        or die "Can't open template: $!";

    my $remote_username     = $remote ? $remote->username     : '';
    my $remote_display_name = $remote ? $remote->display_name : '';

    my $form_intro;

    $form_intro .= LJ::form_auth();

    # Login challenge/response
    my $authchal = LJ::challenge_generate(900);    # 15 minute auth token
    $form_intro .= qq{
        <input type='hidden' name='chal' id='login_chal' value='$authchal' />
        <input type='hidden' name='response' id='login_response' value='' />
    };

    # hidden values
    my $parent = $opts->{replyto} + 0;
    $form_intro .= LJ::html_hidden(
        'replyto'      => $opts->{'replyto'},
        'parenttalkid' => $parent,
        'itemid'       => $opts->{'ditemid'},
        'journal'      => $journalu->username,
        'stylemine'    => $opts->{'stylemine'},
        'editid'       => $editid,
        'talkpost_do'  => $opts->{'talkpost_do'}? 1 : 0,
    );

    # rate limiting challenge
    my ( $secret_time, $secret ) = LJ::get_secret();
    my $rchars = LJ::rand_chars(20);
    my $chal   = join( '-',
        ( $entry->ditemid, $journalu->id, $secret_time, $rchars ) );
    my $res = Digest::MD5::md5_hex( $secret . $chal );
    $form_intro .= LJ::html_hidden( "chrp1", "$chal-$res" );

    $opts->{'errors'} ||= [];
    my $have_errors = scalar( @{ $opts->{errors} } );
    my @errors_show = map { { 'error' => $_ } } @{ $opts->{errors} };

    # if we know the user who is posting (error on talkpost_do POST action),
    # then see if we
    my $html_tosagree = '';
    if ( $opts->{require_tos} ) {
        $html_tosagree = LJ::tosagree_html( 'comment', $form->{agree_tos},
            LJ::Lang::ml('tos.error') );
    }

    my ( $is_identity, $oid_identity );
    if ( $remote && $remote->is_identity ) {
        $is_identity = 1;
        my $id = $remote->identity;
        if ( $id->short_code eq 'openid' ) {
            $oid_identity = $id->value;
        }
    }

    # special link to create an account
    my $create_link;
    if ( !$remote || $is_identity ) {
        $create_link = LJ::run_hook( "override_create_link_on_talkpost_form",
            $journalu );
    }

    my @author_options;
    my $usertype_default = $form->{'usertype'};

    # LJSUP-8788; I admit this is a hack
    if ( $usertype_default eq 'user' && !$form->{'userpost'} ) {
        undef $usertype_default;
    }

    foreach my $author_class (LJ::Talk::Author->all) {
        next unless $author_class->enabled;

        my $params = $author_class->display_params($opts);
        $params->{'short_code'} = $author_class->short_code;
        push @author_options, $params;

        $usertype_default ||= $author_class->usertype_default($remote);
    }

    # LJSUP-10659
    @author_options = sort { $LJ::FORM_AUTH_PRIORITY{ lc $a->{'short_code'} } <=> $LJ::FORM_AUTH_PRIORITY{ lc $b->{'short_code'} } } @author_options;

    # LJSUP-10674
    $usertype_default = $1 if $usertype_default =~ m/^(\w+)_cookie$/;

    # from registered user or anonymous?
    my $screening = LJ::Talk::screening_level( $journalu, $entry->jitemid );

    my $willscreen;
    if ( $screening eq 'A' ) {
        $willscreen = 1;
    }
    elsif ( $screening eq 'F' ) {
        $willscreen = !( $remote && $is_person && $is_friend );
    }
    elsif ( $screening eq 'R' ) {
        $willscreen = !($remote? $remote->is_validated : 0);
    }

    my ( $ml_willscreen, $ml_willscreenfriend );
    if ($willscreen) {
        $ml_willscreen = LJ::Lang::ml('/talkpost.bml.opt.willscreen'),;
    }
    elsif ( $screening eq 'F' ) {
        $ml_willscreenfriend
            = LJ::Lang::ml('/talkpost.bml.opt.willscreenfriend');
    }

    my $basesubject = $form->{subject} || "";
    if ( $opts->{replyto} && !$basesubject && $parpost->{'subject'} ) {
        $basesubject = $parpost->{'subject'};
        $basesubject =~ s/^Re:\s*//i;
        $basesubject = "Re: $basesubject";
    }

    # subject
    $basesubject = BML::eall($basesubject) if $basesubject;

    # Subject Icon toggle button
    my $pics     = LJ::Talk::get_subjecticons();
    my $subjicon = $form->{subjecticon};
    my $picinfo  = $pics->{'pic'}->{$subjicon};
    $subjicon = 'none' unless $picinfo;

    my %subicon_current_show;
    if ($picinfo) {
        %subicon_current_show = (
            'img' => $picinfo->{'img'},
            'w'   => $picinfo->{'w'},
            'h'   => $picinfo->{'h'},
        );
    }

    my @subjicon_types;

    foreach my $type ( @{ $pics->{'types'} } ) {
        my @subjicons;
        foreach my $pi ( @{ $pics->{'lists'}->{$type} } ) {
            push @subjicons,
                {
                'subjicon_img' => $pi->{'img'},
                'subjicon_w'   => $pi->{'w'},
                'subjicon_h'   => $pi->{'h'},
                'subjicon_id'  => $pi->{'id'},
                };
        }

        push @subjicon_types, { 'subjicons' => \@subjicons };
    }

    my %res;
    if ($remote) {
        LJ::do_request(
            {   "mode"      => "login",
                "ver"       => ( $LJ::UNICODE ? "1" : "0" ),
                "user"      => $remote->{'user'},
                "getpickws" => 1,
                'getpickwurls' => 1,
            },
            \%res,
            { "noauth" => 1, "userid" => $remote->{'userid'} }
        );
    }

    my ( $show_userpics, @pics_display, %userpicmap, $defaultpicurl );
    if ( $res{'pickw_count'} ) {
        $show_userpics = 1;

        my @pics =
            sort { lc($a) cmp lc($b) }
            map { $res{"pickw_$_"} } ( 1 .. $res{'pickw_count'} );

        push @pics_display,
            {
            'userpic_keyword' => '',
            'userpic_title'   => LJ::Lang::ml('/talkpost.bml.opt.defpic'),
            };

        foreach my $pickw (@pics) {
            push @pics_display,
                {
                'userpic_keyword'  => LJ::ehtml($pickw),
                'userpic_title'    => LJ::ehtml($pickw),
                'userpic_selected' => $pickw eq
                    $form->{'prop_picture_keyword'},
                };
        }

        foreach my $i (1 .. $res{'pickw_count'}) {
            $userpicmap{LJ::ehtml($res{"pickw_$i"})} = $res{"pickwurl_$i"};
        }

        if (my $upi = $remote->userpic) {
            $defaultpicurl = $upi->url;
        }
    }

    # only show on initial compostion
    my $show_quick_quote = $remote && !$have_errors;

    # Display captcha challenge if over rate limits.
    my $captcha_html = '';
    if ( $opts->{do_captcha} ) {
        if ( LJ::is_enabled("recaptcha") ) {
            my $c      = Captcha::reCAPTCHA->new;
            my $apikey = LJ::conf_test( $LJ::RECAPTCHA{public_key} );

            $captcha_html .= $c->get_options_setter(
                {   'theme' => 'clean',
                    'lang'  => BML::get_language(),
                }
            );
            $captcha_html .= $c->get_html($apikey);
        }
        else {
            my ( $wants_audio, $captcha_sess, $captcha_chal );
            $wants_audio = 1 if lc( $form->{answer} ) eq 'audio';

            # Captcha sessions
            my $cid = $journalu->{clusterid};
            $captcha_chal = $form->{captcha_chal}
                || LJ::challenge_generate(900);
            $captcha_sess = LJ::get_challenge_attributes($captcha_chal);
            my $dbcr = LJ::get_cluster_reader($journalu);

            my $try = 0;
            if ( $form->{captcha_chal} ) {
                $try = $dbcr->selectrow_array(
                    'SELECT trynum FROM captcha_session ' . 'WHERE sess=?',
                    undef, $captcha_sess );
            }
            $captcha_html .= '<br /><br />';

            # Visual challenge
            if ( !$wants_audio && !$form->{audio_chal} ) {
                $captcha_html
                    .= "<div class='formitemDesc'>$BML::ML{'/create.bml.captcha.desc'}</div>";
                $captcha_html
                    .= "<img src='/captcha/image.bml?chal=$captcha_chal&amp;cid=$cid&amp;try=$try' width='175' height='35' />";
                $captcha_html
                    .= "<br /><br />$BML::ML{'/create.bml.captcha.answer'}";
            }

            # Audio challenge
            else {
                $captcha_html
                    .= "<div class='formitemDesc'>$BML::ML{'/create.bml.captcha.audiodesc'}</div>";
                $captcha_html
                    .= "<a href='/captcha/audio.bml?chal=$captcha_chal&amp;cid=$cid&amp;try=$try'>$BML::ML{'/create.bml.captcha.play'}</a> &nbsp; ";
                $captcha_html .= LJ::html_hidden( audio_chal => 1 );
            }
            $captcha_html
                .= LJ::html_text( { name => 'answer', size => 15 } );
            $captcha_html .= LJ::html_hidden( captcha_chal => $captcha_chal );
        }
    }

    my $logips = $journalu->{'opt_logcommentips'};
    my ( $ml_logcommentips, $show_logips );
    if ( $logips =~ /[AS]/ ) {
        my $mlkey =
            $logips eq 'A'
            ? '/talkpost.bml.logyourip'
            : '/talkpost.bml.loganonip';

        $show_logips      = $logips;
        $ml_logcommentips = LJ::Lang::ml($mlkey);
    }

    my %ml = (
        'loggedin' => LJ::Lang::ml(
            '/talkpost.bml.opt.loggedin',
            {   'username' => '<i>'
                    . LJ::ehtml($remote_display_name) . '</i>',
            }
        ),
        'banned' => LJ::Lang::ml(
            '/talkpost.bml.opt.bannedfrom',
            { 'journal' => $journalu->username, }
        ),
        'noopenidpost' => LJ::Lang::ml(
            '/talkpost.bml.opt.noopenidpost',
            {   'aopts1' => "href='$LJ::SITEROOT/changeemail.bml'",
                'aopts2' => "href='$LJ::SITEROOT/register.bml'",
            }
        ),
        'friendsonly' => LJ::Lang::ml(
            '/talkpost.bml.opt.'
                . ( $personal ? 'friends' : 'members' ) . 'only',
            { 'username' => '<b>' . $journalu->username . '</b>', }
        ),
        'notafriend' => LJ::Lang::ml(
            '/talkpost_do.bml.error.nota'
                . ( $personal ? 'friend' : 'member' ),
            { 'user' => $journalu->username, }
        ),
        'noaccount' => LJ::Lang::ml(
            '/talkpost.bml.noaccount',
            { 'aopts' => "href='$LJ::SITEROOT/create.bml'", }
        ),
        'picturetouse' => LJ::Lang::ml(
            '/talkpost.bml.label.picturetouse2',
            {   'aopts' =>
                    "href='$LJ::SITEROOT/allpics.bml?user=$remote_username'",
            }
        ),
        'usermismatch' =>
            LJ::ejs( LJ::Lang::ml('/talkpost.bml.usermismatch') ),
        'logcommentips'    => $ml_logcommentips,
        'willscreen'       => $ml_willscreen,
        'willscreenfriend' => $ml_willscreenfriend,
    );

    # COMMON TEMPLATE PARAMS ARE DEFINED HERE
    $template->param(

        # string values the template may wish
        'remote_username'        => $remote_username,
        'remote_display_name'    => $remote_display_name,
        'journalu_username'      => $journalu->username,
        'editid'                 => $editid,
        'entry_url'              => $entry->url,
        'nocomments'             => $entry->prop('opt_nocomments'),
        'suspended'              => $remote? $remote->is_suspended : 0,
        'deleted'                => $remote ? $remote->is_deleted || $remote->is_expunged : 0,
        will_be_screened         => $entry->prop('opt_screening')  || ($journalu? $journalu->prop("opt_whoscreened")  : 0),

        # various checks
        'remote_banned'          => LJ::is_banned( $remote, $journalu ),
        'everyone_can_comment'   => $entry->everyone_can_comment,
        'registered_can_comment' => $entry->registered_can_comment,
        'friends_can_comment'    => $entry->friends_can_comment,
        'is_public'              => $entry->is_public,
        'is_person'              => $is_person,
        'is_identity'            => $remote && $remote->is_identity,
        'remote_can_comment'     => $remote_can_comment,
        is_friend                => $is_friend,
        whocanreply              => $journalu->prop('opt_whocanreply'),
        email_active             => $remote? $remote->is_validated : 0,

        # ml variables. it is weird that we've got to pass these to
        # the template, but well, the logic here is considered too
        # complex to be in a template, so whatever.
        'ml_banned'              => $ml{'banned'},
        'ml_friendsonly'         => $ml{'friendsonly'},
        'ml_logcommentips'       => $ml{'logcommentips'},
        'ml_loggedin'            => $ml{'loggedin'},
        'ml_noaccount'           => $ml{'noaccount'},
        'ml_noopenidpost'        => $ml{'noopenidpost'},
        'ml_notafriend'          => $ml{'notafriend'},
        'ml_picturetouse'        => $ml{'picturetouse'},
        'ml_usermismatch'        => $ml{'usermismatch'},
        'ml_willscreen'          => $ml{'willscreen'},
        'ml_willscreenfriend'    => $ml{'willscreenfriend'},

        # help icons
        'helpicon_userpics'      => LJ::help_icon_html( "userpics",     " " ),
        'helpicon_noautoformat'  => LJ::help_icon_html( "noautoformat", " " ),
        'helpicon_iplogging'     => LJ::help_icon_html( "iplogging",    " " ),

        # Captcha keys
        captcha_private          => LJ::conf_test( $LJ::RECAPTCHA{'private_key'} ),
        captcha_public           => LJ::conf_test( $LJ::RECAPTCHA{'public_key'} ),

        need_captcha             => $opts->{'do_captcha'},
        commentcaptcha           => $captcha_html ? $journalu->prop("opt_show_captcha_to") : '',
        notaspammer              => $remote? LJ::is_friend($LJ::NOTASPAMMERS_COMM_UID, $remote) : 0,

        'captcha_html'              => $captcha_html,
        'comment_length_cap'        => LJ::CMAX_COMMENT,
        'show_spellcheck'           => $LJ::SPELLER ? 1 : 0,
        'show_logips'               => $show_logips,
        'comment_body'              => LJ::ehtml( $form->{'body'} ),
        'show_quick_quote'          => $show_quick_quote,
        'opt_preformatted_selected' => $form->{'prop_opt_preformatted'},
        'show_userpics'             => $show_userpics,
        'userpics'                  => \@pics_display,
        'userpicmap'                => LJ::JSON->to_json(\%userpicmap),
        'defaultpicurl'             => $defaultpicurl,
        'subjicon_types'            => \@subjicon_types,
        'text_hint'                 => $opts->{'text_hint'},
        'create_link'               => $create_link,
        'subjicon'                  => $subjicon,
        'subjicon_none'             => $subjicon eq 'none',
        'subjicon_current_img'      => $subicon_current_show{'img'},
        'subjicon_current_w'        => $subicon_current_show{'w'},
        'subjicon_current_h'        => $subicon_current_show{'h'},
        'warnscreened'              => !$editid && $parpost->{'state'} eq "S",
        parpost                     => $parpost->{'jtalkid'}? 1 : 0,

        'form_intro'                => $form_intro,
        'errors'                    => \@errors_show,
        'tosagree'                  => $html_tosagree,

        'basesubject'           => $basesubject,
        'author_options'        => \@author_options,
        'usertype_default'      => $usertype_default,
        usertype                => $usertype_default,
        authtype                => $remote? ($remote->is_identity? lc $remote->identity->short_code : 'cookieuser') : 'anonymous',

        'extra_rows'            => LJ::run_hook('extra_talkform_rows', {
            'entry'     => $entry,
            'editid'    => $editid,
        }) || undef,

        'logout_url'            => $opts->{'logout_url'},
        'js_check_domain'       => $opts->{'js_check_domain'},
        'resources_html'        => $opts->{'resources_html'},
        'partner_domain'        => $opts->{'partner_domain'},
        'partner_remote_ljuser' => $opts->{'partner_remote_ljuser'},

        'talkpost_do' => $opts->{'talkpost_do'}? 1 : 0,
    );

    return $template->output;
}

# mobile commenting form 
sub talkform_mobile {
    my $opts = shift;

    my @opts = (
        'read','user',$opts->{form}{journal}, $opts->{form}{itemid}, 'comments', 
    );

    push @opts, $opts->{form}{thread}
        if $opts->{form}{thread};

    push @opts, 'reply';

    my $controller = LJ::Mob::Controller::ReadPost->new;

    # emulating controller work
    if($opts->{form}{mobile_domain} =~ m!^0.$LJ::DOMAIN!) {
        if(my $location = $controller->check_access('zero', LJ::get_remote_ip())) {
            BML::redirect($location);
        }

        LJ::Request->notes(branding_id => 'zero');
    }

    # run controller
    my $controller = LJ::Mob::Controller::ReadPost->new;
    $controller->_user(LJ::get_remote());
    my $res = $controller->reply(\@opts);

    return $res->output
        if ref($res) eq 'LJ::Mob::Response::AuthRequired';

    # passing error messages
    $res->template->param(
        errors          => [map { { 'error' => $_ } } @{ $opts->{errors} }],    
    );
    
    # and get ready html code
    return $res->output_html;
}

# <LJFUNC>
# name: LJ::record_anon_comment_ip
# class: web
# des: Records the IP address of an anonymous comment.
# args: journalu, jtalkid, ip
# des-journalu: User object of journal comment was posted in.
# des-jtalkid: ID of this comment.
# des-ip: IP address of the poster.
# returns: 1 for success, 0 for failure
# </LJFUNC>
sub record_anon_comment_ip {
    my ($journalu, $jtalkid, $ip) = @_;
    $journalu = LJ::want_user($journalu);
    $jtalkid += 0;
    return 0 unless LJ::isu($journalu) && $jtalkid && $ip;

    $journalu->do("INSERT INTO tempanonips (reporttime, journalid, jtalkid, ip) VALUES (UNIX_TIMESTAMP(),?,?,?)",
                  undef, $journalu->{userid}, $jtalkid, $ip);
    return 0 if $journalu->err;
    return 1;
}

# <LJFUNC>
# name: LJ::mark_comment_as_spam
# class: web
# des: Copies a comment into the global [dbtable[spamreports]] table.
# args: journalu, jtalkid
# des-journalu: User object of journal comment was posted in.
# des-jtalkid: ID of this comment.
# returns: 1 for success, 0 for failure
# </LJFUNC>
sub mark_comment_as_spam {
    my ($journalu, $jtalkid) = @_;
    $journalu = LJ::want_user($journalu);
    $jtalkid += 0;
    return 0 unless $journalu && $jtalkid;

    my $dbcr = LJ::get_cluster_def_reader($journalu);
    my $dbh = LJ::get_db_writer();

    # step 1: get info we need
    my $row = LJ::Talk::get_talk2_row($dbcr, $journalu->{userid}, $jtalkid);
    my $temp = LJ::get_talktext2($journalu, $jtalkid);
    my ($subject, $body, $posterid) = ($temp->{$jtalkid}[0], $temp->{$jtalkid}[1], $row->{posterid});
    return 0 unless ($body && $body ne '');

    # can't mark your own comments as spam.
    return 0 if $posterid && $posterid == $journalu->id;

    LJ::run_hooks('spam_comment', $journalu->userid, $row->{nodeid}, $jtalkid);

    # step 2a: if it's a suspended user, don't add, but pretend that we were successful
    if ($posterid) {
    	my $posteru = LJ::want_user($posterid);
    	return 1 if $posteru->is_suspended;
    }

    # step 2b: if it was an anonymous comment, attempt to get comment IP to make some use of the report
    my $ip;
    unless ($posterid) {
        $ip = $dbcr->selectrow_array('SELECT ip FROM tempanonips WHERE journalid=? AND jtalkid=?',
                                      undef, $journalu->{userid}, $jtalkid);
        return 0 if $dbcr->err;

        # we want to fail out if we have no IP address and this is anonymous, because otherwise
        # we have a completely useless spam report.  pretend we were successful, too.
        return 1 unless $ip;

        # we also want to log this attempt so that we can do some throttling
        my $rates = LJ::MemCache::get("spamreports:anon:$ip") || $RATE_DATAVER;
        $rates .= pack("N", time);
        LJ::MemCache::set("spamreports:anon:$ip", $rates);
    }

    # step 3: insert into spamreports
    $dbh->do('INSERT INTO spamreports (reporttime, posttime, ip, journalid, posterid, subject, body) ' .
             'VALUES (UNIX_TIMESTAMP(), UNIX_TIMESTAMP(?), ?, ?, ?, ?, ?)',
             undef, $row->{datepost}, $ip, $journalu->{userid}, $posterid, $subject, $body);
    return 0 if $dbh->err;
    return 1;
}

# <LJFUNC>
# name: LJ::Talk::get_talk2_row
# class: web
# des: Gets a row of data from [dbtable[talk2]].
# args: dbcr, journalid, jtalkid
# des-dbcr: Database handle to read from.
# des-journalid: Journal id that comment is posted in.
# des-jtalkid: Journal talkid of comment.
# returns: Hashref of row data, or undef on error.
# </LJFUNC>
sub get_talk2_row {
    my ($dbcr, $journalid, $jtalkid) = @_;
    return $dbcr->selectrow_hashref('SELECT journalid, jtalkid, nodetype, nodeid, parenttalkid, ' .
                                    '       posterid, datepost, state ' .
                                    'FROM talk2 WHERE journalid = ? AND jtalkid = ?',
                                    undef, $journalid+0, $jtalkid+0);
}

# <LJFUNC>
# name: LJ::Talk::get_talk2_row_multi
# class: web
# des: Gets multiple rows of data from [dbtable[talk2]].
# args: items
# des-items: Array of arrayrefs; each arrayref: [ journalu, jtalkid ].
# returns: Array of hashrefs of row data, or undef on error.
# </LJFUNC>
sub get_talk2_row_multi {
    my (@items) = @_; # [ journalu, jtalkid ], ...
    croak("invalid items for get_talk2_row_multi")
        if grep { ! LJ::isu($_->[0]) || @$_ != 2 } @items;

    # what do we need to load per-journalid
    my %need    = (); # journalid => { jtalkid => 1, ... }
    my %have    = (); # journalid => { jtalkid => $row_ref, ... }
    my %cluster = (); # cid => { jid => journalu, jid => journalu }

    # first, what is in memcache?
    my @keys = ();
    foreach my $it (@items) {
        my ($journalu, $jtalkid) = @$it;

        # can't load comments in purged users' journals
        next if $journalu->is_expunged;

        my $cid = $journalu->clusterid;
        my $jid = $journalu->id;

        # we need this for now
        $need{$jid}->{$jtalkid} = 1;

        # which cluster is this user on?
        $cluster{$cid}->{$jid} = $journalu;

        push @keys, LJ::Talk::make_talk2row_memkey($jid, $jtalkid);
    }

    # return an array of rows preserving order in which they were requested
    my $ret = sub {
        my @ret = ();
        foreach my $it (@items) {
            my ($journalu, $jtalkid) = @$it;
            push @ret, $have{$journalu->id}->{$jtalkid};
        }

        return @ret;
    };

    my $mem = LJ::MemCache::get_multi(@keys);
    if ($mem) {
        while (my ($key, $array) = each %$mem) {
            my (undef, $jid, $jtalkid) = split(":", $key);
            my $row = LJ::MemCache::array_to_hash("talk2row", $array);
            next unless $row;

            # add in implicit keys:
            $row->{journalid} = $jid;
            $row->{jtalkid}   = $jtalkid;

            # update our needs
            $have{$jid}->{$jtalkid} = $row;
            delete $need{$jid}->{$jtalkid};
            delete $need{$jid} unless %{$need{$jid}}
        }

        # was everything in memcache?
        return $ret->() unless %need;
    }

    # uh oh, we have things to retrieve from the db!
  CLUSTER:
    foreach my $cid (keys %cluster) {

        # build up a valid where clause for this cluster's select
        my @vals = ();
        my @where = ();
        foreach my $journalu (values %{$cluster{$cid}}) {
            my $jid = $journalu->id;
            my @jtalkids = keys %{$need{$jid}};
            next unless @jtalkids;

            my $bind = join(",", map { "?" } @jtalkids);
            push @where, "(journalid=? AND jtalkid IN ($bind))";
            push @vals, $jid => @jtalkids;
        }
        # is there anything to actually query for this cluster?
        next CLUSTER unless @vals;

        my $dbcr = LJ::get_cluster_reader($cid)
            or die "unable to get cluster reader: $cid";

        my $where = join(" OR ", @where);
        my $sth = $dbcr->prepare
            ("SELECT journalid, jtalkid, nodetype, nodeid, parenttalkid, " .
             "       posterid, datepost, state " .
             "FROM talk2 WHERE $where");
        $sth->execute(@vals);

        while (my $row = $sth->fetchrow_hashref) {
            my $jid = $row->{journalid};
            my $jtalkid = $row->{jtalkid};

            # update our needs
            $have{$jid}->{$jtalkid} = $row;
            delete $need{$jid}->{$jtalkid};
            delete $need{$jid} unless %{$need{$jid}};

            # update memcache
            LJ::Talk::add_talk2row_memcache($jid, $jtalkid, $row);
        }
    }

    return $ret->();
}

sub make_talk2row_memkey {
    my ($jid, $jtalkid) = @_;
    return [ $jid, join(":", "talk2row", $jid, $jtalkid) ];
}

sub add_talk2row_memcache {
    my ($jid, $jtalkid, $row) = @_;

    my $memkey = LJ::Talk::make_talk2row_memkey($jid, $jtalkid);
    my $exptime = 60*30;
    my $array = LJ::MemCache::hash_to_array("talk2row", $row);

    return LJ::MemCache::add($memkey, $array, $exptime);
}

sub invalidate_comment_cache {
    my ($jid, $nodeid, @jtalkids) = @_;

    ## invalidate cache with all commments for this entry
    LJ::MemCache::delete([$jid, "talk2:$jid:L:$nodeid"]);
 
    ## and invalidate all individual caches for each comment
    foreach my $jtalkid (@jtalkids) {
        LJ::MemCache::delete([ $jid, "talk2row:$jid:$jtalkid" ]);
    }

    ## and invalidate items for "/tools/recent_comments.bml" page
    LJ::MemCache::delete([$jid, "rcntalk:$jid" ]);

    return 1;
}

# get a comment count for a journal entry.
sub get_replycount {
    my ($ju, $jitemid) = @_;
    $jitemid += 0;
    return undef unless $ju && $jitemid;

    my $memkey = LJ::Entry::reply_count_memkey($ju, $jitemid);
    my $count = LJ::MemCache::get($memkey);
    return $count if $count;

    my $dbcr = LJ::get_cluster_def_reader($ju);
    return unless $dbcr;

    $count = $dbcr->selectrow_array("SELECT replycount FROM log2 WHERE " .
                                    "journalid=? AND jitemid=?", undef,
                                    $ju->{'userid'}, $jitemid) || 0;
    LJ::MemCache::add($memkey, $count);
    return $count;
}

# <LJFUNC>
# name: LJ::Talk::get_thread_html
# input: $u - LJ::User object of viewing journal;
#        $up - LJ::User object of user posted journal item;
#        $entry - LJ::Entry object of viewing post;
#        $thread - thread id;
#        $input - hashref of input parameters:
#            viewsome
#            viewall
#            view
#            page
#            expand        : 'all'
#            LJ_cmtinfo    : hashref, where to put loaded comments data;
#            format        : 'light'
#            style         : 'mine'
#            showmultiform
#            nohtml
#            show_expand_collapse : BOOLEAN - if true, all comments have "Expand" and "Collapse" link. Otherwise only "Expand" link, if collapsed or has collapsed children;
#            get_root_only : retrieve only root of requested thread subtree;
#            depth         : initial depth of requested thread (0, if not specified);
#            talkid
#            mode
#            from_rpc      : if from /tools/endpoints/get_thread.bml then 1 else 0
#        $output - hashref of output parameters:
#            error
#            page
#            pages
#            multiform_selects
#
# returns: Arrayref of hashrefs:
# 
# </LJFUNC>
sub get_thread_html
{
    my ($u, $up, $entry, $thread, $input, $output) = @_;

    my $remote = LJ::get_remote();

    my $tz_remote;
    my $s2_ctx = [];  # ghetto fake S2 context object
    if ($remote) {
        $tz_remote = $remote->prop('timezone') || undef;
    }    

    my $viewsome = $input->{viewsome};
    my $viewall = $input->{viewall};

    my $view_arg = $input->{view} || "";
    my $flat_mode = ($view_arg =~ /\bflat\b/);
    my $view_num = ($view_arg =~ /(\d+)/) ? $1 : undef;

    my %user;
    my %userpics;

    my $opts = {
        flat        => $flat_mode,
        thread      => $thread,
        page        => $input->{page},
        view        => $view_num,
        userpicref  => \%userpics,
        userref     => \%user,
        up          => $up,
        viewall     => $viewall,
        init_comobj => 0,
        showspam    => $input->{mode} eq 'showspam' && LJ::is_enabled('spam_button')
                       && LJ::Talk::can_unmark_spam($remote, $u, $up) && !$input->{from_rpc},
        expand_all  => 0,
    };

    ## Expand all comments on page
    unless ($LJ::DISABLED{allow_expand_all_comments}) {
        $opts->{expand_all} = 1 if $input->{expand} eq 'all';
    }

    ## allow to modify strategies to load/expand comments tree.
    LJ::run_hooks('load_comments_opts', $u, $entry->jitemid, $opts);

    my @comments = LJ::Talk::load_comments($u, $remote, "L", $entry->jitemid, $opts);
        
    if ($opts->{'out_error'} eq "nodb")
    {
        $output->{error} = BML::ml('error.nodbmaintenance');
        return undef;
    }

    $output->{page} = $opts->{out_page};
    $output->{pages} = $opts->{out_pages};

    ##################################################
        
    my $LJ_cmtinfo = $input->{LJ_cmtinfo};

    my $formatlight = $input->{'format'} eq 'light' ? 'format=light' : '';
    my $stylemine = $input->{'style'} eq "mine" ? "style=mine" : "";
        
    my ($last_talkid, $last_jid) = LJ::get_lastcomment();
        
    my $fmt_time_short = "%%hh%%:%%min%% %%a%%m";
    my $jarg = "journal=$u->{'user'}&";
    my $jargent ="journal=$u->{'user'}&amp;";
    my $allow_commenting = $entry->posting_comments_allowed;
    my $pics = LJ::Talk::get_subjecticons();
    my $talkurl = LJ::journal_base($u) . "/" . $entry->ditemid() . ".html";
    my $showmultiform = $input->{showmultiform};
    my $anum = $entry->anum();

    my $comments = [];

    my $recurse_post = sub {

        my ($self, $post, $depth) = @_;
        $depth ||= 0;
        
        my $tid = $post->{'talkid'};
        my $dtid = $tid * 256 + $anum;
        my $thread_url = LJ::Talk::talkargs($talkurl, "thread=$dtid", $stylemine, $formatlight) . "#t$dtid";
        my $LJci = $LJ_cmtinfo->{$dtid} = { rc => [], u => '', full => $post->{_loaded}, depth => $depth };

        my $s2_datetime = $tz_remote ?
            LJ::S2::DateTime_tz($post->{'datepost_unix'}, $tz_remote) :
            LJ::S2::DateTime_unix($post->{'datepost_unix'});

        my $datepost = S2::Builtin::LJ::Date__date_format($s2_ctx, $s2_datetime, "iso") . " " .
                       S2::Builtin::LJ::DateTime__time_format($s2_ctx, $s2_datetime, $fmt_time_short) .
                       ($tz_remote ? " (local)" : " UTC");

        my $bgcolor = ($depth % 2) ? "emcolorlite" : "emcolor";
        $bgcolor = BML::get_template_def($bgcolor);
        if ($post->{'state'} eq "S") {
            $bgcolor = BML::get_template_def("screenedbarcolor") || $bgcolor;
        } elsif ($post->{'state'} eq "B" && LJ::is_enabled('spam_button')) {
            $bgcolor = BML::get_template_def("spamedbarcolor") || $bgcolor;
        } elsif ($last_talkid == $dtid && $last_jid == $u->{'userid'}) {
            $bgcolor = BML::get_template_def("altcolor1");
        }

        my $pu = $post->{'posterid'} ? $user{$post->{'posterid'}} : undef;
        $LJci->{u} = $pu->{$pu->{journaltype} eq 'I' ? 'name' : 'user'} if $pu;
        $LJci->{username} = $pu->{'user'} if $pu;

        my $userpost = $post->{'userpost'};
        my $upost    = $post->{'upost'};

        my $user;
        if ($post->{'props'}->{'deleted_poster'}) {
            $user = BML::ml('.deleteduser', { username => $post->{'deleted_poster'} });
        } else {
            $user = BML::ml('.anonuser');
        }

        my $comment_header = sub {
            my $table_style = shift || '';
            $table_style = ' ' . $table_style if $table_style;

            my $width = $depth * 25;

            return "<div id='ljcmt$dtid'><a name='t$dtid'></a><table$table_style><tr>" .
                   "<td><img src='$LJ::IMGPREFIX/dot.gif' height='1' width='$width'></td>" .
                   "<td id='ljcmtxt$dtid' width='100%'>";
        };

        my $comment_footer = sub {
            return "</td></tr></table></div>\n";
        };

        my $html = {};
        my $state;
                
        if ($post->{'state'} eq "D") ## LJSUP-6433
        {
            $state = 'deleted';
            $html->{header} = $comment_header->();
            $html->{text}   = BML::ml('.deletedpost');
            $html->{footer} = $comment_footer->();
        }
        elsif ($post->{'state'} eq "S" && !$post->{'_loaded'} && !$post->{'_show'})
        {
            $state = 'screened';
            $html->{header} = $comment_header->();
            $html->{text}   = BML::ml('.screenedpost');
            $html->{footer} = $comment_footer->();
        }
        elsif ($post->{'state'} ne 'B' && $opts->{'showspam'}) {
            $html->{text} = undef;
        }
        elsif ($post->{'state'} eq 'B' && !$opts->{'showspam'} && !($remote && $remote->user eq (ref $userpost ? $userpost->{'user'} : $userpost))) 
        {
            $state = 'spamed';
            if ($post->{'_show'}) { 
                $html->{header} = $comment_header->();
                $html->{text}   = BML::ml('.spamedpost');
                $html->{footer} = $comment_footer->();
            } else {
                $html->{text} = undef;
            }
        }
        elsif ($pu && $pu->is_suspended && !$viewsome)
        {
            $state = 'suspended';
            $html->{header} = $comment_header->();
            $html->{footer} = $comment_footer->();

            my $text = BML::ml('.replysuspended');
            if (LJ::Talk::can_delete($remote, $u, $up, $userpost)) {
                $text .= " <a href='$LJ::SITEROOT/delcomment.bml?${jargent}id=$dtid'>" .
                         LJ::img("btn_del", "", { 'align' => 'absmiddle', 'hspace' => 2, 'vspace' => }) .
                         "</a>";
            }
            if ($post->{state} ne 'F' && LJ::Talk::can_freeze($remote, $u, $up, $userpost)) {
                $text .= "<a href='$LJ::SITEROOT/talkscreen.bml?mode=freeze&amp;${jargent}talkid=$dtid'>" .
                         LJ::img("btn_freeze", "", { align => 'absmiddle', hspace => 2, vspace => }) .
                         "</a>";
            }
            if ($post->{state} eq 'F' && LJ::Talk::can_unfreeze($remote, $u, $up, $userpost)) {
                $text .= "<a href='$LJ::SITEROOT/talkscreen.bml?mode=unfreeze&amp;${jargent}talkid=$dtid'>" .
                         LJ::img("btn_unfreeze", "", { align => 'absmiddle', hspace => 2, vspace => }) .
                         "</a>";
            }
               
            $html->{text} = $text;
        }
        else
        {
            $user = LJ::ljuser($upost, { side_alias => 1 }) if $upost;
                
            my $icon = LJ::Talk::show_image($pics, $post->{'props'}->{'subjecticon'});

            my $get_expand_link = sub {
                return
                    "<span id='expand_$dtid'>" . 
                        " (<a href='$thread_url' onclick=\"ExpanderEx.make(event,this,'$thread_url','$dtid',true)\">" .
                            BML::ml('talk.expandlink') .
                        "</a>)" .
                    "</span>";
            };

            my $get_collapse_link = sub {
                return
                    "<span id='collapse_$dtid'>" .
                        " (<a href='$thread_url' onclick=\"ExpanderEx.collapse(event,this,'$thread_url','$dtid',true)\">" .
                            BML::ml('talk.collapselink') .
                        "</a>)" .
                    "</span>";
            };

            if ($post->{'_loaded'})
            {
                $state = 'expanded';
                my $comment = LJ::Comment->new($u, dtalkid => $dtid);

                my $edittime;
                if ($comment->is_edited)
                {
                    my $s2_datetime_edittime = $tz_remote ?
                        LJ::S2::DateTime_tz($comment->edit_time, $tz_remote) :
                        LJ::S2::DateTime_unix($comment->edit_time);

                    $edittime = S2::Builtin::LJ::Date__date_format($s2_ctx, $s2_datetime_edittime, "iso") . " " .
                                S2::Builtin::LJ::DateTime__time_format($s2_ctx, $s2_datetime_edittime, $fmt_time_short) .
                                ($tz_remote ? " (local)" : " UTC");
                }

                $html->{header} = $comment_header->("width='100%' class='talk-comment'");
                $html->{footer} = $comment_footer->();
                    
                my $text = "<div id='cmtbar$dtid' class='talk-comment-head' style='background-color:$bgcolor'>";

                if (my $picid = $post->{'picid'}) {
                    my $alt = $pu->{'name'};
                    if ($post->{'props'}->{'picture_keyword'}) {
                        $alt .= ": $post->{'props'}->{'picture_keyword'}";
                    }
                    $alt = LJ::ehtml($alt);
                    my ($w, $h) = ($userpics{$picid}->{'width'}, $userpics{$picid}->{'height'});
                    $text .= "<img align='left' hspace='3' src='$LJ::USERPIC_ROOT/$picid/$post->{'posterid'}'";
                    $text .= " width='$w' title='$alt' alt='' height='$h' />";
                }

                my $cleansubject = LJ::ehtml($post->{'subject'});
                $text .= "<font size='+1' face='Arial,Helvetica'><b>$cleansubject</b></font> $icon";
                $text .= "<br />$user\n";
                $text .= "<br /><font size='-1'>$datepost</font>\n";
                if ($post->{'props'}->{'poster_ip'} &&
                    $remote && ($remote->{'user'} eq $up->{'user'} || $remote->can_manage($u) || $viewall))
                {
                    ## resolve IP to a location
                    my $ip   = $post->{'props'}->{'poster_ip'};
                    my $info = LJ::is_enabled('display_remote_location_on_comments_page')
                                ? LJ::GeoLocation->get_city_info_by_ip($ip)
                                : '';

                    if ($info and my $country = $info->{country_name} and my $city = $info->{city_name}){
                        ## Display location of an IP.
                        $text .= LJ::Lang::ml('.fromip.extended', { ip => $ip, country => $country, city => $city });
                    } else {
                        ## IP location is unknown 
                        $text .= LJ::Lang::ml('.fromip', { ip => $ip });
                    }
                }

                if ($post->{'state'} ne 'B') {
                    $text .= " <font size='-1'>(<a href='" .
                             LJ::Talk::talkargs($talkurl, "thread=$dtid", $formatlight) .
                             "#t$dtid' rel='nofollow'>" .
                             BML::ml('talk.commentpermlink') . "</a>)</font> ";
                }
                
                if ($comment->remote_can_edit) {
                    $text .= "<a href='" .
                             LJ::Talk::talkargs($comment->edit_url, $stylemine, $formatlight) .
                             "' rel='nofollow'>" .
                             LJ::img("editcomment", "", { 'align' => 'absmiddle', 'hspace' => 2, 'vspace' => }) . "</a>";
                }

                if (LJ::Talk::can_delete($remote, $u, $up, $userpost)) {
                    $text .= "<a href='$LJ::SITEROOT/delcomment.bml?${jargent}id=$dtid" .
                             ($opts->{'showspam'} ? '&spam=1' : '') . "' rel='nofollow'>" .
                             LJ::img("btn_del", "", { 'align' => 'absmiddle', 'hspace' => 2, 'vspace' => }) .
                             "</a>";
                }

                if ($post->{'state'} ne 'B' && LJ::Talk::can_marked_as_spam($remote, $u, $up, $userpost)) {
                    $text .= "<a href='$LJ::SITEROOT/delcomment.bml?${jargent}id=$dtid&spam=1' rel='nofollow'>" .
                             LJ::img("btn_spam", "", { 'align' => 'absmiddle', 'hspace' => 2, 'vspace' => }) .
                             "</a>";
                }

                if ($post->{'state'} eq 'B' && LJ::Talk::can_unmark_spam($remote, $u, $up, $userpost)) {
                    $text .= "<a href='$LJ::SITEROOT/spamcomment.bml?mode=unspam&amp;${jargent}talkid=$dtid' rel='nofollow'>" .
                             LJ::img("btn_unspam", "", { 'align' => 'absmiddle', 'hspace' => 2, 'vspace' => }) .
                             "</a>";
                }

                if ($post->{'state'} ne 'F' && ($LJ::DISABLED{'spam_button'} || $post->{'state'} ne 'B') && LJ::Talk::can_freeze($remote, $u, $up, $userpost)) {
                    $text .= "<a href='$LJ::SITEROOT/talkscreen.bml?mode=freeze&amp;${jargent}talkid=$dtid' rel='nofollow'>" .
                             LJ::img("btn_freeze", "", { align => 'absmiddle', hspace => 2, vspace => }) .
                             "</a>";
                }
                    
                if ($post->{'state'} eq 'F' && LJ::Talk::can_unfreeze($remote, $u, $up, $userpost)) {
                    $text .= "<a href='$LJ::SITEROOT/talkscreen.bml?mode=unfreeze&amp;${jargent}talkid=$dtid' rel='nofollow'>" .
                             LJ::img("btn_unfreeze", "", { align => 'absmiddle', hspace => 2, vspace => }) .
                             "</a>";
                }

                if ($post->{'state'} ne 'S' && ($LJ::DISABLED{'spam_button'} || $post->{'state'} ne 'B') && LJ::Talk::can_screen($remote, $u, $up, $userpost)) {
                    $text .= "<a href='$LJ::SITEROOT/talkscreen.bml?mode=screen&amp;${jargent}talkid=$dtid' rel='nofollow'>" .
                             LJ::img("btn_scr", "", { 'align' => 'absmiddle', 'hspace' => 2, 'vspace' => }) .
                             "</a>";
                }
                   
                if ($post->{'state'} eq 'S' && LJ::Talk::can_unscreen($remote, $u, $up, $userpost)) {
                    $text .= "<a href='$LJ::SITEROOT/talkscreen.bml?mode=unscreen&amp;${jargent}talkid=$dtid' rel='nofollow'>" .
                             LJ::img("btn_unscr", "", { 'align' => 'absmiddle', 'hspace' => 2, 'vspace' => }) .
                             "</a>";
                }

                if ($remote && $remote->can_use_esn && ($LJ::DISABLED{'spam_button'} || $post->{'state'} ne 'B')) {
                    my $track_img = 'track';

                    my $comment_watched = $remote->has_subscription(
                        event   => "JournalNewComment",
                        journal => $u,
                        arg2    => $comment->jtalkid,
                        require_active => 1,
                    );

                    if ($comment_watched) {
                        $track_img = 'track_active';
                    } else {
                        # see if any parents are being watched
                        while ($comment && $comment->valid && $comment->parenttalkid)
                        {
                            # check cache
                            $comment->{_watchedby} ||= {};
                            my $thread_watched = $comment->{_watchedby}->{$u->{userid}};

                            # not cached
                            if (!defined $thread_watched)
                            {
                                $thread_watched = $remote->has_subscription(
                                    event   => "JournalNewComment",
                                    journal => $u,
                                    arg2    => $comment->parenttalkid,
                                    require_active => 1,
                                );
                            }

                            $track_img = 'track_thread_active' if ($thread_watched);

                            # cache in this comment object if it's being watched by this user
                            $comment->{_watchedby}->{$u->{userid}} = $thread_watched;

                            $comment = $comment->parent;
                        }
                    }

                    my $track_url = "$LJ::SITEROOT/manage/subscriptions/comments.bml?journal=$u->{'user'}&amp;talkid=$dtid";
                    $text .= "<a href='$track_url' rel='nofollow'>" . LJ::img($track_img, '', {'align' => 'absmiddle'}) . "</a>";
                }

                if ($showmultiform) {
                    $text .= " <nobr><input type='checkbox' name='selected_$tid' id='s$tid' />";
                    $text .= " <label for='s$tid'>" . BML::ml('.select') . "</label></nobr>";
                    $output->{multiform_selects} = 1;
                }

                # Comment Posted Notice
                $text .= "<br /><b>" . BML::ml('.posted') . "</b>"
                    if $last_talkid == $dtid && $last_jid == $u->{'userid'};

                $text .= "</div><div class='talk-comment-box'>";

                LJ::CleanHTML::clean_comment(
                    \$post->{'body'},
                    {
                        preformatted => $post->{'props'}->{'opt_preformatted'},
                        anon_comment => (!$pu || $pu->{'journaltype'} eq 'I'),
                        nocss        => 1,
                        posterid     => ($pu ? $pu->userid : 0),
                    }
                );

                BML::ebml(\$post->{'body'});
                my $event = $post->{'body'};
    
                if ($input->{nohtml})
                {
                    # quote all non-LJ tags
                    $event =~ s{<(?!/?lj)(.*?)>} {&lt;$1&gt;}gi;
                }

                my $edit_html = $edittime
                                ? "<br /><br /><span class='ljedittime'><em>" .
                                    BML::ml('.edittime', { edittime => $edittime }) .
                                  "</em></span>"
                                : "";

                $text .= "$event$edit_html";

                $text .= "<p style='margin: 0.7em 0 0.2em 0'><font size='-2'>";

                if ($allow_commenting)
                {
                    my $replyurl = LJ::Talk::talkargs($talkurl, "replyto=$dtid", $stylemine, $formatlight);
                    if ($post->{'state'} eq 'F') {
                        $text .= "(" . BML::ml('talk.frozen') . ") ";
                    }
                    elsif ($remote) {
                        # See if we want to force them to change their password
                        my $bp = LJ::bad_password_redirect({ 'returl' => 1 });
                        if ($bp) {
                            $text .= "(<a href='$bp' rel='nofollow'>" . BML::ml('talk.replytothis') . "</a>) ";
                        }
                        else {
                            if ($post->{state} eq 'S') {
                                # show unscreen to reply link id comment screened
                                $text .= "(<a href='$LJ::SITEROOT/talkscreen.bml?mode=unscreen&amp;${jargent}talkid=$dtid'>" . BML::ml('talk.unscreentoreply') . "</a>) ";
                            }
                            else {
                                $text .= "(" . LJ::make_qr_link($dtid, $post->{'subject'}, BML::ml('talk.replytothis'), $replyurl) .  ") ";
                            }
                        }
                    }
                    else {
                        $text .= "(<a href='$replyurl' rel='nofollow'>" . BML::ml('talk.replytothis') . "</a>) ";
                    }
                }

                my $parentid = $post->{'parenttalkid'} || $post->{'parenttalkid_actual'};
                if ($parentid != 0) {
                    my $dpid = $parentid * 256 + $anum;
                    $text .= "(<a href='" . LJ::Talk::talkargs($talkurl, "thread=$dpid", $stylemine, $formatlight) . "#t$dpid' rel='nofollow'>" . BML::ml('talk.parentlink') . "</a>) ";
                }
   
                my $has_closed_children = 0;
                if ($post->{'children'} && @{$post->{'children'}}) {
                    $text .= "(<a href='$thread_url' rel='nofollow'>" . BML::ml('talk.threadlink') . "</a>) ";

                    if (grep {! $_->{_loaded} and !($_->{state} eq "D")} @{$post->{'children'}}) {
                        $has_closed_children = 1;
                    }
                }

                $LJci->{has_link} = ($has_closed_children ? 1 : 0);

                if (LJ::run_hook('show_thread_expander', { is_s1 => 1 })) {
                    if ($input->{'show_expand_collapse'}) {
                        $text .= $get_expand_link->() . $get_collapse_link->();
                    }
                    elsif ($has_closed_children) {
                        $text .= $get_expand_link->();
                    }
                }

                $text .= "</font></p>";
                $text .= LJ::make_qr_target($dtid) if $remote;
                $text .= "</div>";

                $html->{text} = $text;
            }
            else {
                $state = 'collapsed';

                # link to message
                $LJci->{has_link} = 1;
                    
                $html->{header} = $comment_header->();
                $html->{footer} = $comment_footer->();

                my $text = "<a href='$thread_url' rel='nofollow'>" . LJ::ehtml($post->{'subject'} || BML::ml('.nosubject')) . "</a> - $user, <i>$datepost</i> ";

                if (LJ::run_hook('show_thread_expander', { is_s1 => 1 })) {
                    $text .= ' ' . $get_expand_link->();
                }

                # Comment Posted Notice
                $text .= " - <b>" . BML::ml('.posted') . "</b>"
                    if $last_talkid == $dtid && $last_jid == $u->{'userid'};

                $html->{text} = $text;
            }
        }

        push @$comments, {
            thread => $dtid,
            depth  => $depth,
            html   => $html->{header} . $html->{text} . $html->{footer},
            state  => $state,
        };

        if (!$input->{get_root_only} && $post->{'children'}) {
            foreach my $childpost (@{$post->{'children'}}) {
                push @{$LJci->{rc}}, $childpost->{talkid} * 256 + $anum;
                $self->($self, $childpost, $depth + 1);
            }
        }
    };

    $recurse_post->($recurse_post, $_, $input->{depth} || 0) foreach @comments;

    return $comments;
}

1;

