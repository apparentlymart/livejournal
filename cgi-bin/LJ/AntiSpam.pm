#
# LiveJournal AntiSpam Object
#
# Is a given entry or comment spam? Store the verdict and related data.
#

package LJ::AntiSpam;
use strict;
use Carp qw/ croak cluck /;

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
             $self->{posterid}, LJ::mysql_time($self->{eventtime}, 1),
             $self->{poster_ip}, $self->{email}, $self->{user_agent},
             $self->{uniq}, $self->{spam}, $self->{confidence} );
    die $dbh->errstr if $dbh->err;

    $self = $class->new( journalid => $self->{journalid},
                         itemid => $self->{itemid}, type => $self->{type} );
    return $self;
}

sub load_recent {
    my $class = shift;
    my $reviewed = shift || 0;

    my $hours = 3600 * 24; # 24 hours

    my $dbh = LJ::get_db_reader()
        or die "unable to contact global db slave to load antispam";

    my $sth;
    my $ago = LJ::mysql_time(time() - $hours, 1);
    my $sortby = "ORDER BY eventtime";

    # Retrieve all antispam
    if ($reviewed) {
        $sth = $dbh->prepare("SELECT * FROM antispam WHERE eventtime > ? $sortby");

    # Retrieve all anitspam not yet reviewed
    } else {
        $sth = $dbh->prepare("SELECT * FROM antispam WHERE eventtime > ? " .
                             "AND review IS NULL $sortby");
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

        $dbh->do("UPDATE antispam SET $key=? WHERE itemid=? AND type=?",
                 undef, $val, $self->{itemid}, $self->{type});
        die $dbh->errstr if $dbh->err;

        return $self->{$key} = $val;
    }

    # getter case
    $self->preload_rows unless $self->{_loaded_row};

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


sub column_list { return @cols }

1;
