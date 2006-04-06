package LJ::Event;
use strict;
use Carp qw(croak);

sub new {
    my ($class, $u, @args) = @_;
    croak("too many args") if @args > 2;
    croak("args must be numeric") if grep { /\D/ } @args;

    return bless {
        u => $u,
        args => \@args,
    }, $class;
}

# returns the eventtypeid for this site.
# don't override this in subclasses.
sub etypeid {
    my ($class_self) = @_;
    my $class = ref $class_self ? ref $class_self : $class_self;

    # TODO: cache this
    my $dbh = LJ::get_db_writer();
    my $etypeid = $dbh->selectrow_array("SELECT eventtypeid FROM eventtypelist WHERE class=?",
                                        undef, $class);
    return $etypeid if $etypeid;

}

1;
