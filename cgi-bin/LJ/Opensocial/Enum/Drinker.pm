# LJ/Opensocial/Enum/Drinker.pm - jop

package LJ::Opensocial::Enum::Drinker;

use strict;

our $HEAVILY = 1;
our $NO = 0;
our $OCCASIONALLY = 2;
our $QUIT = 3;
our $QUITTING = 4;
our $REGULARLY = 5;
our $SOCIALLY = 6;
our $YES = 7;

our @EXPORT_OK = qw ( $HEAVILY $NO $OCCASIONALLY $QUIT
                      $QUITTING $REGULARLY $SOCIALLY $YES
                    );
#####

sub lookup {
  my $p_tag = shift;
  return "HEAVILY" if $p_tag == $HEAVILY;
  return "NO" if $p_tag == $NO;
  return "OCCASIONALLY" if $p_tag == $OCCASIONALLY;
  return "QUIT" if $p_tag == $QUIT;
  return "QUITTING" if $p_tag == $QUITTING;
  return "REGULARLY" if $p_tag == $REGULARLY;
  return "SOCIALLY" if $p_tag == $SOCIALLY;
  return "YES" if $p_tag == $YES;
  return "UNDEFINED";
}

#####

1;

# End of file.
