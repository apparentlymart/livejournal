#
# LiveJournal entry object.
#
# Just framing right now, not much to see here!
#

package LJ::Comment;

use strict;
use vars qw/ $AUTOLOAD /;
use Carp qw/ croak /;
use Class::Autouse qw(
                      LJ::Entry
                      );

# internal fields:
#
#    journalid:     journalid where the commend was
#                   posted,                          always present
#    jtalkid:       jtalkid identifying this comment
#                   within the journal_u,            always present
#
#    nodetype:      single-char nodetype identifier, loaded if _loaded_row
#    nodeid:        nodeid to which this comment
#                   applies (often an entry itemid), loaded if _loaded_row
#
#    parenttalkid   talkid of parent comment,        loaded if _loaded_row
#    posterid:      userid of posting user           lazily loaded at access
#    datepost_unix: unixtime from the 'datepost'     loaded if _loaded_row
#    state:         comment state identifier,        loaded if _loaded_row

#    props:   hashref of props,                    loaded if _loaded_props

#    _loaded_text:   loaded talktext2 row
#    _loaded_row:    loaded talk2 row
#    _loaded_props:  loaded props

# <LJFUNC>
# name: LJ::Comment::new
# class: comment
# des: Gets a comment given journal_u entry and jtalkid.
# args: uuserid, opts
# des-uobj: A user id or $u to load the comment for.
# des-opts: Hash of optional keypairs.
#           jtalkid => talkid journal itemid (no anum)
# returns: A new LJ::Comment object.  undef on failure.
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

    $self->{journalid} = LJ::want_userid($uuserid) or
        croak("invalid journalid parameter");

    $self->{jtalkid} = int(delete $opts{jtalkid});

    if (my $dtalkid = int(delete $opts{dtalkid})) {
        $self->{jtalkid} = $dtalkid >> 8;
    }

    croak("need to supply jtalkid") unless $self->{jtalkid};
    croak("unknown parameters: " . join(", ", keys %opts))
        if %opts;
    return $self;
}

# return LJ::User of journal comment is in
sub journal {
    my $self = shift;
    return LJ::load_userid($self->{journalid});
}

# return LJ::Entry of entry comment is in, or undef if it's not
# a nodetype of L
sub entry {
    my $self = shift;
    __PACKAGE__->preload_rows([ $self ]) unless $self->{_loaded_row};
    return undef unless $self->{nodetype} eq "L";
    return LJ::Entry->new($self->journal, jitemid => $self->{nodeid});
}

sub jtalkid {
    my $self = shift;
    return $self->{jtalkid};
}

sub parenttalkid {
    my $self = shift;
    __PACKAGE__->preload_rows([ $self ]) unless $self->{_loaded_row};
    return $self->{parenttalkid};
}

# returns a LJ::Comment object for the parent
sub parent {
    my $self = shift;
    my $ptalkid = $self->parenttalkid or return undef;

    return LJ::Comment->new($self->journal, jtalkid => $ptalkid);
}

# returns true if entry currently exists.  (it's possible for a given
# $u, to make a fake jitemid and that'd be a valid skeleton LJ::Entry
# object, even though that jitemid hasn't been created yet, or was
# previously deleted)
sub valid {
    my $self = shift;
    __PACKAGE__->preload_rows([ $self ]) unless $self->{_loaded_row};
    return $self->{_loaded_row};
}


# returns LJ::User object for the poster of this entry, or undef for anonymous
sub poster {
    my $self = shift;
    return LJ::load_userid($self->posterid);
}

sub posterid {
    my $self = shift;
    __PACKAGE__->preload_rows([ $self ]) unless $self->{_loaded_row};
    return $self->{posterid};
}


# class method:
sub preload_rows {
    my ($class, $obj_list) = @_;
    foreach my $obj (@$obj_list) {
        next if $obj->{_loaded_row};

        my $u = $obj->journal;
        my $row = LJ::Talk::get_talk2_row($u, $obj->{journalid}, $obj->jtalkid);
        next unless $row; # FIXME: die?

        for my $f (qw(nodetype nodeid parenttalkid posterid datepost state)) {
            $obj->{$f} = $row->{$f};
        }
        $obj->{_loaded_row} = 1;
    }
}

# class method:
sub preload_props {
    my ($class, $entlist) = @_;
    foreach my $en (@$entlist) {
        next if $en->{_loaded_props};
        $en->_load_props;
    }
}

# returns true if loaded, zero if not.
# also sets _loaded_text and subject and event.
sub _load_text {
    my $self = shift;
    return 1 if $self->{_loaded_text};

    my $ret = LJ::get_logtext2($self->{'u'}, $self->{'jitemid'});
    my $lt = $ret->{$self->{jitemid}};
    return 0 unless $lt;

    $self->{subject}      = $lt->[0];
    $self->{event}        = $lt->[1];

    if ($self->prop("unknown8bit")) {
        # save the old ones away, so we can get back at them if we really need to
        $self->{subject_orig}  = $self->{subject};
        $self->{event_orig}    = $self->{event};

        # FIXME: really convert all the props?  what if we binary-pack some in the future?
        LJ::item_toutf8($self->{u}, \$self->{'subject'}, \$self->{'event'}, $self->{props});
    }

    $self->{_loaded_text} = 1;
    return 1;
}

sub prop {
    my ($self, $prop) = @_;
    $self->_load_props unless $self->{_loaded_props};
    return $self->{props}{$prop};
}

sub props {
    my ($self, $prop) = @_;
    $self->_load_props unless $self->{_loaded_props};
    return $self->{props} || {};
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

# raw utf8 text, with no HTML cleaning
sub subject_raw {
    my $self = shift;
    $self->_load_text  unless $self->{_loaded_text};
    return $self->{subject};
}

# raw utf8 text, with no HTML cleaning
sub event_raw {
    my $self = shift;
    $self->_load_text unless $self->{_loaded_text};
    return $self->{event};
}

# raw text as user sent us, without transcoding while correcting for unknown8bit
sub event_orig {
    my $self = shift;
    $self->_load_text unless $self->{_loaded_text};
    return $self->{event_orig} || $self->{event};
}

sub subject_html
{
    my $self = shift;
    $self->_load_text unless $self->{_loaded_text};
    return LJ::ehtml($self->{subject});
}

1;
