#!/usr/bin/perl
#

package LJ::Lang;

my %day_short = ('EN' => [qw[Sun Mon Tue Wed Thu Fri Sat]],
                 'DE' => [qw[Son Mon Dien Mitt Don Frei Sam]],
                 );
my %day_long = ('EN' => [qw[Sunday Monday Tuesday Wednesday Thursday Friday Saturday]],
                'DE' => [qw[Sonntag Montag Dienstag Mittwoch Donnerstag Freitag Samstag]],
                'ES' => [("Domingo", "Lunes", "Martes", "Mi\xC3\xA9rcoles", "Viernes", "Jueves", "Sabado")],
                );
my %month_short = ('EN' => [qw[Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec]],
                   'DE' => [qw[Jan Feb Mar Apr Mai Jun Jul Aug Sep Okt Nov Dez]],
                   );
my %month_long = ('EN' => [qw[January February March April May June July August September October November December]],
                  'DE' => [("Januar", "Februar", "M\xC3\xA4rz", "April", "Mai", "Juni",
                            "Juli", "August", "September", "Oktober", "November", "Dezember")],
                  'ES' => [qw[Enero Febrero Marzo Abril Mayo Junio Julio Agosto Setiembre Octubre Noviembre Diciembre]],
                  );

sub enum_trans 
{
    my ($hash, $lang, $num) = @_;
    return "" unless defined $num;
    unless (defined $hash->{$lang}) { $lang = "EN"; }
    return $hash->{$lang}->[$num-1];
}

sub day_short   { return &enum_trans(\%day_short,   @_); }
sub day_long    { return &enum_trans(\%day_long,    @_); }
sub month_short { return &enum_trans(\%month_short, @_); }
sub month_long  { return &enum_trans(\%month_long,  @_); }

## ordinal suffix
sub day_ord 
{
    my ($lang, $day) = @_;
    if ($lang eq "DE") {
        
    }
    else
    {
        ### default to english
        
        # teens all end in 'th'
        if ($day =~ /1\d$/) { return "th"; }
        
        # otherwise endings in 1, 2, 3 are special
        if ($day % 10 == 1) { return "st"; }
        if ($day % 10 == 2) { return "nd"; }
        if ($day % 10 == 3) { return "rd"; }

        # everything else (0,4-9) end in "th"
        return "th";
    }
}

sub time_format
{
    my ($hours, $h, $m, $formatstring) = @_;

    if ($formatstring eq "short") {
        if ($hours == 12) {
            my $ret;
            my $ap = "a";
            if ($h == 0) { $ret .= "12"; }
            elsif ($h < 12) { $ret .= ($h+0); }
            elsif ($h == 12) { $ret .= ($h+0); $ap = "p"; }
            else { $ret .= ($h-12); $ap = "p"; }
            $ret .= sprintf(":%02d$ap", $m);
            return $ret;
        } elsif ($hours == 24) {
            return sprintf("%02d:%02d", $h, $m);
        }
    }
    return "";
}

1;
