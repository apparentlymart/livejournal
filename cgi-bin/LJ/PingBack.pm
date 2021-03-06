package LJ::PingBack;
use strict;
use LJ::Entry;
use LJ::Subscription;
use LJ::Event;
use LJ::NotificationMethod;
use Digest::MD5 qw/md5_hex/;

# Add comment to pinged post, if allowed.
# returns comment object in success,
# error string otherwise.
sub ping_post {
    my $class = shift;
    my %args  = @_;
    my $targetURI = $args{targetURI};
    my $sourceURI = $args{sourceURI};
    my $context   = $args{context};
    my $title     = $args{title};

    #
    my $target_entry = LJ::Entry->new_from_url($targetURI);

    unless ($target_entry) {
        warn "Unknown entry: $targetURI";
        return "Unknown entry";
    }

    # empty object means, that sourceURI is not LJ.com's page.
    # it's an usual case.
    my $source_entry = LJ::Entry->new_from_url($sourceURI);

    # can we add pingback comment to post?
    return "pingbacks are forbidden for the target."
        unless $class->should_entry_recieve_pingback($target_entry, $source_entry);

    #
    return "no pingback notifications between posts of the same journal"
        if $source_entry and $source_entry->journalid eq $target_entry->journalid;

    return "no pingback notifications between posts of the same user"
        if $source_entry and $source_entry->posterid eq $target_entry->posterid;

    my $poster_u = LJ::load_user($LJ::PINGBACK->{comments_bot_username});

    unless ($poster_u){
        warn "Pingback bot user does not exists";
        return "Pingback bot user does not exists";
    }

    #
    my $subject = $source_entry
                    ? ($source_entry->subject_raw || LJ::Lang::ml("pingback.sourceURI.default_title"))
                    : ($title || LJ::Lang::ml("pingback.sourceURI.default_title"));

    my $journal = $target_entry->journal;
    LJ::load_user_props($journal, 'browselang');
    my $lang    = $journal->{'browselang'};

    my $comment = LJ::Comment->create(
        state   => 'S', # this comment should be 'Screened'
        journal => $journal,
        ditemid => $target_entry->ditemid,
        poster  => $poster_u,

        body    => ($source_entry
            ? LJ::Lang::get_text(
                $lang,
                "pingback.ljping.comment.text",
                undef,
                {
                    context   => $context,
                    subject   => $subject,
                    sourceURI => $sourceURI,
                    poster    => $source_entry->poster->username,
              })
            : LJ::Lang::ml(
                $lang,
                "pingback.public.comment.text",
                undef,
                {
                    sourceURI => $sourceURI,
                    title     => $subject,
                    context   => $context
              })
        ),
        subject => $subject,
        props   => { picture_keyword => $LJ::PINGBACK->{userpic} },
    );

    LJ::Talk::screen_comment($journal, $target_entry->jitemid, $comment->jtalkid)
        if ref $comment;

    return $comment;
}

sub notify_about_reference {
    my $class = shift;
    my %args  = @_;
    my $ref_usr    = $args{user};
    my $source_uri = $args{source_uri};
    my $context    = $args{context};
    my $comment    = $args{comment};
    my $target_entry = LJ::Entry->new_from_url($source_uri);
    my $poster = $comment ? LJ::load_userid($comment->{posterid}) : LJ::load_userid($target_entry->posterid);
    $source_uri = $source_uri . '?thread=' . $comment->{dtalkid} . '#t' . $comment->{dtalkid} if $comment;

    my @send_list;
    my %union = ();

    if ( $ref_usr->is_community() ) {
        my $prop_pingback = $ref_usr->prop('pingback') || 'O';
        return if $prop_pingback eq 'D';

        my @maintainers = @{LJ::load_rel_user_cache($ref_usr->{userid}, 'A')};
        my @owner = @{LJ::load_rel_user_cache($ref_usr->{userid}, 'S')};

        #find union mainteiners and owners
        foreach my $m (@maintainers) { $union{$m} = 1; }
        foreach my $o (@owner) { $union{$o} = 1; }

        #take users which have subscription
        foreach my $user_id (keys %union) {
            my $user = LJ::load_userid($user_id);
            my %opts = (
               journalid => $ref_usr->{userid},
               etypeid   => LJ::Event::CommunityMantioned->etypeid,
               ntypeid   => LJ::NotificationMethod::Email->ntypeid,
            );
            my @subs = LJ::Subscription->find( $user, %opts );
            if (@subs) {
                $union{$user_id} = $subs[0]->id;
            } else {
                delete $union{$user_id};
            }
        }

        @send_list = keys %union;
        @send_list = map { LJ::load_userid($_) } @send_list;
    }
    else {
        push @send_list, $ref_usr;
    }

    foreach my $u (@send_list) {
        return 0 unless $class->should_user_recieve_notice($u, $poster);
        LJ::load_user_props($u, 'browselang');
        my $lang = $u->{'browselang'};
        my $html = $u->receives_html_emails;

        my %text_params = (
            'usernameA'   => $html ? $u->ljuser_display : $u->username,
            'usernameB'   => $html ? $poster->ljuser_display : $poster->username,
            'context'     => $context,
            'entry_URL'   => $source_uri,
        );

        my $text_var = 'pingback.notifyref.';

        #especial params for community
        if ( $ref_usr->is_community() ) {
            $text_var .= ($comment ? 'communitycomment' : 'communitypost').'.'.($html ? 'html' : 'plain');
            $text_params{'community'} = $html ? $ref_usr->ljuser_display : $ref_usr->username;
            %text_params = (
                %text_params,
                'subs_id' => $union{$u->{userid}},
                'hash' => md5_hex($u->user, $LJ::ESN_UNSUBSCR_SECRET_CODE),
                'siteroot' => $LJ::SITEROOT,
                'username' => $u->username,
            )
        }
        else {
            $text_var .= ($comment ? 'textcomment' : 'text').'.'.($html ? 'html' : 'plain');
        }

        my $body = LJ::Lang::get_text(
            $lang,
            $text_var,
            undef,
            \%text_params
        );

        my $subject = LJ::Lang::get_text(
            $lang,
            'pingback.notifyref.subject',
            undef,
            { usernameB   => $poster->username, }
        );

        my %mail_options = (
            'to'      => $u->email_raw,
            'from'    => $LJ::DONOTREPLY_EMAIL,
            'subject' => $subject,
            'body'    => $body,
        );
        $mail_options{'html'} = $body if ($html);

        LJ::send_mail(\%mail_options);
    }
}

sub should_user_recieve_notice {
    my ( $class, $user, $poster ) = @_;

    return 0 if $user->userid eq $poster->userid;

    return 0 if LJ::is_banned($poster->userid, $user->userid);

#    warn("status: ".$user->statusvis);
#    warn("locked: ".$user->is_locked);
#    warn("suspended: ".$user->is_suspended);
#    warn("readonly: ".$user->is_readonly);
#    warn("memorial: ".$user->is_memorial);
#    warn("deleted: ".$user->is_deleted);

    return 0 if $user->is_locked ||
                $user->is_suspended ||
                $user->is_readonly ||
                $user->is_memorial ||
                $user->is_deleted;

    return 0 unless $user->is_person || $user->is_identity;

    my $ping_back = $user->prop("pingback") ? $user->prop("pingback") : "O"; #if a user have not pingback parameter then think Open
    return 0 unless ($ping_back eq "U") || ($ping_back eq "O");

    return 1;
}

sub should_entry_recieve_pingback {
    my $class        = shift;
    my $target_entry = shift;

    return 0 if $LJ::DISABLED{'pingback_receive'};
    return 0 if $target_entry->is_suspended;

    # Pingback is open for all users
    # return 0 unless $target_entry->journal->get_cap('pingback');

    # not RO?
    return 0 if $target_entry->journal->readonly; # Check "is_readonly".

    # are comments allowed?
    return 0 unless $target_entry->posting_comments_allowed;

    # Poster's preferences have more priority than Communities have.
    return 0 if $target_entry->poster->prop("pingback") eq 'D';

=head
    # did user allow to add pingbacks?
    # journal's default. We do not store "J" value in DB.
    my $entry_pb_prop = $target_entry->prop("pingback") || 'J';
    return 0 if $entry_pb_prop eq 'D';  # disabled

    ## Option value 'L' (Livejournal only) is removed so far, it means 'O' (Open) now
    if ($entry_pb_prop eq 'J'){
        my $journal_pb_prop = $target_entry->journal->prop("pingback") || 'D';
        return 0 if $journal_pb_prop eq 'D';       # pingback disabled
    }
    return 1;
=cut

    return 1;
}

sub notify {
    my ( $class, %args ) = @_;

    return if $LJ::DISABLED{pingback};

    my $uri          = $args{uri};
    my $mode         = $args{mode};
    my $comment      = $args{comment};
    my $comment_data = $args{comment_data};

    return unless $mode =~ m!^[OLEU]$!; # (L)ivejournal only, (O)pen.

    my $sclient = LJ::theschwartz();

    unless ( $sclient ) {
        warn "LJ::PingBack: Could not get TheSchwartz client";
        return;
    }

    my $job = TheSchwartz::Job->new(
        funcname => "TheSchwartz::Worker::NotifyPingbackServer",
        arg      => {
            uri          => $uri,
            mode         => $mode,
            comment      => $comment,
            comment_data => $comment_data,
        },
    );

    $sclient->insert($job);
}

sub has_user_pingback {
    my ( $class, $u ) = @_;

    return 0 if $LJ::DISABLED{'pingback'};
    #return 0 unless $u->get_cap('pingback');
    return 1;
}

1;
