package LJ::Directory::Search;
use strict;
use warnings;

use LJ::Directory::Results;
use LJ::Directory::Constraint;
use Gearman::Task;
use Gearman::Taskset;
use LJ::UserSearch;
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
    return $self->search_no_dispatch;
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
sub search_no_dispatch {
    my ($self) = @_;

    my @seth = $self->get_set_handles;
    LJ::UserSearch::init_new_search();
    foreach my $sh (@seth) {
        my $packsize = $sh->pack_size;
        LJ::UserSearch::isect_begin($packsize);
        $sh->load_pack_data(sub {
            my $pd = shift;
            LJ::UserSearch::isect_push($pd);
        });
        LJ::UserSearch::isect_end();
    }
    # arrayref of sorted uids
    my $uids = LJ::UserSearch::get_results();

    my $page = 1;
    # TODO: do paging.
    # trim down $uids
    my $pages = 20;

    my $res = LJ::Directory::Results->new(
                                          page_size => $self->page_size,
                                          pages     => $pages,
                                          page      => $page,
                                          userids   => $uids,
                                          );
    return $res;
}

# we want to return these in the smallest to largest sets.
sub get_set_handles {
    my $self = shift;
    my @seth;
    my $n = 0;
    my @todo;  # subrefs to fetch
    my $failed = 0;
    my $ts = Gearman::Taskset->new(LJ::gearman_client());

    foreach my $cs (sort { $a->cardinality <=> $b->cardinality } $self->constraints) {
        warn "getting set handle for $cs";

        my $sh = $cs->cached_sethandle;
        if ($sh) {
            $seth[$n] = $sh;
        } else {
            if (@LJ::GEARMAN_SERVERS) {
                my $index = $n;
                push @todo, sub {
                    my $constraint_str = $cs->serialize;
                    my $searcharg = Storable::nfreeze([\$constraint_str]);
                    $ts->add_task(Gearman::Task->new("directory_search_constraint",
                                                     \$searcharg,
                                                     {
                                                         on_complete => sub {
                                                             my $shstr = shift;
                                                             $seth[$index] = LJ::Directory::SetHandle->new_from_string($$shstr),
                                                         },
                                                         on_fail => sub {
                                                             $failed = 1;
                                                         },
                                                     }
                                                     ));
                };
            } else {
                $seth[$n] = $cs->sethandle;
            }
        }
        $n++;
    }

    $_->() foreach @todo;

    if ($failed) {
        die "boom";
    }

    $ts->wait;
    return @seth;
}

1;
