#
# LiveJournal entry object.
#
# Just framing right now, not much to see here!
#

package LJ::Entry;
use strict;

use vars qw/ $AUTOLOAD /;

# <LJFUNC>
# name: LJ::Entry::new
# class: entry
# des: Gets a journal entry.
# args: uobj, itemid, anum?
# des-uobj: A user id or object to load the entry for.
# des-itemid: The journal id to load.
# des-opts: Hashref of optional keypairs.
#           'anum' - the id passed was an ditemid, use the anum
#                    to create a proper jitemid.
# returns: A new LJ::Entry object.  undef on failure.
# </LJFUNC>
sub new
{
    my $self = {};
    bless $self, shift();
    return $self->_init(@_);
}

sub _init
{
    my ( $self, $u, $id, $opts ) = @_;

    $u = LJ::load_userid( $u ) unless ref $u;
    return unless ref $u && $id+0;

    # 'id' was a ditemid.  switch it to a jitemid.
    $id = $id >> 8
        if ref $opts && defined $opts->{'anum'};

    # some parts of the codebase refer to a jitemid as an itemid.
    # include both to avoid breakage.
    $self->{'jitemid'} = $self->{'itemid'} = $id;

    $self->{'u'}       = $u;
    $self->{'_loaded'}  = 0;

    return $self;
}

sub load
{
    my $self = shift;

    # row data
    my $log2row = LJ::get_log2_row( $self->{'u'}, $self->{'jitemid'} );
    return unless scalar keys %$log2row;
    map { $self->{$_} = $log2row->{$_} } keys %$log2row;

    # entry data
    my $logtext2 = LJ::get_logtext2( $self->{'u'}, $self->{'jitemid'} );
    ( $self->{'subject'}, $self->{'event'} ) = @{ $logtext2->{ $self->{'jitemid'} } };
    chomp $self->{'subject'};

    # props
    my $props = {};
    LJ::load_log_props2( $self->{'u'}, [ $self->{'jitemid'} ], $props );
    $self->{'props'} = $props->{ $self->{'jitemid'} };

    $self->{'_loaded'} = 1;
    return $self;
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
    $self->load() unless $self->{'_loaded'};

    LJ::load_user_props( $self->{'u'}, 'opt_synlevel' );
    $self->{'u'}->{'opt_synlevel'} ||= 'full';

    my $ctime = LJ::mysqldate_to_time($self->{'logtime'}, 1);
    $self->{'modtime'} = $self->{'props'}->{'revtime'} || $ctime;

    my $item = {
        'itemid'     => $self->{'itemid'},
        'ditemid'    => $self->{'itemid'}*256 + $self->{'anum'},
        'eventtime'  => LJ::alldatepart_s2($self->{'eventtime'}),
        'modtime'    => $self->{'props'}->{'revtime'} || $ctime,
        'subject'    => $self->{'subject'},
        'event'      => $self->{'event'},
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

sub clean_subject
{
    my $self = shift;
    $self->load() unless $self->{'_loaded'};

    my $subject = $self->{'subject'};
    LJ::CleanHTML::clean_subject( \$subject ) if $subject;
    return $subject;
}

sub clean_event
{
    my $self = shift;
    $self->load() unless $self->{'_loaded'};

    my $event = $self->{'event'};
    LJ::CleanHTML::clean_event( \$event );
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
        } else { 
            $self->load() unless $self->{'_loaded'};
        }

        return $self->{$data};
    };

    goto &$AUTOLOAD;
}

sub DESTROY {}

1;
