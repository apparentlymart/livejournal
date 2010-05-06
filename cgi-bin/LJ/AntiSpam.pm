#
# LiveJournal AntiSpam Object
#
# Is a given entry or comment spam? Store the verdict and related data.
#

package LJ::AntiSpam;
use strict;
use Net::Akismet::TPAS;
use Carp qw/ croak cluck /;
use LJ::TimeUtil;

my @cols = qw( itemid type posterid journalid eventtime poster_ip email user_agent uniq spam confidence );
my @extra_cols = qw( review );

# Constructor
sub new {
    my $class = shift;

    my $n_arg   = scalar @_;
    croak("wrong number of arguments")
        unless $n_arg && ($n_arg % 2 == 0);

    my %opts = @_;

    my $self = bless {
        # arguments
        journalid  => delete $opts{journalid},
        itemid     => delete $opts{itemid},
        type       => delete $opts{type},
    };

    croak("need to supply journalid") unless defined $self->{journalid};
    croak("need to supply itemid") unless defined $self->{itemid};
    croak("need to supply type") unless defined $self->{type};

    croak("unknown parameters: " . join(", ", keys %opts))
        if %opts;

    return $self;
}

# Create a new AntiSpam object
sub create {
    my $class = shift;
    my $self  = bless {};

    my %opts = @_;
    foreach my $f (@cols) {
        croak("need to supply $f") unless exists $opts{$f};
        $self->{$f} = delete $opts{$f};
    }

    croak("unknown parameters: " . join(", ", keys %opts))
        if %opts;

    my $dbh = LJ::get_db_writer()
        or die "unable to contact global db master to create antispam entry";

    $dbh->do("REPLACE INTO antispam VALUES (?,?,?,?,?,?,?,?,?,?,?,NULL)",
             undef, $self->{journalid}, $self->{itemid}, $self->{type},
             $self->{posterid}, LJ::TimeUtil->mysql_time($self->{eventtime}, 1),
             $self->{poster_ip}, $self->{email}, $self->{user_agent},
             $self->{uniq}, $self->{spam}, $self->{confidence} );
    die $dbh->errstr if $dbh->err;

    $self = $class->new( journalid => $self->{journalid},
                         itemid => $self->{itemid}, type => $self->{type} );
    return $self;
}

sub load_recent {
    my $class = shift;
    my %opts = @_;
    my $type = (exists $opts{type}) ? $opts{type} : 'E'; # default to entries
    my $reviewed = $opts{reviewed} || 0;
    my $limit = $opts{limit} || 50;

    my $hours = 3600 * 24; # 24 hours

    my $dbh = LJ::get_db_reader()
        or die "unable to contact global db slave to load antispam";

    my $sth;
    my $ago = LJ::TimeUtil->mysql_time(time() - $hours, 1);
    my $xsql = "AND type='$type' ";
    $xsql .= "ORDER BY eventtime DESC";
    $xsql .= " LIMIT $limit";

    # Retrieve all antispam
    if ($reviewed) {
        $sth = $dbh->prepare("SELECT * FROM antispam WHERE eventtime > ? $xsql");

    # Retrieve all anitspam not yet reviewed
    } else {
        $sth = $dbh->prepare("SELECT * FROM antispam WHERE eventtime > ? " .
                             "AND review IS NULL $xsql");
    }
    $sth->execute($ago);
    die $dbh->errstr if $dbh->err;

    my @antispams;
    while (my $row = $sth->fetchrow_hashref) {
        my $as = $class->new( journalid => $row->{journalid},
                              itemid => $row->{itemid},
                              type => $row->{type} );
        $as->absorb_row($row);

        push @antispams, $as;
    }

    return @antispams;
}

sub load_row {
    my $self = shift;
    return 1 if $self->{_loaded_row};

    my $dbh = LJ::get_db_reader()
        or die "unable to contact global db slave to load antispam";

    my $sth = $dbh->prepare("SELECT * FROM antispam WHERE journalid=? AND " .
                            "itemid=? AND type=?");
    $sth->execute($self->{journalid}, $self->{itemid}, $self->{type});
    die $dbh->errstr if $dbh->err;

    $self->absorb_row($sth->fetchrow_hashref);
}

sub absorb_row {
    my ($self, $row) = @_;

    $self->{$_} = $row->{$_} foreach @cols;
    $self->{$_} = $row->{$_} foreach @extra_cols;

    $self->{_loaded_row} = 1;

    return 1;
}

sub _get_set {
    my $self = shift;
    my $key  = shift;

    if (@_) { # setter case
        my $val = shift;

        my $dbh = LJ::get_db_writer()
            or die "unable to contact global db master to load category";

        $dbh->do("UPDATE antispam SET $key=? WHERE journalid=? AND itemid=? " .
                 "AND type=?", undef, $val, $self->{journalid},
                 $self->{itemid}, $self->{type});
        die $dbh->errstr if $dbh->err;

        return $self->{$key} = $val;
    }

    # getter case
    $self->load_row unless $self->{_loaded_row};

    return $self->{$key};
}

sub journalid   { shift->_get_set('journalid')  }
sub itemid      { shift->_get_set('itemid')     }
sub type        { shift->_get_set('type')       }
sub posterid    { shift->_get_set('posterid')   }
sub eventtime   { shift->_get_set('eventtime')  }
sub poster_ip   { shift->_get_set('poster_ip')  }
sub email       { shift->_get_set('email')      }
sub user_agent  { shift->_get_set('user_agent') }
sub uniq        { shift->_get_set('uniq')       }
sub spam        { shift->_get_set('spam')       }
sub confidence  { shift->_get_set('confidence') }
sub review      { shift->_get_set('review')     }
sub set_review  { shift->_get_set('review' => $_[0]) }


sub column_list { return @cols }

#############################
# Comment/Entry related subs
#

sub is_entry {
    my $self = shift;

    return $self->type eq 'E' ? 1 : 0;
}

sub is_comment {
    my $self = shift;

    return $self->type eq 'C' ? 1 : 0;
}

# This can be an Entry or Comment object
sub _post {
    my $self = shift;

    return $self->{_post} if $self->{_post};

    if ($self->is_entry) {
        $self->{_post} = LJ::Entry->new($self->journalid, jitemid => $self->itemid);
    } elsif ($self->is_comment) {
        $self->{_post} = LJ::Comment->new($self->journalid, jtalkid => $self->itemid);
    }

    return $self->{_post};
}

sub valid_post {
    my $self = shift;

    # valid is a method common to Entry and Comment objects
    return $self->_post->valid;
}

sub url {
    my $self = shift;

    # url is a method common to Entry and Comment objects
    return $self->_post->url;
}

sub subject {
    my $self = shift;

    # subject_html is a method common to Entry and Comment objects
    return $self->_post->subject_html;
}

sub body {
    my $self = shift;

    if ($self->is_entry) {
        return $self->_post->event_html;
    } elsif ($self->is_comment) {
        return $self->_post->body_html;
    }
}

sub post_time {
    my $self = shift;

    if ($self->is_entry) {
        return $self->_post->eventtime_mysql;
    } elsif ($self->is_comment) {
        return LJ::TimeUtil->mysql_time($self->_post->unixtime);
    }
}

#
#######################################

################################
# Review subs

# Set review as 'T' for True.
sub mark_reviewed {
    my $class = shift;
    my @recs = @_;

    foreach my $rec (@recs) {
        my $as = LJ::AntiSpam->new(journalid => $rec->{journalid},
                                   itemid => $rec->{itemid},
                                   type => $rec->{type} );
        $as->set_review('T');
    }
}

sub mark_false_neg {
    my $class = shift;
    return $class->_mark_false_do("false_neg", @_);
}

sub mark_false_pos {
    my $class = shift;
    return $class->_mark_false_do("false_pos", @_);
}

sub _mark_false_do {
    my $class = shift;
    my $sign = shift;
    my @recs = @_;

    foreach my $rec (@recs) {
        my $as = LJ::AntiSpam->new(journalid => $rec->{journalid},
                                   itemid => $rec->{itemid},
                                   type => $rec->{type} );
        my $ju = LJ::load_userid($as->journalid);
        my $poster = LJ::load_userid($as->posterid);
        my $content;

        if ($as->type eq 'E') {
            my $entry = LJ::Entry->new($ju, jitemid => $as->itemid);
            $content = $entry->event_html;
        } elsif ($as->type eq 'C') {
            my $comment = LJ::Comment->new($ju->userid, jtalkid => $as->itemid);
            $content = $comment->body_html;
        }

        my $tpas = LJ::AntiSpam->tpas($as->posterid, LJ::journal_base($ju) . "/");

        if ($sign eq 'false_neg' && !$as->spam) {
            my $feedback = $tpas->spam(
                            USER_IP                 => $as->poster_ip,
                            COMMENT_USER_AGENT      => $as->user_agent,
                            COMMENT_CONTENT         => $content,
                            COMMENT_AUTHOR          => $poster->user,
                            COMMENT_AUTHOR_EMAIL    => $as->email,
                           ) or die "Failed to get response from antispam server.\n";
        } elsif ($sign eq 'false_pos' && $as->spam) {
            my $feedback = $tpas->ham(
                            USER_IP                 => $as->poster_ip,
                            COMMENT_USER_AGENT      => $as->user_agent,
                            COMMENT_CONTENT         => $content,
                            COMMENT_AUTHOR          => $poster->user,
                            COMMENT_AUTHOR_EMAIL    => $as->email,
                           ) or die "Failed to get response from antispam server.\n";
        }
        $as->set_review('F');
    }
}

#
###############################

sub tpas {
    my $class = shift;
    my $uid = shift;
    my $url = shift;

    my $tpas = Net::Akismet::TPAS->new(
                KEY => $LJ::TPAS_KEY->($uid),
                URL => $url,
                SERVER => $LJ::TPAS_SERVER,
                STRICT => 0,
                VERIFY_KEY => 0,
               ) or die "Key verification failure!";

    return $tpas;
}

1;
