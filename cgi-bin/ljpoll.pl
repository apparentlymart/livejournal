#!/usr/bin/perl
#

package LJ::Poll;

use strict;
use HTML::TokeParser ();

require "$ENV{'LJHOME'}/cgi-bin/cleanhtml.pl";
require "$ENV{'LJHOME'}/cgi-bin/ljlang.pl";

sub clean_poll
{
    my $ref = shift;
    if ($$ref !~ /[<>]/) {
        LJ::text_out($ref);
        return;
    }

    my $poll_eat = [qw[head title style layer iframe applet object]];
    my $poll_allow = [qw[a b i u strong em img]];
    my $poll_remove = [qw[bgsound embed object caption link font]];

    LJ::CleanHTML::clean($ref, {
        'wordlength' => 40,
        'addbreaks' => 0,
        'eat' => $poll_eat,
        'mode' => 'deny',
        'allow' => $poll_allow,
        'remove' => $poll_remove,
    });
    LJ::text_out($ref);
}


sub contains_new_poll
{
    my $postref = shift;
    return ($$postref =~ /<lj-poll\b/i);
}

sub parse
{
    &LJ::nodb;
    my ($postref, $error, $iteminfo) = @_;

    $iteminfo->{'posterid'} += 0;
    $iteminfo->{'journalid'} += 0;

    my $newdata;

    my $popen = 0;
    my %popts;

    my $qopen = 0;
    my %qopts;
    
    my $iopen = 0;
    my %iopts;

    my @polls;  # completed parsed polls

    my $p = HTML::TokeParser->new($postref);

    # if we're being called from mailgated, then we're not in web context and therefore
    # do not have any BML::ml functionality.  detect this now and report errors in a 
    # plaintext, non-translated form to be bounced via email.

    # FIXME: the above comment is obsolete, we now have LJ::Lang::ml
    # which will do the right thing
    my $have_bml = eval { LJ::Lang::ml() } || ! $@;

    my $err = sub {
        # more than one element, either make a call to LJ::Lang::ml
        # or build up a semi-useful error string from it
        if (@_ > 1) {
            if ($have_bml) {
                $$error = LJ::Lang::ml(@_);
                return 0;
            }

            $$error = shift() . ": ";
            while (my ($k, $v) = each %{$_[0]}) {
                $$error .= "$k=$v,";
            }
            chop $$error;
            return 0;
        }

        # single element, either look up in %BML::ML or return verbatim
        $$error = $have_bml ? LJ::Lang::ml($_[0]) : $_[0];
        return 0;
    };

    while (my $token = $p->get_token)    
    {
        my $type = $token->[0];
        my $append;
        
        if ($type eq "S")     # start tag
        {
            my $tag = $token->[1];
            my $opts = $token->[2];
    
            ######## Begin poll tag
            
            if ($tag eq "lj-poll") {
                return $err->('poll.error.nested', { 'tag' => 'lj-poll' })
                    if $popen;

                $popen = 1;
                %popts = ();
                $popts{'questions'} = [];

                $popts{'name'} = $opts->{'name'};
                $popts{'whovote'} = lc($opts->{'whovote'}) || "all";
                $popts{'whoview'} = lc($opts->{'whoview'}) || "all";

                if ($popts{'whovote'} ne "all" && 
                    $popts{'whovote'} ne "friends")
                {
                    return $err->('poll.error.whovote');
                }
                if ($popts{'whoview'} ne "all" && 
                    $popts{'whoview'} ne "friends" &&
                    $popts{'whoview'} ne "none")
                {
                    return $err->('poll.error.whoview');
                }
            }

            ######## Begin poll question tag
            
            elsif ($tag eq "lj-pq") 
            {
                return $err->('poll.error.nested', { 'tag' => 'lj-pq' })
                    if $qopen;

                return $err->('poll.error.missingljpoll')
                    unless $popen;

                $qopen = 1;
                %qopts = ();
                $qopts{'items'} = [];

                $qopts{'type'} = $opts->{'type'};
                if ($qopts{'type'} eq "text") {
                    my $size = 35;
                    my $max = 255;
                    if (defined $opts->{'size'}) {
                        if ($opts->{'size'} > 0 &&
                            $opts->{'size'} <= 100)
                        {
                            $size = $opts->{'size'}+0;
                        } else {
                            return $err->('poll.error.badsize');
                        }
                    }
                    if (defined $opts->{'maxlength'}) {
                        if ($opts->{'maxlength'} > 0 &&
                            $opts->{'maxlength'} <= 255)
                        {
                            $max = $opts->{'maxlength'}+0;
                        } else {
                            return $err->('poll.error.badmaxlength');
                        }
                    }

                    $qopts{'opts'} = "$size/$max";
                }
                if ($qopts{'type'} eq "scale") 
                {
                    my $from = 1;
                    my $to = 10;
                    my $by = 1;

                    if (defined $opts->{'from'}) {
                        $from = int($opts->{'from'});
                    }
                    if (defined $opts->{'to'}) {
                        $to = int($opts->{'to'});
                    }
                    if (defined $opts->{'by'}) {
                        $by = int($opts->{'by'});
                    }
                    if ($by < 1) {
                        return $err->('poll.error.scaleincrement');
                    }
                    if ($from >= $to) {
                        return $err->('poll.error.scalelessto');
                    }
                    if ((($to-$from)/$by) > 20) {
                        return $err->('poll.error.scaletoobig');
                    }
                    $qopts{'opts'} = "$from/$to/$by";
                }

                $qopts{'type'} = lc($opts->{'type'}) || "text";

                if ($qopts{'type'} ne "radio" &&
                    $qopts{'type'} ne "check" &&
                    $qopts{'type'} ne "drop" &&
                    $qopts{'type'} ne "scale" &&
                    $qopts{'type'} ne "text")
                {
                    return $err->('poll.error.unknownpqtype');
                }
                
                
            }

            ######## Begin poll item tag

            elsif ($tag eq "lj-pi")
            {
                if ($iopen) {
                    return $err->('poll.error.nested', { 'tag' => 'lj-pi' });
                }
                if (! $qopen) {
                    return $err->('poll.error.missingljpq');
                }
                if ($qopts{'type'} eq "text")
                {
                    return $err->('poll.error.noitemstext');
                }
                
                $iopen = 1;
                %iopts = ();
            }   

            #### not a special tag.  dump it right back out.

            else 
            {
                $append .= "<$tag";
                foreach (keys %$opts) {
                    $append .= " $_=\"$opts->{$_}\"";
                }
                $append .= ">";
            }
        }
        elsif ($type eq "E") 
        {
            my $tag = $token->[1];

            ##### end POLL

            if ($tag eq "lj-poll") {
                return $err->('poll.error.tagnotopen', { 'tag' => 'lj-poll' })
                    unless $popen;

                $popen = 0;

                return $err->('poll.error.noquestions')
                    unless @{$popts{'questions'}};
                
                $popts{'journalid'} = $iteminfo->{'journalid'};
                $popts{'posterid'} = $iteminfo->{'posterid'};
                
                push @polls, { %popts };

                $append .= "<lj-poll-placeholder>";
            } 

            ##### end QUESTION

            elsif ($tag eq "lj-pq") {
                return $err->('poll.error.tagnotopen', { 'tag' => 'lj-pq' })
                    unless $qopen;

                unless ($qopts{'type'} eq "scale" || 
                        $qopts{'type'} eq "text" || 
                        @{$qopts{'items'}}) 
                {
                    return $err->('poll.error.noitems');
                }

                $qopts{'qtext'} =~ s/^\s+//;
                $qopts{'qtext'} =~ s/\s+$//;
                my $len = length($qopts{'qtext'})
                    or return $err->('poll.error.notext');

                push @{$popts{'questions'}}, { %qopts };
                $qopen = 0;
                
            }

            ##### end ITEM

            elsif ($tag eq "lj-pi") {
                return $err->('poll.error.tagnotopen', { 'tag' => 'lj-pi' })
                    unless $iopen;

                $iopts{'item'} =~ s/^\s+//;
                $iopts{'item'} =~ s/\s+$//;

                my $len = length($iopts{'item'});
                return $err->('poll.error.pitoolong', { 'len' => $len, })
                    if $len > 255 || $len < 1;

                push @{$qopts{'items'}}, { %iopts };
                $iopen = 0;
            }
            
            ###### not a special tag.
            
            else
            {
                $append .= "</$tag>";
            }
        }
        elsif ($type eq "T" || $type eq "D") 
        {
            $append = $token->[1];
        } 
        elsif ($type eq "C") {
            # ignore comments
        }
        elsif ($type eq "PI") {
            $newdata .= "<?$token->[1]>";
        }
        else {
            $newdata .= "<!-- OTHER: " . $type . "-->\n";
        }

        ##### append stuff to the right place
        if (length($append))
        {
            if ($iopen) {
                $iopts{'item'} .= $append;
            }
            elsif ($qopen) {
                $qopts{'qtext'} .= $append;
            }
            elsif ($popen) {
                0;       # do nothing.
            } else {
                $newdata .= $append;
            }
        }

    } 

    if ($popen) { return $err->('poll.error.unlockedtag', { 'tag' => 'lj-poll' }); }
    if ($qopen) { return $err->('poll.error.unlockedtag', { 'tag' => 'lj-pq' }); }
    if ($iopen) { return $err->('poll.error.unlockedtag', { 'tag' => 'lj-pi' }); }

    $$postref = $newdata;
    return @polls;
}

# preview poll
#  -- accepts $poll hashref as found in the array returned by LJ::Poll::parse()
sub preview {
    my $poll = shift;
    return unless ref $poll eq 'HASH';
    
    my $ret = '';
    
    $ret .= "<form action='#'>\n";
    $ret .= "<b>" . LJ::Lang::ml('poll.pollnum', { 'num' => 'xxxx' }) . "</b>";
    if ($poll->{'name'}) {
        LJ::Poll::clean_poll(\$poll->{'name'});
        $ret .= " <i>$poll->{'name'}</i>";
    }
    $ret .= "<br />\n";
    $ret .= LJ::Lang::ml('poll.security', { 'whovote' => LJ::Lang::ml('poll.security.'.$poll->{whovote}), 'whoview' => LJ::Lang::ml('poll.security.'.$poll->{whoview}), });
    
    # iterate through all questions
    foreach my $q (@{$poll->{'questions'}}) {
        if ($q->{'qtext'}) {
            LJ::Poll::clean_poll(\$q->{'qtext'});
            $ret .= "<p>$q->{'qtext'}</p>\n";
        }
        $ret .= "<div style='margin: 10px 0 10px 40px'>";

        # text questions
        if ($q->{'type'} eq 'text') {
            my ($size, $max) = split(m!/!, $q->{'opts'});
            $ret .= LJ::html_text({ 'size' => $size, 'maxlength' => $max });

        # scale questions
        } elsif ($q->{'type'} eq 'scale') {
            my ($from, $to, $by) = split(m!/!, $q->{'opts'});
            $by ||= 1;
            my $count = int(($to-$from)/$by) + 1;
            my $do_radios = ($count <= 11);
            
            # few opts, display radios
            if ($do_radios) {
                $ret .= "<table><tr valign='top' align='center'>\n";
                for (my $at = $from; $at <= $to; $at += $by) {
                    $ret .= "<td>" . LJ::html_check({ 'type' => 'radio' }) . "<br />$at</td>\n";
                }
                $ret .= "</tr></table>\n";

            # many opts, display select
            } else {
                my @optlist = ();
                for (my $at = $from; $at <= $to; $at += $by) {
                    push @optlist, ('', $at);
                }
                $ret .= LJ::html_select({}, @optlist);
            }
            
        # questions with items
        } else {

            # drop-down list
            if ($q->{'type'} eq 'drop') {
                my @optlist = ('', '');
                foreach my $it (@{$q->{'items'}}) {
                    LJ::Poll::clean_poll(\$it->{'item'});
                    push @optlist, ('', $it->{'item'});
                }
                $ret .= LJ::html_select({}, @optlist);


            # radio or checkbox
            } else {
                foreach my $it (@{$q->{'items'}}) {
                    LJ::Poll::clean_poll(\$it->{'item'});
                    $ret .= LJ::html_check({ 'type' => $q->{'type'} }) . "$it->{'item'}<br />\n";
                }
            }
        }
        
        $ret .= "</div>\n";
        
    }
    
    $ret .= LJ::html_submit('', LJ::Lang::ml('poll.submit'), { 'disabled' => 1 }) . "\n";
    $ret .= "</form>";
    
    return $ret; 
}

# note: $itemid is a $ditemid (display itemid, *256 + anum)
sub register
{
    &LJ::nodb;
    my $dbh = LJ::get_db_writer();
    my $post = shift;
    my $error = shift;
    my $itemid = shift;
    my @polls = @_;
    
    foreach my $po (@polls)
    {
        my %popts = %$po;
        $popts{'itemid'} = $itemid+0;

        #### CREATE THE POLL!
        
        my $sth = $dbh->prepare("INSERT INTO poll (itemid, journalid, posterid, whovote, whoview, name) " .
                                "VALUES (?, ?, ?, ?, ?, ?)");
        $sth->execute($itemid, $popts{'journalid'}, $popts{'posterid'},
                      $popts{'whovote'}, $popts{'whoview'}, $popts{'name'});
        if ($dbh->err) {
            $$error = LJ::Lang::ml('poll.dberror', { errmsg => $dbh->errstr });
            return 0;
        }
        my $pollid = $dbh->{'mysql_insertid'};

        $$post =~ s/<lj-poll-placeholder>/<lj-poll-$pollid>/;  # NOT global replace!
        
        ## start inserting poll questions
        my $qnum = 0;
        foreach my $q (@{$popts{'questions'}})
        {
            $qnum++;
            $sth = $dbh->prepare("INSERT INTO pollquestion (pollid, pollqid, sortorder, type, opts, qtext) " . 
                                 "VALUES (?, ?, ?, ?, ?, ?)");
            $sth->execute($pollid, $qnum, $qnum, $q->{'type'}, $q->{'opts'}, $q->{'qtext'});
            if ($dbh->err) {
                $$error = LJ::Lang::ml('poll.dberror.questions', { errmsg => $dbh->errstr });
                return 0;
            }
            
            my $pollqid = $dbh->{'mysql_insertid'};
            
            ## start inserting poll items
            my $inum = 0;
            foreach my $it (@{$q->{'items'}}) {
                $inum++;
                $dbh->do("INSERT INTO pollitem (pollid, pollqid, pollitid, sortorder, item) " . 
                         "VALUES (?, ?, ?, ?, ?)", undef, $pollid, $qnum, $inum, $inum, $it->{'item'});
                if ($dbh->err) {
                    $$error = LJ::Lang::ml('poll.dberror.items', { errmsg => $dbh->errstr });
                    return 0;
                }
            }
            ## end inserting poll items
            
        }
        ## end inserting poll questions
        
    }  ### end while over all poles

}

sub show_polls
{
    &LJ::nodb;
    my $itemid = shift;
    my $remote = shift;
    my $postref = shift;

    $$postref =~ s/<lj-poll-(\d+)>/&show_poll($itemid, $remote, $1)/eg;
}

sub show_poll
{
    &LJ::nodb;
    my $dbr = LJ::get_db_reader();
    my $itemid = shift;
    my $remote = shift;
    my $pollid = shift;
    my $opts = shift;  # hashref.  {"mode" => results/enter/ans}
    my $sth;

    my $mode = $opts->{'mode'};
    $pollid += 0;
    
    my $po = $dbr->selectrow_hashref("SELECT * FROM poll WHERE pollid=?", undef, $pollid);
    return "<b>[" . LJ::Lang::ml('poll.error.pollnotfound', { 'num' => $pollid }) . "]</b>" unless $po;
    return "<b>[" . LJ::Lang::ml('poll.error.noentry') . "</b>"
        if $itemid && $po->{'itemid'} != $itemid;

    my ($can_vote, $can_view) = find_security($po, $remote);

    # update the mode if we need to
    $mode = 'results' unless $remote;
    if (!$mode && $remote) {
        my $time = $dbr->selectrow_array('SELECT datesubmit FROM pollsubmission '.
                                         'WHERE pollid=? AND userid=?', undef, $pollid, $remote->{userid});
        $mode = $time ? 'results' : $can_vote ? 'enter' : 'results';
    }

    ### load all the questions
    my @qs;
    $sth = $dbr->prepare('SELECT * FROM pollquestion WHERE pollid=?');
    $sth->execute($pollid);
    push @qs, $_ while $_ = $sth->fetchrow_hashref;
    @qs = sort { $a->{sortorder} <=> $b->{sortorder} } @qs;

    ### load all the items
    my %its;
    $sth = $dbr->prepare("SELECT pollqid, pollitid, item FROM pollitem WHERE pollid=? ORDER BY sortorder");
    $sth->execute($pollid);
    while (my ($qid, $itid, $item) = $sth->fetchrow_array) {
        push @{$its{$qid}}, [ $itid, $item ];
    }

    # see if we have a hook for alternate poll contents
    my $ret = LJ::run_hook('alternate_show_poll_html', $po, $mode, \@qs);
    return $ret if $ret;

    ### view answers to a particular question in a poll
    if ($mode eq "ans") 
    {
        return "<b>[" . LJ::Lang::ml('poll.error.cantview') . "]</b>"
            unless $can_view;

        # get the question from @qs, which we loaded earlier
        my $q;
        foreach (@qs) {
            $q = $_ if $_->{pollqid} == $opts->{qid};
        }
        return "<b>[" . LJ::Lang::ml('poll.error.questionnotfound') . "]</b>"
            unless $q;

        # get the item information from %its, also loaded earlier
        my %it;
        $it{$_->[0]} = $_->[1] foreach (@{$its{$opts->{qid}}});

        LJ::Poll::clean_poll(\$q->{'qtext'});
        $ret .= $q->{'qtext'};
        $ret .= "<p>";

        my $LIMIT = 2000;
        $sth = $dbr->prepare("SELECT u.user, pr.value, ps.datesubmit ".
                             "FROM useridmap u, pollresult pr, pollsubmission ps " . 
                             "WHERE u.userid=pr.userid AND pr.pollid=? AND pollqid=? " . 
                             "AND ps.pollid=pr.pollid AND ps.userid=pr.userid LIMIT $LIMIT");
        $sth->execute($pollid, $opts->{'qid'});

        my @res;
        push @res, $_ while $_ = $sth->fetchrow_hashref;
        @res = sort { $a->{datesubmit} cmp $b->{datesubmit} } @res;
        
        foreach my $res (@res) {
            my ($user, $value) = ($res->{user}, $res->{value});
            
            ## some question types need translation; type 'text' doesn't.
            if ($q->{'type'} eq "radio" || $q->{'type'} eq "drop") {
                $value = $it{$value};
            }
            elsif ($q->{'type'} eq "check") {
                $value = join(", ", map { $it{$_} } split(/,/, $value));
            }

            LJ::Poll::clean_poll(\$value);
            $ret .= "<p>" . LJ::ljuser($user) . " -- $value</p>\n";
        }

        # temporary
        if (@res == $LIMIT) {
            $ret .= "<p>[" . LJ::Lang::ml('poll.error.truncated') . "]</p>";
        }
        
        return $ret;
    }

    # Users cannot vote unless they are logged in
    return "<?needlogin?>"
        if $mode eq 'enter' && !$remote;

    my $do_form = $mode eq 'enter' && $can_vote;
    my %preval;

    if ($do_form) {
        $sth = $dbr->prepare("SELECT pollqid, value FROM pollresult WHERE pollid=? AND userid=?");
        $sth->execute($pollid, $remote->{'userid'});
        while (my ($qid, $value) = $sth->fetchrow_array) {
            $preval{$qid} = $value;
        }

        $ret .= "<form action='$LJ::SITEROOT/poll/?id=$pollid' method='post'>";
        $ret .= LJ::form_auth();
        $ret .= LJ::html_hidden('pollid', $pollid);
    }

    $ret .= "<b><a href='$LJ::SITEROOT/poll/?id=$pollid'>" . LJ::Lang::ml('poll.pollnum', { 'num' => $pollid }) . "</a></b> ";
    if ($po->{'name'}) {
        LJ::Poll::clean_poll(\$po->{'name'});
        $ret .= "<i>$po->{'name'}</i>";
    }
    $ret .= "<br />\n";
    $ret .= LJ::Lang::ml('poll.security', { 'whovote' => LJ::Lang::ml('poll.security.'.$po->{whovote}), 
                                       'whoview' => LJ::Lang::ml('poll.security.'.$po->{whoview}) }); 
    my $text = LJ::run_hook('extra_poll_description', $po, \@qs);
    $ret .= "<br />$text" if $text;

    ## go through all questions, adding to buffer to return
    foreach my $q (@qs)
    {
        my $qid = $q->{'pollqid'};
        LJ::Poll::clean_poll(\$q->{'qtext'});
        $ret .= "<p>$q->{'qtext'}</p><div style='margin: 10px 0 10px 40px'>";
        
        ### get statistics, for scale questions
        my ($valcount, $valmean, $valstddev, $valmedian);
        if ($q->{'type'} eq "scale") 
        {
            ## manually add all the possible values, since they aren't in the database
            ## (which was the whole point of making a "scale" type):
            my ($from, $to, $by) = split(m!/!, $q->{'opts'});
            $by = 1 unless ($by > 0 and int($by) == $by);
            for (my $at=$from; $at<=$to; $at+=$by) {
                push @{$its{$qid}}, [ $at, $at ];  # note: fake itemid, doesn't matter, but needed to be unique
            }

            $sth = $dbr->prepare("SELECT COUNT(*), AVG(value), STDDEV(value) FROM pollresult WHERE pollid=? AND pollqid=?");
            $sth->execute($pollid, $qid);
            ($valcount, $valmean, $valstddev) = $sth->fetchrow_array;
            
            # find median:
            $valmedian = 0;
            if ($valcount == 1) { 
                $valmedian = $valmean;
            } elsif ($valcount > 1) {
                my ($mid, $fetch);
                # fetch two mids and average if even count, else grab absolute middle
                $fetch = ($valcount % 2) ? 1 : 2;
                $mid = int(($valcount+1)/2);
                my $skip = $mid-1;

                $sth = $dbr->prepare("SELECT value FROM pollresult WHERE pollid=? AND pollqid=? " .
                                     "ORDER BY value+0 LIMIT $skip,$fetch");
                $sth->execute($pollid, $qid);
                while (my ($v) = $sth->fetchrow_array) {
                    $valmedian += $v;
                }
                $valmedian /= $fetch;
            }
        }

        my $usersvoted = 0;
        my %itvotes;
        my $maxitvotes = 1;

        if ($mode eq "results")
        {
            ### to see individual's answers
            $ret .= "<a href='$LJ::SITEROOT/poll/?id=$pollid&amp;qid=$qid&amp;mode=ans'>" .
                LJ::Lang::ml('poll.viewanswers') . "</a><br />";

            ### but, if this is a non-text item, and we're showing results, need to load the answers:
            if ($q->{'type'} ne "text") {
                $sth = $dbr->prepare("SELECT value FROM pollresult WHERE pollid=? AND pollqid=?");
                $sth->execute($pollid, $qid);
                while (my ($val) = $sth->fetchrow_array) {
                    $usersvoted++;
                    if ($q->{'type'} eq "check") {
                        foreach (split(/,/,$val)) {
                            $itvotes{$_}++;
                        }
                    } else {
                        $itvotes{$val}++;
                    }
                }
                
                foreach (values %itvotes) {
                    $maxitvotes = $_ if ($_ > $maxitvotes);
                }
            }
        }

        #### text questions are the easy case

        if ($q->{'type'} eq "text" && $do_form) {
            my ($size, $max) = split(m!/!, $q->{'opts'});

            $ret .= LJ::html_text({ 'size' => $size, 'maxlength' => $max, 
                                    'name' => "pollq-$qid", 'value' => $preval{$qid} });
        }

        #### drop-down list
        elsif ($q->{'type'} eq 'drop' && $do_form) {
            my @optlist = ('', '');
            foreach my $it (@{$its{$qid}}) {
                my ($itid, $item) = @$it;
                LJ::Poll::clean_poll(\$item);
                push @optlist, ($itid, $item);
            }
            $ret .= LJ::html_select({ 'name' => "pollq-$qid", 
                                      'selected' => $preval{$qid} }, @optlist);
        }

        #### scales (from 1-10) questions

        elsif ($q->{'type'} eq "scale" && $do_form) {
            my ($from, $to, $by) = split(m!/!, $q->{'opts'});
            $by ||= 1;
            my $count = int(($to-$from)/$by) + 1;
            my $do_radios = ($count <= 11);

            # few opts, display radios
            if ($do_radios) {

                $ret .= "<table><tr valign='top' align='center'>";

                for (my $at=$from; $at<=$to; $at+=$by) {
                    $ret .= "<td style='text-align: center;'>";
                    $ret .= LJ::html_check({ 'type' => 'radio', 'name' => "pollq-$qid",
                                             'value' => $at, 'id' => "pollq-$pollid-$qid-$at",
                                             'selected' => (defined $preval{$qid} && $at == $preval{$qid}) });
                    $ret .= "<br /><label for='pollq-$pollid-$qid-$at'>$at</label></td>";
                }

                $ret .= "</tr></table>\n";

            # many opts, display select
            # but only if displaying form
            } else {

                my @optlist = ('', '');
                for (my $at=$from; $at<=$to; $at+=$by) {
                    push @optlist, ($at, $at);
                }
                $ret .= LJ::html_select({ 'name' => "pollq-$qid", 'selected' => $preval{$qid} }, @optlist);
            }

        }

        #### now, questions with items

        else
        {
            my $do_table = 0;

            if ($q->{'type'} eq "scale") { # implies ! do_form
                my $stddev = sprintf("%.2f", $valstddev);
                my $mean = sprintf("%.2f", $valmean);
                $ret .= LJ::Lang::ml('poll.scaleanswers', { 'mean' => $mean, 'median' => $valmedian, 'stddev' => $stddev });
                $ret .= "<br />\n";
                $do_table = 1;
                $ret .= "<table>";
            }

            foreach my $it (@{$its{$qid}})
            {
                my ($itid, $item) = @$it;
                LJ::Poll::clean_poll(\$item);

                # displaying a radio or checkbox
                if ($do_form) {
                    $ret .= LJ::html_check({ 'type' => $q->{'type'}, 'name' => "pollq-$qid",
                                             'value' => $itid, 'id' => "pollq-$pollid-$qid-$itid",
                                             'selected' => ($preval{$qid} =~ /\b$itid\b/) });
                    $ret .= " <label for='pollq-$pollid-$qid-$itid'>$item</label><br />";
                    next;
                }

                # displaying results
                my $count = $itvotes{$itid}+0;
                my $percent = sprintf("%.1f", (100 * $count / ($usersvoted||1)));
                my $width = 20+int(($count/$maxitvotes)*380);

                if ($do_table) {
                    $ret .= "<tr valign='middle'><td align='right'>$item</td>";
                    $ret .= "<td><img src='$LJ::IMGPREFIX/poll/leftbar.gif' style='vertical-align:middle' height='14' width='7' alt='' />";
                    $ret .= "<img src='$LJ::IMGPREFIX/poll/mainbar.gif' style='vertical-align:middle' height='14' width='$width' alt='' />";
                    $ret .= "<img src='$LJ::IMGPREFIX/poll/rightbar.gif' style='vertical-align:middle' height='14' width='7' alt='' /> ";
                    $ret .= "<b>$count</b> ($percent%)</td></tr>";
                } else {
                    $ret .= "<p>$item<br />";
                    $ret .= "<span style='white-space: nowrap'><img src='$LJ::IMGPREFIX/poll/leftbar.gif' style='vertical-align:middle' height='14' alt='' />";
                    $ret .= "<img src='$LJ::IMGPREFIX/poll/mainbar.gif' style='vertical-align:middle' height='14' width='$width' alt='' />";
                    $ret .= "<img src='$LJ::IMGPREFIX/poll/rightbar.gif' style='vertical-align:middle' height='14' width='7' alt='' /> ";
                    $ret .= "<b>$count</b> ($percent%)</span></p>";
                }
            }

            if ($do_table) {
                $ret .= "</table>";
            }

        }

        $ret .= "</div>";
    }
    
    if ($do_form) {
        $ret .= LJ::html_submit('poll-submit', LJ::Lang::ml('poll.submit')) . "</form>\n";;
    }
    
    return $ret;
}

sub find_security
{
    &LJ::nodb;

    my $po = shift;
    my $remote = shift;
    my $sth;

    ## if remote is poll owner, can do anything.
    if ($remote && $remote->{'userid'} == $po->{'posterid'}) {
        return (1, 1);
    }

    ## need to be both a person and with a visible journal to vote
    if ($remote &&
        ($remote->{'journaltype'} ne "P" || $remote->{'statusvis'} ne "V")) {
        return (0, 0);
    }

    my $is_friend = 0;
    if (($po->{'whoview'} eq "friends" || 
         $po->{'whovote'} eq "friends") && $remote)
    {
        $is_friend = LJ::is_friend($po->{'journalid'}, $remote->{'userid'});
    }

    my %sec;
    if ($po->{'whoview'} eq "all" ||
        ($po->{'whoview'} eq "friends" && $is_friend) ||
        ($po->{'whoview'} eq "none" && $remote && $remote->{'userid'} == $po->{'posterid'}))
    {
        $sec{'view'} = 1;
    }

    if ($po->{'whovote'} eq "all" ||
        ($po->{'whovote'} eq "friends" && $is_friend))
    {
        $sec{'vote'} = 1;
    }

    if ($sec{'vote'} && (LJ::is_banned($remote, $po->{'journalid'}) ||
                         LJ::is_banned($remote, $po->{'posterid'}))) {
        $sec{'vote'} = 0;
    }
    
    return ($sec{'vote'}, $sec{'view'});
}

sub submit
{
    &LJ::nodb;
    
    my $remote = shift;
    my $form = shift;
    my $error = shift;
    my $sth;

    my $dbh = LJ::get_db_writer();

    unless ($remote) {
        $$error = LJ::error_noremote(); # instead of <?needlogin?>, because errors are displayed in LJ::bad_input()
        return 0;
    }

    my $pollid = $form->{'pollid'}+0;
    my $po = $dbh->selectrow_hashref("SELECT itemid, whovote, journalid, posterid, whoview, whovote, name ".
                                     "FROM poll WHERE pollid=?", undef, $pollid);
    unless ($po) {
        $$error = LJ::Lang::ml('poll.error.nopollid');
        return 0;	
    }
    
    my ($can_vote, undef) = find_security($po, $remote);

    unless ($can_vote) {
        $$error = LJ::Lang::ml('poll.error.cantvote');
        return 0;
    }

    ### load all the questions
    my @qs;
    $sth = $dbh->prepare("SELECT pollqid, type, opts, qtext FROM pollquestion WHERE pollid=?");
    $sth->execute($pollid);
    push @qs, $_ while $_ = $sth->fetchrow_hashref;
    
    foreach my $q (@qs) {
        my $qid = $q->{'pollqid'}+0;
        my $val = $form->{"pollq-$qid"};
        if ($q->{'type'} eq "check") {
            ## multi-selected items are comma separated from htdocs/poll/index.bml
            $val = join(",", sort { $a <=> $b } split(/,/, $val));
        }
        if ($q->{'type'} eq "scale") {
            my ($from, $to, $by) = split(m!/!, $q->{'opts'});
            if ($val < $from || $val > $to) { 
                # bogus! cheating?
                $val = "";
            }
        }
        if ($val ne "") {
            $dbh->do("REPLACE INTO pollresult (pollid, pollqid, userid, value) VALUES (?, ?, ?, ?)",
                     undef, $pollid, $qid, $remote->{'userid'}, $val);
        } else {
            $dbh->do("DELETE FROM pollresult WHERE pollid=? AND pollqid=? AND userid=?",
                     undef, $pollid, $qid, $remote->{'userid'});
        }
    }
    
    ## finally, register the vote happened
    $dbh->do("REPLACE INTO pollsubmission (pollid, userid, datesubmit) VALUES (?, ?, NOW())",
             undef, $pollid, $remote->{'userid'});

    return 1;
}

1;
