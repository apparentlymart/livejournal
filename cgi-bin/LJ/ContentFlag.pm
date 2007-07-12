use strict;
package LJ::ContentFlag;
use Carp qw (croak);

use constant {
    # status
    NEW             => 'N',
    ABUSE           => 'A',
    ABUSE_WARN      => 'W',
    ABUSE_DELETE    => 'D',
    ABUSE_SUSPEND   => 'S',
    ABUSE_TERMINATE => 'T',
    REPORTER_BANNED => 'B',
    PERM_OK         => 'O',
    CLOSED          => 'C',

    # category
    CHILD_PORN => 1,
    ILLEGAL_ACTIVITY => 2,
    ILLEGAL_CONTENT => 3,

    # type
    ENTRY   => 1,
    COMMENT => 2,
    JOURNAL => 3,
    PROFILE => 4,
};

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
    my $type = delete $opts{type};
    my $item = delete $opts{item};
    my $itemid = delete $opts{itemid} || croak 'itemid required when passing type' if defined $type;
    my $reporter = (delete $opts{reporter} || LJ::get_remote()) or croak 'no reporter';
    my $cat = delete $opts{cat} or croak 'no category';

    croak "need item or type" unless $item || $type;
    croak "need journal" unless $journal;

    croak "unknown options: " . join(', ', keys %opts) if %opts;

    # if $item passed, get itemid and type from it
    if ($item) {
        if ($item->isa("LJ::Entry")) {
            $itemid = $item->jitemid;
            $type = ENTRY;
        } else {
            croak "unknown item type: $item";
        }
    }

    my $uniq = LJ::is_web_context() ? Apache->request->notes('uniq') : '';

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

    my $dbh = LJ::get_db_reader() or die "could not get db writer";
    my @params = keys %flag;
    my $bind = LJ::bindstr(@params);
    $dbh->do("INSERT INTO content_flag (" . join(',', @params) . ") VALUES ($bind)",
             undef, map { $flag{$_} } @params);
    die $dbh->errstr if $dbh->err;

    my $flagid = $dbh->{mysql_insertid};
    die "did not get an insertid" unless defined $flagid;

    $flag{flagid} = $flagid;
    return $class->absorb_row(\%flag);
}
# alias flag() to create()
*flag = \&create;

*load_by_flagid = \&load_by_id;
sub load_by_id {
    my ($class, $flagid, %opts) = @_;
    return $class->load(flagid => $flagid+0, %opts);
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

# given a flag, find other flags that have the same journalid, typeid, itemid
sub find_similar_flags {
    my ($self) = @_;
    return $self->load(
                       journalid => $self->journalid,
                       itemid => $self->itemid,
                       typeid => $self->typeid,
                       group => 1,
                       );
}

# load rows from DB
# if $opts{lock}, this will lock the result set for a while so that
# other people won't get the same set of flags to work on
sub load {
    my ($class, %opts) = @_;

    my $instime = $opts{from};

    # default to showing everything in the past month
    $instime = time() - 86400*30 unless defined $instime;
    $opts{instime} ||= $instime;

    my $catid = $opts{catid};
    my $status = $opts{status};
    my $flagid = $opts{flagid};

    my $sort = $opts{sort};

    my $fields = join(',', @fields);

    my $dbr = LJ::get_db_reader() or die "Could not get db reader";

    my @vals = ();
    my $constraints = "";

    # add other constraints
    foreach my $c (qw( catid status typeid flagid modtime instime journalid reporterid )) {
        my $val = delete $opts{$c} or next;

        my $cmp = '=';

        # use > for selecting by time, = for everything else
        if ($c eq 'modtime' || $c eq 'instime') {
            $cmp = '>';
        }
          
        # build sql
        $constraints .= $constraints ? " AND $c $cmp ?" : "$c $cmp ?";
        push @vals, $val;
    }

    croak "no constraints specified" unless $constraints;

    my @locked;

    if ($opts{lock}) {
        my $lockedref = LJ::MemCache::get($class->memcache_key);
        my @locked = $lockedref ? @$lockedref : ();

        if (@locked) {
            my $lockedbind = LJ::bindstr(@locked);
            $constraints .= "AND flagid NOT IN ($lockedbind)";
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

    my $sql = "SELECT $fields FROM content_flag WHERE $constraints $groupby ORDER BY $sort DESC LIMIT 1000";

    my $rows = $dbr->selectall_arrayref($sql, undef, @vals);
    die $dbr->errstr if $dbr->err;

    if ($opts{lock}) {
        # lock flagids for a few minutes
        my @flagids = keys %$rows;
        push @locked, @flagids;
        LJ::MemCache::set($class->memcache_key, \@locked, 30);
    }

    return map { $class->absorb_row($_) } @$rows;
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


######## instance methods

sub u { LJ::load_userid($_[0]->{journalid}) }
sub flagid { $_[0]->{flagid} }
sub status { $_[0]->{status} }
sub catid { $_[0]->{catid} }
sub modtime { $_[0]->{modtime} }
sub typeid { $_[0]->{typeid} }
sub itemid { $_[0]->{itemid} }
sub count { $_[0]->{_count} }

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
        return LJ::Entry->new($self->u, jitemid => $self->itemid);
    } elsif ($typeid == LJ::ContentFlag::COMMENT) {
        return LJ::Comment->new($self->u, dtalkid => $self->itemid);
    }

    return undef;
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

1;
