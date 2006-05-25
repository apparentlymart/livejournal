package LJ::Setting;
use strict;
use warnings;

sub tags { () }

sub pkgkey {
    my $class = shift;
    $class =~ s/::/__/g;
    return $class . "_";
}

sub errdiv {
    my (undef, $errs, $key) = @_;
    return "" unless $errs;
    my $err = $errs->{$key}   or return "";
    # TODO: red is temporary.  move to css.
    return "<div style='color: red' class='ljinlinesettingerror'>$err</div>";
}

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
