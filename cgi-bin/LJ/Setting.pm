package LJ::Setting;
use strict;
use warnings;

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
    LJ::errobj("SettingSave", 'map' => \%map)->throw;
}

package LJ::Error::SettingSave;

sub user_caused { 1 }
sub fields      { qw(map); }  # key -> english  (keys are LJ::Setting:: subclass-defined)

1;
