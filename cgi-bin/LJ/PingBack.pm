package LJ::PingBack;
use strict;
use LJ::Entry;

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

    unless ($target_entry){
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
	my $u = $args{user};
	my $source_uri = $args{source_uri};
	my $context = $args{context};
	my $comment = $args{comment};
	my $target_entry = LJ::Entry->new_from_url($source_uri);
	my $poster = $comment ? LJ::load_userid($comment->{posterid}) : LJ::load_userid($target_entry->posterid);
	$source_uri = $source_uri.'?thread='.$comment->{dtalkid}.'#t'.$comment->{dtalkid} if $comment;
	return if $u->is_community();
	
#	my $super_maintainer;
#	if( $u->is_community() ) {
#        $super_maintainer = LJ::load_rel_user_cache($u, 'S');
#        $u = LJ::load_userid($super_maintainer);
#   }

	return 0 unless $class->should_user_recieve_notice($u, $poster);
	
	LJ::load_user_props($u, 'browselang');
    my $lang = $u->{'browselang'};
    my $html = $u->receives_html_emails;
    
    my $body = LJ::Lang::get_text(
        $lang,
        'pingback.notifyref.'.($comment ? 'textcomment' : 'text').'.'.($html ? 'html' : 'plain'),
        undef,
        {
            'usernameA'   => $u->username,
            'usernameB'   => $poster->username,
            'context'     => $context,
            'entry_URL'   => $source_uri,
        }
    );
    
    my $subject = LJ::Lang::get_text(
        $lang,
        'pingback.notifyref.subject',
        undef,
        {
            usernameB   => $poster->username,
        }
    );
    
	if ($html) {	
	   LJ::send_mail({
	        'to'      => $u->email_raw,
	        'from'    => $LJ::DONOTREPLY_EMAIL,
	        'subject' => $subject,
	        'body'    => $body,
			'html'    => $body,
	   });
	} else {
        LJ::send_mail({
            'to'      => $u->email_raw,
            'from'    => $LJ::DONOTREPLY_EMAIL,
            'subject' => $subject,
            'body'    => $body,
        });
	}
}
sub should_user_recieve_notice {
	my $class = shift;
    my $user = shift;
    my $poster = shift;
    
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

    return 1; #

}


#
sub notify {
    my $class = shift;
    my %args  = @_;

    return if $LJ::DISABLED{pingback};

    my $uri  = $args{uri};
    my $mode = $args{mode};
    my $comment  = $args{comment};
    my $comment_data = $args{comment_data};

    return unless $mode =~ m!^[OLEU]$!; # (L)ivejournal only, (O)pen.

    my $sclient = LJ::theschwartz();

    unless ( $sclient ) {
        warn "LJ::PingBack: Could not get TheSchwartz client";
        return;
    }

    #
    my $job = TheSchwartz::Job->new(
        funcname => "TheSchwartz::Worker::NotifyPingbackServer",
        arg      => {
            uri  => $uri,
            mode => $mode,
            comment => $comment,
            comment_data => $comment_data,
        },
    );
    $sclient->insert($job);

}


sub has_user_pingback {
    my $class = shift;
    my $u     = shift;

    return 0 if $LJ::DISABLED{'pingback'};
    #return 0 unless $u->get_cap('pingback');
    return 1;
}


1;
