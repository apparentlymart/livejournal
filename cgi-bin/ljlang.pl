#!/usr/bin/perl
#

BEGIN {
    unshift @INC, "$ENV{'LJHOME'}/cgi-bin";
}

use strict;
use LJ::Cache;

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
my $LAST_ERROR;
my $TXT_CACHE;      # LJ::Cache for text

sub last_error
{
    return $LAST_ERROR;
}

sub set_error
{
    $LAST_ERROR = $_[0];
    return 0;
}

sub get_lang
{
    my $code = shift;
    load_lang_struct() unless $LS_CACHED;
    return $LN_CODE{$code};
}

sub get_lang_id
{
    my $id = shift;
    load_lang_struct() unless $LS_CACHED;
    return $LN_ID{$id};
}

sub get_dom
{
    my $dmcode = shift;
    load_lang_struct() unless $LS_CACHED;
    return $DM_UNIQ{$dmcode};
}

sub get_dom_id
{
    my $dmid = shift;
    load_lang_struct() unless $LS_CACHED;
    return $DM_ID{$dmid};
}

sub get_domains
{
    load_lang_struct() unless $LS_CACHED;
    return values %DM_ID;
}

sub load_lang_struct
{
    return 1 if $LS_CACHED;
    my $dbr = LJ::get_dbh("slave", "master");
    return 0 unless $dbr;
    my $sth;

    $TXT_CACHE = new LJ::Cache { 'maxsize' => $LJ::LANG_CACHE_SIZE || 2000 };

    $sth = $dbr->prepare("SELECT dmid, type, args FROM ml_domains");
    $sth->execute;
    while (my ($dmid, $type, $args) = $sth->fetchrow_array) {
        my $uniq = $args ? "$type/$args" : $type;
        $DM_UNIQ{$uniq} = $DM_ID{$dmid} = { 
            'type' => $type, 'args' => $args, 'dmid' => $dmid,
            'uniq' => $uniq,
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
        $DM_ID{$dmid}->{'langs'}->{$lnid} = $dmmaster;
    }
    
    $LS_CACHED = 1;
}

sub get_itemid
{
    my ($dbarg, $dmid, $itcode, $opts) = @_;
    load_lang_struct() unless $LS_CACHED;

    my $dbs = LJ::make_dbs_from_arg($dbarg);
    my $dbh = $dbs->{'dbh'};
    my $dbr = $dbs->{'reader'};

    $dmid += 0;
    my $qcode = $dbh->quote($itcode);
    my $itid = $dbr->selectrow_array("SELECT itid FROM ml_items WHERE dmid=$dmid AND itcode=$qcode");
    return $itid if defined $itid;
    my $qnotes = $dbh->quote($opts->{'notes'});
    $dbh->do("INSERT INTO ml_items (dmid, itid, itcode, notes) VALUES ($dmid, NULL, $qcode, $qnotes)");
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

    my $l = $LN_CODE{$lncode} or return set_error("Language not defined.");
    my $lnid = $l->{'lnid'};
    $dmid += 0;

    # is this domain/language request even possible?
    return set_error("Bogus domain") 
        unless exists $DM_ID{$dmid};
    return set_error("Bogus lang for that domain") 
        unless exists $DM_ID{$dmid}->{'langs'}->{$lnid};

    my $itid = get_itemid($dbs, $dmid, $itcode, { 'notes' => $opts->{'notes'}});
    return set_error("Couldn't allocate itid.") unless $itid;

    my $txtid = 0;
    if (defined $text) {
        my $userid = $opts->{'userid'} + 0;
        my $qtext = $dbh->quote($text);
        $dbh->do("INSERT INTO ml_text (dmid, txtid, lnid, itid, text, userid) ".
                 "VALUES ($dmid, NULL, $lnid, $itid, $qtext, $userid)");
        return set_error("Error inserting ml_text: ".$dbh->err) if $dbh->err;
        $txtid = $dbh->{'mysql_insertid'};
    }
    if ($opts->{'txtid'}) {
        $txtid = $opts->{'txtid'}+0;
    }

    my $staleness = $opts->{'staleness'}+0;
    $dbh->do("REPLACE INTO ml_latest (lnid, dmid, itid, txtid, chgtime, staleness) ".
             "VALUES ($lnid, $dmid, $itid, $txtid, NOW(), $staleness)");
    return set_error("Error inserting ml_latest: ".$dbh->err) if $dbh->err;

    # set descendants to use this mapping
    if ($opts->{'childrenlatest'}) {
        my $vals;
        my $rec = sub {
            my $l = shift;
            my $rec = shift;
            foreach my $cid (@{$l->{'children'}}) {
                my $clid = $LN_ID{$cid};
                my $stale = $clid->{'parenttype'} eq "diff" ? 3 : 0;
                $vals .= "," if $vals;
                $vals .= "($cid, $dmid, $itid, $txtid, NOW(), $stale)";
                $rec->($clid, $rec);
            }
        };
        $rec->($l, $rec);
        $dbh->do("INSERT IGNORE INTO ml_latest (lnid, dmid, itid, txtid, chgtime, staleness) ".
                 "VALUES $vals") if $vals;
    }
    
    if ($opts->{'changeseverity'} && $l->{'children'} && @{$l->{'children'}}) {
        my $in = join(",", @{$l->{'children'}});
        my $newstale = $opts->{'changeseverity'} == 2 ? 2 : 1;
        $dbh->do("UPDATE ml_latest SET staleness=$newstale WHERE lnid IN ($in) AND ".
                 "dmid=$dmid AND itid=$itid AND staleness < $newstale");
    }

    return 1;
}

sub _get_cache
{
    return $TXT_CACHE;
}

sub get_text_bml 
{
    my ($lang, $code) = @_;
    load_lang_struct() unless $LS_CACHED;
    my $l = $LN_CODE{$lang};
    return unless $l;

    my $text = $TXT_CACHE->get("$lang-$code");
    return $text if defined $text;
    
    my $dbr = LJ::get_dbh("slave", "master");
    $text = $dbr->selectrow_array("SELECT t.text FROM ml_text t, ml_latest l, ml_items i WHERE t.dmid=1 ".
                                  "AND t.txtid=l.txtid AND l.dmid=1 AND l.lnid=$l->{'lnid'} AND l.itid=i.itid ".
                                  "AND i.dmid=1 AND i.itcode=" . $dbr->quote($code));
    $TXT_CACHE->set("$lang-$code", $text);
    return $text;
}

1;
