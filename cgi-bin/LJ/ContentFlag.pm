use strict;
package LJ::ContentFlag;
use Carp qw (croak);

use constant {
    # status
    NEW             => 'N',
    CLOSED          => 'C',

    ABUSE_WARN      => 'W',
    ABUSE_DELETE    => 'D',
    ABUSE_SUSPEND   => 'S',
    ABUSE_TERMINATE => 'T',

    REPORTER_BANNED => 'B',
    PERM_OK         => 'O',

    # category
    CHILD_PORN       => 1,
    ILLEGAL_ACTIVITY => 2,
    ILLEGAL_CONTENT  => 3,

    # type
    ENTRY   => 1,
    COMMENT => 2,
    JOURNAL => 3,
    PROFILE => 4,
};

# constants to English
our %CAT_NAMES = (
                  LJ::ContentFlag::CHILD_PORN       => "Child Pornography",
                  LJ::ContentFlag::ILLEGAL_ACTIVITY => "Illegal Activity",
                  LJ::ContentFlag::ILLEGAL_CONTENT  => "Illegal Content",
                  );

our %STATUS_NAMES = (
                     LJ::ContentFlag::NEW             => 'New',
                     LJ::ContentFlag::CLOSED          => "Closed Without Action",
                     LJ::ContentFlag::ABUSE_DELETE    => 'Deletion Required',
                     LJ::ContentFlag::ABUSE_SUSPEND   => 'Account Suspended',
                     LJ::ContentFlag::ABUSE_WARN      => 'Warning Issued',
                     LJ::ContentFlag::ABUSE_TERMINATE => 'Account Terminated',
                     LJ::ContentFlag::PERM_OK         => 'Permanently OK',
                     );

sub category_names { \%CAT_NAMES }
sub status_names   { \%STATUS_NAMES }

our @fields;

# there has got to be a better way to use fields with a list
BEGIN {
    @fields = qw (flagid journalid typeid itemid catid reporterid reporteruniq instime modtime status);
    eval "use fields qw(" . join (' ', @fields) . " _count); 1;" or die $@;
};


####### Class methods


# create a flag for an item
#  opts:
#   $item or $type + $itemid - need to pass $item (entry, comment, etc...) or $type constant with $itemid
#   $journal - journal the $item is in (not needed if $item passed)
#   $reporter - person flagging this item
#   $cat - category constant (why is the reporter flagging this?)
sub create {
    my ($class, %opts) = @_;

    my $journal = delete $opts{journal} || LJ::load_userid(delete $opts{journalid});
    my $type = delete $opts{type} || delete $opts{typeid};
    my $item = delete $opts{item};
    my $itemid = delete $opts{itemid};
    my $reporter = (delete $opts{reporter} || LJ::get_remote()) or croak 'no reporter';
    my $cat = delete $opts{cat} || delete $opts{catid} or croak 'no category';

    croak "need item or type" unless $item || $type;
    croak "need journal" unless $journal;

    croak "unknown options: " . join(', ', keys %opts) if %opts;

    # if $item passed, get itemid and type from it
    if ($item) {
        if ($item->isa("LJ::Entry")) {
            $itemid = $item->ditemid;
            $type = ENTRY;
        } else {
            croak "unknown item type: $item";
        }
    }

    my $uniq = LJ::UniqCookie->current_uniq;

    my %flag = (
                journalid    => $journal->id,
                itemid       => $itemid,
                typeid       => $type,
                catid        => $cat,
                reporterid   => $reporter->id,
                status       => LJ::ContentFlag::NEW,
                instime      => time(),
                reporteruniq => $uniq,
                );

    my $dbh = LJ::get_db_writer() or die "could not get db writer";
    my @params = keys %flag;
    my $bind = LJ::bindstr(@params);
    $dbh->do("INSERT INTO content_flag (" . join(',', @params) . ") VALUES ($bind)",
             undef, map { $flag{$_} } @params);
    die $dbh->errstr if $dbh->err;

    my $flagid = $dbh->{mysql_insertid};
    die "did not get an insertid" unless defined $flagid;

    # log this rating
    LJ::rate_log($reporter, 'ctflag', 1);

    $flag{flagid} = $flagid;
    my ($dbflag) = $class->absorb_row(\%flag);
    return $dbflag;
}
# alias flag() to create()
*flag = \&create;

*load_by_flagid = \&load_by_id;
sub load_by_id {
    my ($class, $flagid, %opts) = @_;
    return undef unless $flagid;
    return $class->load(flagid => $flagid+0, %opts);
}

sub load_by_flagids {
    my ($class, $flagidsref, %opts) = @_;
    croak "not passed a flagids arrayref" unless ref $flagidsref && ref $flagidsref eq 'ARRAY';
    return () unless @$flagidsref;
    return $class->load(flagids => $flagidsref, %opts);
}

sub load_by_journal {
    my ($class, $journal, %opts) = @_;
    return $class->load(journalid => LJ::want_userid($journal), %opts);
}

sub load_by_status {
    my ($class, $status, %opts) = @_;
    return $class->load(status => $status, %opts);
}

# load flags marked NEW
sub load_outstanding {
    my ($class, %opts) = @_;
    return $class->load(status => LJ::ContentFlag::NEW, %opts);
}

# given a flag, find other flags that have the same journalid, typeid, itemid, catid
sub find_similar_flags {
    my ($self, %opts) = @_;
    return $self->load(
                       journalid => $self->journalid,
                       itemid => $self->itemid,
                       typeid => $self->typeid,
                       catid => $self->catid,
                       %opts,
                       );
}

sub find_similar_flagids {
    my ($self, %opts) = @_;
    my $dbr = LJ::get_db_reader();
    my $flagids = $dbr->selectcol_arrayref("SELECT flagid FROM content_flag WHERE " .
                                           "journalid=? AND typeid=? AND itemid=? AND catid=? AND flagid != ? LIMIT 1000",
                                           undef, $self->journalid, $self->typeid, $self->itemid, $self->catid, $self->flagid);
    die $dbr->errstr if $dbr->err;
    return @$flagids;
}

# load rows from DB
# if $opts{lock}, this will lock the result set for a while so that
# other people won't get the same set of flags to work on
#
# other opts:
#  limit, catid, status, flagid, flagids (arrayref), sort
sub load {
    my ($class, %opts) = @_;

    my $instime = $opts{from};

    # default to showing everything in the past month
    $instime = time() - 86400*30 unless defined $instime;
    $opts{instime} ||= $instime;

    my $limit = $opts{limit}+0 || 1000;

    my $catid = $opts{catid};
    my $status = $opts{status};
    my $flagid = $opts{flagid};
    my $flagidsref = $opts{flagids};

    croak "cannot pass flagid and flagids" if $flagid && $flagidsref;

    my $sort = $opts{sort};

    my $fields = join(',', @fields);

    my $dbr = LJ::get_db_reader() or die "Could not get db reader";

    my @vals = ();
    my $constraints = "";

    # add other constraints
    foreach my $c (qw( journalid typeid itemid catid status flagid modtime instime reporterid )) {
        my $val = delete $opts{$c} or next;

        my $cmp = '=';

        # use > for selecting by time, = for everything else
        if ($c eq 'modtime' || $c eq 'instime') {
            $cmp = '>';
        }

        # build sql
        $constraints .= ($constraints ? " AND " : " ") . "$c $cmp ?";
        push @vals, $val;
    }

    if ($flagidsref) {
        my @flagids = @$flagidsref;
        my $bind = LJ::bindstr(@flagids);
        $constraints .= ($constraints ? " AND " : " ") . "flagid IN ($bind)";
        push @vals, @flagids;
    }

    croak "no constraints specified" unless $constraints;

    my @locked;

    if ($opts{lock}) {
        my $lockedref = LJ::MemCache::get($class->memcache_key);
        @locked = $lockedref ? @$lockedref : ();

        if (@locked) {
            my $lockedbind = LJ::bindstr(@locked);
            $constraints .= " AND flagid NOT IN ($lockedbind)";
            push @vals, @locked;
        }
    }

    my $groupby = '';

    $sort =~ s/\W//g if $sort;

    if ($opts{group}) {
        $groupby = ' GROUP BY journalid,typeid,itemid';
        $fields .= ',COUNT(flagid) as count';
        $sort ||= 'count';
    }

    $sort ||= 'instime';

    my $sql = "SELECT $fields FROM content_flag WHERE $constraints $groupby ORDER BY $sort DESC LIMIT $limit";
    print STDERR $sql if $opts{debug};

    my $rows = $dbr->selectall_arrayref($sql, undef, @vals);
    die $dbr->errstr if $dbr->err;

    if ($opts{lock}) {
        # lock flagids for a few minutes
        my @flagids = map { $_->[0] } @$rows;

        # lock flags on the same items as well
        my @items = $class->load_by_flagids(\@flagids);
        my @related_flagids = map { $_->find_similar_flagids } @items;

        push @flagids, (@related_flagids, @locked);

        $class->lock(@flagids);
    }

    return map { $class->absorb_row($_) } @$rows;
}

sub num_locked_flags {
    my $class = shift;

    my $lockedref = LJ::MemCache::get($class->memcache_key) || [];
    return scalar @$lockedref;
}

# append these flagids to the locked set
sub lock {
    my ($class, @flagids) = @_;

    my $lockedref = LJ::MemCache::get($class->memcache_key) || [];
    my @locked = @$lockedref;

    my %new_locked = map { $_ => 1 } @flagids, @locked;
    LJ::MemCache::set($class->memcache_key, [ keys %new_locked ], 5 * 60);
}

# remove these flagids from the locked set
sub unlock {
    my ($class, @flagids) = @_;

    # if there's nothing memcached, there's nothing to unlock!
    my $lockedref = LJ::MemCache::get($class->memcache_key) or return;

    my %locked = map { ($_ => 1) } @$lockedref;
    delete $locked{$_} foreach @flagids;

    LJ::MemCache::set($class->memcache_key, [ keys %locked ], 5 * 60);
}

sub memcache_key { 'ct_flag_locked' }

sub absorb_row {
    my ($class, $row) = @_;

    my $self = fields::new($class);

    if (ref $row eq 'ARRAY') {
        $self->{$_} = (shift @$row) foreach @fields;
        $self->{_count} = (shift @$row) if @$row;
    } elsif (ref $row eq 'HASH') {
        $self->{$_} = $row->{$_} foreach @fields;

        if ($row->{'count'}) {
            $self->{_count} = $row->{'count'};
        }
    } else {
        croak "unknown row type";
    }

    return $self;
}

# given journalid, typeid, catid and itemid returns userids of all the reporters of this item
sub get_reporters {
    my ($class, %opts) = @_;

    croak "invalid params" unless $opts{journalid} && $opts{typeid};
    $opts{itemid} += 0;

    my $dbr = LJ::get_db_reader();
    my $rows = $dbr->selectcol_arrayref('SELECT reporterid FROM content_flag WHERE ' .
                                        'journalid=? AND typeid=? AND itemid=? AND catid=? ORDER BY instime DESC LIMIT 1000',
                                        undef, $opts{journalid}, $opts{typeid}, $opts{itemid}, $opts{catid});
    die $dbr->errstr if $dbr->err;

    my $users = LJ::load_userids(@$rows);

    return values %$users;
}

# returns a hash of catid => count
sub flag_count_by_category {
    my ($class, %opts) = @_;

    # this query is unpleasant, so memcache it
    my $countref = LJ::MemCache::get('ct_flag_cat_count');
    return %$countref if $countref;

    my $dbr = LJ::get_db_reader();
    my $rows = $dbr->selectall_hashref("SELECT catid, COUNT(*) as cat_count FROM content_flag " .
                                       "WHERE status = 'N' GROUP BY catid", 'catid');
    die $dbr->errstr if $dbr->err;

    my %count = map { $_, $rows->{$_}->{cat_count} } keys %$rows;

    LJ::MemCache::set('ct_flag_cat_count', \%count, 5);

    return %count;
}

######## instance methods

sub u { LJ::load_userid($_[0]->journalid) }
sub flagid { $_[0]->{flagid} }
sub status { $_[0]->{status} }
sub catid { $_[0]->{catid} }
sub modtime { $_[0]->{modtime} }
sub typeid { $_[0]->{typeid} }
sub itemid { $_[0]->{itemid} }
sub count { $_[0]->{_count} }
sub journalid { $_[0]->{journalid} }
sub reporter { LJ::load_userid($_[0]->{reporterid}) }

sub set_field {
    my ($self, $field, $val) = @_;
    my $dbh = LJ::get_db_writer() or die;

    my $modtime = time();

    $dbh->do("UPDATE content_flag SET $field = ?, modtime = UNIX_TIMESTAMP() WHERE flagid = ?", undef,
             $val, $self->flagid);
    die $dbh->errstr if $dbh->err;

    $self->{$field} = $val;
    $self->{modtime} = $modtime;

    return 1;
}

sub set_status {
    my ($self, $status) = @_;
    return $self->set_field('status', $status);
}

# returns flagged item (entry, comment, etc...)
sub item {
    my ($self, $status) = @_;

    my $typeid = $self->typeid;
    if ($typeid == LJ::ContentFlag::ENTRY) {
        return LJ::Entry->new($self->u, ditemid => $self->itemid);
    } elsif ($typeid == LJ::ContentFlag::COMMENT) {
        return LJ::Comment->new($self->u, dtalkid => $self->itemid);
    }

    return undef;
}

sub url {
    my $self = shift;

    if ($self->item) {
        return $self->item->url;
    } elsif ($self->typeid == LJ::ContentFlag::JOURNAL) {
        return $self->u->journal_base;
    } elsif ($self->typeid == LJ::ContentFlag::PROFILE) {
        return $self->u->profile_url('full' => 1);
    } else {
        return undef;
    }

}

sub summary {

}

sub close { $_[0]->set_status(LJ::ContentFlag::CLOSED) }

sub delete {
    my ($self) = @_;
    my $dbh = LJ::get_db_writer() or die;

    $dbh->do("DELETE FROM content_flag WHERE flagid = ?", undef, $self->flagid);
    die $dbh->errstr if $dbh->err;

    return 1;
}


sub move_to_abuse {
    my ($class, $action, @flags) = @_;

    return unless $action;
    return unless @flags;

    my %req;
    $req{reqtype}      = "email";
    $req{reqemail}     = $LJ::CONTENTFLAG_EMAIL;
    $req{no_autoreply} = 1;

    if ($action eq LJ::ContentFlag::ABUSE_WARN || $action eq LJ::ContentFlag::ABUSE_DELETE) {
        $req{spcatid} = $LJ::CONTENTFLAG_ABUSE;

    } elsif ($action eq LJ::ContentFlag::ABUSE_SUSPEND || $action eq LJ::ContentFlag::ABUSE_TERMINATE) {
        $req{spcatid} = $LJ::CONTENTFLAG_PRIORITY;

    }

    return unless $req{spcatid};

    # take one flag, should be representative of all
    my $flag = $flags[0];
    $req{subject} = "$action: " . $flag->u->user;

    $req{body}  = "Username: " . $flag->u->user . "\n";
    $req{body} .= "URL: " . $flag->url . "\n";
    $req{body} .= "\n" . "=" x 25 . "\n\n";

    foreach (@flags) {
        $req{body} .= "Reporter: " . $_->reporter->user;
        $req{body} .= " (" . $CAT_NAMES{$_->catid} . ")\n";
    }

    my @errors;
    # returns support request id
    return LJ::Support::file_request(\@errors, \%req);
}

1;
