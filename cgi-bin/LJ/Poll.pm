package LJ::Poll;
use strict;
use Carp qw (croak);
use Class::Autouse qw (LJ::Entry);

# loads a poll
sub new {
    my ($class, $pollid) = @_;

    croak "No pollid passed to LJ::Poll->new"
        unless $pollid;

    my $self = {
        pollid => $pollid,
    };

    bless $self, 'LJ::PollObj';
    return $self;
}

# create a new poll
# returns created poll object on success, 0 on failure
#
# %opts:
#   questions: arrayref of poll questions
#   error: scalarref for errors to be returned in
#   entry: LJ::Entry object that this poll is attached to
#   ditemid, journalid, posterid: required if no entry object passed
#   whovote: who can vote in this poll
#   whoview: who can view this poll
#   name: name of this poll
sub create {
    my ($class, %opts) = @_;

    my $entry = $opts{entry};

    my ($ditemid, $journalid, $posterid);

    if ($entry) {
        $ditemid   = $entry->ditemid;
        $journalid = $entry->journalid;
        $posterid  = $entry->posterid;
    } else {
        $ditemid   = $opts{ditemid} or croak "No ditemid";
        $journalid = $opts{journalid} or croak "No journalid";
        $posterid  = $opts{posterid} or croak "No posterid";
    }

    my $questions = delete $opts{questions}
        or croak "No questions passed to create";

    my $dbh = LJ::get_db_writer()
        or die "Could not get db writer";

    my $sth = $dbh->prepare("INSERT INTO poll (itemid, journalid, posterid, whovote, whoview, name) " .
                            "VALUES (?, ?, ?, ?, ?, ?)");
    $sth->execute($ditemid, $journalid, $posterid,
                  $opts{whovote}, $opts{whoview}, $opts{name});
    if ($dbh->err) {
        ${$opts{error}} = LJ::Lang::ml('poll.dberror', { errmsg => $dbh->errstr });
        return 0;
    }

    my $pollid = $dbh->{'mysql_insertid'};

    ## start inserting poll questions
    my $qnum = 0;

    foreach my $q (@$questions) {
        $qnum++;
        $sth = $dbh->prepare("INSERT INTO pollquestion (pollid, pollqid, sortorder, type, opts, qtext) " .
                             "VALUES (?, ?, ?, ?, ?, ?)");
        $sth->execute($pollid, $qnum, $qnum, $q->{'type'}, $q->{'opts'}, $q->{'qtext'});
        if ($dbh->err) {
            ${$opts{error}} = LJ::Lang::ml('poll.dberror.questions', { errmsg => $dbh->errstr });
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
                ${$opts{error}} = LJ::Lang::ml('poll.dberror.items', { errmsg => $dbh->errstr });
                return 0;
            }
        }
        ## end inserting poll items

    }
    ## end inserting poll questions

    return LJ::Poll->new($pollid);
}

package LJ::PollObj;
use strict;
use Carp qw (croak);
require "$ENV{LJHOME}/cgi-bin/ljpoll.pl"; # goal is to get rid of this

##### Poll rendering

sub render_results {
    my $self = shift;
    my %opts = @_;
    return LJ::PollObj::render($self, mode => 'results', %opts);
}

sub render_enter {
    my $self = shift;
    my %opts = @_;
    return LJ::PollObj::render($self, mode => 'enter', %opts);
}

sub render_ans {
    my $self = shift;
    my %opts = @_;
    return LJ::PollObj::render($self, mode => 'ans', %opts);
}

###### Utility methods

# loads poll from db
sub _load {
    my $self = shift;

    # global query for now
    my $dbr = LJ::get_db_reader();
    my $row = $dbr->selectrow_hashref("SELECT pollid, itemid, journalid, " .
                                      "posterid, whovote, whoview, name " .
                                      "FROM poll WHERE pollid=?", undef, $self->pollid);
    return undef unless $row; # throw error?

    $self->absorb_row($row);
}

sub absorb_row {
    my ($self, $row) = @_;
    croak "No row" unless $row;

    $self->{$_} = $row->{$_} foreach qw(pollid itemid journalid posterid whovote whoview name);
}

######### Accessors
# ditemid
sub itemid {
    my $self = shift;
    $self->_load;
    return $self->{itemid};
}
sub name {
    my $self = shift;
    $self->_load;
    return $self->{name};
}
sub whovote {
    my $self = shift;
    $self->_load;
    return $self->{whovote};
}
sub whoview {
    my $self = shift;
    $self->_load;
    return $self->{whoview};
}
sub journalid {
    my $self = shift;
    $self->_load;
    return $self->{journalid};
}
sub posterid {
    my $self = shift;
    $self->_load;
    return $self->{posterid};
}

sub pollid { $_[0]->{pollid} }

sub entry {
    my $self = shift;
    return LJ::Entry->new($self->journal, ditemid => $self->itemid);
}

sub journal {
    my $self = shift;
    return LJ::load_userid($self->journalid);
}


######## Instance Methods

# returns HTML of rendered poll
# opts:
#   mode => enter|results|ans
#   qid  => show a specific question
sub render {
    my ($self, %opts) = @_;

    my $remote = LJ::get_remote();
    my $itemid = $self->itemid;
    my $pollid = $self->pollid;

    my $mode = delete $opts{mode};
    my $qid  = delete $opts{qid};

    return "<b>[" . LJ::Lang::ml('poll.error.pollnotfound', { 'num' => $pollid }) . "]</b>" unless $pollid;
    return "<b>[" . LJ::Lang::ml('poll.error.noentry') . "</b>" unless $itemid;

    my $can_vote = $self->can_vote;
    my $can_voew = $self->can_view;

    my $dbr = LJ::get_db_reader();

    # update the mode if we need to
    $mode = 'results' if !$remote || !$mode;
    if (!$mode && $remote) {
        my $time = $dbr->selectrow_array('SELECT datesubmit FROM pollsubmission '.
                                         'WHERE pollid=? AND userid=?', undef, $pollid, $remote->userid);
        $mode = $time ? 'results' : $can_vote ? 'enter' : 'results';
    }

    ### load all the questions
    my @qs;
    my $sth = $dbr->prepare('SELECT * FROM pollquestion WHERE pollid=?');
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

    my $ret = '';

    ### view answers to a particular question in a poll
    if ($mode eq "ans")
    {
        return "<b>[" . LJ::Lang::ml('poll.error.cantview') . "]</b>"
            unless $self->can_view;

        # get the question from @qs, which we loaded earlier
        my $q;
        foreach (@qs) {
            $q = $_ if $_->{pollqid} == $qid;
        }
        return "<b>[" . LJ::Lang::ml('poll.error.questionnotfound') . "]</b>"
            unless $q;

        # get the item information from %its, also loaded earlier
        my %it;
        $it{$_->[0]} = $_->[1] foreach (@{$its{$qid}});

        LJ::Poll::clean_poll(\$q->{'qtext'});
        $ret .= $q->{'qtext'};
        $ret .= "<p>";

        my $LIMIT = 2000;
        $sth = $dbr->prepare("SELECT u.user, pr.value, ps.datesubmit ".
                             "FROM useridmap u, pollresult pr, pollsubmission ps " .
                             "WHERE u.userid=pr.userid AND pr.pollid=? AND pollqid=? " .
                             "AND ps.pollid=pr.pollid AND ps.userid=pr.userid LIMIT $LIMIT");
        $sth->execute($pollid, $qid);

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
    if ($self->name) {
        my $name = $self->name;
        LJ::Poll::clean_poll(\$name);
        $ret .= "<i>$name</i>";
    }
    $ret .= "<br />\n";
    $ret .= LJ::Lang::ml('poll.security', { 'whovote' => LJ::Lang::ml('poll.security.'.$self->whovote),
                                       'whoview' => LJ::Lang::ml('poll.security.'.$self->whoview) });
    #my $text = LJ::run_hook('extra_poll_description', $po, \@qs);
    #$ret .= "<br />$text" if $text;

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
            my $posterid = $self->posterid;
            $ret .= qq {
                <a href='$LJ::SITEROOT/poll/?id=$pollid&amp;qid=$qid&amp;mode=ans'
                    class='LJPollAnswerLink' lj_pollid='$pollid' lj_qid='$qid' lj_posterid='$posterid'>
                } . LJ::Lang::ml('poll.viewanswers') . "</a><br />";

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

sub can_vote {
    my ($self, $remote) = @_;
    $remote ||= LJ::get_remote();

    # owner can do anything
    return 1 if $remote && $remote->userid == $self->posterid;

    my $is_friend = $remote && LJ::is_friend($self->journalid, $remote->userid);

    return 0 if $self->whovote eq "friends" && !$is_friend;

    if (LJ::is_banned($remote, $self->journalid) || LJ::is_banned($remote, $self->posterid)) {
        return 0;
    }

    return 1;
}

sub can_view {
    my ($self, $remote) = @_;
    $remote ||= LJ::get_remote();

    # owner can do anything
    return 1 if $remote && $remote->userid == $self->posterid;

    # not the owner, can't view results
    return 0 if $self->whoview eq 'none';

    # okay if everyone can view or if friends can view and remote is a friend
    my $is_friend = $remote && LJ::is_friend($self->journalid, $remote->userid);
    return 1 if $self->whoview eq "all" || ($self->whoview eq "friends" && $is_friend);

    return 0;
}


########## Class methods

package LJ::Poll;
use strict;
use Carp qw (croak);

sub process_submission {
    my $class = shift;
    my $form = shift;
    my $error = shift;
    my $sth;

    my $dbh = LJ::get_db_writer();

    my $remote = LJ::get_remote();

    unless ($remote) {
        $$error = LJ::error_noremote();
        return 0;
    }

    my $pollid = int($form->{'pollid'});
    my $poll = LJ::Poll->new($pollid);
    unless ($poll) {
        $$error = LJ::Lang::ml('poll.error.nopollid');
        return 0;
    }

    unless ($poll->can_vote($remote)) {
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
