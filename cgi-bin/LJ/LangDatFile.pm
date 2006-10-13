package LJ::LangDatFile;
use strict;
use warnings;
use Carp qw (croak);


sub new {
    my ($class, $filename) = @_;

    my $self = {
        # initialize
        file_name => $filename,
        values    => {},          # string -> value mapping
        meta      => {},          # string -> {metakey => metaval}
    };

    bless $self, $class;
    $self->parse;

    return $self;
}

sub parse {
    my $self = shift;
    my $file_name = $self->file_name;

    open my $datfile, $file_name
        or croak "Could not open file $file_name: $!";

    my $lnum = 0;
    my ($code, $text);
    while ( my $line = <$datfile> ) {
        $lnum++;
        my $del;
        my $action_line;

        if ($line =~ /^(\S+?)=(.*)/) {
            ($code, $text) = ($1, $2);
            $action_line = 1;
        } elsif ($line =~ /^\!\s*(\S+)/) {
            $del = $code;
            $action_line = 1;
        } elsif ($line =~ /^(\S+?)\<\<\s*$/) {
            ($code, $text) = ($1, "");
            while (<$datfile>) {
                $lnum++;
                last if $_ eq ".\n";
                s/^\.//;
                $text .= $_;
            }
            chomp $text;  # remove file new-line (we added it)
            $action_line = 1;
        } elsif ($line =~ /^[\#\;]/) {
            # comment line
            next;
        } elsif ($line =~ /\S/) {
            croak "$file_name:$lnum: Bogus format.";
        }

        if ($code =~ s/\|(.+)//) {
            $self->{meta}->{$code} ||= {};
            $self->{meta}->{$code}->{$1} = $text;
            next;
        }

        next unless $action_line;
        $self->{values}->{$code} = $text;
    }

    close $datfile;
}

sub file_name { $_[0]->{file_name} }

sub value {
    my ($self, $key) = @_;

    return $self->{values}->{$key};
}


1;
