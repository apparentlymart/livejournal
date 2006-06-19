package LJ::Setting;
use strict;
use warnings;
use Carp qw(croak);

# ----------------------------------------------------------------------------

sub tags { () }

sub error_check {
    my ($class, $u, $args) = @_;
    my $val = $class->get_arg($args, "foo");
    #unless ($val =~ /blah/) {
    #   $class->errors("foo" => "Invalid foo");
    #}

    die "No 'error_check' configured for settings module '$class'\n";
}

sub as_html {
    my ($class, $u, $errmap) = @_;
    return "No 'as_html' implemented for $class.";
}

sub save {
    my ($class, $u, $postargs, @classes) = @_;
    if ($class ne __PACKAGE__) {
        die "No 'save' implemented for '$class'\n";
    } else {
        die "No classes given to save\n" unless @classes;
    }

    my %posted;  # class -> key -> value
    while (my ($k, $v) = each %$postargs) {
        next unless $k =~ /^LJ__Setting__([a-zA-Z0-9]+)_(\w+)$/;
        my $class = "LJ::Setting::$1";
        my $key = $2;
        $posted{$class}{$key} = $v;
    }

    foreach my $setclass (@classes) {
        my $args = $posted{$setclass} || {};
        $setclass->save($u, $args);
    }
}

# ----------------------------------------------------------------------------

# Don't override:

sub pkgkey {
    my $class = shift;
    $class =~ s/::/__/g;
    return $class . "_";
}

sub errdiv {
    my ($class, $errs, $key) = @_;
    return "" unless $errs;

    # $errs can be a hashref of { $class => LJ::Error::SettingSave::Foo } or a map of
    # { $errfield => $errtxt }.  this converts the former to latter.
    if (my $classerr = $errs->{$class}) {
        $errs = $classerr->field('map');
    }

    my $err = $errs->{$key}   or return "";
    # TODO: red is temporary.  move to css.
    return "<div style='color: red' class='ljinlinesettingerror'>$err</div>";
}


# don't override this.
sub errors {
    my ($class, %map) = @_;

    my $errclass = $class;
    $errclass =~ s/^LJ::Setting:://;
    $errclass = "LJ::Error::SettingSave::" . $errclass;
    eval "\@${errclass}::ISA = ('LJ::Error::SettingSave');";

    my $eo = eval { $errclass->new(map => \%map) };
    $eo->log;
    $eo->throw;
}

# gets a key out of the $args hash, which can be either \%POST or a class-specific one
sub get_arg {
    my ($class, $args, $which) = @_;
    my $key = $class->pkgkey;
    return $args->{"${key}$which"} || $args->{$which} || "";
}

# called like:
#   LJ::Setting->error_map($u, \%POST, @multiple_setting_classnames)
# or:
#   LJ::Setting::SpecificOption->error_map($u, \%POST)
# returns:
#   undef if no errors found,
#   LJ::SettingErrors object if any errors.
sub error_map {
    my ($class, $u, $post, @classes) = @_;
    if ($class ne __PACKAGE__) {
        croak("Can't call error_map on LJ::Setting subclass with \@classes set.") if @classes;
        @classes = ($class);
    }

    my %errors;
    foreach my $setclass (@classes) {
        my $okay = eval {
            $setclass->error_check($u, $post);
        };
        next if $okay;
        $errors{$setclass} = $@;
    }
    return undef unless %errors;
    return \%errors;
}

package LJ::Error::SettingSave;
use base 'LJ::Error';

sub user_caused { 1 }
sub fields      { qw(map); }  # key -> english  (keys are LJ::Setting:: subclass-defined)

sub as_string {
    my $self = shift;
    my $map   = $self->field('map');
    return join(", ", map { $_ . '=' . $map->{$_} } sort keys %$map);
}

1;
