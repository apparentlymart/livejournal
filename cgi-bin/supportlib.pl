#!/usr/bin/perl
#

package LJ::Support;

use strict;
use Digest::MD5 qw(md5_hex);

## pass $id of zero or blank to get all categories
sub load_cats
{
    my ($dbh, $id) = @_;
    my $hashref = {};
    $id += 0;
    my $where = $id ? "WHERE spcatid=$id" : "";
    my $sth = $dbh->prepare("SELECT * FROM supportcat $where");
    $sth->execute;
    $hashref->{$_->{'spcatid'}} = $_ while ($_ = $sth->fetchrow_hashref);
    return $hashref;
}

sub load_email_to_cat_map
{
    my $dbh = shift;
    my $map = {};
    my $sth = $dbh->prepare("SELECT * FROM supportcat ORDER BY sortorder DESC");
    $sth->execute;
    while (my $sp = $sth->fetchrow_hashref) {
        next unless ($sp->{'replyaddress'});
        $map->{$sp->{'replyaddress'}} = $sp;
    }
    return $map;
}

sub calc_points
{
    my ($sp, $secs) = @_;
    my $base = $sp->{_cat}->{'basepoints'};    
    $secs = int($secs / (3600*6));
    my $total = ($base + $secs);
    if ($total > 10) { $total = 10; }
    $total ||= 1;
    return $total;
}

sub init_remote
{
    my $dbh = shift;
    my $remote = shift;
    my $form = shift;
    return unless ($remote);

    if ($remote->{'userid'}) {
        my $u = LJ::load_userid($dbh, $remote->{'userid'});
        %$remote = %$u;
        LJ::load_user_privs($dbh, $remote, 
                            qw(supportclose supporthelp 
                               supportdelete supportread));
    }

    # on see_request.bml page, an 'auth' argument can be passed in
    # to let the requester see their own stuff, regardless of login status.
    if (defined $form->{'auth'}) { 
        $remote->{'_support'}->{'miniauth'} = $form->{'auth'};
    }
}

# given all the categories, maps a catkey into a cat
sub get_cat_by_key
{
    my ($cats, $cat) = @_;
    foreach (keys %$cats) {
        if ($cats->{$_}->{'catkey'} eq $cat) {
            return $cats->{$_};
        }
    }
    return undef;
}

sub filter_cats
{
    my $remote = shift;
    my $cats = shift;

    return grep {
        can_read_cat(undef, $_, $remote);
    } sorted_cats($cats);
}

sub sorted_cats
{
    my $cats = shift;
    return sort { $a->{'catname'} cmp $b->{'catname'} } values %$cats;
}

# takes raw support request record and puts category info in it
# so it can be used in other functions like can_*
sub fill_request_with_cat
{
    my ($sp, $cats) = @_;
    $sp->{_cat} = $cats->{$sp->{'spcatid'}};
}

sub is_poster
{
    my ($sp, $remote) = @_;
    return 0 unless ($remote);
    if ($remote->{'_support'}->{'miniauth'} eq mini_auth($sp)) {
        return 1;
    }
    if ($sp->{'reqtype'} eq "email") {
        if ($remote->{'email'} eq $sp->{'reqemail'} && $remote->{'status'} eq "A") {
            return 1;
        }
    } elsif ($sp->{'reqtype'} eq "user") {
        if ($remote->{'userid'} eq $sp->{'requserid'}) { return 1; }
    }
    return 0;
}

sub can_see_helper
{
    my ($dbh, $sp, $remote) = @_;
    my $see = 1;
    if ($sp->{_cat}->{'hide_helpers'}) { 
        $see = 0; 
        if (can_help($dbh, $sp, $remote)) {
            $see = 1;
        }
    }
    return $see;
}

sub can_read
{
    my ($dbh, $sp, $remote) = @_;
    return (is_poster($sp, $remote) ||
            can_read_cat($dbh, $sp->{_cat}, $remote));
}

sub can_read_cat
{
    my ($dbh, $cat, $remote) = @_;
    return unless ($cat);
    return ($cat->{'public_read'} || 
            LJ::check_priv($dbh, $remote, "supportread", $cat->{'catkey'}));
}

sub can_close
{
    my ($dbh, $sp, $remote) = @_;
    if (is_poster($sp, $remote)) { return 1; }
    if ($sp->{_cat}->{'public_read'}) {
        if (LJ::check_priv($dbh, $remote, "supportclose", "")) { return 1; }
    }
    my $catkey = $sp->{_cat}->{'catkey'};
    if (LJ::check_priv($dbh, $remote, "supportclose", $catkey)) { return 1; }
    return 0;
}

sub can_append
{
    my ($dbh, $sp, $remote) = @_;    
    if (is_poster($sp, $remote)) { return 1; }
    if ($sp->{_cat}->{'allow_screened'}) { return 1; }
    if (can_help($dbh, $sp, $remote)) { return 1; }
    return 0;
}

# can they read internal comments?  if they're a helper or have
# extended supportread (with a plus sign at the end of the category key)
sub can_read_internal
{
    my ($dbh, $sp, $remote) = @_;    
    if (can_help($dbh, $sp, $remote)) { return 1; }
    my $catkey = $sp->{_cat}->{'catkey'};
    if (LJ::check_priv($dbh, $remote, "supportread", $catkey."+")) { return 1; }
    return 0;
}

sub can_help
{
    my ($dbh, $sp, $remote) = @_;
    if ($sp->{_cat}->{'public_read'}) {
        if ($sp->{_cat}->{'public_help'}) {
            return 1;
        }
        if (LJ::check_priv($dbh, $remote, "supporthelp", "")) { return 1; }
    }
    my $catkey = $sp->{_cat}->{'catkey'};
    if (LJ::check_priv($dbh, $remote, "supporthelp", $catkey)) { return 1; }
    return 0;
}

sub load_request
{
    my $dbh = shift;
    my $spid = shift;
    my $sth;

    $spid += 0;

    # load the support request
    $sth = $dbh->prepare("SELECT * FROM support WHERE spid=$spid");
    $sth->execute;
    my $sp = $sth->fetchrow_hashref;

    return undef unless $sp;

    # load the category the support requst is in
    $sth = $dbh->prepare("SELECT * FROM supportcat WHERE spcatid=$sp->{'spcatid'}");
    $sth->execute;
    $sp->{_cat} = $sth->fetchrow_hashref;

    return $sp;
}

sub load_response
{
    my $dbh = shift;
    my $splid = shift;
    my $sth;

    $splid += 0;

    # load the support request
    $sth = $dbh->prepare("SELECT * FROM supportlog WHERE splid=$splid");
    $sth->execute;
    my $res = $sth->fetchrow_hashref;

    return $res;
}

sub get_answer_types
{
    my ($dbh, $sp, $remote) = @_;
    my @ans_type;

    if (is_poster($sp, $remote)) {
        push @ans_type, ("comment", "More information");
        return @ans_type;
    } 

    if (can_help($dbh, $sp, $remote)) {
        push @ans_type, ("answer" => "Answer", 
                         "screened" => "Screened Answer (if unsure)", 
                         "comment" => "Comment or Question");
    }

    if (can_read_internal($dbh, $sp, $remote) &&
        ! $sp->{_cat}->{'public_help'})
    {
        push @ans_type, ("internal" => "Internal Comment / Action");
        return @ans_type;
    }
    
    if ($sp->{_cat}->{'allow_screened'}) {
        push @ans_type, ("screened" => "Screened Answer");
    }

    return @ans_type;
}

sub file_request
{
    my $dbh = shift;
    my $errors = shift;
    my $o = shift;

    unless ($o->{'subject'}) {
        push @$errors, "You must enter a problem summary.";
    }
    unless ($o->{'body'}) {
        push @$errors, "You did not enter a support request.";
    }
    my $scat = $o->{'supportcat'};

    if (@$errors) { return 0; }
    
    my $dup_id = 0;
    my $qsubject = $dbh->quote($o->{'subject'});
    my $qbody = $dbh->quote($o->{'body'});
    my $qreqtype = $dbh->quote($o->{'reqtype'});
    my $qrequserid = $o->{'requserid'}+0;
    my $qreqname = $dbh->quote($o->{'reqname'});
    my $qreqemail = $dbh->quote($o->{'reqemail'});
    my $qspcatid = ($scat->{'spcatid'} || $o->{'spcatid'})+0;

    # make the authcode
    my $authcode = LJ::make_auth_code(15);
    my $qauthcode = $dbh->quote($authcode);

    my $md5 = md5_hex("$qreqname$qreqemail$qsubject$qbody");
    my $sth;
 
    $dbh->do("LOCK TABLES support WRITE, duplock WRITE");
    $sth = $dbh->prepare("SELECT dupid FROM duplock WHERE realm='support' AND reid=0 AND userid=$qrequserid AND digest='$md5'");
    $sth->execute;
    ($dup_id) = $sth->fetchrow_array;
    if ($dup_id) {
        $dbh->do("UNLOCK TABLES");
        return $dup_id;
    }

    my ($urlauth, $url, $spid);  # used at the bottom

    my $sql = "INSERT INTO support (spid, reqtype, requserid, reqname, reqemail, state, authcode, spcatid, subject, timecreate, timetouched, timeclosed, timelasthelp) VALUES (NULL, $qreqtype, $qrequserid, $qreqname, $qreqemail, 'open', $qauthcode, $qspcatid, $qsubject, UNIX_TIMESTAMP(), UNIX_TIMESTAMP(), 0, 0)";
    $sth = $dbh->prepare($sql);
    $sth->execute;
    
    if ($dbh->err) { 
        my $error = $dbh->errstr;
        $dbh->do("UNLOCK TABLES");
        push @$errors, "<B>Database error:</B> (report this)<BR>$error";
        return 0;
    }
    $spid = $dbh->{'mysql_insertid'};
        
    $dbh->do("INSERT INTO duplock (realm, reid, userid, digest, dupid, instime) VALUES ('support', 0, $qrequserid, '$md5', $spid, NOW())");
    $dbh->do("UNLOCK TABLES");
    
    unless ($spid) { 
        push @$errors, "<B>Database error:</B> (report this)<BR>Didn't get a spid."; 
        return 0;
    }
        
    $sth = $dbh->prepare("INSERT INTO supportlog (splid, spid, timelogged, type, faqid, userid, message) VALUES (NULL, $spid, UNIX_TIMESTAMP(), 'req', 0, $qrequserid, $qbody)");
    $sth->execute;
    
    my $email = $o->{'reqtype'} eq "email" ? $o->{'reqemail'} : "";
    unless ($email) {
        if ($o->{'reqtype'} eq "user") {
            my $u = LJ::load_userid($dbh, $o->{'requserid'});
            $email = $u->{'email'};
        }
    }
    
    my $body;
    my $miniauth = mini_auth({ 'authcode' => $authcode });
    $url = "$LJ::SITEROOT/support/see_request.bml?id=$spid";
    $urlauth = "$url&auth=$miniauth";

    $body = "Your LiveJournal support request regarding \"$o->{'subject'}\" has been filed and will be answered as soon as possible.  Your request tracking number is $spid.\n\n";
    $body .= "You can track your request's progress or add information here:\n\n  ";
    $body .= LJ::make_text_link($urlauth, $email);
    
    $body .= "\n\nIf you figure out the problem before somebody gets back to you, please cancel your request by clicking this:\n\n  ";
    $body .= LJ::make_text_link("$LJ::SITEROOT/support/act.bml?close;$spid;$authcode", $email);
   
    unless ($scat->{'no_autoreply'})
    {
      LJ::send_mail({ 
          'to' => $email,
          'from' => $LJ::BOGUS_EMAIL,
          'fromname' => 'LiveJournal Support',
          'subject' => "Support Request \#$spid",
          'body' => $body  
          });
    }
    
    ########## send notifications
    
    $sth = $dbh->prepare("SELECT u.email FROM supportnotify sn, user u WHERE sn.userid=u.userid AND sn.spcatid=$qspcatid AND sn.level IN ('new', 'all')");
    $sth->execute;
    my @to_notify;
    while ($_ = $sth->fetchrow_hashref) {
        push @to_notify, $_->{'email'};
    }
    $body = "A LiveJournal support request regarding \"$o->{'subject'}\" has been submitted.  You can track its progress or add information here:\n\n  ";
    $body .= LJ::make_text_link($url, $_->{'email'});
    $body .= "\n\n" . "="x70 . "\n\n";
    $body .= $o->{'body'};
    
    LJ::send_mail({ 
        'bcc' => join(", ", @to_notify),
        'from' => $LJ::BOGUS_EMAIL,
        'fromname' => 'LiveJournal Support',
        'subject' => "Support Request \#$spid",
        'body' => $body
        });
    
    return $spid;
}

sub append_request
{
    my $dbh = shift;
    my $sp = shift;  # support request to be appended to.
    my $re = shift;  # hashref of attributes of response to be appended
    my $sth;

    # $re->{'body'}
    # $re->{'type'}    (req, answer, comment, internal, screened)
    # $re->{'faqid'}
    # $re->{'posterid'}  (or 0 if no username known)

    my $message = $re->{'body'};
    $message =~ s/^\s+//;
    $message =~ s/\s+$//;

    my $qmessage = $dbh->quote($message);
    my $qtype = $dbh->quote($re->{'type'});

    my $qfaqid = $re->{'faqid'}+0;
    my $quserid = $re->{'posterid'}+0;
    my $spid = $sp->{'spid'}+0;

    my $sql = "INSERT INTO supportlog (splid, spid, timelogged, type, faqid, userid, message) VALUES (NULL, $spid, UNIX_TIMESTAMP(), $qtype, $qfaqid, $quserid, $qmessage)";
    $dbh->do($sql);
    my $splid = $dbh->{'mysql_insertid'};


    my $url = "$LJ::SITEROOT/support/see_request.bml?id=$spid";
    
    my $qspcatid = $sp->{'spcatid'}+0;
    $sth = $dbh->prepare("SELECT u.email, u.userid, u.user ".
                         "FROM supportnotify sn, user u WHERE ".
                         "sn.userid=u.userid AND sn.spcatid=$qspcatid ".
                         "AND sn.level IN ('all')");
    $sth->execute;
    my @to_notify;
    while (my ($email, $userid, $user) = $sth->fetchrow_array) {
        next if $re->{'posterid'} == $userid;
        next if ($re->{'type'} eq "internal" &&
                 ! can_read_internal($dbh, $sp, LJ::make_remote($user, $userid)));
        push @to_notify, $email;
    }
    
    my $body;
    $body = "A follow-up to the request regarding \"$sp->{'subject'}\" has ";
    $body .= "been submitted.  You can track its progress or add ";
    $body .= "information here:\n\n  ";
    $body .= LJ::make_text_link($url, $_->{'email'});
    $body .= "\n\n" . "="x70 . "\n\n";
    $body .= $message;
    
    LJ::send_mail({ 
        'bcc' => join(", ", @to_notify),
        'from' => $LJ::BOGUS_EMAIL,
        'fromname' => 'LiveJournal Support',
        'subject' => "Re: Support Request \#$spid",
        'body' => $body
        });
    
    return $splid;    
}

sub mail_response_to_user
{
    my $dbh = shift;
    my $sp = shift;
    my $splid = shift;

    $splid += 0;

    my $res = load_response($dbh, $splid);
    
    my $email;
    if ($sp->{'reqtype'} eq "email") {
        $email = $sp->{'reqemail'};
    } else {
        my $u = LJ::load_userid($dbh, $sp->{'requserid'});
        $email = $u->{'email'};
    }

    my $spid = $sp->{'spid'}+0;
    my $faqid = $res->{'faqid'}+0;

    my $type = $res->{'type'};

    # don't mail internal comments (user shouldn't see) or 
    # screened answers (have to wait for somebody to approve it first)
    return if ($type eq "internal" || $type eq "screened");

    # the only way it can be zero is if it's a reply to an email, so it's
    # problem the person replying to their own request, so we don't want
    # to mail them:
    return unless ($res->{'userid'});
    
    # also, don't send them their own replies:
    return if ($sp->{'requserid'} == $res->{'userid'});

    my $body = "";
    my $what = $type eq "answer" ? "an answer to" : "a comment on";
    $body .= "Below is $what your support question regarding \"$sp->{'subject'}\".\n";
    $body .= "="x70 . "\n\n";
    if ($faqid) {
        my $faqname = "";
        my $sth = $dbh->prepare("SELECT question FROM faq WHERE faqid=$faqid");
        $sth->execute;
        ($faqname) = $sth->fetchrow_array;
        if ($faqname) {
            $body .= "FAQ QUESTION: " . $faqname . "\n";
            $body .= LJ::make_text_link("$LJ::SITEROOT/support/faqbrowse.bml?faqid=$faqid", $email);
            $body .= "\n\n";
        }
    }

    # Need to escape HTML for AOL's crappy client.
    if ($email =~ /\@aol\.com$/i) {
        $res->{'message'} =~ s/\&/&amp;/g;
        $res->{'message'} =~ s/</&lt;/g;
        $res->{'message'} =~ s/>/&gt;/g;
    } 

    $body .= $res->{'message'};
    $body .= "\n\n" . "="x70 . "\n";
    $body .= "Did this answer your question?  If so, please CLOSE THIS SUPPORT REQUEST\n";
    $body .= "so we can help other people by going here:\n";
    if ($type eq "answer") {
        $body .= LJ::make_text_link("$LJ::SITEROOT/support/act.bml?close;$spid;$sp->{'authcode'};$splid", $email);
    } else {
        $body .= LJ::make_text_link("$LJ::SITEROOT/support/act.bml?close;$spid;$sp->{'authcode'}", $email);
    }
    
    if ($type eq "answer")
    {
        $body .= "\n\nIf this wasn't helpful, you need to go to the following address to prevent\n";
        $body .= "this request from being closed in 7 days.  Click here:\n";
        $body .= LJ::make_text_link("$LJ::SITEROOT/support/act.bml?touch;$spid;$sp->{'authcode'}", $email);
    }
    
    my $miniauth = mini_auth($sp);
    $body .= "\n\nTo read all the comments or add more, go here:\n";
    $body .= LJ::make_text_link("$LJ::SITEROOT/support/see_request.bml?id=$spid&auth=$miniauth", $email);
    
    $body .= "\n";
    
    my $fromemail = $LJ::BOGUS_EMAIL;
    if ($sp->{_cat}->{'replyaddress'}) {
        my $miniauth = mini_auth($sp);
        $fromemail = $sp->{_cat}->{'replyaddress'};
        # insert mini-auth stuff:
        my $rep = "+${spid}z$miniauth\@";
        $fromemail =~ s/\@/$rep/;
    }
    
    LJ::send_mail({ 
        'to' => $email,
        'from' => $fromemail,
        'fromname' => 'LiveJournal Support',
        'subject' => "Re: $sp->{'subject'}",
        'body' => $body  
        });

    if ($type eq "answer") {
        $dbh->do("UPDATE support SET timelasthelp=UNIX_TIMESTAMP() WHERE spid=$spid");
    }
}

sub mini_auth
{
    my $sp = shift;
    return substr($sp->{'authcode'}, 0, 4);
}

1;
