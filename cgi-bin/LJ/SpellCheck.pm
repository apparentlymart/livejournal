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
use IPC::Run;

use vars qw($VERSION);
$VERSION = '1.0';

# Good spellcommand values:
#    ispell -a -h  (default)
#    /usr/local/bin/aspell pipe -H --sug-mode=fast --ignore-case

my @DEFAULT_COMMAND = qw/aspell -a -H --ignore-case --sug-mode=fast --encoding=utf-8/;

my $LANGUAGES = {
    'ru'    => 'ru',
    'en_lj' => 'en',    # lower case of 'en_LJ'
    'en_gb' => 'en_GB',
    'de'    => 'de',
};

sub new {
    my ($class, $args) = @_;
    my $self = {};
    bless $self, ref $class || $class;

    $self->{command} = $args->{spellcommand} || [ @DEFAULT_COMMAND ];
    $self->{color} = $args->{color} || "#FF0000";
    return $self;
}

sub run_aspell {
    my ($text_ref, $opts, $handler_misspelled, $handler_text) = @_;

    if (ref($handler_misspelled) ne 'CODE') {
        die "Invalid handler_misspelled parameter - need coderef";
    }

    $handler_text = undef unless defined $handler_text && ref($handler_text) eq 'CODE';

    $opts = {} unless defined($opts) && ref($opts) eq 'HASH';

    my $command = $opts->{command};
    if ($command) {
        if (ref($command) ne 'ARRAY') {
            die "Invalid parameter 'command' - need arrayref";
        }
    }
    else {
        $command = [ @DEFAULT_COMMAND ];
        if (my $language = $opts->{language}) {
            $language = $LANGUAGES->{lc($language)};
            return (0, 'unsupported_language') unless $language;

            push @$command, "--lang=$language";
        }
    }

    my @in_lines = split qr/[\r\n]+/, $$text_ref;
    my @out_lines;

    {
        my ($in, $out, $err);
        
        ## ! = turn terse mode on (don't write correct words to output)
        ## ^ = escape each line (i.e. each line is text, not control command for aspell)
        $in = "!\n" . join("\n", map { "^$_" } @in_lines);

        warn join(' ', @$command), "\n";

        IPC::Run::run($command, \$in, \$out, \$err, IPC::Run::timeout(10))
            or die "Can't run spellchecker: $? ($err)";

        @out_lines = split /\n/, $out;

        warn "Spellchecker warning: $err" 
            if $err;

        my $signature = shift @out_lines;
        die "Invalid spellchecker reply: $signature"
            unless $signature && $signature =~ /^@\(#\)/;
    }

    INPUT_LINE:
    foreach my $input_line (@in_lines) {
        my $text_pos = 0;
        ASPELL_LINE: 
        while (my $aspell_line = shift @out_lines) {
            my ($word, $offset, $suggestions_str);

            if (!$aspell_line) {
                next INPUT_LINE;
            }
            elsif ($aspell_line =~ /^& (\S+) \d+ (\d+): (.*)$/) {
                ($word, $offset, $suggestions_str) = ($1, $2, $3);
            }
            elsif ($aspell_line =~ /^\# (\S+) (\d+)/) {
                ($word, $offset, $suggestions_str) = ($1, $2, undef);
            }
            else {
                next ASPELL_LINE;
            }

            $offset--; # due to escaping each line by char '^'

            $handler_text->(substr($input_line, $text_pos, $offset - $text_pos)) if $handler_text && $text_pos < $offset;
            $handler_misspelled->($word, $suggestions_str);
            $text_pos = $offset + length($word);
        }

        $handler_text->(substr($input_line, $text_pos, length($input_line) - $text_pos) . "\n") if $handler_text && $text_pos < length($input_line);
    }
  
    return (1, 'ok');
}

sub check {
    my ($text_ref, $opts) = @_;

    $opts = {} unless defined $opts && ref($opts) eq 'HASH';
    my $limit = 0 + $opts->{limit};

    my %words;
    my $handler_misspelled = sub {
        my ($word, $suggestions_str) = @_;

        return unless $suggestions_str;
        return if exists $words{$word};

        my @suggestions = split qr/,\s*/, $suggestions_str;
        if ($limit && @suggestions > $limit) {
            @suggestions = @suggestions[0 .. $limit - 1];
        }
        $words{$word} = [ @suggestions ];
    };

    my ($result, $status) = run_aspell($text_ref, $opts, $handler_misspelled, undef);

    if ($result) {
        return {
            status   => 'ok',
            words    => \%words,
            language => $opts->{language},
        };
    }
    else {
        return {
            status   => 'status',
            language => $opts->{language},
        }
    }
}

# This function takes a block of text to spell-check and returns HTML 
# to show suggesting correction, if any.  If the return from this 
# function is empty, then there were no misspellings found.

sub check_html {
    my ($self, $text_ref) = @_;

    my $color = $self->{'color'};

    my ($output, $footnotes, %seen_mispelled_words);
    my $pos = 0;

    my $handler_misspelled = sub {
        my ($word, $suggestions_str) = @_;

        $output .= "<font color='$color'>" . LJ::ehtml($word) . "</font>";

        if ($suggestions_str && !$seen_mispelled_words{$word}++) {
            $footnotes .= 
                "<tr valign=top>" .
                    "<td align=right>" . 
                        "<font color='$color'>" . LJ::ehtml($word) . "</font>" . 
                    "</td>" .
                    "<td>" .
                        LJ::ehtml($suggestions_str) .
                    "</td>" .
                "</tr>\n";
        }
    };

    my $handler_text = sub {
        my $text = LJ::ehtml(shift);
        $text =~ s/[\r\n]+/<br>/g;
        $output .= $text;
    };

    my ($result, $status) = run_aspell($text_ref, {language => 'ru'}, $handler_misspelled, $handler_text);

    return '' unless $result;

    $output .= "<p><b>Suggestions:</b><table cellpadding=3 border=0>$footnotes</table>" if $footnotes;
    return $output;
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
