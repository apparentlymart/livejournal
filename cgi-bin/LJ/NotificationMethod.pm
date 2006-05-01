package LJ::NotificationMethod;
use strict;
use Carp qw/ croak /;
use Class::Autouse qw (LJ::Typemap
                       LJ::NotificationMethod::Email
                       LJ::NotificationMethod::Queue);

# make sure all the config'd classes are mapped
if(@LJ::NOTIFY_TYPES) {
    my $tm = __PACKAGE__->typemap or die "Could not make typemap.";
    $tm->map_classes(@LJ::NOTIFY_TYPES);
}

# this mofo is basically just an interface
# Mischa's contribution:  "straight up"
sub new    { croak "can't instantiate base LJ::NotificationMethod" }
sub notify { croak "can't call notification on LJ::NotificationMethod base class" }
sub title  { croak "can't call title on LJ::NotificationMethod base class" }

sub can_digest { 0 }

# subclasses have to override
sub configured          { 0 }  # system-wide configuration
sub configured_for_user { my $u = shift; return 0; }

sub new_from_subscription {
    my ($class, $subscription) = @_;

    my $sub_class = $class->class($subscription->ntypeid)
        or return undef;

    return $sub_class->new_from_subscription($subscription);
}

# get the typemap for the notifytype classes (class/instance method)
sub typemap {
    return LJ::Typemap->new(
        table       => 'notifytypelist',
        classfield  => 'class',
        idfield     => 'ntypeid',
    );
}

# returns the class name, given an ntypid
sub class {
    my ($class, $typeid) = @_;
    my $tm = $class->typemap
        or return undef;

    return $tm->typeid_to_class($typeid);
}

# returns the notifytypeid for this site.
# don't override this in subclasses.
sub ntypeid {
    my ($class_self) = @_;
    my $class = ref $class_self ? ref $class_self : $class_self;

    my $tm = $class->typemap
        or return undef;

    return $tm->class_to_typeid($class);
}

# this returns a list of all possible notification method classes
# class method
sub all_classes {
    my $class = shift;
    croak "all_classes is a class method" unless $class;

    return grep {
        ! $LJ::DISABLED{$_} &&
        $_->configured
    } qw(
         LJ::NotificationMethod::Email
         LJ::NotificationMethod::SMS
         );
}

1;
