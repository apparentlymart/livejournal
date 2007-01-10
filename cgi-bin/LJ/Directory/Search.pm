package LJ::Directory::Search;
use strict;
use warnings;
use LJ::Directory::Results;
use LJ::Directory::Constraint;
use Storable;
use Carp qw(croak);

sub new {
    my ($pkg, %args) = @_;
    my $self = bless {}, $pkg;
    $self->{page_size} = int(delete $args{page_size} || 100);
    $self->{page_size} = 25  if $self->{page_size} < 25;
    $self->{page_size} = 200 if $self->{page_size} > 200;

    $self->{page} = int(delete $args{page} || 1);
    $self->{page} = 1  if $self->{page} < 1;

    $self->{constraints} = delete $args{constraints} || [];
    croak "constraints not a hashref" unless ref $self->{constraints} eq "ARRAY";
    croak "Unknown parameters" if %args;
    return $self;
}

sub page_size { $_[0]->{page_size} }
sub page { $_[0]->{page} }
sub constraints { @{$_[0]->{constraints}} }

sub add_constraint {
    my ($self, $con) = @_;
    push @{$self->{constraints}}, $con;
}

# do a synchronous search, blocking until finished
# returns LJ::Directory::Results object of the search results
# %opts gets passed through to gearman
sub search {
    my ($self, %opts) = @_;

    return LJ::Directory::Results->empty_set unless @{$self->{constraints}};

    if (@LJ::GEARMAN_SERVERS && (my $gc = LJ::gearman_client())) {
        # do with gearman, if avail
        my $resref  = $gc->do_task('directory_search', Storable::nfreeze($self), {%opts});
        my $results = Storable::thaw($$resref);
        return $results;
    }

    # no gearman, just do in web context
    return $self->_search;
}

# do an asynchronous search with gearman
# returns a gearman task handle of the task doing the search
# %opts gets passed through to gearman
sub search_background {
    my ($self, %opts) = @_;

    return undef unless @{$self->{constraints}};

    # return undef if no gearman
    my $gc = LJ::gearman_client();
    return undef unless @LJ::GEARMAN_SERVERS && $gc;

    # fire off gearman task in background
    return $gc->dispatch_background('directory_search', Storable::nfreeze($self), {%opts});
}

# this does the actual search, should be called from gearman worker
sub _search {
    my ($self) = @_;
    my $res = LJ::Directory::Results->new(
                                          page_size => $self->page_size,
                                          pages     => 20,
                                          page      => $self->page,
                                          userids   => [ map { 1 } 1..$self->page_size ],
                                          );
    return $res;
}

1;
