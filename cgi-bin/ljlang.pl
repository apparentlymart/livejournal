#!/usr/bin/perl
#

use strict;
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

#### ml_ stuff:
my $LS_CACHED = 0;
my %DM_ID = ();     # id -> { type, args, dmid, langs => { => 1, => 0, => 1 } }
my %DM_UNIQ = ();   # "$type/$args" => ^^^
my %LN_ID = ();     # id -> { ..., ..., 'children' => [ $ids, .. ] }
my %LN_CODE = ();   # $code -> ^^^^

sub get_dmid
{
    my $dmcode = shift;
    load_lang_struct() unless $LS_CACHED;
    my $d = $DM_UNIQ{$dmcode};
    return $d ? $d->{'dmid'} : undef;
}

sub load_lang_struct
{
    return 1 if $LS_CACHED;
    my $dbr = LJ::get_dbh("slave", "master");
    return 0 unless $dbr;
    my $sth;

    $sth = $dbr->prepare("SELECT dmid, type, args FROM ml_domains");
    $sth->execute;
    while (my ($dmid, $type, $args) = $sth->fetchrow_array) {
        $DM_UNIQ{"$type/$args"} = $DM_ID{$dmid} = { 
            'type' => $type, 'args' => $args, 'dmid' => $dmid,
        };
    }

    $sth = $dbr->prepare("SELECT lnid, lncode, lnname, parenttype, parentlnid FROM ml_langs");
    $sth->execute;
    while (my ($id, $code, $name, $ptype, $pid) = $sth->fetchrow_array) {
        $LN_ID{$id} = $LN_CODE{$code} = {
            'lnid' => $id,
            'lncode' => $code,
            'lnname' => $name,
            'parenttype' => $ptype,
            'parentlnid' => $pid,
        };
    }
    foreach (values %LN_CODE) {
        next unless $_->{'parentlnid'};
        push @{$LN_ID{$_->{'parentlnid'}}->{'children'}}, $_->{'lnid'};
    }
    
    $sth = $dbr->prepare("SELECT lnid, dmid, dmmaster FROM ml_langdomains");
    $sth->execute;
    while (my ($lnid, $dmid, $dmmaster) = $sth->fetchrow_array) {
        $DM_ID{$dmid}->{'langs'}->{$dmid} = $dmmaster;
    }
    
    $LS_CACHED = 1;
}

sub get_itemid
{
    my ($dbarg, $dmid, $itcode, $create) = @_;
    load_lang_struct() unless $LS_CACHED;

    my $dbs = LJ::make_dbs_from_arg($dbarg);
    my $dbh = $dbs->{'dbh'};
    my $dbr = $dbs->{'reader'};

    $dmid += 0;
    my $qcode = $dbh->quote($itcode);
    my $itid = $dbr->selectrow_array("SELECT itid FROM ml_items WHERE dmid=$dmid AND itcode=$qcode");
    return $itid if defined $itid;
    $dbh->do("INSERT INTO ml_items (dmid, itid, itcode) VALUES ($dmid, NULL, $qcode)");
    if ($dbh->err) {
        return $dbh->selectrow_array("SELECT itid FROM ml_items WHERE dmid=$dmid AND itcode=$qcode");
    }
    return $dbh->{'mysql_insertid'};
}

sub set_text
{
    my ($dbarg, $dmid, $lncode, $itcode, $text, $opts) = @_;
    load_lang_struct() unless $LS_CACHED;

    my $dbs = LJ::make_dbs_from_arg($dbarg);
    my $dbh = $dbs->{'dbh'};
    my $dbr = $dbs->{'reader'};

    my $l = $LN_CODE{$lncode} or return 0;
    my $lnid = $l->{'lnid'};
    $dmid += 0;

    # is this domain/language request even possible?
    return 0 unless
        exists $DM_ID{$dmid} and
        exists $DM_ID{$dmid}->{'langs'}->{$lnid};

    my $itid = get_itemid($dbs, $dmid, $itcode, 1);
    return 0 unless $itid;

    my $txtid;

    # TODO: make it either check if existing text matches and use that txtid,
    # or make a new txtid
    my $userid = $opts->{'userid'} + 0;
    my $qtext = $dbh->quote($text);
    $dbh->do("INSERT INTO ml_text (dmid, txtid, lnid, itid, text, userid) ".
             "VALUES ($dmid, NULL, $lnid, $itid, $qtext, $userid)");
    return 0 if $dbh->err;
    $txtid = $dbh->{'mysql_insertid'};

    $dbh->do("REPLACE INTO ml_latest (lnid, dmid, itid, txtid, chgtime, staleness) ".
             "VALUES ($lnid, $dmid, $itid, $txtid, NOW(), 0)");
    return 0 if $dbh->err;
    
    # Todo: stale-ify child languages one layer down if severity
    return 1;
}

1;
