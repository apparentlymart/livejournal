#
# LiveJournal entry object.
#
# Just framing right now, not much to see here!
#

package LJ::Entry;
use strict;
use vars qw/ $AUTOLOAD /;
use Carp qw/ croak /;

# internal fields:
#
#    u: object, always present
#    nocache: bool.  off by default, if set, loaded data won't use memcache
#    anum:    lazily loaded, either by ctor or _loaded_row
#    ditemid: lazily loaded
#    jitemid: always present
#    props:   hashref of props,  loaded if _loaded_props
#    subject: text of subject,   loaded if _loaded_text
#    event:   text of log event, loaded if _loaded_text

#    eventtime:  mysql datetime of event, loaded if _loaded_row
#    logtime:    mysql datetime of event, loaded if _loaded_row
#    security:   "public", "private", "usemask", loaded if _loaded_row
#    allowmask:  if _loaded_row
#    posterid:   if _loaded_row

#    _loaded_text:   loaded subject/text
#    _loaded_row:    loaded log2 row
#    _loaded_props:  loaded props

# <LJFUNC>
# name: LJ::Entry::new
# class: entry
# des: Gets a journal entry.
# args: uuserid, opts
# des-uobj: A user id or $u to load the entry for.
# des-opts: Hash of optional keypairs.
#           'jitemid' => a journal itemid (no anum)
#           'ditemid' => display itemid (a jitemid << 8 + anum)
#           'anum'    => the id passed was an ditemid, use the anum
#                        to create a proper jitemid.
# returns: A new LJ::Entry object.  undef on failure.
# </LJFUNC>
sub new
{
    my $class = shift;
    my $self  = bless {};

    my $uuserid = shift;
    my $n_arg   = scalar @_;
    croak("wrong number of arguments")
        unless $n_arg && ($n_arg % 2 == 0);

    my %opts = @_;

    croak("can't supply both anum and ditemid")
        if defined $opts{anum} && defined $opts{ditemid};

    croak("can't supply both itemid jand ditemid")
        if defined $opts{ditemid} && defined $opts{jitemid};

    $self->{u}       = LJ::want_user($uuserid) or croak("invalid user/userid parameter");

    $self->{anum}    = delete $opts{anum};
    $self->{ditemid} = delete $opts{ditemid};
    $self->{jitemid} = delete $opts{jitemid};
    $self->{nocache} = delete $opts{nocache};

    # make arguments numeric
    for my $f (qw(ditemid jitemid anum)) {
        $self->{$f} = int($self->{$f}) if defined $self->{$f};
    }

    croak("need to supply either a jitemid or ditemid")
        unless $self->{ditemid} || $self->{jitemid};

    croak("Unknown parameters: " . join(", ", keys %opts))
        if %opts;

    if ($self->{ditemid}) {
        $self->{anum}    = $self->{ditemid} & 255;
        $self->{jitemid} = $self->{ditemid} >> 8;
    }

    return $self;
}

sub set_caching {
    my ($self, $val) = @_;
    $self->{nocache} = $val ? 0 : 1;
}

sub caching {
    my $self = shift;
    return ! $self->{nocache};
}

sub jitemid {
    my $self = shift;
    return $self->{jitemid};
}

sub ditemid {
    my $self = shift;
    return $self->{ditemid} ||= (($self->{jitemid} << 8) + $self->anum);
}

# returns permalink url
sub url {
    my $self = shift;
    my $u = $self->{u};
    my $url = $u->journal_base . "/" . $self->ditemid . ".html";
    return $url;
}

sub anum {
    my $self = shift;
    return $self->{anum} if defined $self->{anum};
    __PACKAGE__->load_rows($self);
    return $self->{anum} if defined $self->{anum};
    croak("couldn't retrieve anum for entry");
}

# class method:
sub load_rows {
    my $class = shift;
    print "class = $class\n";
    my @objs  = @_;
    print "objs = [@objs]\n";
    foreach my $obj (@objs) {
        # row data
        my $log2row = LJ::get_log2_row($obj->{u}, $obj->{jitemid});
        next unless $log2row;
        for my $f (qw(allowmask posterid eventtime logtime security anum)) {
            $obj->{$f} = $log2row->{$f};
        }
    }
}

# returns true if loaded, zero if not.
# also sets _loaded_text and subject and event.
sub _load_text {
    my $self = shift;
    return 1 if $self->{'_loaded_text'};

    my $opts = {};
    $opts->{usemaster} = 1 if $self->{nocache};

    my $ret = LJ::get_logtext2($self->{'u'}, $opts, $self->{'jitemid'});
    my $lt = $ret->{$self->{jitemid}};
    return 0 unless $lt;

    $self->{subject}      = $lt->[0];
    $self->{event}        = $lt->[1];
    $self->{_loaded_text} = 1;
    return 1;
}

sub _load_props {
    my $self = shift;
    return 1 if $self->{_loaded_props};

    my $props = {};
    LJ::load_log_props2($self->{u}, [ $self->{jitemid} ], $props);
    $self->{props} = $props->{ $self->{jitemid} };

    $self->{_loaded_props} = 1;
    return 1;
}


# called automatically on $event->comments
# returns the same data as LJ::get_talk_data, with the addition
# of 'subject' and 'event' keys.
sub _load_comments
{
    my $self = shift;
    $self->{'comments'} =
      ( $self->{'_loaded'} && ! $self->{'props'}->{'replycount'} )
      ? undef
      : LJ::Talk::get_talk_data( $self->{'u'}, 'L', $self->{'jitemid'} );

    my $comments = LJ::get_talktext2( $self->{'u'}, keys %{ $self->{'comments'} } );
    foreach (keys %$comments) {
        $self->{'comments'}->{$_}->{'subject'} = $comments->{$_}[0];
        $self->{'comments'}->{$_}->{'event'}   = $comments->{$_}[1];
    }

    return $self;
}


sub as_atom
{
    my $self = shift;

    my $u         = $self->{u};

    # bleh: should be using a method on LJ::User.  and shouldn't be
    # modifying attributes inside the $u either.  and LJ::Feed should
    # be loading it if it's not preloaded as an optimization.
    # this action-at-a-distance bullshit must die.  --brad
    LJ::load_user_props($u, 'opt_synlevel');
    $u->{'opt_synlevel'} ||= 'full';

    my $ctime   = LJ::mysqldate_to_time($self->{'logtime'}, 1);
    my $modtime = $self->{'props'}->{'revtime'} || $ctime;

    my $item = {
        'itemid'     => $self->{jitemid},
        'ditemid'    => $self->ditemid,
        'eventtime'  => LJ::alldatepart_s2($self->{'eventtime'}),
        'modtime'    => $modtime,
        'subject'    => $self->subject,
        'event'      => $self->event,
    };

    my $atom = LJ::Feed::create_view_atom(
        {
            u      => $self->{'u'},
            'link' => ( LJ::journal_base( $self->{'u'}, "" ) . '/' ),
        },
        $self->{'u'},
        {
            'single_entry' => 1,
            'apilinks'     => 1,
        },
        [$item]
    );

    return $atom;
}

sub subject {
    my $self = shift;
    $self->_load_text unless $self->{_loaded_text};
    return $self->{subject};
}

sub event {
    my $self = shift;
    $self->_load_text unless $self->{_loaded_text};
    return $self->{event};
}

sub clean_subject
{
    my $self = shift;
    $self->_load_text unless $self->{_loaded_text};
    my $subject = $self->{subject};
    LJ::CleanHTML::clean_subject( \$subject ) if $subject;
    return $subject;
}

# instance method.  returns HTML-cleaned/formatted version of the event
# optional $opt may be:
#    undef:   loads the opt_preformatted key and uses that for formatting options
#    1:       treats entry as preformatted (no breaks applied)
#    0:       treats entry as normal (newlines convert to HTML breaks)
#    hashref: passed to LJ::CleanHTML::clean_event verbatim
sub clean_event
{
    my ($self, $opts) = @_;

    if (! defined $opts) {
        $self->_load_props unless $self->{_loaded_props};
        $opts = { preformatted => $self->{props}{opt_preformatted} };
    } elsif (! ref $opts) {
        $opts = { preformatted => $opts };
    }

    $self->_load_text unless $self->{_loaded_text};
    my $event = $self->{event};
    LJ::CleanHTML::clean_event(\$event, $opts);
    return $event;
}

# currently, methods are just getters.
#
# posterid, eventtime, logtime, security, allowmask,
# journalid, jitemid, anum, subject, event, comments
sub AUTOLOAD {
    no strict 'refs';
    my $self = shift;
    (my $data = $AUTOLOAD) =~ s/.+:://;

    *$AUTOLOAD = sub {

        if ($data eq 'comments') {
            $self->_load_comments() unless defined $self->{'comments'};
        }

        return $self->{$data};
    };

    goto &$AUTOLOAD;
}

sub DESTROY {}

package LJ;

# <LJFUNC>
# name: LJ::get_logtext2multi
# des: Gets log text from clusters.
# info: Fetches log text from clusters. Trying slaves first if available.
# returns: hashref with keys being "jid jitemid", values being [ $subject, $body ]
# args: idsbyc
# des-idsbyc: A hashref where the key is the clusterid, and the data
#             is an arrayref of [ ownerid, itemid ] array references.
# </LJFUNC>
sub get_logtext2multi
{
    &nodb;
    return _get_posts_raw_wrapper(shift, "text");
}

# this function is used to translate the old get_logtext2multi and load_log_props2multi
# functions into using the new get_posts_raw.  eventually, the above functions should
# be taken out of the rest of the code, at which point this function can also die.
sub _get_posts_raw_wrapper {
    # args:
    #   { cid => [ [jid, jitemid]+ ] }
    #   "text" or "props"
    #   optional hashref to put return value in.  (see get_logtext2multi docs)
    # returns: that hashref.
    my ($idsbyc, $type, $ret) = @_;

    my $opts = {};
    if ($type eq 'text') {
        $opts->{text_only} = 1;
    } elsif ($type eq 'prop') {
        $opts->{prop_only} = 1;
    } else {
        return undef;
    }

    my @postids;
    while (my ($cid, $ids) = each %$idsbyc) {
        foreach my $pair (@$ids) {
            push @postids, [ $cid, $pair->[0], $pair->[1] ];
        }
    }
    my $rawposts = LJ::get_posts_raw($opts, @postids);

    # add replycounts fields to props
    if ($type eq "prop") {
        while (my ($k, $v) = each %{$rawposts->{"replycount"}||{}}) {
            $rawposts->{prop}{$k}{replycount} = $rawposts->{replycount}{$k};
        }
    }

    # translate colon-separated (new) to space-separated (old) keys.
    $ret ||= {};
    while (my ($id, $data) = each %{$rawposts->{$type}}) {
        $id =~ s/:/ /;
        $ret->{$id} = $data;
    }
    return $ret;
}

# <LJFUNC>
# name: LJ::get_posts_raw
# des: Gets raw post data (text and props) efficiently from clusters.
# info: Fetches posts from clusters, trying memcache and slaves first if available.
# returns: hashref with keys 'text', 'prop', or 'replycount', and values being
#          hashrefs with keys "jid:jitemid".  values of that are as follows:
#          text: [ $subject, $body ], props: { ... }, and replycount: scalar
# args: opts?, id+
# des-opts: An optional hashref of options:
#            - memcache_only:  Don't fall back on the database.
#            - text_only:  Retrieve only text, no props (used to support old API).
#            - prop_only:  Retrieve only props, no text (used to support old API).
# des-id: An arrayref of [ clusterid, ownerid, itemid ].
# </LJFUNC>
sub get_posts_raw
{
    my $opts = ref $_[0] eq "HASH" ? shift : {};
    my $ret = {};
    my $sth;

    LJ::load_props('log') unless $opts->{text_only};

    # throughout this function, the concept of an "id"
    # is the key to identify a single post.
    # it is of the form "$jid:$jitemid".

    # build up a list for each cluster of what we want to get,
    # as well as a list of all the keys we want from memcache.
    my %cids;      # cid => 1
    my $needtext;  # text needed:  $cid => $id => 1
    my $needprop;  # props needed: $cid => $id => 1
    my $needrc;    # replycounts needed: $cid => $id => 1
    my @mem_keys;

    # if we're loading entries for a friends page,
    # silently failing to load a cluster is acceptable.
    # but for a single user, we want to die loudly so they don't think
    # we just lost their journal.
    my $single_user;

    # because the memcache keys for logprop don't contain
    # which cluster they're in, we also need a map to get the
    # cid back from the jid so we can insert into the needfoo hashes.
    # the alternative is to not key the needfoo hashes on cluster,
    # but that means we need to grep out each cluster's jids when
    # we do per-cluster queries on the databases.
    my %cidsbyjid;
    foreach my $post (@_) {
        my ($cid, $jid, $jitemid) = @{$post};
        my $id = "$jid:$jitemid";
        if (not defined $single_user) {
            $single_user = $jid;
        } elsif ($single_user and $jid != $single_user) {
            # multiple users
            $single_user = 0;
        }
        $cids{$cid} = 1;
        $cidsbyjid{$jid} = $cid;
        unless ($opts->{prop_only}) {
            $needtext->{$cid}{$id} = 1;
            push @mem_keys, [$jid,"logtext:$cid:$id"];
        }
        unless ($opts->{text_only}) {
            $needprop->{$cid}{$id} = 1;
            push @mem_keys, [$jid,"logprop:$id"];
            $needrc->{$cid}{$id} = 1;
            push @mem_keys, [$jid,"rp:$id"];
        }
    }

    # first, check memcache.
    my $mem = LJ::MemCache::get_multi(@mem_keys) || {};
    while (my ($k, $v) = each %$mem) {
        next unless defined $v;
        next unless $k =~ /(\w+):(?:\d+:)?(\d+):(\d+)/;
        my ($type, $jid, $jitemid) = ($1, $2, $3);
        my $cid = $cidsbyjid{$jid};
        my $id = "$jid:$jitemid";
        if ($type eq "logtext") {
            delete $needtext->{$cid}{$id};
            $ret->{text}{$id} = $v;
        } elsif ($type eq "logprop" && ref $v eq "HASH") {
            delete $needprop->{$cid}{$id};
            $ret->{prop}{$id} = $v;
        } elsif ($type eq "rp") {
            delete $needrc->{$cid}{$id};
            $ret->{replycount}{$id} = int($v); # remove possible spaces
        }
    }

    # we may be done already.
    return $ret if $opts->{memcache_only};
    return $ret unless values %$needtext or values %$needprop
        or values %$needrc;

    # otherwise, hit the database.
    foreach my $cid (keys %cids) {
        # for each cluster, get the text/props we need from it.
        my $cneedtext = $needtext->{$cid} || {};
        my $cneedprop = $needprop->{$cid} || {};
        my $cneedrc   = $needrc->{$cid} || {};

        next unless %$cneedtext or %$cneedprop or %$cneedrc;

        my $make_in = sub {
            my @in;
            foreach my $id (@_) {
                my ($jid, $jitemid) = map { $_ + 0 } split(/:/, $id);
                push @in, "(journalid=$jid AND jitemid=$jitemid)";
            }
            return join(" OR ", @in);
        };

        # now load from each cluster.
        my $fetchtext = sub {
            my $db = shift;
            return unless %$cneedtext;
            my $in = $make_in->(keys %$cneedtext);
            $sth = $db->prepare("SELECT journalid, jitemid, subject, event ".
                                "FROM logtext2 WHERE $in");
            $sth->execute;
            while (my ($jid, $jitemid, $subject, $event) = $sth->fetchrow_array) {
                LJ::text_uncompress(\$event);
                my $id = "$jid:$jitemid";
                my $val = [ $subject, $event ];
                $ret->{text}{$id} = $val;
                LJ::MemCache::add([$jid,"logtext:$cid:$id"], $val);
                delete $cneedtext->{$id};
            }
        };

        my $fetchprop = sub {
            my $db = shift;
            return unless %$cneedprop;
            my $in = $make_in->(keys %$cneedprop);
            $sth = $db->prepare("SELECT journalid, jitemid, propid, value ".
                                "FROM logprop2 WHERE $in");
            $sth->execute;
            my %gotid;
            while (my ($jid, $jitemid, $propid, $value) = $sth->fetchrow_array) {
                my $id = "$jid:$jitemid";
                my $propname = $LJ::CACHE_PROPID{'log'}->{$propid}{name};
                $ret->{prop}{$id}{$propname} = $value;
                $gotid{$id} = 1;
            }
            foreach my $id (keys %gotid) {
                my ($jid, $jitemid) = map { $_ + 0 } split(/:/, $id);
                LJ::MemCache::add([$jid, "logprop:$id"], $ret->{prop}{$id});
                delete $cneedprop->{$id};
            }
        };

        my $fetchrc = sub {
            my $db = shift;
            return unless %$cneedrc;
            my $in = $make_in->(keys %$cneedrc);
            $sth = $db->prepare("SELECT journalid, jitemid, replycount FROM log2 WHERE $in");
            $sth->execute;
            while (my ($jid, $jitemid, $rc) = $sth->fetchrow_array) {
                my $id = "$jid:$jitemid";
                $ret->{replycount}{$id} = $rc;
                LJ::MemCache::add([$jid, "rp:$id"], $rc);
                delete $cneedrc->{$id};
            }
        };

        my $dberr = sub {
            die "Couldn't connect to database" if $single_user;
            next;
        };

        # run the fetch functions on the proper databases, with fallbacks if necessary.
        my ($dbcm, $dbcr);
        if (@LJ::MEMCACHE_SERVERS or $opts->{use_master}) {
            $dbcm ||= LJ::get_cluster_master($cid) or $dberr->();
            $fetchtext->($dbcm) if %$cneedtext;
            $fetchprop->($dbcm) if %$cneedprop;
            $fetchrc->($dbcm) if %$cneedrc;
        } else {
            $dbcr ||= LJ::get_cluster_reader($cid);
            if ($dbcr) {
                $fetchtext->($dbcr) if %$cneedtext;
                $fetchprop->($dbcr) if %$cneedprop;
                $fetchrc->($dbcr) if %$cneedrc;
            }
            # if we still need some data, switch to the master.
            if (%$cneedtext or %$cneedprop) {
                $dbcm ||= LJ::get_cluster_master($cid) or $dberr->();
                $fetchtext->($dbcm);
                $fetchprop->($dbcm);
                $fetchrc->($dbcm);
            }
        }

        # and finally, if there were no errors,
        # insert into memcache the absence of props
        # for all posts that didn't have any props.
        foreach my $id (keys %$cneedprop) {
            my ($jid, $jitemid) = map { $_ + 0 } split(/:/, $id);
            LJ::MemCache::set([$jid, "logprop:$id"], {});
        }
    }
    return $ret;
}

sub get_posts
{
    my $opts = ref $_[0] eq "HASH" ? shift : {};
    my $rawposts = get_posts_raw($opts, @_);

    # fix up posts as needed for display, following directions given in opts.


    # XXX this function is incomplete.  it should also HTML clean, etc.
    # XXX we need to load users when we have unknown8bit data, but that
    # XXX means we have to load users.


    while (my ($id, $rp) = each %$rawposts) {
        if ($LJ::UNICODE && $rp->{props}{unknown8bit}) {
            #LJ::item_toutf8($u, \$rp->{text}[0], \$rp->{text}[1], $rp->{props});
        }
    }

    return $rawposts;
}

#
# returns a row from log2, trying memcache
# accepts $u + $jitemid
# returns hash with: posterid, eventtime, logtime,
# security, allowmask, journalid, jitemid, anum.

sub get_log2_row
{
    my ($u, $jitemid) = @_;
    my $jid = $u->{'userid'};

    my $memkey = [$jid, "log2:$jid:$jitemid"];
    my ($row, $item);

    $row = LJ::MemCache::get($memkey);

    if ($row) {
        @$item{'posterid', 'eventtime', 'logtime', 'allowmask', 'ditemid'} = unpack("NNNNN", $row);
        $item->{'security'} = ($item->{'allowmask'} == 0 ? 'private' :
                               ($item->{'allowmask'} == 2**31 ? 'public' : 'usemask'));
        $item->{'journalid'} = $jid;
        @$item{'jitemid', 'anum'} = ($item->{'ditemid'} >> 8, $item->{'ditemid'} % 256);
        $item->{'eventtime'} = LJ::mysql_time($item->{'eventtime'}, 1);
        $item->{'logtime'} = LJ::mysql_time($item->{'logtime'}, 1);

        return $item;
    }

    my $db = LJ::get_cluster_def_reader($u);
    return undef unless $db;

    my $sql = "SELECT posterid, eventtime, logtime, security, allowmask, " .
              "anum FROM log2 WHERE journalid=? AND jitemid=?";

    $item = $db->selectrow_hashref($sql, undef, $jid, $jitemid);
    return undef unless $item;
    $item->{'journalid'} = $jid;
    $item->{'jitemid'} = $jitemid;
    $item->{'ditemid'} = $jitemid*256 + $item->{'anum'};

    my ($sec, $eventtime, $logtime);
    $sec = $item->{'allowmask'};
    $sec = 0 if $item->{'security'} eq 'private';
    $sec = 2**31 if $item->{'security'} eq 'public';
    $eventtime = LJ::mysqldate_to_time($item->{'eventtime'}, 1);
    $logtime = LJ::mysqldate_to_time($item->{'logtime'}, 1);

    $row = pack("NNNNN", $item->{'posterid'}, $eventtime, $logtime, $sec,
                $item->{'ditemid'});
    LJ::MemCache::set($memkey, $row);

    return $item;
}

# get 2 weeks worth of recent items, in rlogtime order,
# using memcache
# accepts $u or ($jid, $clusterid) + $notafter - max value for rlogtime
# $update is the timeupdate for this user, as far as the caller knows,
# in UNIX time.
# returns hash keyed by $jitemid, fields:
# posterid, eventtime, rlogtime,
# security, allowmask, journalid, jitemid, anum.

sub get_log2_recent_log
{
    my ($u, $cid, $update, $notafter) = @_;
    my $jid = LJ::want_userid($u);
    $cid ||= $u->{'clusterid'} if ref $u;

    my $DATAVER = "3"; # 1 char

    my $memkey = [$jid, "log2lt:$jid"];
    my $lockkey = $memkey->[1];
    my ($rows, $ret);

    $rows = LJ::MemCache::get($memkey);
    $ret = [];

    my $rows_decode = sub {
        return 0
            unless $rows && substr($rows, 0, 1) eq $DATAVER;
        my $tu = unpack("N", substr($rows, 1, 4));

        # if update time we got from upstream is newer than recorded
        # here, this data is unreliable
        return 0 if $update > $tu;

        my $n = (length($rows) - 5 )/20;
        for (my $i=0; $i<$n; $i++) {
            my ($posterid, $eventtime, $rlogtime, $allowmask, $ditemid) =
                unpack("NNNNN", substr($rows, $i*20+5, 20));
            next if $notafter and $rlogtime > $notafter;
            $eventtime = LJ::mysql_time($eventtime, 1);
            my $security = $allowmask == 0 ? 'private' :
                ($allowmask == 2**31 ? 'public' : 'usemask');
            my ($jitemid, $anum) = ($ditemid >> 8, $ditemid % 256);
            my $item = {};
            @$item{'posterid','eventtime','rlogtime','allowmask','ditemid',
                   'security','journalid', 'jitemid', 'anum'} =
                       ($posterid, $eventtime, $rlogtime, $allowmask,
                        $ditemid, $security, $jid, $jitemid, $anum);
            $item->{'ownerid'} = $jid;
            $item->{'itemid'} = $jitemid;
            push @$ret, $item;
        }
        return 1;
    };

    return $ret
        if $rows_decode->();
    $rows = "";

    my $db = LJ::get_cluster_def_reader($cid);
    # if we use slave or didn't get some data, don't store in memcache
    my $dont_store = 0;
    unless ($db) {
        $db = LJ::get_cluster_reader($cid);
        $dont_store = 1;
        return undef unless $db;
    }

    my $lock = $db->selectrow_array("SELECT GET_LOCK(?,10)", undef, $lockkey);
    return undef unless $lock;

    $rows = LJ::MemCache::get($memkey);
    if ($rows_decode->()) {
        $db->selectrow_array("SELECT RELEASE_LOCK(?)", undef, $lockkey);
        return $ret;
    }
    $rows = "";

    # get reliable update time from the db
    # TODO: check userprop first
    my $tu;
    my $dbh = LJ::get_db_writer();
    if ($dbh) {
        $tu = $dbh->selectrow_array("SELECT UNIX_TIMESTAMP(timeupdate) " .
                                    "FROM userusage WHERE userid=?",
                                    undef, $jid);
        # if no mistake, treat absence of row as tu==0 (new user)
        $tu = 0 unless $tu || $dbh->err;

        LJ::MemCache::set([$jid, "tu:$jid"], pack("N", $tu), 30*60)
            if defined $tu;
        # TODO: update userprop if necessary
    }

    # if we didn't get tu, don't bother to memcache
    $dont_store = 1 unless defined $tu;

    # get reliable log2lt data from the db

    my $max_age = $LJ::MAX_FRIENDS_VIEW_AGE || 3600*24*14; # 2 weeks default

    my $sql = "SELECT jitemid, posterid, eventtime, rlogtime, " .
        "security, allowmask, anum, replycount FROM log2 " .
        "USE INDEX (rlogtime) WHERE journalid=? AND " .
        "rlogtime <= ($LJ::EndOfTime - UNIX_TIMESTAMP()) + $max_age";

    my $sth = $db->prepare($sql);
    $sth->execute($jid);
    my @row;
    push @row, $_ while $_ = $sth->fetchrow_hashref;
    @row = sort { $a->{'rlogtime'} <=> $b->{'rlogtime'} } @row;
    my $itemnum = 0;

    foreach my $item (@row) {
        $item->{'ownerid'} = $item->{'journalid'} = $jid;
        $item->{'itemid'} = $item->{'jitemid'};
        push @$ret, $item;

        my ($sec, $ditemid, $eventtime, $logtime);
        $sec = $item->{'allowmask'};
        $sec = 0 if $item->{'security'} eq 'private';
        $sec = 2**31 if $item->{'security'} eq 'public';
        $ditemid = $item->{'jitemid'}*256 + $item->{'anum'};
        $eventtime = LJ::mysqldate_to_time($item->{'eventtime'}, 1);

        $rows .= pack("NNNNN",
                      $item->{'posterid'},
                      $eventtime,
                      $item->{'rlogtime'},
                      $sec,
                      $ditemid);

        if ($itemnum++ < 50) {
            LJ::MemCache::add([$jid, "rp:$jid:$item->{'jitemid'}"], $item->{'replycount'});
        }
    }

    $rows = $DATAVER . pack("N", $tu) . $rows;
    LJ::MemCache::set($memkey, $rows) unless $dont_store;

    $db->selectrow_array("SELECT RELEASE_LOCK(?)", undef, $lockkey);
    return $ret;
}

sub get_log2_recent_user
{
    my $opts = shift;
    my $ret = [];

    my $log = LJ::get_log2_recent_log($opts->{'userid'}, $opts->{'clusterid'},
              $opts->{'update'}, $opts->{'notafter'});

    my $left = $opts->{'itemshow'};
    my $notafter = $opts->{'notafter'};
    my $remote = $opts->{'remote'};

    foreach my $item (@$log) {
        last unless $left;
        last if $notafter and $item->{'rlogtime'} > $notafter;
        next unless $remote || $item->{'security'} eq 'public';
        next if $item->{'security'} eq 'private'
            and $item->{'journalid'} != $remote->{'userid'};
        if ($item->{'security'} eq 'usemask') {
            next unless $remote->{'journaltype'} eq "P";
            my $permit = ($item->{'journalid'} == $remote->{'userid'});
            unless ($permit) {
                my $mask = LJ::get_groupmask($item->{'journalid'}, $remote->{'userid'});
                $permit = $item->{'allowmask'}+0 & $mask+0;
            }
            next unless $permit;
        }

        # date conversion
        if ($opts->{'dateformat'} eq "S2") {
            $item->{'alldatepart'} = LJ::alldatepart_s2($item->{'eventtime'});
        } else {
            $item->{'alldatepart'} = LJ::alldatepart_s1($item->{'eventtime'});
        }
        push @$ret, $item;
    }

    return @$ret;
}

sub get_itemid_near2
{
    my $u = shift;
    my $jitemid = shift;
    my $after_before = shift;

    $jitemid += 0;

    my ($inc, $order);
    if ($after_before eq "after") {
        ($inc, $order) = (-1, "DESC");
    } elsif ($after_before eq "before") {
        ($inc, $order) = (1, "ASC");
    } else {
        return 0;
    }

    my $dbr = LJ::get_cluster_reader($u);
    my $jid = $u->{'userid'}+0;
    my $field = $u->{'journaltype'} eq "P" ? "revttime" : "rlogtime";

    my $stime = $dbr->selectrow_array("SELECT $field FROM log2 WHERE ".
                                      "journalid=$jid AND jitemid=$jitemid");
    return 0 unless $stime;


    my $day = 86400;
    foreach my $distance ($day, $day*7, $day*30, $day*90) {
        my ($one_away, $further) = ($stime + $inc, $stime + $inc*$distance);
        if ($further < $one_away) {
            # swap them, BETWEEN needs lower number first
            ($one_away, $further) = ($further, $one_away);
        }
        my ($id, $anum) =
            $dbr->selectrow_array("SELECT jitemid, anum FROM log2 WHERE journalid=$jid ".
                                  "AND $field BETWEEN $one_away AND $further ".
                                  "ORDER BY $field $order LIMIT 1");
        if ($id) {
            return wantarray() ? ($id, $anum) : ($id*256 + $anum);
        }
    }
    return 0;
}

sub get_itemid_after2  { return get_itemid_near2(@_, "after");  }
sub get_itemid_before2 { return get_itemid_near2(@_, "before"); }

sub set_logprop
{
    my ($u, $jitemid, $hashref, $logprops) = @_;  # hashref to set, hashref of what was done

    $jitemid += 0;
    my $uid = $u->{'userid'} + 0;
    my $kill_mem = 0;
    my $del_ids;
    my $ins_values;
    while (my ($k, $v) = each %{$hashref||{}}) {
        my $prop = LJ::get_prop("log", $k);
        next unless $prop;
        $kill_mem = 1 unless $prop eq "commentalter";
        if ($v) {
            $ins_values .= "," if $ins_values;
            $ins_values .= "($uid, $jitemid, $prop->{'id'}, " . $u->quote($v) . ")";
            $logprops->{$k} = $v;
        } else {
            $del_ids .= "," if $del_ids;
            $del_ids .= $prop->{'id'};
        }
    }

    $u->do("REPLACE INTO logprop2 (journalid, jitemid, propid, value) ".
           "VALUES $ins_values") if $ins_values;
    $u->do("DELETE FROM logprop2 WHERE journalid=? AND jitemid=? ".
           "AND propid IN ($del_ids)", undef, $u->{'userid'}, $jitemid) if $del_ids;

    LJ::MemCache::delete([$uid,"logprop:$uid:$jitemid"]) if $kill_mem;
}

# <LJFUNC>
# name: LJ::load_log_props2
# class:
# des:
# info:
# args: db?, uuserid, listref, hashref
# des-:
# returns:
# </LJFUNC>
sub load_log_props2
{
    my $db = isdb($_[0]) ? shift @_ : undef;

    my ($uuserid, $listref, $hashref) = @_;
    my $userid = want_userid($uuserid);
    return unless ref $hashref eq "HASH";

    my %needprops;
    my %needrc;
    my %rc;
    my @memkeys;
    foreach (@$listref) {
        my $id = $_+0;
        $needprops{$id} = 1;
        $needrc{$id} = 1;
        push @memkeys, [$userid, "logprop:$userid:$id"];
        push @memkeys, [$userid, "rp:$userid:$id"];
    }
    return unless %needprops || %needrc;

    my $mem = LJ::MemCache::get_multi(@memkeys) || {};
    while (my ($k, $v) = each %$mem) {
        next unless $k =~ /(\w+):(\d+):(\d+)/;
        if ($1 eq 'logprop') {
            next unless ref $v eq "HASH";
            delete $needprops{$3};
            $hashref->{$3} = $v;
        }
        if ($1 eq 'rp') {
            delete $needrc{$3};
            $rc{$3} = int($v);  # change possible "0   " (true) to "0" (false)
        }
    }

    foreach (keys %rc) {
        $hashref->{$_}{'replycount'} = $rc{$_};
    }

    return unless %needprops || %needrc;

    unless ($db) {
        my $u = LJ::load_userid($userid);
        $db = @LJ::MEMCACHE_SERVERS ? LJ::get_cluster_def_reader($u) :  LJ::get_cluster_reader($u);
        return unless $db;
    }

    if (%needprops) {
        LJ::load_props("log");
        my $in = join(",", keys %needprops);
        my $sth = $db->prepare("SELECT jitemid, propid, value FROM logprop2 ".
                                 "WHERE journalid=? AND jitemid IN ($in)");
        $sth->execute($userid);
        while (my ($jitemid, $propid, $value) = $sth->fetchrow_array) {
            $hashref->{$jitemid}->{$LJ::CACHE_PROPID{'log'}->{$propid}->{'name'}} = $value;
        }
        foreach my $id (keys %needprops) {
            LJ::MemCache::set([$userid,"logprop:$userid:$id"], $hashref->{$id} || {});
          }
    }

    if (%needrc) {
        my $in = join(",", keys %needrc);
        my $sth = $db->prepare("SELECT jitemid, replycount FROM log2 WHERE journalid=? AND jitemid IN ($in)");
        $sth->execute($userid);
        while (my ($jitemid, $rc) = $sth->fetchrow_array) {
            $hashref->{$jitemid}->{'replycount'} = $rc;
            LJ::MemCache::add([$userid, "rp:$userid:$jitemid"], $rc);
        }
    }


}

# <LJFUNC>
# name: LJ::load_log_props2multi
# class:
# des:
# info:
# args:
# des-:
# returns:
# </LJFUNC>
sub load_log_props2multi
{
    &nodb;
    my ($ids, $props) = @_;
    _get_posts_raw_wrapper($ids, "prop", $props);
}

# <LJFUNC>
# name: LJ::delete_entry
# des: Deletes a user's journal entry
# args: uuserid, jitemid, quick?, anum?
# des-uuserid: Journal itemid or $u object of journal to delete entry from
# des-jitemid: Journal itemid of item to delete.
# des-quick: Optional boolean.  If set, only [dbtable[log2]] table
#            is deleted from and the rest of the content is deleted
#            later using [func[LJ::cmd_buffer_add]].
# des-anum: The log item's anum, which'll be needed to delete lazily
#           some data in tables which includes the anum, but the
#           log row will already be gone so we'll need to store it for later.
# returns: boolean; 1 on success, 0 on failure.
# </LJFUNC>
sub delete_entry
{
    my ($uuserid, $jitemid, $quick, $anum) = @_;
    my $jid = LJ::want_userid($uuserid);
    my $u = ref $uuserid ? $uuserid : LJ::load_userid($jid);
    $jitemid += 0;

    my $and;
    if (defined $anum) { $and = "AND anum=" . ($anum+0); }

    my $dc = $u->log2_do(undef, "DELETE FROM log2 WHERE journalid=$jid AND jitemid=$jitemid $and");
    return 0 unless $dc;
    LJ::MemCache::delete([$jid, "log2:$jid:$jitemid"]);
    LJ::MemCache::decr([$jid, "log2ct:$jid"]);
    LJ::memcache_kill($jid, "dayct");

    # delete tags
    LJ::Tags::delete_logtags($u, $jitemid);

    # if this is running the second time (started by the cmd buffer),
    # the log2 row will already be gone and we shouldn't check for it.
    if ($quick) {
        return 1 if $dc < 1;  # already deleted?
        return LJ::cmd_buffer_add($u->{clusterid}, $jid, "delitem", {
            'itemid' => $jitemid,
            'anum' => $anum,
        });
    }

    # delete from clusters
    foreach my $t (qw(logtext2 logprop2 logsec2)) {
        $u->do("DELETE FROM $t WHERE journalid=$jid AND jitemid=$jitemid");
    }
    $u->dudata_set('L', $jitemid, 0);

    # delete all comments
    LJ::delete_all_comments($u, 'L', $jitemid);

    return 1;
}

# <LJFUNC>
# name: LJ::mark_entry_as_spam
# class: web
# des: Copies an entry in a community into the global spamreports table
# args: journalu, jitemid
# des-journalu: User object of journal (community) entry was posted in.
# des-jitemid: ID of this entry.
# returns: 1 for success, 0 for failure
# </LJFUNC>
sub mark_entry_as_spam {
    my ($journalu, $jitemid) = @_;
    $journalu = LJ::want_user($journalu);
    $jitemid += 0;
    return 0 unless $journalu && $jitemid;

    my $dbcr = LJ::get_cluster_def_reader($journalu);
    my $dbh = LJ::get_db_writer();
    return 0 unless $dbcr && $dbh;

    my $item = LJ::get_log2_row($journalu, $jitemid);
    return 0 unless $item;

    # step 1: get info we need
    my $logtext = LJ::get_logtext2($journalu, $jitemid);
    my ($subject, $body, $posterid) = ($logtext->{$jitemid}[0], $logtext->{$jitemid}[1], $item->{posterid});
    return 0 unless $body;

    # step 2: insert into spamreports
    $dbh->do('INSERT INTO spamreports (reporttime, posttime, journalid, posterid, subject, body, report_type) ' .
             'VALUES (UNIX_TIMESTAMP(), UNIX_TIMESTAMP(?), ?, ?, ?, ?, \'entry\')',
              undef, $item->{logtime}, $journalu->{userid}, $posterid, $subject, $body);

    return 0 if $dbh->err;
    return 1;
}

# replycount_do
# input: $u, $jitemid, $action, $value
# action is one of: "init", "incr", "decr"
# $value is amount to incr/decr, 1 by default

sub replycount_do {
    my ($u, $jitemid, $action, $value) = @_;
    $value = 1 unless defined $value;
    my $uid = $u->{'userid'};
    my $memkey = [$uid, "rp:$uid:$jitemid"];

    # "init" is easiest and needs no lock (called before the entry is live)
    if ($action eq 'init') {
        LJ::MemCache::set($memkey, "0   ");
        return 1;
    }

    return 0 unless $u->writer;

    my $lockkey = $memkey->[1];
    $u->selectrow_array("SELECT GET_LOCK(?,10)", undef, $lockkey);

    my $ret;

    if ($action eq 'decr') {
        $ret = LJ::MemCache::decr($memkey, $value);
        $u->do("UPDATE log2 SET replycount=replycount-$value WHERE journalid=$uid AND jitemid=$jitemid");
    }

    if ($action eq 'incr') {
        $ret = LJ::MemCache::incr($memkey, $value);
        $u->do("UPDATE log2 SET replycount=replycount+$value WHERE journalid=$uid AND jitemid=$jitemid");
    }

    if (@LJ::MEMCACHE_SERVERS && ! defined $ret) {
        my $rc = $u->selectrow_array("SELECT replycount FROM log2 WHERE journalid=$uid AND jitemid=$jitemid");
        if (defined $rc) {
            $rc = sprintf("%-4d", $rc);
            LJ::MemCache::set($memkey, $rc);
        }
    }

    $u->selectrow_array("SELECT RELEASE_LOCK(?)", undef, $lockkey);

    return 1;
}

# <LJFUNC>
# name: LJ::get_logtext2
# des: Efficiently retrieves a large number of journal entry text, trying first
#      slave database servers for recent items, then the master in
#      cases of old items the slaves have already disposed of.  See also:
#      [func[LJ::get_talktext2]].
# args: u, opts?, jitemid*
# returns: hashref with keys being jitemids, values being [ $subject, $body ]
# des-opts: Optional hashref of special options.  Currently only 'usemaster'
#           key is supported, which always returns a definitive copy,
#           and not from a cache or slave database.
# des-jitemid: List of jitemids to retrieve the subject & text for.
# </LJFUNC>
sub get_logtext2
{
    my $u = shift;
    my $clusterid = $u->{'clusterid'};
    my $journalid = $u->{'userid'}+0;

    my $opts = ref $_[0] ? shift : {};

    # return structure.
    my $lt = {};
    return $lt unless $clusterid;

    # keep track of itemids we still need to load.
    my %need;
    my @mem_keys;
    foreach (@_) {
        my $id = $_+0;
        $need{$id} = 1;
        push @mem_keys, [$journalid,"logtext:$clusterid:$journalid:$id"];
    }

    # pass 0: memory, avoiding databases
    unless ($opts->{'usemaster'}) {
        my $mem = LJ::MemCache::get_multi(@mem_keys) || {};
        while (my ($k, $v) = each %$mem) {
            next unless $v;
            $k =~ /:(\d+):(\d+):(\d+)/;
            delete $need{$3};
            $lt->{$3} = $v;
        }
    }

    return $lt unless %need;

    # pass 1 (slave) and pass 2 (master)
    foreach my $pass (1, 2) {
        next unless %need;
        next if $pass == 1 && $opts->{'usemaster'};
        my $db = $pass == 1 ? LJ::get_cluster_reader($clusterid) :
            LJ::get_cluster_def_reader($clusterid);
        next unless $db;

        my $jitemid_in = join(", ", keys %need);
        my $sth = $db->prepare("SELECT jitemid, subject, event FROM logtext2 ".
                               "WHERE journalid=$journalid AND jitemid IN ($jitemid_in)");
        $sth->execute;
        while (my ($id, $subject, $event) = $sth->fetchrow_array) {
            LJ::text_uncompress(\$event);
            my $val = [ $subject, $event ];
            $lt->{$id} = $val;
            LJ::MemCache::add([$journalid,"logtext:$clusterid:$journalid:$id"], $val);
            delete $need{$id};
        }
    }
    return $lt;
}

1;
