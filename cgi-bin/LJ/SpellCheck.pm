#!/usr/bin/perl
#
# LJ::SpellCheck class
# See perldoc documentation at the end of this file.
#
# -------------------------------------------------------------------------
#
# This package is released under the LGPL (GNU Library General Public License)
#
# A copy of the license has been included with the software as LGPL.txt.  
# If not, the license is available at:
#      http://www.gnu.org/copyleft/library.txt
#
# -------------------------------------------------------------------------


package LJ::SpellCheck;

use strict;
use IPC::Run qw/run timeout/;

use vars qw($VERSION);
$VERSION = '1.0';

# Good spellcommand values:
#    ispell -a -h  (default)
#    /usr/local/bin/aspell pipe -H --sug-mode=fast --ignore-case

sub new {
    my ($class, $args) = @_;
    my $self = {};
    bless $self, ref $class || $class;

    $self->{'command'} = $args->{'spellcommand'} || [qw/ispell -a -h/];
    $self->{'color'} = $args->{'color'} || "#FF0000";
    return $self;
}

# This function takes a block of text to spell-check and returns HTML 
# to show suggesting correction, if any.  If the return from this 
# function is empty, then there were no misspellings found.

sub check_html {
    my $self = shift;
    my $journal = shift;
 
    my @in_lines    = split /[\r\n]+/, $$journal;
    my @out_lines; 
    my $color = $self->{'color'};

    {
        my ($in, $out, $err);
        
        ## ! = turn terse mode on (don't write correct words to output)
        ## ^ = escape each line (i.e. each line is text, not control command for aspell)
        $in = "!\n" . join("\n", map { "^$_" } @in_lines);

        run($self->{'command'}, \$in, \$out, \$err, timeout(10))
            or die "Can't run spellchecker: $?";
        @out_lines = split /\n/, $out;
        
        warn "Spellchecker warning: $err" 
            if $err;
        
        my $signature = shift @out_lines;
        die "Invalid spellchecker reply: $signature"
            unless $signature && $signature =~ /^@\(#\)/;
    }

    my ($output, $footnotes, $has_errors, %seen_mispelled_words);

    INPUT_LINE:
    foreach my $input_line (@in_lines) {
        my $pos = 0;
        ASPELL_LINE: 
        while (my $aspell_line = shift @out_lines) {
            my ($word, $offset, $suggestions_list);
            if (!$aspell_line) {
                next INPUT_LINE;
            } elsif ($aspell_line =~ /^& (\S+) \d+ (\d+): (.*)$/) {
                ($word, $offset, $suggestions_list) = ($1, $2, $3);
            } elsif ($aspell_line =~ /^\# (\S+) (\d+)/) {
                my ($word, $offset, $suggestions_list) = ($1, $2, undef);
            } else {
                next ASPELL_LINE;
            }

            $output .= LJ::ehtml(substr($input_line, $pos, $offset-$pos-1));
            $output .= "<font color='$color'>".LJ::ehtml($word)."</font>";

            if ($suggestions_list && !$seen_mispelled_words{$word}++) {
                $footnotes .= 
                    "<tr valign=top><td align=right><font color='$color'>".LJ::ehtml($word).
                    "</font></td><td>".LJ::ehtml($suggestions_list)."</td></tr>\n";
            }
            $pos = $offset + length($word) - 1;
            $has_errors++;
        }
        $output .= LJ::ehtml(substr($input_line, $pos, length($input_line)-$pos)) . "<br>\n";
    }
   
    return ($has_errors) 
            ? "$output<p><b>Suggestions:</b><table cellpadding=3 border=0>$footnotes</table>"
            : "";
}

1;
__END__

=head1 NAME

LJ::SpellCheck - let users check spelling on web pages

=head1 SYNOPSIS

  use LJ::SpellCheck;
  my $s = new LJ::SpellCheck { 'spellcommand' => [ qw/ispell -a -h/ ],
                               'color' => '#ff0000',
                           };

  my $text = "Lets mispell thigns!";
  my $correction = $s->check_html(\$text);
  if ($correction) {
      print $correction;  # contains a ton of HTML
  } else {
      print "No spelling problems.";
  }

=head1 DESCRIPTION

The object constructor takes a 'spellcommand' argument.  This has to be some ispell compatible program, like aspell.  Optionally, it also takes a color to highlight mispelled words.

The only method on the object is check_html, which takes a reference to the text to check and returns a bunch of HTML highlighting misspellings and showing suggestions.  If it returns nothing, then there no misspellings found.

=head1 BUGS

Sometimes the opened spell process hangs and eats up tons of CPU.  Fixed now, though... I think.

check_html returns HTML we like.  You may not.  :)

=head1 AUTHORS

Evan Martin, evan@livejournal.com
Brad Fitzpatrick, bradfitz@livejournal.com

=cut
