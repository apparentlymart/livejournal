package LJ::TopEntries;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);

sub new {
    my $class = shift;
    my %opts = @_;

    my $journal = $opts{'journal'};

    my $self = {journal => $journal};

    $self->{'remote'} = $opts{'remote'} || LJ::get_remote();

    $self->{'timelimit'} = $opts{'timelimit'} || 24 * 3600;

    return bless $self, $class;
}

# key <---> hash. Key - a string with four numbers, hash - full info about post.
sub _key_from_hash {
    my $self = shift;
    my $h = shift;
    return "$h->{'timestamp'}:$h->{'journalid'}:$h->{'jitemid'}:$h->{'userpicid'}";
}

sub _hash_from_key {
    my $self = shift;
    my $key = shift;

    my ($timestamp, $journalid, $jitemid, $userpicid) = @$key;

    return undef unless $journalid && $jitemid && $userpicid;

    my $entry = LJ::Entry->new($journalid, jitemid => $jitemid);

    return undef unless $entry;

    my $poster = $entry->poster();
    my $journal = LJ::load_userid($journalid);

    return undef unless $poster && $journal;

    my $comment_ref = LJ::Talk::get_talk_data($journal, 'L', $jitemid);
    return undef unless ref $comment_ref;

    # Get userpic from entry
    my $userpic = LJ::Userpic->new($poster, $userpicid);

    return undef unless $userpic && $userpic->valid();

    return
        {
            posterid    => $poster->{'userid'},
            journalid   => $journalid,
            jitemid     => $jitemid,
            userpicid   => $userpicid,

            subj        => $entry->subject_text(),
            text        => LJ::html_trim_4gadgets($entry->event_text(), 50, $entry->url()),
            revtime     => $entry->prop('revtime'),
            url         => $entry->url(),
            time        => $entry->logtime_unix(),
            userpic     => $userpic->url(),
            poster      => $poster->ljuser_display(),
            timestamp   => $timestamp,

            comments    => scalar keys %$comment_ref,

            key         => "$journalid:$jitemid",
        };
}

# Clean list before store: remove old elements.
sub _clean_list {
    my $self = shift;
    my %opts = @_;

    my @list = sort {$b->{'timestamp'} <=> $a->{'timestamp'}} @{$self->{'featured_posts'}};

    return @list if $self->{'min_entries'} >= scalar @list; # We already has a minimum.

    # Remove old entries - stay at least 'min_entries' recent and all within 24h from now.
    my $time_edge = time() - $self->{'timelimit'};
    my $count = $self->{'min_entries'};
    @list = grep { ($count-- > 0) || ($time_edge - $_->{'timestamp'} < 0) } @list;

    return @list;
}

sub _sort_list {
    my $self = shift;
    my %opts = @_;
    my @list =
        sort {$b->{'timestamp'} <=> $a->{'timestamp'}}
            grep { $_ && !($_->{'revtime'} && $_->{'revtime'} > $_->{'timestamp'}) }  # Sanity check
                    @{$self->{'featured_posts'}};

    return @list if $opts{'raw'};

    # Remove old entries - stay at least 'min_entries' recent and all within 24h from now.
    my $time_edge = time() - 24 * 3600;
    my $count = $self->{'min_entries'};
    @list = grep { ($count-- > 0) || ($time_edge - $_->{'timestamp'} < 0) } @list;

    # Remove elements below 'max_entries'.
    $count = scalar @list - $self->{'max_entries'};

    return @list if $count <= 0;

    while ($count--) {
        splice @list, int(rand(scalar @list)), 1;
    }

    return @list;
}

# store all from blessed hash to journal property.
sub _store_featured_posts {
    my $self = shift;
    my %opts = @_;
 
    my $prop = $self->{'min_entries'} . ':' . $self->{'max_entries'} . ':0:0|' .
        join('|', map { $self->_key_from_hash($_) } $self->_clean_list(%opts));
    $prop =~ s/\|$//;

    my $journal = $self->{'journal'};
    $journal->set_prop('widget_top_entries', $prop);
}

# load all from property to blessed hash.
sub _load_featured_posts {
    my $self = shift;
    my %opts = @_;

    my $journal = $self->{'journal'};
    my $remote = $self->{'remote'};

    my $prop_val = $journal->prop('widget_top_entries');

    $prop_val = '3:5:0:0' unless $prop_val;

    my @entities = map { [ split /:/ ] } split(/\|/, $prop_val);

    my ($min_entries, $max_entries, undef, undef) = @{shift @entities};

    $self->{'min_entries'}      = $min_entries;
    $self->{'max_entries'}      = $max_entries;
    $self->{'featured_posts'}   = [ map { $self->_hash_from_key($_) } @entities ];

    return $self->_sort_list(%opts);
}

# geters/seters
sub get_featured_posts {
    my $self = shift;
    my %opts = @_;
    return $self->{'featured_posts'} ?
        $self->_sort_list(%opts) : $self->_load_featured_posts(%opts);
}

sub min_entries {
    my $self = shift;

    $self->_load_featured_posts() unless $self->{'min_entries'};
    if ($_[0]) {
        my $min_entries = shift;
        if ($self->{'min_entries'} != $min_entries) {
            $self->{'min_entries'} = $min_entries;
            $self->_store_featured_posts();
        }
    }

    return $self->{'min_entries'};
}

sub max_entries {
    my $self = shift;

    $self->_load_featured_posts() unless $self->{'max_entries'};
    if ($_[0]) {
        my $max_entries = shift;
        if ($self->{'max_entries'} != $max_entries) {
            $self->{'max_entries'} = $max_entries;
            $self->_store_featured_posts();
        }
    }

    return $self->{'max_entries'};
}

# Add/del entries.
sub add_entry {
    my $self = shift;
    my %opts = @_;

    my $entry = $opts{'entry'};
    return 'wrong entry' unless $entry;

    my $timestamp = time();

    my ($journalid, $jitemid, $poster, $userpic) =
        ($entry->journalid(), $entry->jitemid(), $entry->poster(), $entry->userpic());

    return 'wrong entry poster' unless $poster;

    my $userpicid   = ($userpic ? LJ::get_picid_from_keyword($poster, $userpic) :
            ($poster->{'defaultpicid'} || 0));

    $self->delete_entry(key => "$journalid:$jitemid");

    $self->get_featured_posts(raw => 1, %opts); # make sure we has all fresh data

    my $post = $self->_hash_from_key( [ $timestamp, $journalid, $jitemid, $userpicid ] );
    if ($post) {
        push @{$self->{'featured_posts'}}, $post;
        $self->_store_featured_posts(%opts);
        return '';
    }

    # all other error conditions checked before call _hash_from_key()
    return 'userpic missed or does not valid';
}

sub delete_entry {
    my $self = shift;
    my %opts = @_;

    return unless $opts{'key'} =~ /(\d+):(\d+)/;

    my ($journalid, $jitemid) = ($1, $2);
    return unless $journalid && $jitemid;

    @{$self->{'featured_posts'}} = grep {
            ! ( $_->{'journalid'} == $journalid && $_->{'jitemid'}   == $jitemid )
        } $self->get_featured_posts(raw => 1, %opts);

    $self->_store_featured_posts(%opts);
}

1;

