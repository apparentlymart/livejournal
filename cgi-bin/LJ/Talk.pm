package LJ::Talk;
use strict;

use LJ::Constants;
use LJ::RateLimit qw//;
use Class::Autouse qw(
                      LJ::Event::JournalNewComment
                      LJ::Event::UserNewComment
                      LJ::Comment
                      LJ::EventLogRecord::NewComment
                      Captcha::reCAPTCHA
                      LJ::OpenID
                      );
use MIME::Words;
use Carp qw(croak);
use LJ::TimeUtil;
use LJ::Talk::Author;

use constant PACK_FORMAT => "NNNNC"; ## $talkid, $parenttalkid, $poster, $time, $state 

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
        my ($url, $piccode) = @_;
        return ("<a href=\"$url\">" .
                LJ::img($piccode, "", { 'align' => 'absmiddle' }) .
                "</a>");
    };

    my $jarg = "journal=$u->{'user'}&";
    my $jargent = "journal=$u->{'user'}&amp;";

    my $entry = LJ::Entry->new($u, ditemid => $itemid);

    # << Previous
    push @linkele, $mlink->("$LJ::SITEROOT/go.bml?${jargent}itemid=$itemid&amp;dir=prev", "prev_entry");
    $$headref .= "<link href='$LJ::SITEROOT/go.bml?${jargent}itemid=$itemid&amp;dir=prev' rel='Previous' />\n";

    # memories
    unless ($LJ::DISABLED{'memories'}) {
        push @linkele, $mlink->("$LJ::SITEROOT/tools/memadd.bml?${jargent}itemid=$itemid", "memadd");
    }

    # edit entry - if we have a remote, and that person can manage
    # the account in question, OR, they posted the entry, and have
    # access to the community in question
    if (defined $remote && (LJ::can_manage($remote, $u) ||
                            (LJ::u_equals($remote, $up) && LJ::can_use_journal($up->{userid}, $u->{user}, {}))))
    {
        push @linkele, $mlink->("$LJ::SITEROOT/editjournal.bml?${jargent}itemid=$itemid", "editentry");
    }

    # edit tags
    unless ($LJ::DISABLED{tags}) {
        if (defined $remote && LJ::Tags::can_add_entry_tags($remote, $entry)) {
            push @linkele, $mlink->("$LJ::SITEROOT/edittags.bml?${jargent}itemid=$itemid", "edittags");
        }
    }

    unless ($LJ::DISABLED{'sharethis'}) {
        my $entry_url = $entry->url;
        my $entry_title = LJ::ejs($entry->subject_html);
        push @linkele, $mlink->("javascript:void(0)", "sharethis") . qq|<script type="text/javascript">
            SHARETHIS.addEntry({url:'$entry_url', title: '$entry_title'}, {button: false})
                .attachButton(jQuery('a:last')[0]);
            </script>|
            if $entry->security eq 'public';
     }

    if ($remote && $remote->can_use_esn) {
        my $img_key = $remote->has_subscription(journal => $u, event => "JournalNewComment", arg1 => $itemid, require_active => 1) ?
            "track_active" : "track";
        push @linkele, $mlink->("$LJ::SITEROOT/manage/subscriptions/entry.bml?${jargent}itemid=$itemid", $img_key);
    }

    if ($remote && $remote->can_see_content_flag_button( content => $entry )) {
        my $flag_url = LJ::ContentFlag->adult_flag_url($entry);
        push @linkele, $mlink->($flag_url, 'flag');
    }


    ## Next
    push @linkele, $mlink->("$LJ::SITEROOT/go.bml?${jargent}itemid=$itemid&amp;dir=next", "next_entry");
    $$headref .= "<link href='$LJ::SITEROOT/go.bml?${jargent}itemid=$itemid&amp;dir=next' rel='Next' />\n";

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

        LJ::assert_is($ju->{user}, lc $journal);

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
            my $host = LJ::Request->header_in("Host");
            my $args = scalar LJ::Request->args;
            my $querysep = $args ? "?" : "";
            my $redir = LJ::eurl("http://" . $host . LJ::Request->uri . $querysep . $args);

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
                LJ::can_manage($remote, $u);
    return 0;
}

sub can_screen {
    my ($remote, $u, $up, $userpost) = @_;
    return 0 unless $remote;
    return 1 if $remote->{'user'} eq $u->{'user'} ||
                $remote->{'user'} eq (ref $up ? $up->{'user'} : $up) ||
                LJ::can_manage($remote, $u);
    return 0;
}

sub can_unscreen {
    return LJ::Talk::can_screen(@_);
}

sub can_view_screened {
    return LJ::Talk::can_delete(@_);
}

sub can_freeze {
    return LJ::Talk::can_screen(@_);
}

sub can_unfreeze {
    return LJ::Talk::can_unscreen(@_);
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
    return $journalu->{opt_whoscreened};
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
    my $num = LJ::delete_comments($u, "L", $jitemid, @$ids);
    LJ::replycount_do($u, $jitemid, "decr", $num);
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
    my $num = LJ::delete_comments($u, "L", $jitemid, @ids);
    LJ::replycount_do($u, $jitemid, "decr", $num);
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
    my $num = LJ::delete_comments($u, "L", $jitemid, $jtalkid);
    LJ::replycount_do($u, $jitemid, "decr", $num);
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

sub get_talk_data {
    my ($u, $nodetype, $nodeid, $opts) = @_;
    return undef unless LJ::isu($u);
    return undef unless $nodetype =~ /^\w$/;
    return undef unless $nodeid =~ /^\d+$/;
    my $uid = $u->id;

    # call normally if no gearman/not wanted
    my $gc = LJ::gearman_client();
    return get_talk_data_do($uid, $nodetype, $nodeid, $opts)
        unless $gc && LJ::conf_test($LJ::LOADCOMMENTS_USING_GEARMAN, $u->id);

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

# retrieves data from the talk2 table (but preferably memcache)
# returns a hashref (key -> { 'talkid', 'posterid', 'datepost', 'datepost_unix',
#                             'parenttalkid', 'state' } , or undef on failure
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
    my $rp_memkey = $nodetype eq "L" ? [$u->{'userid'}, "rp:$u->{'userid'}:$nodeid"] : undef;
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

        my $gc = LJ::gearman_client();
        if ($gc && LJ::conf_test($LJ::FIXUP_USING_GEARMAN, $u)) {
            $gc->dispatch_background("fixup_logitem_replycount",
                                     Storable::nfreeze([ $u->id, $nodeid ]), {
                                         uniq => "-",
                                     });
        } else {
            LJ::Talk::fixup_logitem_replycount($u, $nodeid);
        }
    };

    my $make_comment_singleton = sub {
        my ($jtalkid, $row) = @_;
        return 1 unless $init_comobj;
        return 1 unless $nodetype eq 'L';
        # at this point we have data for this comment loaded in memory
        # -- instantiate an LJ::Comment object as a singleton and absorb
        #    that data into the object
        my $comment = LJ::Comment->new($u, jtalkid => $jtalkid);
        # add important info to row
        $row->{nodetype} = $nodetype;
        $row->{nodeid}   = $nodeid;
        $comment->absorb_row(%$row);

        return 1;
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
        my $n = (length($packed) - 1) / $RECORD_SIZE;
        for (my $i=0; $i<$n; $i++) {
            my ($talkid, $par, $poster, $time, $state) = unpack(LJ::Talk::PACK_FORMAT, substr($packed,$i*$RECORD_SIZE+1,$RECORD_SIZE));

            $state = chr($state);
            $ret->{$talkid} = {
                talkid => $talkid,
                state => $state,
                posterid => $poster,
                datepost_unix => $time,
                datepost => LJ::TimeUtil->mysql_time($time),  # timezone surely fucked.  deprecated.
                parenttalkid => $par,
            };

            # instantiate comment singleton
            $make_comment_singleton->($talkid, $ret->{$talkid});

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
            $make_comment_singleton->($r->{talkid}, \%row_arg);

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

    my $rp_memkey = [$u->{'userid'}, "rp:$u->{'userid'}:$jitemid"];
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
        $u->do("LOCK TABLES log2 WRITE, talk2 READ");
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

    my $n = $u->{'clusterid'};
    my $viewall = $opts->{viewall};

    my $gtd_opts = {init_comobj => $opts->{init_comobj}};
    my $posts = get_talk_data($u, $nodetype, $nodeid, $gtd_opts);  # hashref, talkid -> talk2 row, or undef
    unless ($posts) {
        $opts->{'out_error'} = "nodb";
        return;
    }
    my %users_to_load;  # userid -> 1
    my @posts_to_load;  # talkid scalars
    my %children;       # talkid -> [ childenids+ ]

    my $uposterid = $opts->{'up'} ? $opts->{'up'}->{'userid'} : 0;

    my $post_count = 0;
    {
        my %showable_children;  # $id -> $count

        foreach my $post (sort { $b->{'talkid'} <=> $a->{'talkid'} } values %$posts) {

            # kill the threading in flat mode
            if ($opts->{'flat'}) {
                $post->{'parenttalkid_actual'} = $post->{'parenttalkid'};
                $post->{'parenttalkid'} = 0;
            }

            # see if we should ideally show it or not.  even if it's
            # zero, we'll still show it if it has any children (but we won't show content)
            my $should_show = $post->{'state'} eq 'D' ? 0 : 1;
            unless ($viewall) {
                $should_show = 0 if
                    $post->{'state'} eq "S" && ! ($remote && ($remote->{'userid'} == $u->{'userid'} ||
                                                              $remote->{'userid'} == $uposterid ||
                                                              $remote->{'userid'} == $post->{'posterid'} ||
                                                              LJ::can_manage($remote, $u) ));
            }
            $post->{'_show'} = $should_show;
            $post_count += $should_show;

            # make any post top-level if it says it has a parent but it isn't
            # loaded yet which means either a) row in database is gone, or b)
            # somebody maliciously/accidentally made their parent be a future
            # post, which could result in an infinite loop, which we don't want.
            $post->{'parenttalkid'} = 0
                if $post->{'parenttalkid'} && ! $posts->{$post->{'parenttalkid'}};

            $post->{'children'} = [ map { $posts->{$_} } @{$children{$post->{'talkid'}} || []} ];

            # increment the parent post's number of showable children,
            # which is our showability plus all those of our children
            # which were already computed, since we're working new to old
            # and children are always newer.
            # then, if we or our children are showable, add us to the child list
            my $sum = $should_show + $showable_children{$post->{'talkid'}};
            if ($sum) {
                $showable_children{$post->{'parenttalkid'}} += $sum;
                unshift @{$children{$post->{'parenttalkid'}}}, $post->{'talkid'};
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
    my $max_subjects = $LJ::TALK_MAX_SUBJECTS || 200;
    my $threading_point = $LJ::TALK_THREAD_POINT || 50;

    # we let the page size initially get bigger than normal for awhile,
    # but if it passes threading_point, then everything's in page_size
    # chunks:
    $page_size = $threading_point if $post_count < $threading_point;

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
    my $itemlast = $page==$pages ? $top_replies : ($page_size * $page);

    @top_replies = @top_replies[$itemfirst-1 .. $itemlast-1];

    push @posts_to_load, @top_replies;

    # mark child posts of the top-level to load, deeper
    # and deeper until we've hit the page size.  if too many loaded,
    # just mark that we'll load the subjects;
    my @check_for_children = @posts_to_load;

    ## expand first reply to top-level comments
    ## %expand_children - list of comments, children of which are to expand
    my %expand_children = map { $_ => 1 } @top_replies;

    ## new strategy to expand comments: by level 
    if ($opts->{expand_strategy} eq 'by_level' and $opts->{expand_level} > 1) {
        my $expand = sub {
            my ($fun, $cur_level, $item_ids) = @_;
            next if $cur_level >= $opts->{expand_level};

            foreach my $itemid (@$item_ids){
                $expand_children{$itemid} = 1;
                next unless $children{$itemid};

                ## expand next level it there are comments
                $fun->($fun, $cur_level+1, $children{$itemid});
            }
        };

        ## go through first level
        foreach my $itemid (keys %expand_children){
            next unless $children{$itemid};
            ## expand next (second) level
            $expand->($expand, 2, $children{$itemid});
        }
    }

    my (@subjects_to_load, @subjects_ignored);
    while (@check_for_children) {
        my $cfc = shift @check_for_children;
        next unless defined $children{$cfc};
        foreach my $child (@{$children{$cfc}}) {
            if (@posts_to_load < $page_size || $expand_children{$cfc} || $opts->{expand_all}) {
                push @posts_to_load, $child;
                ## expand only the first child (unless 'by_level' strategy is in use), 
                ## then clear the flag
                delete $expand_children{$cfc}
                    unless $opts->{expand_strategy} eq 'by_level';
            }
            elsif (@posts_to_load < $page_size) {
                push @posts_to_load, $child;
            } else {
                if (@subjects_to_load < $max_subjects) {
                    push @subjects_to_load, $child;
                } else {
                    push @subjects_ignored, $child;
                }
            }
            push @check_for_children, $child;
        }
    }

    $opts->{'out_pages'} = $pages;
    $opts->{'out_page'} = $page;
    $opts->{'out_itemfirst'} = $itemfirst;
    $opts->{'out_itemlast'} = $itemlast;
    $opts->{'out_pagesize'} = $page_size;
    $opts->{'out_items'} = $top_replies;

    # load text of posts
    my ($posts_loaded, $subjects_loaded);
    $posts_loaded = LJ::get_talktext2($u, @posts_to_load);
    $subjects_loaded = LJ::get_talktext2($u, {'onlysubjects'=>1}, @subjects_to_load) if @subjects_to_load;
    foreach my $talkid (@posts_to_load) {
        next unless $posts->{$talkid}->{'_show'};
        $posts->{$talkid}->{'_loaded'} = 1;
        $posts->{$talkid}->{'subject'} = $posts_loaded->{$talkid}->[0];
        $posts->{$talkid}->{'body'} = $posts_loaded->{$talkid}->[1];
        $users_to_load{$posts->{$talkid}->{'posterid'}} = 1;
    }
    foreach my $talkid (@subjects_to_load) {
        next unless $posts->{$talkid}->{'_show'};
        $posts->{$talkid}->{'subject'} = $subjects_loaded->{$talkid}->[0];
        $users_to_load{$posts->{$talkid}->{'posterid'}} ||= 0.5;  # only care about username
    }
    foreach my $talkid (@subjects_ignored) {
        next unless $posts->{$talkid}->{'_show'};
        $posts->{$talkid}->{'subject'} = "...";
        $users_to_load{$posts->{$talkid}->{'posterid'}} ||= 0.5;  # only care about username
    }

    # load meta-data
    {
        my %props;
        LJ::load_talk_props2($u->{'userid'}, \@posts_to_load, \%props);
        foreach (keys %props) {
            next unless $posts->{$_}->{'_show'};
            $posts->{$_}->{'props'} = $props{$_};
        }
    }

    if ($LJ::UNICODE) {
        foreach (@posts_to_load) {
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
            if ($up && $up->is_deleted) {
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
            foreach my $talkid (@posts_to_load) {
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
    return map { $posts->{$_} } @top_replies;
}

# XXX these strings should be in talk, but moving them means we have
# to retranslate.  so for now we're just gonna put it off.
my $SC = '/talkpost_do.bml';

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
    my $is_friend = LJ::is_friend( $journalu, $remote );
    my $remote_can_comment = $entry->registered_can_comment
        || ( $remote and $is_friend );

    return "You cannot edit this comment."
        if $editid && !$is_person;

    my $template = LJ::HTML::Template->new(
        { use_expr => 1 },    # force HTML::Template::Pro with Expr support
        filename          => "$ENV{'LJHOME'}/templates/CommentForm/Form.tmpl",
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
    foreach my $author_class (LJ::Talk::Author->all) {
        next unless $author_class->enabled;

        my $params = $author_class->display_params($opts);
        $params->{'short_code'} = $author_class->short_code;
        push @author_options, $params;
    }

    # from registered user or anonymous?
    my $screening = LJ::Talk::screening_level( $journalu, $entry->jitemid );

    my $willscreen;
    if ( $screening eq 'A' ) {
        $willscreen = 1;
    }
    elsif ( $screening eq 'F' ) {
        $willscreen = !( $remote && $is_person && $is_friend );
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
                'userpic_keyword'  => $pickw,
                'userpic_title'    => $pickw,
                'userpic_selected' => $pickw eq
                    $form->{'prop_picture_keyword'},
                };
        }

        foreach my $i (1 .. $res{'pickw_count'}) {
            $userpicmap{$res{"pickw_$i"}} = $res{"pickwurl_$i"};
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
                {   'theme' => 'white',
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

        $show_logips      = 1;
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
                . ( $is_person ? 'friends' : 'members' ) . 'only',
            { 'username' => '<b>' . $journalu->username . '</b>', }
        ),
        'notafriend' => LJ::Lang::ml(
            '/talkpost_do.bml.error.nota'
                . ( $is_person ? 'friend' : 'member' ),
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

        # various checks
        'remote_banned'          => LJ::is_banned( $remote, $journalu ),
        'everyone_can_comment'   => $entry->everyone_can_comment,
        'registered_can_comment' => $entry->registered_can_comment,
        'friends_can_comment'    => $entry->friends_can_comment,
        'is_public'              => $entry->is_public,
        'is_person'              => $is_person,
        'is_identity'            => $remote && $remote->is_identity,
        'remote_can_comment'     => $remote_can_comment,

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

        'form_intro'                => $form_intro,
        'errors'                    => \@errors_show,
        'tosagree'                  => $html_tosagree,

        'basesubject'           => $basesubject,
        'author_options'        => \@author_options,

        'extra_rows'            => LJ::run_hook('extra_talkform_rows', {
            'entry'     => $entry,
            'editid'    => $editid,
        }),
    );

    return $template->output;
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

    my $memkey = [$ju->{'userid'}, "rp:$ju->{'userid'}:$jitemid"];
    my $count = LJ::MemCache::get($memkey);
    return $count if $count;

    my $dbcr = LJ::get_cluster_def_reader($ju);
    return unless $dbcr;

    $count = $dbcr->selectrow_array("SELECT replycount FROM log2 WHERE " .
                                    "journalid=? AND jitemid=?", undef,
                                    $ju->{'userid'}, $jitemid);
    LJ::MemCache::add($memkey, $count);
    return $count;
}

1;
