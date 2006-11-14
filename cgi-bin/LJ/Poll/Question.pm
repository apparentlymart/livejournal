package LJ::Poll::Question;
use strict;
use Carp qw (croak);

sub new {
    my ($class, $poll, $pollqid) = @_;

    my $self = {
        poll    => $poll,
        pollqid => $pollqid,
    };

    bless $self, $class;
    return $self;
}

sub new_from_row {
    my ($class, $row) = @_;

    my $pollid = $row->{pollid};
    my $pollqid = $row->{pollqid};

    my $poll;
    $poll = LJ::Poll->new($pollid) if $pollid;

    my $question = __PACKAGE__->new($poll, $pollqid);
    $question->absorb_row($row);

    return $question;
}

sub absorb_row {
    my ($self, $row) = @_;

    # items is optional, used for caching
    $self->{$_} = $row->{$_} foreach qw (sortorder type opts qtext items);
    $self->{_loaded} = 1;
}

sub _load {
    my $self = shift;
    return if $self->{_loaded};

    croak "_load called on a LJ::Poll::Question object with no pollid"
        unless $self->pollid;
    croak "_load called on a LJ::Poll::Question object with no pollqid"
        unless $self->pollqid;

    my $dbr = LJ::get_db_reader();
    my $sth = $dbr->prepare('SELECT * FROM pollquestion WHERE pollid=? AND pollqid=?');
    $sth->execute($self->pollid, $self->pollqid);
    $self->absorb_row($sth->fetchrow_hashref);
}

# returns the question rendered
sub as_html {
    my $self = shift;
    my $ret = '';

    my $type = $self->type;
    my $opts = $self->opts;

    my $qtext = $self->qtext;
    if ($qtext) {
        LJ::Poll->_clean_poll(\$qtext);
          $ret .= "<p>$qtext</p>\n";
      }
    $ret .= "<div style='margin: 10px 0 10px 40px'>";

    # text questions
    if ($type eq 'text') {
        my ($size, $max) = split(m!/!, $opts);
        $ret .= LJ::html_text({ 'size' => $size, 'maxlength' => $max });

        # scale questions
    } elsif ($type eq 'scale') {
        my ($from, $to, $by) = split(m!/!, $opts);
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
        if ($type eq 'drop') {
            my @optlist = ('', '');
            foreach my $it ($self->items) {
                LJ::Poll->_clean_poll(\$it->{item});
                  push @optlist, ('', $it->{item});
              }
            $ret .= LJ::html_select({}, @optlist);

            # radio or checkbox
        } else {
            foreach my $it ($self->items) {
                LJ::Poll->_clean_poll(\$it->{item});
                  $ret .= LJ::html_check({ 'type' => $self->type }) . "$it->{item}<br />\n";
              }
        }
    }
    $ret .= "</div>";
    return $ret;
}

sub items {
    my $self = shift;

    return @{$self->{items}} if $self->{items};

    my $dbr = LJ::get_db_reader();
    my $sth = $dbr->prepare('SELECT * FROM pollitem WHERE pollid=? AND pollqid=?');
    $sth->execute($self->pollid, $self->pollqid);

    my @items;

    while (my $row = $sth->fetchrow_hashref) {
        my $item = {};
        $item->{$_} = $row->{$_} foreach qw(pollitid sortorder item);
        push @items, $item;
    }

    @items = sort { $a->{sortorder} <=> $b->{sortorder} } @items;

    $self->{items} = \@items;

    return @items;
}

# accessors
sub poll {
    my $self = shift;
    return $self->{poll};
}
sub pollid {
    my $self = shift;
    return $self->poll->pollid;
}
sub pollqid {
    my $self = shift;
    return $self->{pollqid};
}
sub sortorder {
    my $self = shift;
    $self->_load;
    return $self->{sortorder};
}
sub type {
    my $self = shift;
    $self->_load;
    return $self->{type};
}
sub opts {
    my $self = shift;
    $self->_load;
    return $self->{opts};
}
sub qtext {
    my $self = shift;
    $self->_load;
    return $self->{qtext};
}

1;
