package LJ::Lang;
use strict;
use warnings;

use lib "$ENV{'LJHOME'}/cgi-bin";
require "ljhooks.pl";

use base qw( Exporter );
our @EXPORT_OK = qw( ml );

use LJ::LangDatFile;
use LJ::TimeUtil;

use constant MAXIMUM_ITCODE_LENGTH => 80;

my @day_short = qw( Sun Mon Tue Wed Thu Fri Sat );
my @day_long = qw( Sunday Monday Tuesday Wednesday Thursday Friday Saturday );
my @month_short = qw( Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec );
my @month_long  = qw(
    January February March April May June
    July August September October November December
);

# get entire array of days and months
sub day_list_short   { return @LJ::Lang::day_short; }
sub day_list_long    { return @LJ::Lang::day_long; }
sub month_list_short { return @LJ::Lang::month_short; }
sub month_list_long  { return @LJ::Lang::month_long; }

# access individual day or month given integer
sub day_short   { return $day_short[ $_[0] - 1 ]; }
sub day_long    { return $day_long[ $_[0] - 1 ]; }
sub month_short { return $month_short[ $_[0] - 1 ]; }
sub month_long  { return $month_long[ $_[0] - 1 ]; }

# lang codes for individual day or month given integer
sub day_short_langcode {
    return "date.day." . lc( LJ::Lang::day_long(@_) ) . ".short";
}

sub day_long_langcode {
    return "date.day." . lc( LJ::Lang::day_long(@_) ) . ".long";
}

sub month_short_langcode {
    return "date.month." . lc( LJ::Lang::month_long(@_) ) . ".short";
}

sub month_long_langcode {
    return "date.month." . lc( LJ::Lang::month_long(@_) ) . ".long";
}

sub month_long_genitive_langcode {
    return "date.month." . lc( LJ::Lang::month_long(@_) ) . ".genitive";
}

## ordinal suffix
sub day_ord {
    my $day = shift;

    # teens all end in 'th'
    if ( $day =~ /1\d$/ ) { return "th"; }

    # otherwise endings in 1, 2, 3 are special
    if ( $day % 10 == 1 ) { return "st"; }
    if ( $day % 10 == 2 ) { return "nd"; }
    if ( $day % 10 == 3 ) { return "rd"; }

    # everything else (0,4-9) end in "th"
    return "th";
}

sub time_format {
    my ( $hours, $h, $m, $formatstring ) = @_;

    if ( $formatstring eq "short" ) {
        if ( $hours == 12 ) {
            my $ret;
            my $ap = "a";
            if    ( $h == 0 )  { $ret .= "12"; }
            elsif ( $h < 12 )  { $ret .= ( $h + 0 ); }
            elsif ( $h == 12 ) { $ret .= ( $h + 0 ); $ap = "p"; }
            else               { $ret .= ( $h - 12 ); $ap = "p"; }
            $ret .= sprintf( ":%02d$ap", $m );
            return $ret;
        } elsif ( $hours == 24 ) {
            return sprintf( "%02d:%02d", $h, $m );
        }
    }
    return "";
}

#### ml_ stuff:
my $LS_CACHED = 0;
my %DM_ID   = ();  # id -> { type, args, dmid, langs => { => 1, => 0, => 1 } }
my %DM_UNIQ = ();  # "$type/$args" => ^^^
my %LN_ID   = ();  # id -> { ..., ..., 'children' => [ $ids, .. ] }
my %LN_CODE = ();  # $code -> ^^^^
my $LAST_ERROR;
my %TXT_CACHE;

if ( $LJ::IS_DEV_SERVER || $LJ::IS_LJCOM_BETA ) {
    our $_hook_is_installed;
    LJ::register_hook( 'start_request', sub { %TXT_CACHE = (); } )
        unless $_hook_is_installed++;
}

sub last_error {
    return $LAST_ERROR;
}

sub set_error {
    $LAST_ERROR = $_[0];
    return 0;
}

sub get_lang {
    my $code = shift;
    load_lang_struct() unless $LS_CACHED;
    return $LN_CODE{$code};
}

sub get_lang_id {
    my $id = shift;
    load_lang_struct() unless $LS_CACHED;
    return $LN_ID{$id};
}

sub get_dom {
    my $dmcode = shift;
    load_lang_struct() unless $LS_CACHED;
    return $DM_UNIQ{$dmcode};
}

sub get_dom_id {
    my $dmid = shift;
    load_lang_struct() unless $LS_CACHED;
    return $DM_ID{$dmid};
}

sub get_domains {
    load_lang_struct() unless $LS_CACHED;
    return values %DM_ID;
}

sub get_root_lang {
    my $dom = shift;    # from, say, get_dom
    return undef unless ref $dom eq "HASH";

    my $lang_override = LJ::run_hook( "root_lang_override", $dom );
    return get_lang($lang_override) if $lang_override;

    foreach ( keys %{ $dom->{'langs'} } ) {
        if ( $dom->{'langs'}->{$_} ) {
            return get_lang_id($_);
        }
    }
    return undef;
}

sub load_lang_struct {
    return 1 if $LS_CACHED;
    my $dbr = LJ::get_db_reader();
    return set_error("No database available") unless $dbr;
    my $sth;

    $sth = $dbr->prepare("SELECT dmid, type, args FROM ml_domains");
    $sth->execute;
    while ( my ( $dmid, $type, $args ) = $sth->fetchrow_array ) {
        my $uniq = $args ? "$type/$args" : $type;
        $DM_UNIQ{$uniq} = $DM_ID{$dmid} = {
            'type' => $type,
            'args' => $args,
            'dmid' => $dmid,
            'uniq' => $uniq,
        };
    }

    $sth = $dbr->prepare(
        "SELECT lnid, lncode, lnname, parenttype, parentlnid FROM ml_langs");
    $sth->execute;
    while ( my ( $id, $code, $name, $ptype, $pid ) = $sth->fetchrow_array ) {
        $LN_ID{$id} = $LN_CODE{$code} = {
            'lnid'       => $id,
            'lncode'     => $code,
            'lnname'     => $name,
            'parenttype' => $ptype,
            'parentlnid' => $pid,
        };
    }
    foreach ( values %LN_CODE ) {
        next unless $_->{'parentlnid'};
        push @{ $LN_ID{ $_->{'parentlnid'} }->{'children'} }, $_->{'lnid'};
    }

    $sth = $dbr->prepare("SELECT lnid, dmid, dmmaster FROM ml_langdomains");
    $sth->execute;
    while ( my ( $lnid, $dmid, $dmmaster ) = $sth->fetchrow_array ) {
        $DM_ID{$dmid}->{'langs'}->{$lnid} = $dmmaster;
    }

    $LS_CACHED = 1;
}

sub langdat_file_of_lang_itcode {
    my ( $lang, $itcode, $want_cvs ) = @_;

    my $langdat_file =
        LJ::Lang::relative_langdat_file_of_lang_itcode( $lang, $itcode );

    my $cvs_extra = "";
    if ($want_cvs) {
        if ( $lang eq "en" ) {
            $cvs_extra = "/cvs/livejournal";
        } else {
            $cvs_extra = "/cvs/local";
        }
    }

    return "$ENV{LJHOME}$cvs_extra/$langdat_file";
}

sub relative_langdat_file_of_lang_itcode {
    my ( $lang, $itcode ) = @_;

    my $root_lang       = "en";
    my $root_lang_local = $LJ::DEFAULT_LANG;

    my $base_file = "bin/upgrading/$lang\.dat";

    # not a root or root_local lang, just return base file location
    unless ( $lang eq $root_lang || $lang eq $root_lang_local ) {
        return $base_file;
    }

    my $is_local = $lang eq $root_lang_local;

    # is this a filename-based itcode?
    if ( $itcode =~ m!^(/.+\.bml)! ) {
        my $file = $1;

        # given the filename of this itcode and the current
        # source, what langdat file should we use?
        my $langdat_file = "htdocs$file\.text";
        $langdat_file .= $is_local ? ".local" : "";
        return $langdat_file;
    }

    # not a bml file, goes into base .dat file
    return $base_file;
}

sub itcode_for_langdat_file {
    my ( $langdat_file, $itcode ) = @_;

    # non-bml itcode, return full itcode path
    unless ( $langdat_file =~ m!^/.+\.bml\.text(?:\.local)?$! ) {
        return $itcode;
    }

    # bml itcode, strip filename and return
    if ( $itcode =~ m!^/.+\.bml(\..+)! ) {
        return $1;
    }

    # fallback -- full $itcode
    return $itcode;
}

sub get_chgtime_unix {
    my ( $lncode, $dmid, $itcode ) = @_;
    load_lang_struct() unless $LS_CACHED;

    $dmid = int( $dmid || 1 );

    my $l = get_lang($lncode) or return "No lang info for lang $lncode";
    my $lnid = $l->{'lnid'}
        or die "Could not get lang_id for lang $lncode";

    my $itid = LJ::Lang::get_itemid( $dmid, $itcode )
        or return 0;

    my $dbr     = LJ::get_db_reader();
    my $chgtime = $dbr->selectrow_array(
        'SELECT chgtime FROM ml_latest WHERE dmid=? AND itid=? AND lnid=?',
        undef, $dmid, $itid, $lnid, );
    die $dbr->errstr if $dbr->err;

    return $chgtime ? LJ::TimeUtil->mysqldate_to_time($chgtime) : 0;
}

sub get_itemid {
    my ( $dmid, $itcode, $opts ) = @_;
    load_lang_struct() unless $LS_CACHED;

    if ( length $itcode > MAXIMUM_ITCODE_LENGTH ) {
        warn "'$itcode' exceeds maximum code length, truncating to "
            . MAXIMUM_ITCODE_LENGTH
            . " symbols";
        $itcode = substr( $itcode, 0, MAXIMUM_ITCODE_LENGTH );
    }

    my $dbr  = LJ::get_db_reader();
    my $itid = $dbr->selectrow_array(
        "SELECT itid FROM ml_items WHERE dmid=? AND itcode=?",
        undef, $dmid, $itcode, );
    return $itid if defined $itid;

    my $dbh = LJ::get_db_writer();
    return 0 unless $dbh;

    # allocate a new id
    LJ::get_lock( $dbh, 'global', 'mlitem_dmid' ) || return 0;
    $itid = $dbh->selectrow_array(
        "SELECT MAX(itid)+1 FROM ml_items WHERE dmid=?",
        undef, $dmid, );
    $itid ||= 1;    # if the table is empty, NULL+1 == NULL

    my $affected = $dbh->do(
        qq{
            INSERT IGNORE INTO ml_items (dmid, itid, itcode, notes)
            VALUES (?, ?, ?, ?)
        },
        undef, $dmid, $itid, $itcode, $opts->{'notes'},
    );
    LJ::release_lock( $dbh, 'global', 'mlitem_dmid' );

    die $dbh->errstr if $dbh->err;
    unless ($affected) {
        $itid = $dbh->selectrow_array(
            "SELECT itid FROM ml_items WHERE dmid=? AND itcode=?",
            undef, $dmid, $itcode, );
    }

    return $itid;
}

# this is called when editing text from a web UI.
# first try and run a local hook to save the text,
# if that fails then just call set_text

# returns ($success, $responsemsg) where responsemsg can be output
# from whatever saves the text
sub web_set_text {
    my ( $dmid, $lncode, $itcode, $text, $opts ) = @_;

    my $resp     = '';
    my $hook_ran = 0;

    if ( LJ::are_hooks('web_set_text') ) {
        $hook_ran =
            LJ::run_hook( 'web_set_text', $dmid, $lncode, $itcode, $text,
            $opts, );
    }

    # save in the db
    my $save_success =
        LJ::Lang::set_text( $dmid, $lncode, $itcode, $text, $opts );

    $resp = LJ::Lang::last_error() unless $save_success;
    warn $resp if !$save_success && $LJ::IS_DEV_SERVER;

    return ( $save_success, $resp );
}

sub set_text {
    my ( $dmid, $lncode, $itcode, $text, $opts ) = @_;
    load_lang_struct() unless $LS_CACHED;

    my $l = $LN_CODE{$lncode} or return set_error("Language $lncode not defined.");
    my $lnid = $l->{'lnid'};

    # is this domain/language request even possible?
    return set_error("Bogus domain")
        unless exists $DM_ID{$dmid};

    return set_error("Bogus lang for that domain")
        unless exists $DM_ID{$dmid}->{'langs'}->{$lnid};

    my $itid = get_itemid( $dmid, $itcode, { 'notes' => $opts->{'notes'} } );
    return set_error("Couldn't allocate itid.") unless $itid;

    my $dbh   = LJ::get_db_writer();
    my $txtid = 0;

    my $oldtextid = $dbh->selectrow_array(
        "SELECT MAX(txtid) FROM ml_text WHERE lnid=? AND dmid=? AND itid=?",
        undef, $lnid, $dmid, $itid, );

    if ( defined $text ) {
        my $userid = $opts->{'userid'} + 0;

        # Strip bad characters
        $text =~ s/\r//;

        LJ::get_lock( $dbh, 'global', 'ml_text_txtid' ) || return 0;

        $txtid = $dbh->selectrow_array(
            "SELECT MAX(txtid)+1 FROM ml_text WHERE dmid=?",
            undef, $dmid, );
        $txtid ||= 1;

        $dbh->do(
            qq{
                INSERT INTO ml_text (dmid, txtid, lnid, itid, text, userid)
                VALUES (?, ?, ?, ?, ?, ?)
            },
            undef, $dmid, $txtid, $lnid, $itid, $text, $userid,
        );
        LJ::release_lock( $dbh, 'global', 'ml_text_txtid' );

        return set_error( "Error inserting ml_text: " . $dbh->errstr )
            if $dbh->err;
    }

    if ( $opts->{'txtid'} ) {
        $txtid = $opts->{'txtid'} + 0;
    }

    my $revid     = LJ::alloc_global_counter("ml_latest_updates_counter");
    my $staleness = int $opts->{'staleness'};
    $dbh->do(
        qq{
            REPLACE INTO ml_latest
            (lnid, dmid, itid, txtid, chgtime, staleness, revid)
            VALUES (?, ?, ?, ?, NOW(), ?, ?)
        },
        undef, $lnid, $dmid, $itid, $txtid, $staleness, $revid,
    );

    return set_error( "Error inserting ml_latest: " . $dbh->errstr )
        if $dbh->err;

    LJ::MemCache::set( "ml.${lncode}.${dmid}.${itcode}", $text )
        if defined $text;

    my @langids;
    my $langids;
    my $vals;

    my $rec;
    $rec = sub {
        my $l   = shift;
        foreach my $cid ( @{ $l->{'children'} } ) {
            my $clid = $LN_ID{$cid};
            if ( $opts->{'childrenlatest'} ) {
                $revid =
                    LJ::alloc_global_counter("ml_latest_updates_counter");
                my $stale = $clid->{'parenttype'} eq "diff" ? 3 : 0;

                # set descendants to use this mapping:
                $dbh->do(
                    qq{
                        INSERT IGNORE INTO ml_latest
                        (lnid, dmid, itid, txtid, chgtime, staleness, revid)
                        VALUES (?, ?, ?, ?, NOW(), ?, ?)
                    },
                    undef, $cid, $dmid, $itid, $txtid, $stale, $revid,
                );
            }
            push @langids, $cid;

            LJ::MemCache::delete("ml.$clid->{'lncode'}.${dmid}.${itcode}");
            $rec->($clid);
        }
    };
    $rec->($l);

    my $langids_in = join( ',', map { int $_ } @langids );

    # update languages that have no translation yet
    $revid = LJ::alloc_global_counter("ml_latest_updates_counter");
    if (@langids) {
        if ($oldtextid) {
            $dbh->do(
                qq{
                    UPDATE ml_latest
                    SET txtid=?, revid=?
                    WHERE
                        dmid=? AND
                        lnid IN ($langids_in)
                        AND itid=? AND
                        txtid=?
                },
                undef, $txtid, $revid, $dmid, $itid, $oldtextid,
            );
        } else {
            $dbh->do(
                qq{
                    UPDATE ml_latest
                    SET txtid=?, revid=?
                    WHERE
                        dmid=? AND
                        lnid IN ($langids_in) AND
                        itid=? AND
                        staleness >= 3
                },
                undef, $txtid, $revid, $dmid, $itid,
            );
        }
    }

    if ( $opts->{'changeseverity'} && @langids ) {
        my $newstale = $opts->{'changeseverity'} == 2 ? 2 : 1;
        $dbh->do(
            qq{
                UPDATE ml_latest
                SET staleness=?
                WHERE
                    lnid IN ($langids_in) AND
                    dmid=? AND
                    itid=? AND
                    txtid<>? AND
                    staleness < ?
            },
            undef, $newstale, $dmid, $itid, $txtid, $newstale,
        );
    }

    LJ::MemCache::set( 'ml_latest_updates_counter', $revid );

    return 1;
}

sub remove_text {
    my ( $dmid, $itcode, $lncode ) = @_;

    my $dbh = LJ::get_db_writer();

    my $itid = $dbh->selectrow_array(
        'SELECT itid FROM ml_items WHERE dmid=? AND itcode=?',
        undef, $dmid, $itcode, );
    die "Unknown item code $itcode." unless $itid;

    # need to delete everything from: ml_items ml_latest ml_text

    $dbh->do( 'DELETE FROM ml_items WHERE dmid=? AND itid=?',
        undef, $dmid, $itid, );

    my $txtids = $dbh->selectcol_arrayref(
        'SELECT txtid FROM ml_latest WHERE dmid=? AND itid=?',
        undef, $dmid, $itid, );

    $dbh->do( 'DELETE FROM ml_latest WHERE dmid=? AND itid=?',
        undef, $dmid, $itid, );

    if (@$txtids) {
        my $txtid_bind = join( ",", map {'?'} @$txtids );
        $dbh->do(
            "DELETE FROM ml_text WHERE dmid=? AND txtid IN ($txtid_bind)",
            undef, $dmid, @$txtids, );
    }

    # delete from memcache if lncode is defined
    LJ::MemCache::delete("ml.${lncode}.${dmid}.${itcode}") if $lncode;

    return 1;
}

sub get_remote_lang {
    if ( my $remote = LJ::get_remote() ) {
        return $remote->prop('browselang')
            || $LJ::DEFAULT_LANG;
    }

    if ( LJ::is_web_context() ) {
        return BML::get_language();
    }

    return $LJ::DEFAULT_LANG;
}

sub string_exists {
    my ( $code, $vars ) = @_;

    my $string = LJ::Lang::ml( $code, $vars );
    return LJ::Lang::is_missing_string($string) ? 0 : 1;
}

# LJ::Lang::ml will return a number of values for "invalid string"
# -- this function will tell you if the value is one of
#    those values.  gross.
sub is_missing_string {
    my $string = shift;

    return (   $string eq ""
            || $string =~ /^\[missing string/
            || $string =~ /^\[uhhh:/ ) ? 1 : 0;
}

sub get_text {
    my ( $lang, $code, $dmid, $vars ) = @_;
    $lang ||= $LJ::DEFAULT_LANG;
    $dmid ||= 1;

    my $from_db = sub {
        my $text = get_text_multi( $lang, $dmid, [$code] );
        return $text->{$code};
    };

    my $_from_files = sub {
        my ( $localcode, @files );
        if ( $code =~ m!^(/.+\.bml)(\..+)! ) {
            my $file;
            ( $file, $localcode ) = ( "$LJ::HTDOCS$1", $2 );
            @files = ( "$file.text.local", "$file.text" );
        } else {
            $localcode = $code;
            @files     = (
                "$LJ::HOME/bin/upgrading/$LJ::DEFAULT_LANG.dat",
                "$LJ::HOME/bin/upgrading/en.dat"
            );
        }

        my $dbmodtime = LJ::Lang::get_chgtime_unix( $lang, $dmid, $code );
        foreach my $tf (@files) {
            next unless -e $tf;

            # compare file modtime to when the string was updated in the DB.
            # whichever is newer is authoritative
            my $fmodtime = ( stat $tf )[9];
            return $from_db->() if !$fmodtime || $dbmodtime > $fmodtime;

            my $ldf = $LJ::REQ_LANGDATFILE{$tf} ||= LJ::LangDatFile->new($tf);
            my $val = $ldf->value($localcode);
            return $val if $val;
        }
        return "[missing string $code]";
    };

    my $from_files = sub {
        my $cache_key = "ml.${lang}.${dmid}.${code}";
        return $TXT_CACHE{$cache_key} ||= $_from_files->();
    };

    ##
    my $gen_mld = LJ::Lang::get_dom('general');
    my $is_gen_dmid = defined $dmid ? $dmid == $gen_mld->{dmid} : 1;
    my $text;

    if (   $LJ::IS_DEV_SERVER
        && $is_gen_dmid
        && ( $lang eq "en" || $lang eq $LJ::DEFAULT_LANG ) )
    {
        $text = $from_files->();
    } else {
        $text = $from_db->();
    }

    if ($vars) {

        # the following regexp parses the [[?num|singular|plural1|...]] syntax
        $text =~ s{
            \[\[\?      # opening literal '[[?'
            ([\w\-]+)   # the number key
            \|          # the pipe delimiter
            (.+?)       # singular/plural variants
            \]\]        # closing literal ']]'
        }
        {resolve_plural($lang, $vars, $1, $2)}xeg;

        # and the following merely substitutes the keys:
        $text =~ s{
            \[\[        # opening literal '[['
            ([^\[]+?)   # the key
            \]\]        # closing literal ']]'
        }
        { defined $vars->{$1} ? $vars->{$1} : "[$1]" }xeg;
    }

    $LJ::_ML_USED_STRINGS{$code} = $text if $LJ::IS_DEV_SERVER;

    return $text || ( $LJ::IS_DEV_SERVER ? "[uhhh: $code]" : "" );
}

# Loads multiple language strings at once.  These strings
# cannot however contain variables, if you have variables
# you wouldn't be calling this anyway!
# args: $lang, $dmid, array ref of lang codes
sub get_text_multi {
    my ( $lang, $dmid, $codes ) = @_;

    return {} unless $codes;
    return { map { $_ => $_ } @$codes }
        if $lang eq 'debug';

    $dmid = int( $dmid || 1 );
    $lang ||= $LJ::DEFAULT_LANG;
    load_lang_struct() unless $LS_CACHED;

    ## %strings: code --> text
    my %strings;

    ## normalize the codes: all chars must be in lower case
    ## MySQL string comparison isn't case-sensitive, but memcaches keys are.
    ## Caller will get %strings with keys in original case.
    ##
    ## Final note about case:
    ##  Codes in disk .text files, mysql and bml files may be mixed-cased
    ##  Codes in memcache and %TXT_CACHE are lower-case
    ##  Codes are not case-sensitive

    ## %lc_code: lower-case code --> original code
    my %lc_codes = map { lc($_) => $_ } @$codes;

    ## %memkeys: lower-case code --> memcache key
    my %memkeys;
    foreach my $code ( keys %lc_codes ) {
        my $cache_key = "ml.${lang}.${dmid}.${code}";
        my $text      = undef;
        $text = $TXT_CACHE{$cache_key} unless $LJ::NO_ML_CACHE;

        if ( defined $text ) {
            $strings{ $lc_codes{$code} } = $text;
            $LJ::_ML_USED_STRINGS{$code} = $text if $LJ::IS_DEV_SERVER;
        } else {
            $memkeys{$cache_key} = $code;
        }
    }

    return \%strings unless %memkeys;

    my $mem = LJ::MemCache::get_multi( keys %memkeys ) || {};

    ## %dbload: lower-case key --> text; text may be empty (but defined) string
    my %dbload;
    foreach my $cache_key ( keys %memkeys ) {
        my $code = $memkeys{$cache_key};
        my $text = $mem->{$cache_key};

        if ( defined $text ) {
            $strings{ $lc_codes{$code} } = $text;
            $LJ::_ML_USED_STRINGS{$code} = $text if $LJ::IS_DEV_SERVER;
            $TXT_CACHE{$cache_key} = $text;
        } else {

            # we need to cache nonexistant/empty strings because
            # otherwise we're running a lot of queries all the time
            # to cache nonexistant strings, value of %dbload must be defined
            $dbload{$code} = '';
        }
    }

    return \%strings unless %dbload;

    my $l = $LN_CODE{$lang};

    # This shouldn't happen!
    die "Unable to load language code: $lang" unless $l;

    my $dbr = LJ::get_db_reader();
    my $bind = join( ',', map {'?'} keys %dbload );

    my $rows = $dbr->selectall_arrayref(
        qq{
            SELECT i.itcode, t.text
            FROM ml_text t, ml_latest l, ml_items i
            WHERE
                t.dmid=? AND
                t.txtid=l.txtid AND
                l.dmid=? AND
                l.lnid=? AND
                l.itid=i.itid AND
                i.dmid=? AND
                i.itcode IN ($bind)
        },
        { 'Slice' => {} },
        $dmid, $dmid, $l->{'lnid'}, $dmid, keys %dbload,
    );

    # now replace the empty strings with the defined ones
    # that we got back from the database
    foreach my $row (@$rows) {

        # some MySQL codes might be mixed-case
        $dbload{ lc $row->{'itcode'} } = $row->{'text'};
    }

    while ( my ( $code, $text ) = each %dbload ) {
        $strings{ $lc_codes{$code} } = $text;
        $LJ::_ML_USED_STRINGS{$code} = $text if $LJ::IS_DEV_SERVER;

        my $cache_key = "ml.${lang}.${dmid}.${code}";
        $TXT_CACHE{$cache_key} = $text;

        if ($text) {
            LJ::MemCache::set( $cache_key, $text );
        } else {
            ## Do not cache empty values forever - they may be inserted later.
            ## This is a hack, what we actually need is a mechanism to delete
            ## the entire language tree for a given $code if it's updated.
            LJ::MemCache::set( $cache_key, $text, 24 * 3600 );
        }
    }

    return \%strings;
}

sub get_lang_names {
    my @langs = @_;
    push @langs, @LJ::LANGS unless @langs;

    my $list = LJ::MemCache::get("langnames");
    return $list if $list;

    $list = [];
    foreach my $code (@langs) {
        my $l = LJ::Lang::get_lang($code);
        next unless $l;

        my $item = "langname.$code";

        ## Native lang name
        my $namenative = LJ::Lang::get_text( $l->{'lncode'}, $item );

        push @$list, $code, $namenative;
    }

    ## cache name on 5 min
    LJ::MemCache::set( 'langnames' => $list, 3660 );

    return $list;
}

# The translation system supports the ability to add multiple plural forms of
# the word given different rules in a languge. This functionality is much like
# the plural support in the S2 styles code. To use this code you must use the
# BML::ml function and pass the number of items as one of the variables. To
# make sure that you are allowing the utmost compatibility for each language
# you should not hardcode the placement of the number of items in relation to
# the noun.  Let the translation string do this for you. A translation string
# is in the format of, with num being the variable storing the number of items.
# =[[num]] [[?num|singular|plural1|plural2|pluralx]]

sub resolve_plural {
    my ( $lang, $vars, $varname, $wordlist ) = @_;

    my $count       = $vars->{$varname};
    my @wlist       = split( /\|/, $wordlist );
    my $plural_form = plural_form( $lang, $count );
    return $wlist[$plural_form];
}

my %PLURAL_FORMS_HANDLERS = (
    'be' => \&plural_form_ru,
    'en' => \&plural_form_en,
    'fr' => \&plural_form_fr,
    'hu' => \&plural_form_singular,
    'is' => \&plural_form_is,
    'ja' => \&plural_form_singular,
    'lt' => \&plural_form_lt,
    'lv' => \&plural_form_lv,
    'pl' => \&plural_form_pl,
    'pt' => \&plural_form_fr,
    'ru' => \&plural_form_ru,
    'tr' => \&plural_form_singular,
    'uk' => \&plural_form_ru,
);

sub plural_form {
    my ( $lang, $count ) = @_;

    my $lang_short = substr( $lang, 0, 2 );
    my $handler = $PLURAL_FORMS_HANDLERS{$lang_short} || \&plural_form_en;

    return $handler->($count);
}

# English, Danish, German, Norwegian, Swedish, Estonian, Finnish, Greek,
# Hebrew, Italian, Spanish, Esperanto
sub plural_form_en {
    my ($count) = @_;

    return 0 if $count == 1;
    return 1;
}

# French, Portugese, Brazilian Portuguese
sub plural_form_fr {
    my ($count) = @_;

    return 1 if $count > 1;
    return 0;
}

# Croatian, Czech, Russian, Slovak, Ukrainian, Belarusian
sub plural_form_ru {
    my ($count) = @_;

    return 0 if ( $count % 10 == 1 && $count % 100 != 11 );
    return 1
        if ( $count % 10 >= 2 && $count % 10 <= 4 )
        && ( $count % 100 < 10 || $count % 100 >= 20 );

    return 2;
}

# Polish
sub plural_form_pl {
    my ($count) = @_;

    return 0 if ( $count == 1 );

    return 1
        if ( $count % 10 >= 2 && $count % 10 <= 4 )
        && ( $count % 100 < 10 || $count % 100 >= 20 );

    return 2;
}

# Lithuanian
sub plural_form_lt {
    my ($count) = @_;

    return 0 if ( $count % 10 == 1 && $count % 100 != 11 );

    return 1
        if ( $count % 10 >= 2 )
        && ( $count % 100 < 10 || $count % 100 >= 20 );

    return 2;
}

# Hungarian, Japanese, Korean (not supported), Turkish
sub plural_form_singular {
    return 0;
}

# Latvian
sub plural_form_lv {
    my ($count) = @_;

    return 0 if ( $count % 10 == 1 && $count % 100 != 11 );
    return 1 if ( $count != 0 );
    return 2;
}

# Icelandic
sub plural_form_is {
    my ($count) = @_;

    return 0 if ( $count % 10 == 1 and $count % 100 != 11 );
    return 1;
}

my ( $current_language, $guessed_language, $language_scope );

sub decide_language {
    return $guessed_language if $guessed_language;

    my %existing_language =
        map { $_ => 1 } ( @LJ::LANGS, @LJ::LANGS_IN_PROGRESS, 'debug' );

    if ( LJ::is_web_context() && LJ::Request->is_inited ) {
        # 'uselang' get param goes first
        if ( my $uselang = LJ::Request->get_param('uselang') ) {
            if ( $existing_language{$uselang} ) {
                return ( $guessed_language = $uselang );
            }
        }

        # next, 'langpref' cookie
        if ( my $cookieval = LJ::Request->cookie('langpref') ) {
            my ( $lang, $mtime ) = split m{/}, $cookieval;

            if ( $existing_language{$lang} ) {
                # let BML know of mtime for backwards compatibility,
                # although it may end up not being used in case
                # this is not a BML page
                BML::note_mod_time($mtime);

                return ( $guessed_language = $lang );
            }
        }

        # if that failed, resort to Accept-Language
        if ( my $headerval = LJ::Request->header_in('Accept-Language') ) {
            my %weights;

            foreach my $langval ( split /\s*,\s*/, $headerval ) {
                my ( $lang, $weight ) = split /;q=/, $langval;

                # $lang may contain country code, remove it:
                $lang =~ s/-.*//;

                # weight may not be specified, default to 1
                $weight ||= 1.0;

                $weights{$lang} = $weight;
            }

            my @langs =
                reverse sort { $weights{$a} <=> $weights{$b} } keys %weights;

            foreach my $lang (@langs) {
                next unless $existing_language{$lang};
                return ( $guessed_language = $lang );
            }
        }

        # all else failing, default to the default language
        return ( $guessed_language = $LJ::DEFAULT_LANG );
    }

    # alright, this is not a web context, so there is little we can do,
    # but at least let's try to extract it from remote, in case
    # someone set it to whatever
    if ( my $remote = LJ::get_remote() ) {
        if ( my $lang = $remote->prop('browselang') ) {
            if ( $existing_language{$lang} ) {
                return ( $guessed_language = $lang );
            }
        }
    }

    # failing that, it's the default language, alas;
    # however, let's not cache it so that we can try remote
    # again if it's set between the calls
    return $LJ::DEFAULT_LANG;
}

sub current_language {
    my @args = @_;

    my $ret = $current_language || decide_language();

    if (@args) {
        $current_language = $args[0];
        $guessed_language = undef;
    }

    return $ret;
}

*get_effective_lang = \&current_language;

sub current_scope {
    my @args = @_;

    my $ret = $language_scope;
    if (@args) { $language_scope = $args[0]; }
    return $ret;
}

sub ml {
    my ( $code, $vars ) = @_;

    if ( current_language() eq 'debug' ) {
        return $code;
    }

    if ( $code =~ /^[.]/ ) {
        $code = current_scope() . $code;
    }

    return get_text( current_language(), $code, undef, $vars );
}

sub init_bml {
    BML::current_site('livejournal');

    BML::implementation( 'decide_language' => \&decide_language );

    BML::implementation( 'get_language' => \&current_language );
    BML::implementation( 'set_language' => \&current_language );

    BML::implementation( 'get_language_scope' => \&current_scope );
    BML::implementation( 'set_language_scope' => \&current_scope );

    BML::implementation( 'ml' => \&ml );
}

1;
