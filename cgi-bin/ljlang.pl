#!/usr/bin/perl
#

use strict;
use lib "$ENV{'LJHOME'}/cgi-bin";
use LJ::Cache;

package LJ::Lang;

my @day_short   = (qw[Sun Mon Tue Wed Thu Fri Sat]);
my @day_long    = (qw[Sunday Monday Tuesday Wednesday Thursday Friday Saturday]);
my @month_short = (qw[Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec]);
my @month_long  = (qw[January February March April May June July August September October November December]);

# get entire array of days and months
sub day_list_short   { return @LJ::Lang::day_short;   }
sub day_list_long    { return @LJ::Lang::day_long;    }
sub month_list_short { return @LJ::Lang::month_short; }
sub month_list_long  { return @LJ::Lang::month_long;  }

# access individual day or month given integer
sub day_short   { return   $day_short[$_[0] - 1]; }
sub day_long    { return    $day_long[$_[0] - 1]; }
sub month_short { return $month_short[$_[0] - 1]; }
sub month_long  { return  $month_long[$_[0] - 1]; }

# lang codes for individual day or month given integer
sub day_short_langcode   { return "date.day."   . lc(LJ::Lang::day_long(@_))    . ".short"; }
sub day_long_langcode    { return "date.day."   . lc(LJ::Lang::day_long(@_))    . ".long";  }
sub month_short_langcode { return "date.month." . lc(LJ::Lang::month_long(@_))  . ".short"; }
sub month_long_langcode  { return "date.month." . lc(LJ::Lang::month_long(@_))  . ".long";  }

## ordinal suffix
sub day_ord {
    my $day = shift;

    # teens all end in 'th'
    if ($day =~ /1\d$/) { return "th"; }
        
    # otherwise endings in 1, 2, 3 are special
    if ($day % 10 == 1) { return "st"; }
    if ($day % 10 == 2) { return "nd"; }
    if ($day % 10 == 3) { return "rd"; }

    # everything else (0,4-9) end in "th"
    return "th";
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

sub get_cache_object { return $TXT_CACHE; }

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

sub get_root_lang
{
    my $dom = shift;  # from, say, get_dom
    return undef unless ref $dom eq "HASH";
    foreach (keys %{$dom->{'langs'}}) {
        if ($dom->{'langs'}->{$_}) {
            return get_lang_id($_);
        }
    }
    return undef;
}

sub load_lang_struct
{
    return 1 if $LS_CACHED;
    my $dbr = LJ::get_db_reader();
    return set_error("No database available") unless $dbr;
    my $sth;

    $TXT_CACHE = new LJ::Cache { 'maxbytes' => $LJ::LANG_CACHE_BYTES || 50_000 };

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
    &LJ::nodb;
    my ($dmid, $itcode, $opts) = @_;
    load_lang_struct() unless $LS_CACHED;

    my $dbr = LJ::get_db_reader();
    $dmid += 0;
    my $itid = $dbr->selectrow_array("SELECT itid FROM ml_items WHERE dmid=$dmid AND itcode=?", undef, $itcode);
    return $itid if defined $itid;

    my $dbh = LJ::get_db_writer();
    $dbh->do("INSERT INTO ml_items (dmid, itid, itcode, notes) ".
             "VALUES ($dmid, NULL, ?, ?)", undef, $itcode, $opts->{'notes'});
    if ($dbh->err) {
        return $dbh->selectrow_array("SELECT itid FROM ml_items WHERE dmid=$dmid AND itcode=?",
                                     undef, $itcode);
    }
    return $dbh->{'mysql_insertid'};
}

sub set_text
{
    &LJ::nodb;
    my ($dmid, $lncode, $itcode, $text, $opts) = @_;
    load_lang_struct() unless $LS_CACHED;

    my $l = $LN_CODE{$lncode} or return set_error("Language not defined.");
    my $lnid = $l->{'lnid'};
    $dmid += 0;

    # is this domain/language request even possible?
    return set_error("Bogus domain") 
        unless exists $DM_ID{$dmid};
    return set_error("Bogus lang for that domain") 
        unless exists $DM_ID{$dmid}->{'langs'}->{$lnid};

    my $itid = get_itemid($dmid, $itcode, { 'notes' => $opts->{'notes'}});
    return set_error("Couldn't allocate itid.") unless $itid;

    my $dbh = LJ::get_db_writer();
    my $txtid = 0;
    if (defined $text) {
        my $userid = $opts->{'userid'} + 0;
        my $qtext = $dbh->quote($text);
        $dbh->do("INSERT INTO ml_text (dmid, txtid, lnid, itid, text, userid) ".
                 "VALUES ($dmid, NULL, $lnid, $itid, $qtext, $userid)");
        return set_error("Error inserting ml_text: ".$dbh->errstr) if $dbh->err;
        $txtid = $dbh->{'mysql_insertid'};
    }
    if ($opts->{'txtid'}) {
        $txtid = $opts->{'txtid'}+0;
    }

    my $staleness = $opts->{'staleness'}+0;
    $dbh->do("REPLACE INTO ml_latest (lnid, dmid, itid, txtid, chgtime, staleness) ".
             "VALUES ($lnid, $dmid, $itid, $txtid, NOW(), $staleness)");
    return set_error("Error inserting ml_latest: ".$dbh->errstr) if $dbh->err;
    LJ::MemCache::set("ml.${lncode}.${dmid}.${itcode}", $text);

    {
        my $vals;
        my $langids;
        my $rec = sub {
            my $l = shift;
            my $rec = shift;
            foreach my $cid (@{$l->{'children'}}) {
                my $clid = $LN_ID{$cid};
                if ($opts->{'childrenlatest'}) {
                    my $stale = $clid->{'parenttype'} eq "diff" ? 3 : 0;
                    $vals .= "," if $vals;
                    $vals .= "($cid, $dmid, $itid, $txtid, NOW(), $stale)";
                }
                $langids .= "," if $langids;
                $langids .= $cid+0;
                LJ::MemCache::delete("ml.$clid->{'lncode'}.${dmid}.${itcode}");
                $rec->($clid, $rec);
            }
        };
        $rec->($l, $rec);

        # set descendants to use this mapping
        $dbh->do("INSERT IGNORE INTO ml_latest (lnid, dmid, itid, txtid, chgtime, staleness) ".
                 "VALUES $vals") if $vals;

        # update languages that have no translation yet
        $dbh->do("UPDATE ml_latest SET txtid=$txtid WHERE dmid=$dmid ".
                 "AND lnid IN ($langids) AND itid=$itid AND staleness >= 3") if $langids;
    }

    if ($opts->{'changeseverity'} && $l->{'children'} && @{$l->{'children'}}) {
        my $in = join(",", @{$l->{'children'}});
        my $newstale = $opts->{'changeseverity'} == 2 ? 2 : 1;
        $dbh->do("UPDATE ml_latest SET staleness=$newstale WHERE lnid IN ($in) AND ".
                 "dmid=$dmid AND itid=$itid AND txtid<>$txtid AND staleness < $newstale");
    }

    return 1;
}

sub get_text
{
    my ($lang, $code, $dmid, $vars) = @_;
    $dmid = int($dmid || 1);
    $lang ||= $LJ::DEFAULT_LANG;
    load_lang_struct() unless $LS_CACHED;
    my $cache_key = "ml.${lang}.${dmid}.${code}";
    
    my $text = $TXT_CACHE->get($cache_key);

    unless (defined $text) {
        my $mem_good = 1;
        $text = LJ::MemCache::get($cache_key);
        unless (defined $text) {
            $mem_good = 0;
            my $l = $LN_CODE{$lang} or return "?lang?";
            my $dbr = LJ::get_db_reader();
            $text = $dbr->selectrow_array("SELECT t.text".
                                          "  FROM ml_text t, ml_latest l, ml_items i".
                                          " WHERE t.dmid=$dmid AND t.txtid=l.txtid".
                                          "   AND l.dmid=$dmid AND l.lnid=$l->{lnid} AND l.itid=i.itid".
                                          "   AND i.dmid=$dmid AND i.itcode=?", undef,
                                          $code);
        }
        if (defined $text) {
            $TXT_CACHE->set($cache_key, $text);
            LJ::MemCache::set($cache_key, $text) unless $mem_good;
        }
    }

    if ($vars) {
        $text =~ s/\[\[\?([\w\-]+)\|(.+?)\]\]/resolve_plural($lang, $vars, $1, $2)/eg;
        $text =~ s/\[\[([^\[]+?)\]\]/$vars->{$1}/g;
    }

    return $text;
}

# The translation system now supports the ability to add multiple plural forms of the word
# given different rules in a languge.  This functionality is much like the plural support
# in the S2 styles code.  To use this code you must use the BML::ml function and pass
# the number of items as one of the variables.  To make sure that you are allowing the
# utmost compatibility for each language you should not hardcode the placement of the
# number of items in relation to the noun.  Let the translation string do this for you.
# A translation string is in the format of, with num being the variable storing the
# number of items.
# =[[num]] [[?num|singular|plural1|plural2|pluralx]]

sub resolve_plural {
    my ($lang, $vars, $varname, $wordlist) = @_;
    my $count = $vars->{$varname};
    my @wlist = split(/\|/, $wordlist);
    my $plural_form = plural_form($lang, $count);
    return $wlist[$plural_form];
}

# TODO: make this faster, using AUTOLOAD and symbol tables pointing to dynamically
# generated subs which only use $_[0] for $count.
sub plural_form {
    my ($lang, $count) = @_;
    return plural_form_en($count) if $lang =~ /^en/;
    return plural_form_ru($count) if $lang =~ /^ru/;
    return plural_form_fr($count) if $lang =~ /^fr/;
    return plural_form_en($count);  # default
}

sub plural_form_en {
    my ($count) = shift;
    return 0 if $count == 1;
    return 1;
}

sub plural_form_fr {
    my ($count) = shift;
    return 1 if $count > 1;
    return 0;
}

sub plural_form_ru {
    my ($count) = shift;
    return 0 if ($count%10 == 1 and $count%100 != 11);
    return 1 if ($count%10 >= 2 and $count%10 <= 4 and ($count%100 < 10 or $count%100>=20));
    return 2;
}

1;
