package LJ::Talk::Post;
use strict;

use LJ::EventLogRecord::NewComment;

sub indent {
    my $a = shift;
    my $leadchar = shift || " ";
    require Text::Wrap;
    $Text::Wrap::columns = 76;
    return Text::Wrap::fill("$leadchar ", "$leadchar ", $a);
}

sub blockquote {
    my $a = shift;
    return "<blockquote style='border-left: #000040 2px solid; margin-left: 0px; margin-right: 0px; padding-left: 15px; padding-right: 0px'>$a</blockquote>";
}

sub generate_messageid {
    my ($type, $journalu, $did) = @_;
    # $type = {"entry" | "comment"}
    # $journalu = $u of journal
    # $did = display id of comment/entry

    my $jid = $journalu->{userid};
    return "<$type-$jid-$did\@$LJ::DOMAIN>";
}

sub enter_comment {
    my ($journalu, $parent, $item, $comment, $errref) = @_;

    my $partid = $parent->{talkid};
    my $itemid = $item->{itemid};

    my $err = sub {
        $$errref = join(": ", @_);
        return 0;
    };

    return $err->("Invalid user object passed.")
        unless LJ::isu($journalu);

    LJ::run_hooks('update_comment_props', $journalu, $comment);

    my $jtalkid = LJ::alloc_user_counter($journalu, "T");
    return $err->("Database Error", "Could not generate a talkid necessary to post this comment.")
        unless $jtalkid;

    # insert the comment
    my $posterid = $comment->{u} ? $comment->{u}{userid} : 0;

    my $errstr;
    $journalu->talk2_do(nodetype => "L", nodeid => $itemid, errref => \$errstr,
                        sql =>  "INSERT INTO talk2 ".
                                "(journalid, jtalkid, nodetype, nodeid, parenttalkid, posterid, datepost, state) ".
                                "VALUES (?,?,'L',?,?,?,NOW(),?)",
                        bindings => [$journalu->{userid}, $jtalkid, $itemid, $partid, $posterid, $comment->{state}],
                        flush_cache => 0, # do not flush cache with talks tree, just append a new comment.
                        );
    if ($errstr) {
        return $err->("Database Error",
            "There was an error posting your comment to the database.  " .
            "Please report this.  The error is: <b>$errstr</b>");
    }

    # append new comment to memcached tree
    {
        my $memkey = [$journalu->{'userid'}, "talk2:$journalu->{'userid'}:L:$itemid"];
        my $append = pack(LJ::Talk::PACK_FORMAT,
                        $jtalkid,
                        $partid,
                        $posterid,
                        time(),
                        ord($comment->{state}));
        my $res = LJ::MemCache::append($memkey, $append);
    }


    LJ::MemCache::incr([$journalu->{'userid'}, "talk2ct:$journalu->{'userid'}"]);

    $comment->{talkid} = $jtalkid;

    # record IP if anonymous
    LJ::Talk::record_anon_comment_ip($journalu, $comment->{talkid}, LJ::get_remote_ip())
        unless $posterid;

    # add to poster's talkleft table, or the xfer place
    if ($posterid) {
        my $table;
        my $db = LJ::get_cluster_master($comment->{u});

        if ($db) {
            # remote's cluster is writable
            $table = "talkleft";
        } else {
            # log to global cluster, another job will move it later.
            $db = LJ::get_db_writer();
            $table = "talkleft_xfp";
        }
        my $pub  = $item->{'security'} eq "public" ? 1 : 0;
        if ($db) {
            $db->do("INSERT INTO $table (userid, posttime, journalid, nodetype, ".
                    "nodeid, jtalkid, publicitem) VALUES (?, UNIX_TIMESTAMP(), ".
                    "?, 'L', ?, ?, ?)", undef,
                    $posterid, $journalu->{userid}, $itemid, $jtalkid, $pub);

        } else {
            # both primary and backup talkleft hosts down.  can't do much now.
        }

        my $poster = LJ::want_user($posterid);
        $poster->incr_num_comments_posted;
    }

    $journalu->do("INSERT INTO talktext2 (journalid, jtalkid, subject, body) ".
                  "VALUES (?, ?, ?, ?)", undef,
                  $journalu->{userid}, $jtalkid, $comment->{subject},
                  LJ::text_compress($comment->{body}));
    die $journalu->errstr if $journalu->err;

    my $memkey = "$journalu->{'clusterid'}:$journalu->{'userid'}:$jtalkid";
    LJ::MemCache::set([$journalu->{'userid'},"talksubject:$memkey"], $comment->{subject});
    LJ::MemCache::set([$journalu->{'userid'},"talkbody:$memkey"], $comment->{body});

    # dudata
    my $bytes = length($comment->{subject}) + length($comment->{body});
    # we used to do a LJ::dudata_set(..) on 'T' here, but decided
    # we could defer that.  to find size of a journal, summing
    # bytes in dudata is too slow (too many seeks)

    my %talkprop;   # propname -> value
    # meta-data
    $talkprop{'unknown8bit'} = 1 if $comment->{unknown8bit};
    $talkprop{'subjecticon'} = $comment->{subjecticon};

    $talkprop{'picture_keyword'} = $comment->{picture_keyword};

    $talkprop{'opt_preformatted'} = $comment->{preformat} ? 1 : 0;
    my $opt_logcommentips = $journalu->{'opt_logcommentips'};
    if ($opt_logcommentips eq "A" ||
        ($opt_logcommentips eq "S" && $comment->{usertype} !~ /^(?:user|cookieuser)$/))
    {
        if (LJ::is_web_context()) {
            my $ip = LJ::Request->remote_ip;
            my $forwarded = LJ::Request->header_in('X-Forwarded-For');
            $ip = "$forwarded, via $ip" if $forwarded && $forwarded ne $ip;
            $talkprop{'poster_ip'} = $ip;
        }
    }

    # remove blank/0 values (defaults)
    foreach (keys %talkprop) { delete $talkprop{$_} unless $talkprop{$_}; }

    # update the talkprops
    LJ::load_props("talk");
    if (%talkprop) {
        my $values;
        my $hash = {};
        foreach (keys %talkprop) {
            my $p = LJ::get_prop("talk", $_);
            next unless $p;
            $hash->{$_} = $talkprop{$_};
            my $tpropid = $p->{'tpropid'};
            my $qv = $journalu->quote($talkprop{$_});
            $values .= "($journalu->{'userid'}, $jtalkid, $tpropid, $qv),";
        }
        if ($values) {
            chop $values;
            $journalu->do("INSERT INTO talkprop2 (journalid, jtalkid, tpropid, value) ".
                      "VALUES $values");
            die $journalu->errstr if $journalu->err;
        }
        LJ::MemCache::set([$journalu->{'userid'}, "talkprop:$journalu->{'userid'}:$jtalkid"], $hash);
    }

    # record up to 25 (or $LJ::TALK_MAX_URLS) urls from a comment
    my (%urls, $dbh);
    if ($LJ::TALK_MAX_URLS &&
        ( %urls = map { $_ => 1 } LJ::get_urls($comment->{body}) ) &&
        ( $dbh = LJ::get_db_writer() )) # don't log if no db available
    {
        my (@bind, @vals);
        my $ip = LJ::get_remote_ip();
        while (my ($url, undef) = each %urls) {
            push @bind, '(?,?,?,?,UNIX_TIMESTAMP(),?)';
            push @vals, $posterid, $journalu->{userid}, $ip, $jtalkid, $url;
            last if @bind >= $LJ::TALK_MAX_URLS;
        }
        my $bind = join(',', @bind);
        my $sql = qq{
            INSERT INTO commenturls
                (posterid, journalid, ip, jtalkid, timecreate, url)
            VALUES $bind
        };
        $dbh->do($sql, undef, @vals);
    }

    # update the "replycount" summary field of the log table
    if ($comment->{state} eq 'A') {
        LJ::replycount_do($journalu, $itemid, "incr");
    }

    # update the "hasscreened" property of the log item if needed
    if ($comment->{state} eq 'S') {
        LJ::set_logprop($journalu, $itemid, { 'hasscreened' => 1 });
    }

    # update the comment alter property
    LJ::Talk::update_commentalter($journalu, $itemid);

    # journals data consists of two types of data: posts and comments.
    # last post time is stored in 'userusage' table.
    # last comment add/update/delete/whateverchange time - here:
    LJ::Talk::update_journals_commentalter($journalu);

    # fire events
    unless ($LJ::DISABLED{esn}) {
        my $cmtobj = LJ::Comment->new($journalu, jtalkid => $jtalkid);
        LJ::Event::JournalNewComment->new($cmtobj)->fire;
        LJ::EventLogRecord::NewComment->new($cmtobj)->fire;
    }

    return $jtalkid;
}

# XXX these strings should be in talk, but moving them means we have
# to retranslate.  so for now we're just gonna put it off.
my $SC = '/talkpost_do.bml';

sub init {
    my ($form, $remote, $need_captcha, $errret) = @_;
    my $sth = undef;
    
    my $err = sub {
        my $error = shift;
        push @$errret, $error;
        return undef;
    };
    my $bmlerr = sub {
        return $err->(LJ::Lang::ml($_[0]));
    };

    my $init = LJ::Talk::init($form);
    return $err->($init->{error}) if $init->{error};

    my $journalu = $init->{'journalu'};
    return $bmlerr->('talk.error.nojournal') unless $journalu;
    return $err->($LJ::MSG_READONLY_USER) if LJ::get_cap($journalu, "readonly");

    return $err->("Account is locked, unable to post or edit a comment.") if $journalu->{statusvis} eq 'L';

    eval {
        LJ::Request->notes("journalid" => $journalu->{'userid'});
    };

    my $dbcr = LJ::get_cluster_def_reader($journalu);
    return $bmlerr->('error.nodb') unless $dbcr;

    my $itemid = $init->{'itemid'}+0;

    my $item = LJ::Talk::get_journal_item($journalu, $itemid);

    if ($init->{'oldurl'} && $item) {
        $init->{'anum'} = $item->{'anum'};
        $init->{'ditemid'} = $init->{'itemid'}*256 + $item->{'anum'};
    }

    unless ($item && $item->{'anum'} == $init->{'anum'}) {
        return $bmlerr->('talk.error.noentry');
    }

    my $iprops = $item->{'props'};
    my $ditemid = $init->{'ditemid'}+0;

    my $entry = LJ::Entry->new($journalu, ditemid => $ditemid);
    $entry->handle_prefetched_props($iprops);

    my $talkurl = $entry->url;
    $init->{talkurl} = $talkurl;

    ### load users
    LJ::load_userids_multiple([
                               $item->{'posterid'} => \$init->{entryu},
                               ], [ $journalu ]);
    LJ::load_user_props($journalu, "opt_logcommentips");

    ### two hacks; unsure if these need to stay
    if ($form->{'userpost'} && $form->{'usertype'} ne "user") {
        unless ($form->{'usertype'} eq "cookieuser" &&
                $form->{'userpost'} eq $form->{'cookieuser'}) {
            $bmlerr->("$SC.error.confused_identity");
        }
    }

    # anonymous/cookie users cannot authenticate with ecphash
    if ($form->{'ecphash'} && $form->{'usertype'} ne "user") {
        $err->(LJ::Lang::ml("$SC.error.badusername2", {'sitename' => $LJ::SITENAMESHORT, 'aopts' => "href='$LJ::SITEROOT/lostinfo.bml'"}));
        return undef;
    }
    ### hacks end here

    ### Logged user may post comment from other one,
    ### in this case we should not loggin them again.
    $form->{donot_login} = 1 if LJ::get_remote();

    my $up;

    my $author_class = LJ::Talk::Author->get_handler($form->{'usertype'});

    # whoops, a bogus usertype value. no way.
    unless ( $author_class && $author_class->enabled ) {
        return $bmlerr->('error.invalidform');
    }

    $up = $author_class->handle_user_input( $form, $remote, $need_captcha,
                                            $errret, $init );
    return if @$errret or LJ::Request->redirected;
    
    # validate the challenge/response value (anti-spammer)
    unless ($init->{'used_ecp'}) {
        my $chrp_err;
        if (my $chrp = $form->{'chrp1'}) {
            my ($c_ditemid, $c_uid, $c_time, $c_chars, $c_res) =
                split(/\-/, $chrp);
            my $chal = "$c_ditemid-$c_uid-$c_time-$c_chars";
            my $secret = LJ::get_secret($c_time);
            my $res = Digest::MD5::md5_hex($secret . $chal);
            if ($res ne $c_res) {
                $chrp_err = "invalid";
            } elsif ($c_time < time() - 2*60*60) {
                $chrp_err = "too_old" if $LJ::REQUIRE_TALKHASH_NOTOLD;
            }
        } else {
            $chrp_err = "missing";
        }
        if ($chrp_err) {
            my $ip = LJ::get_remote_ip();
            if ($LJ::DEBUG{'talkspam'}) {
                my $ruser = $remote ? $remote->{user} : "[nonuser]";
                print STDERR "talkhash error: from $ruser \@ $ip - $chrp_err - $talkurl\n";
            }
            if ($LJ::REQUIRE_TALKHASH) {
                return $err->("Sorry, form expired.  Press back, copy text, reload form, paste into new form, and re-submit.")
                    if $chrp_err eq "too_old";
                return $err->("Missing parameters");
            }
        }
    }

    # check that user can even view this post, which is required
    # to reply to it
    ####  Check security before viewing this post
    unless (LJ::can_view($up, $item)) {
        $bmlerr->("$SC.error.mustlogin") unless (defined $up);
        $bmlerr->("$SC.error.noauth");
        return undef;
    }

    ### see if the user is banned from posting here
    if ($up && LJ::is_banned($up, $journalu)) {
        $bmlerr->("$SC.error.banned");
    }

    # If the reply is to a comment, check that it exists.
    # if it's screened, check that the user has permission to
    # reply and unscreen it

    my $parpost;
    my $partid = $form->{'parenttalkid'}+0;

    if ($partid) {
        $parpost = LJ::Talk::get_talk2_row($dbcr, $journalu->{userid}, $partid);
        unless ($parpost) {
            $bmlerr->("$SC.error.noparent");
        }

        # can't use $remote because we may get here
        # with a reply from email. so use $up instead of $remote
        # in the call below.

        if ($parpost && $parpost->{'state'} eq "S" &&
            !LJ::Talk::can_unscreen($up, $journalu, $init->{entryu}, $init->{entryu}{'user'})) {
            $bmlerr->("$SC.error.screened");
        }
    }
    $init->{parpost} = $parpost;

    # don't allow anonymous comments on syndicated items
    if ($journalu->{'journaltype'} eq "Y" && $journalu->{'opt_whocanreply'} eq "all") {
        $journalu->{'opt_whocanreply'} = "reg";
    }

    if (!$up && $journalu->{'opt_whocanreply'} ne "all") {
        $bmlerr->("$SC.error.noanon");
    }

    unless ($entry->posting_comments_allowed) {
        $bmlerr->("$SC.error.nocomments");
    }

    if ($up) {
        if ($up->{'status'} eq "N" && $up->{'journaltype'} ne "I" && !LJ::run_hook("journal_allows_unvalidated_commenting", $journalu, $up)) {
            $err->(LJ::Lang::ml("$SC.error.noverify2", {'aopts' => "href='$LJ::SITEROOT/register.bml'"}));
        }
        if ($up->{'statusvis'} eq "D") {
            $bmlerr->("$SC.error.deleted");
        } elsif ($up->{'statusvis'} eq "S") {
            $bmlerr->("$SC.error.suspended");
        } elsif ($up->{'statusvis'} eq "X") {
            $bmlerr->("$SC.error.purged");
        }
    }

    if ($journalu->{'opt_whocanreply'} eq "friends") {
        if ($up) {
            if ($up->{'userid'} != $journalu->{'userid'}) {
                unless (LJ::is_friend($journalu, $up)) {
                    my $msg = $journalu->is_comm ? "notamember" : "notafriend";
                    $err->(LJ::Lang::ml("$SC.error.$msg", {'user'=>$journalu->{'user'}}));
                }
            }
        } else {
            my $msg = $journalu->is_comm ? "membersonly" : "friendsonly";
            $err->(LJ::Lang::ml("$SC.error.$msg", {'user'=>$journalu->{'user'}}));
        }
    }

    $bmlerr->("$SC.error.blankmessage") unless $form->{'body'} =~ /\S/;

    # in case this post comes directly from the user's mail client, it
    # may have an encoding field for us.
    if ($form->{'encoding'}) {
        $form->{'body'} = Unicode::MapUTF8::to_utf8({-string=>$form->{'body'}, -charset=>$form->{'encoding'}});
        $form->{'subject'} = Unicode::MapUTF8::to_utf8({-string=>$form->{'subject'}, -charset=>$form->{'encoding'}});
    }

    # unixify line-endings
    $form->{'body'} =~ s/\r\n/\n/g;

    # now check for UTF-8 correctness, it must hold

    return $err->("<?badinput?>") unless LJ::text_in($form);

    $init->{unknown8bit} = 0;
    unless (LJ::is_ascii($form->{'body'}) && LJ::is_ascii($form->{'subject'})) {
        if ($LJ::UNICODE) {
            # no need to check if they're well-formed, we did that above
        } else {
            # so rest of site can change chars to ? marks until
            # default user's encoding is set.  (legacy support)
            $init->{unknown8bit} = 1;
        }
    }

    my ($bl, $cl) = LJ::text_length($form->{'body'});
    if ($cl > LJ::CMAX_COMMENT) {
        $err->(LJ::Lang::ml("$SC.error.manychars", {'current'=>$cl, 'limit'=>LJ::CMAX_COMMENT}));
    } elsif ($bl > LJ::BMAX_COMMENT) {
        $err->(LJ::Lang::ml("$SC.error.manybytes", {'current'=>$bl, 'limit'=>LJ::BMAX_COMMENT}));
    }
    # the Subject can be silently shortened, no need to reject the whole comment
    $form->{'subject'} = LJ::text_trim($form->{'subject'}, 100, 100);

    my $subjecticon = "";
    if ($form->{'subjecticon'} ne "none" && $form->{'subjecticon'} ne "") {
        $subjecticon = LJ::trim(lc($form->{'subjecticon'}));
    }

    # New comment state
    my $state = 'A';
    my $screening = LJ::Talk::screening_level($journalu, int($ditemid / 256));
    if ($form->{state} =~ /^[A-Z]\z/){
        # use provided state.
        $state = $form->{state};
    } else {
        # figure out whether to post this comment screened
        if (!$form->{editid} && ($screening eq 'A' ||
            ($screening eq 'R' && ! $up) ||
            ($screening eq 'F' && !($up && LJ::is_friend($journalu, $up))))) {
            $state = 'S';
        }
        $state = 'A' if LJ::Talk::can_unscreen($up, $journalu, $init->{entryu}, $init->{entryu}{user});
    }

    my $can_mark_spam = LJ::Talk::can_mark_spam($up, $journalu, $init->{entryu}, $init->{entryu}{user});
    my $need_spam_check = 0;
    LJ::run_hook('need_spam_check_comment', \$need_spam_check, $entry, $state, $journalu, $up);
    if ( $need_spam_check && !$can_mark_spam ) {
        my $spam = 0;
        LJ::run_hook('spam_comment_detector', $form, \$spam, $journalu, $up);
        LJ::run_hook('spam_in_all_journals', \$spam, $journalu, $up) unless $spam;
        $state = 'B' if $spam;
    }
    
    my $parent = {
        state     => $parpost->{state},
        talkid    => $partid,
    };
    my $comment = {
        u               => $up,
        usertype        => $form->{'usertype'},
        subject         => $form->{'subject'},
        body            => $form->{'body'},
        unknown8bit     => $init->{unknown8bit},
        subjecticon     => $subjecticon,
        preformat       => $form->{'prop_opt_preformatted'},
        picture_keyword => $form->{'prop_picture_keyword'},
        state           => $state,
        editid          => $form->{editid},
    };

    $init->{item} = $item;
    $init->{parent} = $parent;
    $init->{comment} = $comment;

    LJ::run_hooks('decode_comment_form', $form, $comment);

    # anti-spam captcha check
    if (ref $need_captcha eq 'SCALAR') {

        # see if they're in the second+ phases of a captcha check.
        # are they sending us a response?
        if (LJ::is_enabled("recaptcha") && $form->{recaptcha_response_field}) {
            # assume they won't pass and re-set the flag
            $$need_captcha = 1;

            my $c = Captcha::reCAPTCHA->new;
            my $result = $c->check_answer(
                LJ::conf_test($LJ::RECAPTCHA{private_key}), $ENV{'REMOTE_ADDR'},
                $form->{'recaptcha_challenge_field'}, $form->{'recaptcha_response_field'}
            );

            return $err->("Incorrect response to spam robot challenge.") unless $result->{is_valid} eq '1';
        } elsif (!LJ::is_enabled("recaptcha") && $form->{captcha_chal}) {
            # assume they won't pass and re-set the flag
            $$need_captcha = 1;

            # if they typed "audio", we don't double-check if they still need
            # a captcha (they still do), they just want an audio version.
            if (lc($form->{answer}) eq 'audio') {
                return;
            }

            my ($capid, $anum) = LJ::Captcha::session_check_code($form->{captcha_chal},
                                                                 $form->{answer}, $journalu);

            return $err->("Incorrect response to spam robot challenge.") unless $capid && $anum;
            my $expire_u = $comment->{'u'} || LJ::load_user('system');
            LJ::Captcha::expire($capid, $anum, $expire_u->{userid});

        } else {
            $$need_captcha = LJ::Talk::Post::require_captcha_test($comment->{'u'}, $journalu, $form->{body}, $ditemid);
            if ($$need_captcha) {
                return $err->("Please confirm you are a human below.");
            }
        }
    }

    return undef if @$errret;
    return $init;
}

# <LJFUNC>
# name: LJ::Talk::Post::require_captcha_test
# des: returns true if user must answer CAPTCHA (human test) before posting a comment
# args: commenter, journal, body, ditemid
# des-commenter: User object of author of comment, undef for anonymous commenter
# des-journal: User object of journal where to post comment
# des-body: Text of the comment (may be checked for spam, may be empty)
# des-ditemid: identifier of post, need for checking reply-count
# </LJFUNC>
sub require_captcha_test {
    my ($commenter, $journal, $body, $ditemid, $nowrite) = @_;

    ## LJSUP-7832: If user is a member of "http://community.livejournal.com/notaspammers/" 
    ##             we shouldn't display captcha for him
            
    return if $commenter && LJ::is_friend($LJ::NOTASPAMMERS_COMM_UID, $commenter);

    ## allow some users (our bots) to post without captchas in any rate
    return if $commenter and 
              grep { $commenter->username eq $_ } @LJ::NO_RATE_CHECK_USERS;

    ## anonymous commenter user =
    ## not logged-in user, or OpenID without validated e-mail
    my $anon_commenter = !LJ::isu($commenter) ||
        ($commenter->identity && !$commenter->is_trusted_identity);

    ##
    ## 1. Check rate by remote user and by IP (for anonymous user)
    ##
    if ($LJ::HUMAN_CHECK{anonpost} || $LJ::HUMAN_CHECK{authpost}) {
        return 1 if !LJ::Talk::Post::check_rate($commenter, $journal, $nowrite);
    }
    if ($LJ::HUMAN_CHECK{anonpost} && $anon_commenter) {
        return 1 if LJ::sysban_check('talk_ip_test', LJ::get_remote_ip());
    }


    ##
    ## 4. Test preliminary limit on comment.
    ## We must check it before we will allow owner to pass.
    ##
    if (LJ::Talk::get_replycount($journal, int($ditemid / 256)) >= LJ::get_cap($journal, 'maxcomments-before-captcha')) {
        return 1;
    }

    ##
    ## 2. Don't show captcha to the owner of the journal, no more checks
    ##
    if (!$anon_commenter && $commenter->{userid}==$journal->{userid}) {
        return;
    }

    ##
    ## 3. Custom (journal) settings
    ##
    my $show_captcha_to = $journal->prop('opt_show_captcha_to');
    if (!$show_captcha_to || $show_captcha_to eq 'N') {
        ## no one
    } elsif ($show_captcha_to eq 'R') {
        ## anonymous
        return 1 if $anon_commenter;
    } elsif ($show_captcha_to eq 'F') {
        ## not friends
        return 1 if !LJ::is_friend($journal, $commenter);
    } elsif ($show_captcha_to eq 'A') {
        ## all
        return 1;
    }

    ##
    ## 4. Global (site) settings
    ## See if they have any tags or URLs in the comment's body
    ##
    if ($LJ::HUMAN_CHECK{'comment_html_auth'}
        || ($LJ::HUMAN_CHECK{'comment_html_anon'} && $anon_commenter))
    {
        if ($body =~ /<[a-z]/i) {
            # strip white-listed bare tags w/o attributes,
            # then see if they still have HTML.  if so, it's
            # questionable.  (can do evil spammy-like stuff w/
            # attributes and other elements)
            my $body_copy = $body;
            $body_copy =~ s/<(?:q|blockquote|b|strong|i|em|cite|sub|sup|var|del|tt|code|pre|p)>//ig;
            return 1 if $body_copy =~ /<[a-z]/i;
        }
        # multiple URLs is questionable too
        return 1 if $body =~ /\b(?:http|ftp|www)\b.+\b(?:http|ftp|www)\b/s;

        # or if they're not even using HTML
        return 1 if $body =~ /\[url/is;

        # or if it's obviously spam
        return 1 if $body =~ /\s*message\s*/is;
    }
}


# returns 1 on success.  0 on fail (with $$errref set)
sub post_comment {
    my ($entryu, $journalu, $comment, $parent, $item, $errref) = @_;

    # unscreen the parent comment if needed
    if ($parent->{state} eq 'S') {
        LJ::Talk::unscreen_comment($journalu, $item->{itemid}, $parent->{talkid});
        $parent->{state} = 'A';
    }

    # unban the parent comment if needed
    if ($parent->{state} eq 'B' && $comment->{u} && LJ::Talk::can_unmark_spam($comment->{u}, $journalu)) {
        LJ::Talk::unspam_comment($journalu, $item->{itemid}, $parent->{talkid});
        $parent->{state} = 'A';
    }

    # make sure they're not underage
    if ($comment->{u} && $comment->{u}->underage) {
        $$errref = $LJ::UNDERAGE_ERROR;
        return 0;
    }

    # check for duplicate entry (double submission)
    # Note:  we don't do it inside a locked section like ljprotocol.pl's postevent,
    # so it's not perfect, but it works pretty well.
    my $posterid = $comment->{u} ? $comment->{u}{userid} : 0;
    my $jtalkid;

    # check for dup ID in memcache.
    my $memkey;
    if (@LJ::MEMCACHE_SERVERS) {
        my $md5_b64 = Digest::MD5::md5_base64(
            join(":", ($comment->{body}, $comment->{subject},
                       $comment->{subjecticon}, $comment->{preformat},
                       $comment->{picture_keyword})));
        $memkey = [$journalu->{userid}, "tdup:$journalu->{userid}:$item->{itemid}-$parent->{talkid}-$posterid-$md5_b64" ];
        $jtalkid = LJ::MemCache::get($memkey);
    }

    # they don't have a duplicate...
    unless ($jtalkid) {
        # XXX do select and delete $talkprop{'picture_keyword'} if they're lying
        my $pic = LJ::get_pic_from_keyword($comment->{u}, $comment->{picture_keyword});
        delete $comment->{picture_keyword} unless $pic && $pic->{'state'} eq 'N';
        $comment->{pic} = $pic;

        # put the post in the database
        my $ditemid = $item->{itemid}*256 + $item->{anum};
        $jtalkid = enter_comment($journalu, $parent, $item, $comment, $errref);
        return 0 unless $jtalkid;

        # save its identifying characteristics to protect against duplicates.
        LJ::MemCache::set($memkey, $jtalkid+0, time()+60*10);
        
        # update spam counter if needed
        if ($comment->{state} eq 'B') {
            my $entry = LJ::Entry->new($journalu, jitemid => $item->{itemid});
            my $spam_counter = $entry->prop('spam_counter') || 0;
            $entry->set_prop('spam_counter', $spam_counter + 1);
        }
    }

    # the caller wants to know the comment's talkid.
    $comment->{talkid} = $jtalkid;

    # cluster tracking
    LJ::mark_user_active($comment->{u}, 'comment');

    LJ::run_hooks('new_comment', $journalu->{userid}, $item->{itemid}, $jtalkid);
    LJ::run_hooks('new_comment2', {
        'data'      => $comment,
        'posterid'  => $posterid,
        'journalid' => $journalu->{'userid'},
        'itemid'    => $item->{'itemid'},
        'jtalkid'   => $jtalkid,
    });

    return 1;
}

# returns 1 on success.  0 on fail (with $$errref set)
sub edit_comment {
    my ($entryu, $journalu, $comment, $parent, $item, $errref, $remote) = @_;
    
    my $err = sub {
        $$errref = join(": ", @_);
        return 0;
    };

    my $comment_obj = LJ::Comment->new($journalu, dtalkid => $comment->{editid});

    $remote ||= LJ::get_remote();
    return 0 unless $comment_obj->user_can_edit($remote, $errref);

    my %props = (
        subjecticon => $comment->{subjecticon},
        picture_keyword => $comment->{picture_keyword},
        opt_preformatted => $comment->{preformat} ? 1 : 0,
    );

    # set most of the props together
    $comment_obj->set_props(%props);

    # set edit time separately since it needs to be a raw value
    $comment_obj->set_prop_raw( edit_time => "UNIX_TIMESTAMP()" );

    # set poster IP separately since it has special conditions
    my $opt_logcommentips = $comment_obj->journal->prop('opt_logcommentips');
    if ($opt_logcommentips eq "A" || 
        ($opt_logcommentips eq "S" && $comment->{usertype} !~ /^(?:user|cookieuser)$/)) 
    {
        $comment_obj->set_poster_ip;
    }
    
    ## Save changes if comment is screened now and it wasn't.
    ## Don't save opposite change (screened --> unscreened), because change
    ## may be caused by that edit comment form misses 'state' field.
    if ($comment_obj->state ne $comment->{state} && $comment->{state} =~ /[SB]/) {
        $comment_obj->set_state($comment->{state});
    }
    
    # set subject and body text
    $comment_obj->set_subject_and_body($comment->{subject}, $comment->{body});

    # the caller wants to know the comment's talkid.
    $comment->{talkid} = $comment_obj->jtalkid;


    # journals data consists of two types of data: posts and comments.
    # last post time is stored in 'userusage' table.
    # last comment add/update/delete/whateverchange time - here:
    LJ::Talk::update_journals_commentalter($comment_obj->journal);

    # cluster tracking
    LJ::mark_user_active($comment_obj->poster, 'comment');

    # fire events
    unless ($LJ::DISABLED{esn}) {
        LJ::Event::JournalNewComment->new($comment_obj)->fire;
        LJ::EventLogRecord::NewComment->new($comment_obj)->fire;
    }

    LJ::run_hooks('edit_comment', $journalu->{userid}, $item->{itemid}, $comment->{talkid});

    return 1;
}

# XXXevan:  this function should have its functionality migrated to talkpost.
# because of that, it's probably not worth the effort to make it not mangle $form...
sub make_preview {
    my ($talkurl, $cookie_auth, $form) = @_;
    my $ret = "";

    my $cleansubject = $form->{'subject'};
    LJ::CleanHTML::clean_subject(\$cleansubject);

    $ret .= '<h1>' . LJ::Lang::ml('/talkpost_do.bml.preview.title') . '</h1>' .
            '<p>'  . LJ::Lang::ml('/talkpost_do.bml.preview')       . '</p>' .
            '<hr/>';

    $ret .= "<div align=\"center\"><b>(<a href=\"$talkurl\">$BML::ML{'talk.commentsread'}</a>)</b></div>";

    my $event = $form->{'body'};
    my $spellcheck_html;
    # clean first; if the cleaner finds it invalid, don't spellcheck, so that we
    # can show the user the error.
    my $cleanok = LJ::CleanHTML::clean_comment(\$event, $form->{'prop_opt_preformatted'});
    if (defined($cleanok) && $LJ::SPELLER && $form->{'do_spellcheck'}) {
        my $s = new LJ::SpellCheck { 'spellcommand' => $LJ::SPELLER,
                                     'color' => '#ff0000', };
        $spellcheck_html = $s->check_html(\$event);
    }

    $ret .= "$BML::ML{'/talkpost_do.bml.preview.subject'} " . LJ::ehtml($cleansubject) . "<hr />\n";
    if ($spellcheck_html) {
        $ret .= $spellcheck_html;
        $ret .= "<p>";
    } else {
        $ret .= $event;
    }

    $ret .= "<hr />";

    # While it may seem like we need form auth for this form, the form for
    # actually composing a comment includes it.  It is then put into this
    # form about 20 lines below: foreach (keys %$form).
    $ret .= "<div style='width: 90%'><form method='post'><p>\n";
    $ret .= "<input name='subject' size='50' maxlength='100' value='" . LJ::ehtml($form->{'subject'}) . "' /><br />";
    $ret .= "<textarea class='textbox' rows='10' cols='50' wrap='soft' name='body' style='width: 100%'>";
    $ret .= LJ::ehtml($form->{'body'});
    $ret .= "</textarea></p>";

    # change mode:
    delete $form->{'submitpreview'}; $form->{'submitpost'} = 1;
    if ($cookie_auth) {
        $form->{'usertype'} = "cookieuser";
        delete $form->{'userpost'};
    }
    delete $form->{'do_spellcheck'};
    foreach (keys %$form) {
        $ret .= LJ::html_hidden($_, $form->{$_})
            unless $_ eq 'body' || $_ eq 'subject' || $_ eq 'prop_opt_preformatted';
    }

    $ret .= "<br /><input type='submit' value='$BML::ML{'/talkpost_do.bml.preview.submit'}' />\n";
    $ret .= "<input type='submit' name='submitpreview' value='$BML::ML{'talk.btn.preview'}' />\n";
    if ($LJ::SPELLER) {
        $ret .= "<input type='checkbox' name='do_spellcheck' value='1' id='spellcheck' /> <label for='spellcheck'>$BML::ML{'talk.spellcheck'}</label>";
    }
    $ret .= "<p>";
    $ret .= "$BML::ML{'/talkpost.bml.opt.noautoformat'} ".
        LJ::html_check({ 'name' => 'prop_opt_preformatted',
                         selected => $form->{'prop_opt_preformatted'} });
    $ret .= LJ::help_icon_html("noautoformat", " ");
    $ret .= "</p>";

    $ret .= "<p> <span class='de'> $BML::ML{'/talkpost.bml.allowedhtml'}: ";
    foreach (sort &LJ::CleanHTML::get_okay_comment_tags()) {
        $ret .= "&lt;$_&gt; ";
    }
    $ret .= "</span> </p>";

    $ret .= "</form></div>";
    return $ret;
}

# given a journalu and jitemid, return 1 if the entry
# is over the maximum comments allowed.
sub over_maxcomments {
    my ($journalu, $jitemid) = @_;
    $journalu = LJ::want_user($journalu);
    $jitemid += 0;
    return 0 unless $journalu && $jitemid;

    my $count = LJ::Talk::get_replycount($journalu, $jitemid);
    return ($count >= LJ::get_cap($journalu, 'maxcomments')) ? 1 : 0;
}

# more anti-spammer rate limiting.  returns 1 if rate is okay, 0 if too fast.
sub check_rate {
    my ($remote, $journalu, $nowrite) = @_;
    return 1 unless $LJ::ANTI_TALKSPAM;

    my $ip = LJ::get_remote_ip();
    my @watch = ();

    if ($remote) {
        # registered human (or human-impersonating robot)
        push @watch,
          [
            "talklog:$remote->{userid}",
            $LJ::RATE_COMMENT_AUTH || [ [ 200, 3600 ], [ 20, 60 ] ],
          ];
    } else {
        # anonymous, per IP address (robot or human)
        push @watch,
          [
            "talklog:$ip",
            $LJ::RATE_COMMENT_ANON ||
                [ [ 300, 3600 ], [ 200, 1800 ], [ 150, 900 ], [ 15, 60 ] ]
          ];

        # anonymous, per journal.
        # this particular limit is intended to combat flooders, instead
        # of the other 'spammer-centric' limits.
        push @watch,
          [
            "talklog:anonin:$journalu->{userid}",
            $LJ::RATE_COMMENT_ANON ||
                [ [ 300, 3600 ], [ 200, 1800 ], [ 150, 900 ], [ 15, 60 ] ]
          ];

        # throttle based on reports of spam
        push @watch,
          [
            "spamreports:anon:$ip",
            $LJ::SPAM_COMMENT_RATE ||
                [ [ 50, 86400], [ 10, 3600 ] ]
          ];
    }

    return LJ::RateLimit->check($remote, \@watch, $nowrite);
}

1;
