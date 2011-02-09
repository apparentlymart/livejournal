package LJ::Poll;
use strict;
use Carp qw (croak);
use Class::Autouse qw (LJ::Entry LJ::Poll::Question LJ::Event::PollVote LJ::Typemap LJ::Text);

##
## Memcache routines
##
use base 'LJ::MemCacheable';
    *_memcache_id                   = \&id;
sub _memcache_key_prefix            { "poll" }
sub _memcache_stored_props          {
    # first element of props is a VERSION
    # next - allowed object properties
    return qw/ 2
               ditemid itemid
               pollid journalid posterid whovote whoview name status questions props
               results
               /;
}
    *_memcache_hashref_to_object    = \*absorb_row;
sub _memcache_expires               { 24*3600 }


# loads a poll
sub new {
    my ($class, $pollid) = @_;

    my $self = {
        pollid => $pollid,
    };

    bless $self, $class;
    return $self;
}

# create a new poll
# returns created poll object on success, 0 on failure
# can be called as a class method or an object method
#
# %opts:
#   questions: arrayref of poll questions
#   error: scalarref for errors to be returned in
#   entry: LJ::Entry object that this poll is attached to
#   ditemid, journalid, posterid: required if no entry object passed
#   whovote: who can vote in this poll
#   whoview: who can view this poll
#   name: name of this poll
#   status: set to 'X' when poll is closed
sub create {
    my ($classref, %opts) = @_;

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

    my $whovote = $opts{whovote} or croak "No whovote";
    my $whoview = $opts{whoview} or croak "No whoview";
    my $name    = $opts{name} || '';

    my $questions = delete $opts{questions}
        or croak "No questions passed to create";

    # get a new pollid
    my $pollid = LJ::alloc_global_counter('L'); # L == poLL
    unless ($pollid) {
        ${$opts{error}} = "Could not get pollid";
        return 0;
    }

    my $u = LJ::load_userid($journalid)
        or die "Invalid journalid $journalid";

    my $dbh = LJ::get_db_writer();
    my $sth;

    if ($u->polls_clustered) {
        # poll stored on user cluster
        $u->do("INSERT INTO poll2 (journalid, pollid, posterid, whovote, whoview, name, ditemid) " .
               "VALUES (?, ?, ?, ?, ?, ?, ?)", undef,
               $journalid, $pollid, $posterid, $whovote, $whoview, $name, $ditemid);
        die $u->errstr if $u->err;

        # made poll, insert global pollid->journalid mapping into global pollowner map
        $dbh->do("INSERT INTO pollowner (journalid, pollid) VALUES (?, ?)", undef,
                 $journalid, $pollid);

        die $dbh->errstr if $dbh->err;
    } else {
        # poll stored on global
        $dbh->do("INSERT INTO poll (pollid, itemid, journalid, posterid, whovote, whoview, name) " .
                 "VALUES (?, ?, ?, ?, ?, ?, ?)", undef,
                 $pollid, $ditemid, $journalid, $posterid, $whovote, $whoview, $name);
        die $dbh->errstr if $dbh->err;
    }

    ## start inserting poll questions
    my $qnum = 0;

    foreach my $q (@$questions) {
        $qnum++;

        if ($u->polls_clustered) {
            $u->do("INSERT INTO pollquestion2 (journalid, pollid, pollqid, sortorder, type, opts, qtext) " .
                        "VALUES (?, ?, ?, ?, ?, ?, ?)", undef,
                        $journalid, $pollid, $qnum, $qnum, $q->{'type'}, $q->{'opts'}, $q->{'qtext'});
            die $u->errstr if $u->err;
        } else {
            $dbh->do("INSERT INTO pollquestion (pollid, pollqid, sortorder, type, opts, qtext) " .
                          "VALUES (?, ?, ?, ?, ?, ?)", undef,
                          $pollid, $qnum, $qnum, $q->{'type'}, $q->{'opts'}, $q->{'qtext'});
            die $dbh->errstr if $dbh->err;
        }

        ## start inserting poll items
        my $inum = 0;
        foreach my $it (@{$q->{'items'}}) {
            $inum++;

            if ($u->polls_clustered) {
                $u->do("INSERT INTO pollitem2 (journalid, pollid, pollqid, pollitid, sortorder, item) " .
                       "VALUES (?, ?, ?, ?, ?, ?)", undef, $journalid, $pollid, $qnum, $inum, $inum, $it->{'item'});
                die $u->errstr if $u->err;
                $u->do("INSERT INTO pollresultaggregated2 (journalid, pollid, what, value) " .
                       "VALUES (?, ?, ?, ?)", undef, $journalid, $pollid, "$qnum:$inum", 0);
                die $u->errstr if $u->err;
            } else { # non-clustered poll will not have aggregated results
                $dbh->do("INSERT INTO pollitem (pollid, pollqid, pollitid, sortorder, item) " .
                         "VALUES (?, ?, ?, ?, ?)", undef, $pollid, $qnum, $inum, $inum, $it->{'item'});
                die $dbh->errstr if $dbh->err;
            }
        }
        ## end inserting poll items

        ## prepare answer variants list for scale question
        if ($q->{'type'} eq 'scale' and $u->polls_clustered) {
            my ($from, $to, $by) = split(m!/!, $q->{'opts'});
            $by ||= 1;
            my $count = int(($to - $from) / $by) + 1;
            for (my $at = $from; $at <= $to; $at += $by) {
                $u->do("INSERT INTO pollresultaggregated2 (journalid, pollid, what, value) " .
                       "VALUES (?, ?, ?, ?)", undef, $journalid, $pollid, "$qnum:$at", 0);
                die $u->errstr if $u->err;
            }
        }
    }
    ## end inserting poll questions

    $u->do("INSERT INTO pollresultaggregated2 (journalid, pollid, what, value) " .
           "VALUES (?, ?, ?, ?)", undef, $journalid, $pollid, "users", 0);
    die $u->errstr if $u->err;

    if (ref $classref eq 'LJ::Poll') {
        $classref->{pollid} = $pollid;
        foreach my $prop (keys %{$opts{props}}) {
            $classref->set_prop($prop, $opts{props}->{$prop});
        }

        return $classref;
    }

    my $pollobj = LJ::Poll->new($pollid);
    foreach my $prop (keys %{$opts{props}}) {
        $pollobj->set_prop($prop, $opts{props}->{$prop});
    }

    return $pollobj;
}

sub clean_poll {
    my ($class, $ref) = @_;
    $$ref = LJ::Text->fix_utf8($$ref);

    if ($$ref !~ /[<>]/) {
        LJ::text_out($ref);
        return;
    }

    my $poll_eat    = [qw[head title style layer iframe applet object]];
    my $poll_allow  = [qw[a b i u strong em img strike]];
    my $poll_remove = [qw[bgsound embed object caption link font]];

    LJ::CleanHTML::clean($ref, {
        'wordlength' => 40,
        'addbreaks'  => 0,
        'eat'        => $poll_eat,
        'mode'       => 'deny',
        'allow'      => $poll_allow,
        'remove'     => $poll_remove,
    });
    LJ::text_out($ref);
}

sub contains_new_poll {
    my ($class, $postref) = @_;
    return ($$postref =~ /<lj-poll\b/i);
}

# parses poll tags and returns whatever polls were parsed out
sub new_from_html {
    my ($class, $postref, $error, $iteminfo) = @_;

    $iteminfo->{'posterid'}  += 0;
    $iteminfo->{'journalid'} += 0;

    my $newdata;

    my $popen = 0;
    my %popts;

    my $numq  = 0;
    my $qopen = 0;
    my %qopts;

    my $numi  = 0;
    my $iopen = 0;
    my %iopts;

    my @polls;  # completed parsed polls

    my $p = HTML::TokeParser->new($postref);

    my $err = sub {
        $$error = LJ::Lang::ml(@_);
        return 0;
    };

    while (my $token = $p->get_token) {
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

                my $journal = LJ::load_userid($iteminfo->{posterid});
                if (LJ::run_hook("poll_unique_prop_is_enabled", $journal)) {
                    $popts{props}->{unique} = $opts->{unique} ? 1 : 0;
                }
                if (LJ::run_hook("poll_createdate_prop_is_enabled", $journal)) {
                    $popts{props}->{createdate} = $opts->{createdate} || undef;
                }
                LJ::run_hook('get_more_options_from_poll', finalopts => \%popts, givenopts => $opts, journalu => $journal);

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

                return $err->("poll.error.toomanyquestions")
                    unless $numq++ < 255;

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

                return $err->("poll.error.toomanyopts")
                    unless $numi++ < 255;

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
                    $opts->{$_} = LJ::no_utf8_flag($opts->{$_});
                    $append .= " $_=\"" . LJ::ehtml($opts->{$_}) . "\"";
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

                # create a fake temporary poll object
                my $pollobj = LJ::Poll->new;
                $pollobj->absorb_row(\%popts);
                push @polls, $pollobj;

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

                my $question = LJ::Poll::Question->new_from_row(\%qopts);
                push @{$popts{'questions'}}, $question;
                $qopen = 0;
                $numi = 0; # number of open opts resets
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
            # <!-- comments -->. keep these, let cleanhtml deal with it.
            $newdata .= $token->[1];
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

###### Utility methods

# if we have a complete poll object (sans pollid) we can save it to
# the database and get a pollid
sub save_to_db {

    # OBSOLETE METHOD?

    my $self = shift;
    my %opts = @_;

    my %createopts;

    # name and props are optional fields
    $createopts{name} = $opts{name} || $self->{name};
    $createopts{props} = $opts{props} || $self->{props};

    foreach my $f (qw(ditemid journalid posterid questions whovote whoview)) {
        $createopts{$f} = $opts{$f} || $self->{$f} or croak "Field $f required for save_to_db";
    }

    # create can optionally take an object as the invocant
    return LJ::Poll::create($self, %createopts);
}

# loads poll from db
sub _load {
    my $self = shift;

    return $self if $self->{_loaded};

    croak "_load called on LJ::Poll with no pollid"
        unless $self->pollid;

    # Requests context
    if (my $obj = $LJ::REQ_CACHE_POLL{ $self->id }){
        %{ $self }= %{ $obj }; # change object in memory
        return $self;
    }

    # Try to get poll from MemCache
    return $self if $self->_load_from_memcache;

    # Load object from MySQL database
    my $dbr = LJ::get_db_reader();

    my $journalid = $dbr->selectrow_array("SELECT journalid FROM pollowner WHERE pollid=?", undef, $self->pollid);
    die $dbr->errstr if $dbr->err;

    my $row = '';

    unless ($journalid) {
        # this is probably not clustered, check global
        $row = $dbr->selectrow_hashref("SELECT pollid, itemid, journalid, " .
                                       "posterid, whovote, whoview, name, status " .
                                       "FROM poll WHERE pollid=?", undef, $self->pollid);
        die $dbr->errstr if $dbr->err;
    } else {
        my $u = LJ::load_userid($journalid)
            or die "Invalid journalid $journalid";
        return unless $u->is_visible; ## expunged and suspended journals

        # double-check to make sure we are consulting the right table
        if ($u->polls_clustered) {
            # clustered poll
            $row = $u->selectrow_hashref("SELECT pollid, journalid, ditemid, " .
                                         "posterid, whovote, whoview, name, status " .
                                         "FROM poll2 WHERE pollid=? " .
                                         "AND journalid=?", undef, $self->pollid, $journalid);
            die $u->errstr if $u->err;
        } else {
            # unclustered poll
            $row = $dbr->selectrow_hashref("SELECT pollid, itemid, journalid, " .
                                           "posterid, whovote, whoview, name, status " .
                                           "FROM poll WHERE pollid=?", undef, $self->pollid);
            die $dbr->errstr if $dbr->err;
        }
    }

    return undef unless $row;

    $self->absorb_row($row);
    $self->{_loaded} = 1; # object loaded

    # store constructed object in caches
    $self->_store_to_memcache;
    $LJ::REQ_CACHE_POLL{ $self->id } = $self;

    return $self;
}

sub absorb_row {
    my ($self, $row) = @_;
    croak "No row" unless $row;

    # questions is an optional field for creating a fake poll object for previewing
    $self->{ditemid} = $row->{ditemid} || $row->{itemid}; # renamed to ditemid in poll2
    $self->{$_} = $row->{$_} foreach qw(pollid journalid posterid whovote whoview name status questions props);
    $self->{_loaded} = 1;
    return $self;
}

# Mark poll as closed
sub close_poll {
    my $self = shift;

    # Nothing to do if poll is already closed
    return if ($self->{status} eq 'X');

    my $u = LJ::load_userid($self->journalid)
        or die "Invalid journalid " . $self->journalid;

    my $dbh = LJ::get_db_writer();

    if ($u->polls_clustered) {
        # poll stored on user cluster
        $u->do("UPDATE poll2 SET status='X' where pollid=? AND journalid=?",
               undef, $self->pollid, $self->journalid);
        die $u->errstr if $u->err;
    } else {
        # poll stored on global
        $dbh->do("UPDATE poll SET status='X' where pollid=? ",
                 undef, $self->pollid);
        die $dbh->errstr if $dbh->err;
    }

    # poll status has changed
    $self->_remove_from_memcache;
    delete $LJ::REQ_CACHE_POLL{ $self->id };

    $self->{status} = 'X';
}

# Mark poll as open
sub open_poll {
    my $self = shift;

    # Nothing to do if poll is already open
    return if ($self->{status} eq '');

    my $u = LJ::load_userid($self->journalid)
        or die "Invalid journalid " . $self->journalid;

    my $dbh = LJ::get_db_writer();

    if ($u->polls_clustered) {
        # poll stored on user cluster
        $u->do("UPDATE poll2 SET status='' where pollid=? AND journalid=?",
               undef, $self->pollid, $self->journalid);
        die $u->errstr if $u->err;
    } else {
        # poll stored on global
        $dbh->do("UPDATE poll SET status='' where pollid=? ",
                 undef, $self->pollid);
        die $dbh->errstr if $dbh->err;
    }

    # poll status has changed
    $self->_remove_from_memcache;
    delete $LJ::REQ_CACHE_POLL{ $self->id };

    $self->{status} = '';
}
######### Accessors
# ditemid
*ditemid = \&itemid;
sub itemid {
    my $self = shift;
    $self->_load;
    return $self->{ditemid};
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
sub poster {
    my $self = shift;
    return LJ::load_userid($self->posterid);
}

*id = \&pollid;
sub pollid { $_[0]->{pollid} }

sub url {
    my $self = shift;
    return "$LJ::SITEROOT/poll/?id=" . $self->id;
}

sub entry {
    my $self = shift;
    return LJ::Entry->new($self->journal, ditemid => $self->ditemid);
}

sub journal {
    my $self = shift;
    return LJ::load_userid($self->journalid);
}

sub is_clustered {
    my $self = shift;
    return $self->journal->polls_clustered;
}

# return true if poll is closed
sub is_closed {
    my $self = shift;
    $self->_load;

    return 1 if $self->{status} eq 'X';

    ## Is this poll is an election poll?
    my $is_super = $self->prop('supermaintainer');
    return 0 unless $is_super;

    my $comm = LJ::load_userid($is_super);
    return 0 unless $comm;

    ## Check for all maintainers have already voted
    my $dbr = LJ::get_db_reader();
    my $sth;
    my @questions = $self->questions;

    ## SuperMaintainer election poll have only one question
    my $qid = $questions[0]->pollqid;
    my @items = $questions[0]->items;

    ## Drop unvisible, non-maintainers and not active users
    @items = grep {
        my $user = $_->{item};
        $user =~ s/<lj user='(.*?)'>/$1/;
        my $u = LJ::load_user($user);
        ($u && $u->is_visible && $u->can_manage($comm) && $u->check_activity(90)) ? 1 : 0;
    } @items;

    ## Fetch poll results
    if ($self->is_clustered) {
        $sth = $self->journal->prepare("SELECT value, userid FROM pollresult2 WHERE pollid=? AND pollqid=? AND journalid=?");
        $sth->execute($self->pollid, $qid, $self->journalid);
    } else {
        $sth = $dbr->prepare("SELECT value, userid FROM pollresult WHERE pollid=? AND pollqid=?");
        $sth->execute($self->pollid, $qid);
    }

    ## We are not calculate results from unvisible, non-maintainers and not active users
    my %results = ();
    my $cnt = 0;
    while (my @res = $sth->fetchrow_array) {
        my $uid = $res[1];
        my $u = LJ::load_userid($uid);
        next unless ($u && $u->is_visible && $u->can_manage($comm) && $u->check_activity(90));
        $results{$res[0]}++;
        $cnt++;
    }

    my @cnts = sort { $b <=> $a } values %results;
    my $max_votes_for = 0;
    ## Max votes
    my $max_votes = $cnts[0];
    ## Check for duplicate of votes count
    foreach my $it (sort { $b <=> $a } keys %results) {
        if (
            $max_votes == $results{$it}     ## Found max votes count
            && $max_votes_for               ## User have selected already
            && $max_votes_for != $it        ## Ooops, it's another user
        ) {
            ## We have two equal votes count for diff users
            $max_votes_for = undef;
            last;
        } elsif ($max_votes == $results{$it}) {
            $max_votes_for = $it;
        }
    }

    ## We are on close date?
    my $create = LJ::TimeUtil->mysqldate_to_time($self->prop('createdate'));
    my $delta = time - $create;
    ## Check for selected winner in a 3-week-end day
    if (($delta % (21 * 86400) < 86400) && $delta > 86400 && !$max_votes_for) {
        return 0;
    }
    
    ## Not all maintainers have voted and poll was prolonged
    if ((@items != $cnt) && ($delta < 86400 || ($delta % (21 * 86400) > 86400))) {
        return 0;
    }

    ## We found election winner. Set this user as supermaintainer and close election.
    if ($max_votes_for && $items[$max_votes_for - 1]) {
        my $winner = $items[$max_votes_for - 1]->{item};
        $winner =~ s/<lj user='(.*?)'>/$1/;
        $winner = LJ::load_user($winner);
        if ($winner && $winner->can_manage($is_super) && $winner->is_visible) {
            LJ::set_rel($is_super, $winner->{userid}, 'S');
            $self->close_poll;

            my $system = LJ::load_user('system');
            $comm->log_event('set_owner', { actiontarget => $winner->{userid}, remote => $system });

            LJ::statushistory_add($comm, $system, 'set_owner', "Poll set owner as ".$winner->{user});

            ## Poll is closed. Emailing to all maintainers about it.
            my $subject = LJ::Lang::ml('poll.election.email.subject.closed');
            my $maintainers = LJ::load_rel_user($comm->userid, 'A');
            foreach my $maint_id (@$maintainers) {
                my $u = LJ::load_userid ($maint_id);
                LJ::send_mail({ 'to'        => $u->email_raw,
                                'from'      => $LJ::ACCOUNTS_EMAIL,
                                'fromname'  => $LJ::SITENAMESHORT,
                                'wrap'      => 1,
                                'charset'   => $u->mailencoding || 'utf-8',
                                'subject'   => $subject,
                                'html'      => (LJ::Lang::ml('poll.election.end.email', {
                                                        username        => LJ::ljuser($u),
                                                        communityname   => LJ::ljuser($comm),
                                                        winner          => LJ::ljuser($winner),
                                                        faqlink         => '#',
                                                        shortsite       => $LJ::SITENAMESHORT,
                                                    })
                                                ),
                            });
            }

            return 1;
        }
    }

    ## Can't set a supermaintainer
    return 0;
}

# return true if remote is also the owner
sub is_owner {
    my ($self, $remote) = @_;
    $remote ||= LJ::get_remote();

    return 1 if $remote && $remote->userid == $self->posterid;
    return 0;
}

# poll requires unique answers (by email address)
sub is_unique {
    my $self = shift;

    return LJ::run_hook("poll_unique_prop_is_enabled", $self->poster) && $self->prop("unique") ? 1 : 0;
}

# poll requires voters to be created on or before a certain date
sub is_createdate_restricted {
    my $self = shift;

    return LJ::run_hook("poll_createdate_prop_is_enabled", $self->poster) && $self->prop("createdate") ? 1 : 0;
}

# do we have a valid poll?
sub valid {
    my $self = shift;
    return 0 unless $self->pollid;
    my $res = eval { $self->_load };
    warn "Error loading poll id: " . $self->pollid . ": $@\n"
        if $@;
    return $res;
}

# get a question by pollqid
sub question {
    my ($self, $pollqid) = @_;
    my @qs = $self->questions;
    my ($q) = grep { $_->pollqid == $pollqid } @qs;
    return $q;
}

sub load_aggregated_results {
    my $self = shift;

    my %aggr_results;
    my $aggr_users;

    if (ref $self->{results} eq 'HASH') { # if poll is new and have aggregated results
        return;
    } elsif (not $self->{results}) { # not loaded
        my $sth = $self->journal->prepare("SELECT what, value FROM pollresultaggregated2 WHERE pollid=? AND journalid=?");
        $sth->execute($self->pollid, $self->journalid);
        while (my $row = $sth->fetchrow_arrayref) {
            last unless ref $row eq 'ARRAY';
            my ($key, $value) = @$row;
            if ($key eq 'users') {
                $aggr_users = $value;
            } elsif ($key =~ /^(\d+):(\d+)$/) {
                my $qid = $1;
                my $item = $2;
                $aggr_results{$qid}->{$item} = $value;
            } else {
                warn "Unknown key in pollresultaggrepated2: '$key'" if $LJ::IS_DEV_SERVER;
            }
        }
    }

    if (scalar keys %aggr_results) {
        $self->{results} = { counts => \%aggr_results, users => $aggr_users};
    } else {
        $self->{results} = 'no'; # we tryed - there are no aggregated results in DB => save negative status to prevent new attempts
    }

    # store poll data with loaded results
    $self->_store_to_memcache;
    $LJ::REQ_CACHE_POLL{ $self->id } = $self;
}

##### Poll rendering

# returns the time that the given user answered the given poll
sub get_time_user_submitted {
    my ($self, $u) = @_;

    my $time;
    if ($self->is_clustered) {
        $time = $self->journal->selectrow_array('SELECT datesubmit FROM pollsubmission2 '.
                                                'WHERE pollid=? AND userid=? AND journalid=?', undef, $self->pollid, $u->userid, $self->journalid);
    } else {
        my $dbr = LJ::get_db_reader();
        $time = $dbr->selectrow_array('SELECT datesubmit FROM pollsubmission '.
                                      'WHERE pollid=? AND userid=?', undef, $self->pollid, $u->userid);
    }

    return $time;
}

# expects a fake poll object (doesn't have to have pollid) and
# an arrayref of questions in the poll object
sub preview {
    my $self = shift;

    my $ret = '';
    my $ret_side = '';

    $ret .= "<form action='#'>\n";
    $ret .= "<b>" . LJ::Lang::ml('poll.pollnum', { 'num' => 'xxxx' }) . "</b>";

    my $name = $self->name;
    if ($name) {
        LJ::Poll->clean_poll(\$name);
        $ret .= " <i>$name</i>";
    }

    $ret .= "<br />\n";

    my $whoview = $self->whoview eq "none" ? "none_remote" : $self->whoview;
    $ret .= LJ::Lang::ml('poll.security2', { 'whovote' => LJ::Lang::ml('poll.security.'.$self->whovote), 'whoview' => LJ::Lang::ml('poll.security.'.$whoview), });

    # iterate through all questions
    foreach my $q ($self->questions) {
        $ret .= $q->preview_as_html;
    }

    $ret .= LJ::html_submit('', LJ::Lang::ml('poll.submit'), { 'disabled' => 1 }) . "\n";
    $ret .= "</form>";

    return $ret;
}

sub render_results {
    my $self = shift;
    my %opts = @_;
    return $self->render(mode => 'results', %opts);
}

sub render_enter {
    my $self = shift;
    my %opts = @_;
    return $self->render(mode => 'enter', %opts);
}

sub render_ans {
    my $self = shift;
    my %opts = @_;
    return $self->render(mode => 'ans', %opts);
}

# returns HTML of rendered poll
# opts:
#   mode => enter|results|ans
#   qid  => show a specific question
#   page => page #
#   widget => true if rendering must be short
sub render {
    my ($self, %opts) = @_;

    my $remote = LJ::get_remote();

    my $ditemid   = $self->ditemid;
    my $pollid    = $self->pollid;
    my $journalid = $self->journalid;

    my $mode     = delete $opts{mode};
    my $qid      = delete $opts{qid};
    my $page     = delete $opts{page};
    my $pagesize = delete $opts{pagesize};

    my $is_super = $self->prop ('supermaintainer');
    ## Only maintainers can view, vote and see results for election polls.
    if ($is_super) {
        if (!$remote || !($remote->can_manage($is_super) || LJ::u_equals($remote, $self->journal))) {
            return "<b>[" . LJ::Lang::ml('poll.error.not_enougth_rights') . "]</b>";
        }
    }

    # Default pagesize.
    $pagesize = 2000 unless $pagesize;

    return "<b>[ Poll owner has been deleted ]</b>" unless $self->journal->clusterid;
    return "<b>[" . LJ::Lang::ml('poll.error.pollnotfound', { 'num' => $pollid }) . "]</b>" unless $pollid;
    return "<b>[" . LJ::Lang::ml('poll.error.noentry') . "</b>" unless $ditemid;

    my $can_vote = $self->can_vote;

    my $dbr = LJ::get_db_reader();

    # update the mode if we need to
    $mode = 'results' if ((!$remote && !$mode) || $self->is_closed);
    if ($remote && !$mode) {
        my $time = $self->get_time_user_submitted($remote);
        $mode = $time ? 'results' : $can_vote ? 'enter' : 'results';
    }

    ## Supermaintainer election has only one mode - voting
    $mode = "enter"
        if ($is_super && !$self->is_closed);

    my $sth;
    my $ret = '';
    my $ret_side = '';

    ### load all the questions
    my @qs = $self->questions;

    ### view answers to a particular question in a poll
    if ($mode eq "ans") {
        return "<b>[" . LJ::Lang::ml('poll.error.cantview') . "]</b>"
            unless $self->can_view;
        my $q = $self->question($qid)
            or return "<b>[" . LJ::Lang::ml('poll.error.questionnotfound') . "]</b>";

        my $text = $q->text;
        LJ::Poll->clean_poll(\$text);
        $ret .= $text;
        $ret .= '<div>' . $q->answers_as_html($self->journalid, $page, $pagesize) . '</div>';
        return $ret;
    }

    # Users cannot vote unless they are logged in
    return "<?needlogin?>"
        if $mode eq 'enter' && !$remote;

    my $do_form = $mode eq 'enter' && $can_vote;

    # from here out, if they can't vote, we're going to force
    # them to just see results.
    $mode = 'results' unless $can_vote;

    my %preval;

    if ($do_form) {
        if ($self->is_clustered) {
            $sth = $self->journal->prepare("SELECT pollqid, value FROM pollresult2 WHERE pollid=? AND userid=? AND journalid=?");
            $sth->execute($pollid, $remote->{'userid'}, $self->journalid);
        } else {
            $sth = $dbr->prepare("SELECT pollqid, value FROM pollresult WHERE pollid=? AND userid=?");
            $sth->execute($pollid, $remote->{'userid'});
        }

        while (my ($qid, $value) = $sth->fetchrow_array) {
            $preval{$qid} = $value;
        }

        $ret .= "<form action='$LJ::SITEROOT/poll/?id=$pollid' method='post'>";
        $ret .= LJ::form_auth();
        $ret .= LJ::html_hidden('pollid', $pollid);
    }

    if ($is_super) {
        $ret .= "<div class='poll-main'>";
    }

    $ret .= "<b><a href='$LJ::SITEROOT/poll/?id=$pollid'>" . LJ::Lang::ml('poll.pollnum', { 'num' => $pollid }) . "</a></b> "
            unless $opts{widget} || $is_super;
    $ret .= $opts{scroll_links} if $opts{widget};
    if ($self->name) {
        my $name = $self->name;
        LJ::Poll->clean_poll(\$name);
        unless ($is_super) {
            if ($opts{widget}) {
                $name = LJ::trim_at_word($name, 70);
                $ret .= "<h3>$name</h3>";
            } else {
                $ret .= "<i>$name</i>";
            }
        }
    }
    $ret .= "<br />\n" unless $opts{widget} || $is_super;
    $ret .= "<span style='font-family: monospace; font-weight: bold; font-size: 1.2em;'>" .
            LJ::Lang::ml('poll.isclosed') . "</span><br />\n"
        if ($self->is_closed && !$is_super);

    my $whoview = $self->whoview;
    if ($whoview eq "none") {
        $whoview = $remote && $remote->id == $self->posterid ? "none_remote" : "none_others";
    }
    $ret .= LJ::Lang::ml('poll.security2', { 'whovote' => LJ::Lang::ml('poll.security.'.$self->whovote),
                                       'whoview' => LJ::Lang::ml('poll.security.'.$whoview) })
            unless $opts{widget} || $is_super;

    my %aggr_results;
    my $aggr_users;
    my $have_aggr_results;

    unless ($do_form) { # we need know poll results
        $self->load_aggregated_results;
        if (ref $self->{results} eq 'HASH') { # if poll is new and have aggregated results
            %aggr_results = %{$self->{results}->{counts}};
            $aggr_users = $self->{results}->{users};
            $have_aggr_results = 1;
        }
    }

    my $results_table = "";
    my $posted = '';
    if ($opts{widget}) {
        my $ago = time() - LJ::TimeUtil->mysqldate_to_time($self->entry->logtime_mysql, 0);
        # This will not work under friendspage, because of bug in calculating logtime from rlogtime somewhere in code - I do not know where...
        $posted = ' <span class="i-potd-ago">' . LJ::Lang::ml('poll.posted') . ' ' . LJ::TimeUtil->ago_text($ago) . '</span>';
        #$posted .= " ($ago; " . LJ::TimeUtil->mysqldate_to_time($self->entry->logtime_mysql, 0) . ")";
        #$posted .= " (" . localtime . " - '" . $self->entry->logtime_mysql . "')";
    }

    if ($is_super && !$self->is_closed) {
        my $sth;
        ## Election poll has a only one question
        my $q = $qs[0];
        if ($self->is_clustered) {
            $sth = $self->journal->prepare("SELECT value FROM pollresult2 WHERE pollid=? AND pollqid=? AND journalid=? AND userid=?");
            $sth->execute($self->pollid, $q->pollqid, $self->journalid, $remote->userid);
        } else {
            $sth = $dbr->prepare("SELECT value FROM pollresult WHERE pollid=? AND pollqid=? AND userid=?");
            $sth->execute($self->pollid, $q->pollqid, $remote->userid);
        }

        if (my @row = $sth->fetchrow_array) {
            my @items = $self->question($q->pollqid)->items;
            my $user = $row[0] ? $items[$row[0] - 1] : undef;
            if ($user) {
                $user = $user->{item};
                LJ::Poll->clean_poll(\$user);
                $ret .=  "<p>" . LJ::Lang::ml('poll.election.selected', { choice => $user }) . "</p>";
                $ret_side .=  "<p class='b-bubble b-bubble-alert'>" . LJ::Lang::ml('poll.election.selected.tip') . "<i class='i-bubble-arrow-border'></i><i class='i-bubble-arrow'></i></p>";
            }
        }

    }

    if ($is_super && !$self->is_closed) {
        use POSIX qw/strftime/;
        my $create = LJ::TimeUtil->mysqldate_to_time($self->prop('createdate'));
        my $delta = time - $create;
        my $close_time = strftime "%B %e %Y", localtime (int(($delta / (21 * 86400)) + 1) * (21 * 86400) + $create);
        $ret_side .= "<p class='b-bubble b-bubble-lite'>" . LJ::Lang::ml('poll.election.description', { enddate => $close_time }) . "<i class='i-bubble-arrow-border'></i><i class='i-bubble-arrow'></i></p>";
        $ret_side .= "<p class='b-bubble b-bubble-alert'>" . LJ::Lang::ml('poll.election.description.extend') . "</p>";
    }

    ## go through all questions, adding to buffer to return
    foreach my $q (@qs) {
        my $qid = $q->pollqid;
        my $text = $q->text;
        $text = LJ::trim_at_word($text, 150) if $opts{widget};
        LJ::Poll->clean_poll(\$text);
        unless ($is_super) {
            if ($opts{widget}) {
                $results_table .= "<p class='b-post-question'>$opts{poll_pic}$text$posted</p><div id='LJ_Poll_${pollid}_$qid' class='b-potd-poll'>";
            } else {
                $results_table .= "<p>$text</p><div id='LJ_Poll_${pollid}_$qid' style='margin: 10px 0pt 10px 40px;'>";
            }
        } else {
            $results_table .= "<p>".LJ::Lang::ml('poll.election.subject')."</p><div class='i-bubble b-bubble-lite' id='LJ_Poll_${pollid}_$qid'><table><tr><th>Candidates</th><th class=\"count-recevied\">Votes</th></tr>";
        }
        $posted = '';
        
        if ($mode eq "results") {
            ### to see individual's answers
            my $posterid = $self->posterid;
            $results_table .= qq {
                <a href='$LJ::SITEROOT/poll/?id=$pollid&amp;qid=$qid&amp;mode=ans'
                     class="LJ_PollAnswerLink" lj_posterid='$posterid'
                     onclick="return LiveJournal.pollAnswerClick(event, {pollid:$pollid,pollqid:$qid,page:0,pagesize:$pagesize})">
                } . LJ::Lang::ml('poll.viewanswers') . "</a><br />" if $self->can_view and not $opts{widget};
        }

        #### text questions are the easy case
        if ($q->type eq "text" && $do_form) {
            my ($size, $max) = split(m!/!, $q->opts);

            $results_table .= LJ::html_text({ 'size' => $size, 'maxlength' => $max,
                                    'name' => "pollq-$qid", 'value' => $preval{$qid} });
        } elsif ($q->type eq 'drop' && $do_form) {
            #### drop-down list
            my @optlist = ('', '');
            foreach my $it ($self->question($qid)->items) {
                my $itid  = $it->{pollitid};
                my $item  = $it->{item};
                LJ::Poll->clean_poll(\$item);
                push @optlist, ($itid, $item);
            }
            $results_table .= LJ::html_select({ 'name' => "pollq-$qid",
                                      'selected' => $preval{$qid} }, @optlist);
        } elsif ($q->type eq "scale" && $do_form) {
            #### scales (from 1-10) questions
            my ($from, $to, $by) = split(m!/!, $q->opts);
            $by ||= 1;
            my $count = int(($to-$from)/$by) + 1;
            my $do_radios = ($count <= 11);

            # few opts, display radios
            if ($do_radios) {

                $results_table .= "<table><tr valign='top' align='center'>";

                for (my $at=$from; $at<=$to; $at+=$by) {
                    $results_table .= "<td style='text-align: center;'>";
                    $results_table .= LJ::html_check({ 'type' => 'radio', 'name' => "pollq-$qid",
                                             'value' => $at, 'id' => "pollq-$pollid-$qid-$at",
                                             'selected' => (defined $preval{$qid} && $at == $preval{$qid}) });
                    $results_table .= "<br /><label for='pollq-$pollid-$qid-$at'>$at</label></td>";
                }

                $results_table .= "</tr></table>\n";

            # many opts, display select
            # but only if displaying form
            } else {

                my @optlist = ('', '');
                for (my $at=$from; $at<=$to; $at+=$by) {
                    push @optlist, ($at, $at);
                }
                $results_table .= LJ::html_select({ 'name' => "pollq-$qid", 'selected' => $preval{$qid} }, @optlist);
            }

        } else {
            #### now, questions with items
            my $do_table = 0;

            if ($q->type eq "scale") { # implies ! do_form

                ### get statistics, for scale questions
                my ($valcount, $valmean, $valstddev, $valmedian);

                # get stats
                if ($have_aggr_results) {
                    $sth = undef;
                    $valcount = 0;
                    $valmean = 0;
                    foreach my $item (keys %{$aggr_results{$qid} || {}}) {
                        $valcount += $aggr_results{$qid}->{$item};
                        $valmean += $aggr_results{$qid}->{$item} * $item;
                    }
                    $valmean /= $valcount if $valcount;
                    $valstddev = 0;
                    foreach my $item (keys %{$aggr_results{$qid} || {}}) {
                        $valstddev += $aggr_results{$qid}->{$item} * ($item - $valmean) * ($item - $valmean);
                    }
                    $valstddev = sqrt($valstddev / $valcount) if $valcount;
                } elsif ($self->is_clustered) {
                    $sth = $self->journal->prepare("SELECT COUNT(*), AVG(value), STDDEV(value) FROM pollresult2 " .
                                                   "WHERE pollid=? AND pollqid=? AND journalid=?");
                    $sth->execute($pollid, $qid, $self->journalid);
                } else {
                    $sth = $dbr->prepare("SELECT COUNT(*), AVG(value), STDDEV(value) FROM pollresult WHERE pollid=? AND pollqid=?");
                    $sth->execute($pollid, $qid);
                }

                if ($sth) { # no aggregated results
                    ($valcount, $valmean, $valstddev) = $sth->fetchrow_array;
                }

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

                    if ($have_aggr_results) {
                        $sth = undef;
                        my @items = sort { $a <=> $b } keys %{$aggr_results{$qid} || {}};

                        my @starting;
                        my $index = 0;
                        foreach my $item (@items) {
                            push @starting, $index;
                            $index += $aggr_results{$qid}->{$item};
                        }
                        push @starting, $index; # end-element, for safeness in accesses [$index + 1]
                        # now we have start position (0-based) for any answer variant
                        # we must fetch 1 or 2 elements
                        for ($index = 0; $index < @items; $index++) {
                            last if $starting[$index] >= $skip;
                        }
                        $index-- if $starting[$index] > $skip;
                        # $item[$index] is first element, we must fetch

                        my $sum = $items[$index];
                        if ($fetch == 2) {
                            if ($starting[$index + 1] > $skip + 1) {
                                $sum += $items[$index];
                            } else {
                                $sum += $items[$index + 1];
                            }
                        }
                        $valmedian = $sum / $fetch;

                    } elsif ($self->is_clustered) {
                        $sth = $self->journal->prepare("SELECT value FROM pollresult2 WHERE pollid=? AND pollqid=? AND journalid=? " .
                                             "ORDER BY value+0 LIMIT $skip,$fetch");
                        $sth->execute($pollid, $qid, $self->journalid);
                    } else {
                        $sth = $dbr->prepare("SELECT value FROM pollresult WHERE pollid=? AND pollqid=? " .
                                             "ORDER BY value+0 LIMIT $skip,$fetch");
                        $sth->execute($pollid, $qid);
                    }

                    if ($sth) { # no aggregated results
                        while (my ($v) = $sth->fetchrow_array) {
                            $valmedian += $v;
                        }
                        $valmedian /= $fetch;
                    }
                }

                my $stddev = sprintf("%.2f", $valstddev);
                my $mean = sprintf("%.2f", $valmean);
                $results_table .= LJ::Lang::ml('poll.scaleanswers', { 'mean' => $mean, 'median' => $valmedian, 'stddev' => $stddev });
                $results_table .= "<br />\n";
                $do_table = 1;
                $results_table .= "<table>";
            }

            my @items = $self->question($qid)->items;
            @items = map { [$_->{pollitid}, $_->{item}] } @items;

            # generate poll items dynamically if this is a scale
            if ($q->type eq 'scale') {
                my ($from, $to, $by) = split(m!/!, $q->opts);
                $by = 1 unless ($by > 0 and int($by) == $by);
                for (my $at=$from; $at<=$to; $at+=$by) {
                    push @items, [$at, $at]; # note: fake itemid, doesn't matter, but needed to be uniqeu
                }
            }

            my $usersvoted = 0;
            my %itvotes;
            my $maxitvotes = 1;

            if ($have_aggr_results) {
                $sth = undef;
                %itvotes = %{$aggr_results{$qid} || {}};
                $usersvoted = 0;
                foreach my $item (keys %itvotes) {
                    $usersvoted += $itvotes{$item};
                }
            } elsif ($self->is_clustered) {
                $sth = $self->journal->prepare("SELECT value FROM pollresult2 WHERE pollid=? AND pollqid=? AND journalid=?");
                $sth->execute($pollid, $qid, $self->journalid);
            } else {
                $sth = $dbr->prepare("SELECT value FROM pollresult WHERE pollid=? AND pollqid=?");
                $sth->execute($pollid, $qid);
            }

            if ($sth) {
                while (my ($val) = $sth->fetchrow_array) {
                    $usersvoted++;
                    if ($q->type eq "check") {
                        foreach (split(/,/,$val)) {
                            $itvotes{$_}++;
                        }
                    } else {
                        $itvotes{$val}++;
                    }
                }
            }

            foreach (values %itvotes) {
                $maxitvotes = $_ if ($_ > $maxitvotes);
            }

            foreach my $item (@items) {
                # note: itid can be fake
                my ($itid, $item) = @$item;

                LJ::Poll->clean_poll(\$item);

                if ($is_super) { $results_table .= "<tr><td>"}
                # displaying a radio or checkbox
                if ($do_form) {
                    $results_table .= LJ::html_check({ 'type' => $q->type, 'name' => "pollq-$qid",
                                             'value' => $itid, 'id' => "pollq-$pollid-$qid-$itid",
                                             'selected' => ($preval{$qid} =~ /\b$itid\b/) });
                    my $received = ($is_super && $itvotes{$itid}) ? LJ::Lang::ml ("poll.election.received.votes", { cnt => $itvotes{$itid} }) : '';
                    if ($is_super) {
                        $results_table .= "<label for='pollq-$pollid-$qid-$itid'>$item</label><br class=\"i-potd-br\" /></td><td class=\"count-recevied\">$received</td>";
                    } else {
                        $results_table .= " <label for='pollq-$pollid-$qid-$itid'>$item $received</label><br class=\"i-potd-br\" />";
                    }
                    next;
                }
                
                # displaying results
                my $count = $itvotes{$itid}+0;
                my $percent = sprintf("%.1f", (100 * $count / ($usersvoted||1)));
                my $width = 20+int(($count/$maxitvotes)*380);
                if ($opts{widget}) {
                    $width = $width -250;
                }
                if ($is_super) { $results_table .= "</td></tr>"}

                if ($do_table) {
                    $results_table .= "<tr valign='middle'><td align='right'>$item</td>";
                    $results_table .= "<td><img src='$LJ::IMGPREFIX/poll/leftbar.gif' style='vertical-align:middle' height='14' width='7' alt='' />";
                    $results_table .= "<img src='$LJ::IMGPREFIX/poll/mainbar.gif' style='vertical-align:middle' height='14' width='$width' alt='' />";
                    $results_table .= "<img src='$LJ::IMGPREFIX/poll/rightbar.gif' style='vertical-align:middle' height='14' width='7' alt='' /> ";
                    $results_table .= "<b>$count</b> ($percent%)</td></tr>";
                } else {
                    $results_table .= "<p>$item<br />";
                    $results_table .= "<span style='white-space: nowrap'><img src='$LJ::IMGPREFIX/poll/leftbar.gif' style='vertical-align:middle' height='14' alt='' />";
                    $results_table .= "<img src='$LJ::IMGPREFIX/poll/mainbar.gif' style='vertical-align:middle' height='14' width='$width' alt='' />";
                    $results_table .= "<img src='$LJ::IMGPREFIX/poll/rightbar.gif' style='vertical-align:middle' height='14' width='7' alt='' /> ";
                    $results_table .= "<b>$count</b> ($percent%)</span></p>";
                }
            }

            if ($do_table) {
                $results_table .= "</table>";
            }

        }
        unless ($is_super) {$results_table .= "</div>";}
    }

    ## calc amount of participants.
    if ($mode eq "results" and not $opts{widget} and !$is_super){
        my $sth = "";
        my $participants;
        if ($have_aggr_results) {
            $participants = $aggr_users || 0;
        } elsif ($self->is_clustered) {
            $sth = $self->journal->prepare("SELECT count(DISTINCT userid) FROM pollresult2 WHERE pollid=? AND journalid=?");
            $sth->execute($pollid, $self->journalid);
        } else {
            $sth = $dbr->prepare("SELECT count(DISTINCT userid) FROM pollresult WHERE pollid=?");
            $sth->execute($pollid);
        }
        ($participants) = $sth->fetchrow_array if $sth;
        $ret .= LJ::Lang::ml('poll.participants', { 'total' => $participants });
    }

    if ($is_super && $self->is_closed) {
        $ret .= LJ::Lang::ml('poll.election.closed');
        my $comm = LJ::load_userid($self->prop('supermaintainer'));
        my $res = LJ::load_rel_user($comm->{userid}, 'S');
        my $user = '';
        if (@$res) {
            $user = LJ::ljuser(LJ::load_userid($res->[0]));
        } else {
            $user = LJ::Lang::ml('poll.supermaintainer.not_selected');
        }
        $ret .= LJ::Lang::ml('poll.supermaintainer.is', { user => $user });
    } else {
        $ret .= $results_table;
    }

    if ($is_super) {
        $ret .= "<tr><td colspan=\"2\">";
    }

    if ($do_form) {
        unless ($is_super) {
            $ret .= LJ::html_submit(
                                    'poll-submit',
                                    $is_super ? LJ::Lang::ml('poll.vote') : LJ::Lang::ml('poll.submit'),
                                    {class => 'LJ_PollSubmit'}) . "</form>\n";;
        }
        if ($is_super && $remote && $remote->can_manage($is_super) && !LJ::u_equals($remote, $self->journal)) {
            $ret .= LJ::html_submit(
                                    'poll-submit',
                                    $is_super ? LJ::Lang::ml('poll.vote') : LJ::Lang::ml('poll.submit'),
                                    {class => 'LJ_PollSubmit'}) . "</form>\n";;
        }
    }
    if ($is_super) {
        $ret .= "</td></tr></table></div></div>" . "<div class='poll-side'>" . $ret_side . "</div>";
    }

    return $ret;
}


######## Security

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

    return 0 if $remote->is_deleted or $remote->is_suspended;

    if ($self->is_createdate_restricted) {
        my $propval = $self->prop("createdate");
        if ($propval =~ /^(\d\d\d\d)-(\d\d)-(\d\d)$/) {
            my $propdate = DateTime->new( year => $1, month => $2, day => $3, hour => 23, minute => 59, second => 59, time_zone => 'America/Los_Angeles' );
            my $timecreate = DateTime->from_epoch( epoch => $remote->timecreate, time_zone => 'America/Los_Angeles' );

            # make sure that timecreate is before or equal to propdate
            return 0 if $propdate && $timecreate && DateTime->compare($timecreate, $propdate) == 1;
        }
    }

    my $can_vote_override = LJ::run_hook("can_vote_poll_override", $self);
    return 0 unless !defined $can_vote_override || $can_vote_override;

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


########## Questions
# returns list of LJ::Poll::Question objects associated with this poll
sub questions {
    my $self = shift;

    return @{$self->{questions}} if $self->{questions};

    croak "questions called on LJ::Poll with no pollid"
        unless $self->pollid;

    my @qs = ();
    my $sth;

    if ($self->is_clustered) {
        $sth = $self->journal->prepare('SELECT * FROM pollquestion2 WHERE pollid=? AND journalid=?');
        $sth->execute($self->pollid, $self->journalid);
    } else {
        my $dbr = LJ::get_db_reader();
        $sth = $dbr->prepare('SELECT * FROM pollquestion WHERE pollid=?');
        $sth->execute($self->pollid);
    }

    die $sth->errstr if $sth->err;

    while (my $row = $sth->fetchrow_hashref) {
        my $q = LJ::Poll::Question->new_from_row($row);
        push @qs, $q if $q;
    }

    @qs = sort { $a->sortorder <=> $b->sortorder } @qs;
    $self->{questions} = \@qs;

    # store poll data with loaded questions
    $self->_store_to_memcache;
    $LJ::REQ_CACHE_POLL{ $self->id } = $self;

    return @qs;
}


########## Props
# get the typemap for pollprop2
sub typemap {
    my $self = shift;

    return LJ::Typemap->new(
        table       => 'pollproplist2',
        classfield  => 'name',
        idfield     => 'propid',
    );
}

sub prop {
    my ($self, $propname) = @_;

    my $tm = $self->typemap;
    my $propid = $tm->class_to_typeid($propname);
    my $u = $self->journal;

    my $sth = $u->prepare("SELECT * FROM pollprop2 WHERE journalid = ? AND pollid = ? AND propid = ?");
    $sth->execute($u->id, $self->pollid, $propid);
    die $sth->errstr if $sth->err;

    if (my $row = $sth->fetchrow_hashref) {
        return $row->{propval};
    }

    return undef;
}

sub set_prop {
    my ($self, $propname, $propval) = @_;

    if (defined $propval) {
        my $tm = $self->typemap;
        my $propid = $tm->class_to_typeid($propname);
        my $u = $self->journal;

        $u->do("INSERT INTO pollprop2 (journalid, pollid, propid, propval) " .
               "VALUES (?,?,?,?)", undef, $u->id, $self->pollid, $propid, $propval);
        die $u->errstr if $u->err;
    }

    return 1;
}

########## Class methods

package LJ::Poll;
use strict;
use Carp qw (croak);

# takes a scalarref to entry text and expands lj-poll tags into the polls
sub expand_entry {
    my ($class, $entryref) = @_;

    my $expand = sub {
        my $pollid = (shift) + 0;

        return "[Error: no poll ID]" unless $pollid;

        my $poll = LJ::Poll->new($pollid);
        return "[Error: Invalid poll ID $pollid]" unless $poll && $poll->valid;

        return $poll->render;
    };

    $$entryref =~ s/<lj-poll-(\d+)>/$expand->($1)/eg;
}

sub process_submission {
    my $class = shift;
    my $form = shift;
    my $error = shift;
    my $warnings = shift;
    my $sth;

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

    if ($poll->is_closed) {
        $$error = LJ::Lang::ml('poll.isclosed');
        return 0;
    }

    unless ($poll->can_vote($remote)) {
        $$error = LJ::Lang::ml('poll.error.cantvote');
        return 0;
    }

    # if this particular user has already voted, let them change their answer
    my $time = $poll->get_time_user_submitted($remote);

    # if unique prop is on, make sure that a particular email address can only vote once
    if ($poll->is_unique) {
        # make sure their email address is validated
        unless ($remote->is_validated) {
            $$error = LJ::Lang::ml('poll.error.notvalidated', { aopts => "href='$LJ::HELPURL{validate_email}'" });
            return 0;
        }

        # if this particular user has already voted, let them change their answer
        unless ($time) {
            my $uids;
            if ($poll->is_clustered) {
                $uids = $poll->journal->selectcol_arrayref("SELECT userid FROM pollsubmission2 " .
                                                           "WHERE journalid = ? AND pollid = ?", undef, $poll->journalid, $poll->pollid);
            } else {
                my $dbr = LJ::get_db_reader();
                $uids = $dbr->selectcol_arrayref("SELECT userid FROM pollsubmission " .
                                                 "WHERE pollid = ?", undef, $poll->pollid);
            }

            if (@$uids) {
                my $remote_email = $remote->email_raw;
                my $us = LJ::load_userids(@$uids);

                # Get all emails for the user submitting the poll
                my $dbr = LJ::get_db_reader();
                my $sth = $dbr->prepare("SELECT oldvalue FROM infohistory " .
                                        "WHERE userid=? AND what='email' " .
                                        "ORDER BY timechange");
                $sth->execute($remote->{'userid'});
                my @emails;
                push @emails, $remote_email;
                while (my $em = $sth->fetchrow_array) {
                    push @emails, $em;
                }

                foreach my $u (values %$us) {
                    next unless $u;

                    my $u_email = $u->email_raw;
                    # compare all the emails for the user against the primary
                    # emails of those who have already answered the poll
                    foreach my $em (@emails) {
                        if (lc $u_email eq lc $em) {
                            $$error = LJ::Lang::ml('poll.error.alreadyvoted',
                                          { user => $u->ljuser_display });
                            return 0;
                        }
                    }
                }
            }
        }
    }

    my $dbh = $poll->is_clustered ? LJ::get_cluster_master($poll->journal) : LJ::get_db_writer();

    ### load all the questions
    my @qs = $poll->questions;

    unless (LJ::get_lock($dbh, 'global', "poll:$pollid:$remote->{userid}")) {
        $$error = LJ::Lang::ml('poll.error.cantlock');
        return 0;
        # it is not very correct, to use clustered $dbh with parameter 'global',
        # but $pollid determines $dbh strongly, so second lock will be same DB
        # that reason I think such code is safe
    }

    my $ct = 0; # how many questions did they answer?
    foreach my $q (@qs) {
        my $qid = $q->pollqid;
        my $val = $form->{"pollq-$qid"};
        if ($q->type eq "check") {
            ## multi-selected items are comma separated from htdocs/poll/index.bml
            $val = join(",", sort { $a <=> $b } split(/,/, $val));
        }
        if ($q->type eq "scale") {
            my ($from, $to, $by) = split(m!/!, $q->opts);
            if ($val < $from || $val > $to) {
                # bogus! cheating?
                $val = "";
            }
        }
        my $prev_value;
        if ($poll->is_clustered) {
            my $sth = $poll->journal->prepare("SELECT value FROM pollresult2 WHERE journalid = ? AND pollid = ? AND pollqid = ? AND userid = ?");
            $sth->execute($poll->journalid, $pollid, $qid, $remote->userid);
            if (my $row = $sth->fetchrow_arrayref) {
                $prev_value = $row->[0];
            }
        }
        if ($val ne "") {
            $ct++;

            my $newval = LJ::Text->truncate_with_ellipsis(
                'str' => $val,
                'bytes' => 255,
            );

            if ($newval ne $val) {
                push @$warnings, LJ::Lang::ml('poll.warning.cutoff', {
                    'oldval' => $val,
                    'newval' => $newval,
                });
            }

            $val = $newval;

            if ($poll->is_clustered) {
                $poll->journal->do("REPLACE INTO pollresult2 (journalid, pollid, pollqid, userid, value) VALUES (?, ?, ?, ?, ?)",
                         undef, $poll->journalid, $pollid, $qid, $remote->userid, $val);
            } else {

                $dbh->do("REPLACE INTO pollresult (pollid, pollqid, userid, value) VALUES (?, ?, ?, ?)",
                         undef, $pollid, $qid, $remote->userid, $val);
            }
        } else {
            if ($poll->is_clustered) {
                $poll->journal->do("DELETE FROM pollresult2 WHERE journalid=? AND pollid=? AND pollqid=? AND userid=?",
                         undef, $poll->journalid, $pollid, $qid, $remote->userid);
            } else {
                $dbh->do("DELETE FROM pollresult WHERE pollid=? AND pollqid=? AND userid=?",
                         undef, $pollid, $qid, $remote->userid);
            }
        }

        next if $q->type eq "text"; # text questions does not have aggregated results
        next unless $poll->is_clustered; # only clustered polls have aggrepaged results
        my @val;

        if ($prev_value) {
            $val[0] = $prev_value if $prev_value;
            @val = split(/,/, $prev_value) if $q->type eq "check";
            foreach my $item (@val) {
                $poll->journal->do("UPDATE pollresultaggregated2 SET value = value - 1 WHERE journalid=? AND pollid=? AND what=? AND value > 0",
                                   undef, $poll->journalid, $pollid, "$qid:$item");        
            }
        }

        @val = ();
        $val[0] = $val if $val;
        @val = split(/,/, $val) if $q->type eq "check";
        foreach my $item (@val) {
            $poll->journal->do("UPDATE pollresultaggregated2 SET value = value + 1 WHERE journalid=? AND pollid=? AND what=?",
                               undef, $poll->journalid, $pollid, "$qid:$item");
        }
    }

    ## finally, register the vote happened
    if ($poll->is_clustered) {
        unless ($time) { # if new vote, not update of existing
            $poll->journal->do("UPDATE pollresultaggregated2 SET value = value + 1 WHERE journalid=? AND pollid=? AND what=?",
                               undef, $poll->journalid, $pollid, 'users');
        }
        $poll->journal->do("REPLACE INTO pollsubmission2 (journalid, pollid, userid, datesubmit) VALUES (?, ?, ?, NOW())",
                           undef, $poll->journalid, $pollid, $remote->userid);
    } else {
        $dbh->do("REPLACE INTO pollsubmission (pollid, userid, datesubmit) VALUES (?, ?, NOW())",
                 undef, $pollid, $remote->userid);
    }

    LJ::release_lock($dbh, 'global', "poll:$pollid:$remote->{userid}");

    # vote results are cached now (in new polls), so we need to modify cache
    $poll->_remove_from_memcache;
    delete $LJ::REQ_CACHE_POLL{ $poll->id };

    LJ::run_hooks('poll_log', $poll->posterid, $pollid, $remote ? $remote->userid : undef);

    # don't notify if they blank-polled
    LJ::Event::PollVote->new($poll->poster, $remote, $poll)->fire
        if $ct;

    return 1;
}

# take a user on dversion 7 and upgrade them to dversion 8 (clustered polls)
sub make_polls_clustered {
    my ($class, $u, $dbh, $dbhslo, $dbcm) = @_;

    return 1 if $u->dversion >= 8;

    return 0 unless ($dbh && $dbhslo && $dbcm);

    # find polls this user owns
    my $psth = $dbhslo->prepare("SELECT pollid, itemid, journalid, posterid, whovote, whoview, name, " .
                             "status FROM poll WHERE journalid=?");
    $psth->execute($u->userid);
    die $psth->errstr if $psth->err;

    while (my @prow = $psth->fetchrow_array) {
        my $pollid = $prow[0];
        # insert a copy into poll2
        $dbcm->do("REPLACE INTO poll2 (pollid, ditemid, journalid, posterid, whovote, whoview, name, " .
               "status) VALUES (?,?,?,?,?,?,?,?)", undef, @prow);
        die $dbcm->errstr if $dbcm->err;

        # map pollid -> userid
        $dbh->do("REPLACE INTO pollowner (journalid, pollid) VALUES (?, ?)", undef,
                 $u->userid, $pollid);
        die $dbh->errstr if $dbh->err;

        # get questions
        my $qsth = $dbhslo->prepare("SELECT pollid, pollqid, sortorder, type, opts, qtext FROM " .
                                 "pollquestion WHERE pollid=?");
        $qsth->execute($pollid);
        die $qsth->errstr if $qsth->err;

        # copy questions to clustered table
        while (my @qrow = $qsth->fetchrow_array) {
            my $pollqid = $qrow[1];

            # insert question into pollquestion2
            $dbcm->do("REPLACE INTO pollquestion2 (journalid, pollid, pollqid, sortorder, type, opts, qtext) " .
                   "VALUES (?, ?, ?, ?, ?, ?, ?)", undef, $u->userid, @qrow);
            die $dbcm->errstr if $dbcm->err;

            # get items
            my $isth = $dbhslo->prepare("SELECT pollid, pollqid, pollitid, sortorder, item FROM pollitem " .
                                     "WHERE pollid=? AND pollqid=?");
            $isth->execute($pollid, $pollqid);
            die $isth->errstr if $isth->err;

            # copy items
            while (my @irow = $isth->fetchrow_array) {
                # copy item to pollitem2
                $dbcm->do("REPLACE INTO pollitem2 (journalid, pollid, pollqid, pollitid, sortorder, item) VALUES " .
                       "(?, ?, ?, ?, ?, ?)", undef, $u->userid, @irow);
                die $dbcm->errstr if $dbcm->err;
            }
        }

        # copy submissions
        my $ssth = $dbhslo->prepare("SELECT userid, datesubmit FROM pollsubmission WHERE pollid=?");
        $ssth->execute($pollid);
        die $ssth->errstr if $ssth->err;

        while (my @srow = $ssth->fetchrow_array) {
            # copy to pollsubmission2
            $dbcm->do("REPLACE INTO pollsubmission2 (pollid, journalid, userid, datesubmit) " .
                   "VALUES (?, ?, ?, ?)", undef, $pollid, $u->userid, @srow);
            die $dbcm->errstr if $dbcm->err;
        }

        # copy results
        my $rsth = $dbhslo->prepare("SELECT pollid, pollqid, userid, value FROM pollresult WHERE pollid=?");
        $rsth->execute($pollid);
        die $rsth->errstr if $rsth->err;

        while (my @rrow = $rsth->fetchrow_array) {
            # copy to pollresult2
            $dbcm->do("REPLACE INTO pollresult2 (journalid, pollid, pollqid, userid, value) " .
                   "VALUES (?, ?, ?, ?, ?)", undef, $u->userid, @rrow);
            die $dbcm->errstr if $dbcm->err;
        }
    }

    return 1;
}

## debug method - returns all data from a single poll in XML format
sub dump_poll {
    my $self = shift;
    my $fh = shift || \*STDOUT;

    my @tables = ($self->is_clustered) ?
        qw(poll2 pollquestion2 pollitem2 pollsubmission2 pollresult2 pollresultaggregated2) :
        qw(poll  pollquestion  pollitem  pollsubmission  pollresult );
    my $db = ($self->is_clustered) ? $self->journal : LJ::get_db_reader();
    my $id = $self->pollid;
    my $journalid = $self->journalid;
    
    print $fh "<poll id='$id'>\n";
    foreach my $t (@tables) {
        ## journalid in SELECT is an optimization, 
        ## because all tables have primary key like (journalid, pollid, ...) 
        my $sth = $db->prepare("SELECT * FROM $t WHERE journalid = ? AND pollid = ?");
        $sth->execute($journalid, $id);
        while (my $data = $sth->fetchrow_hashref) {
            print $fh "<$t ";
            foreach my $k (sort keys %$data) {
                my $v = LJ::ehtml($data->{$k});
                print $fh "$k='$v' ";
            }
            print $fh "/>\n";
        }
    }
    print $fh "</poll>\n";
}

1;
