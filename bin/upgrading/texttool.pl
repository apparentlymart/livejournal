#!/usr/bin/perl
#
# This program deals with inserting/extracting text/language data
# from the database.
#

use strict;
use Getopt::Long;
use lib "$ENV{LJHOME}/cgi-bin";
use LJ::LangDatFile;

my $opt_help = 0;
my $opt_local_lang;
my $opt_only;
my $opt_verbose;
my $opt_all;    ## load texts for all known languages
my $force_override          = 0;
my $opt_force_popstruct     = 0;
my $opt_process_deadphrases = 0;
GetOptions(
    "help"                => \$opt_help,
    "local-lang=s"        => \$opt_local_lang,
    "verbose"             => \$opt_verbose,
    "only=s"              => \$opt_only,
    "all"                 => \$opt_all,
    "force-override"      => \$force_override,
    'force-popstruct'     => \$opt_force_popstruct,
    'process-deadphrases' => \$opt_process_deadphrases,
) or die "can't parse arguments";

my $mode = shift @ARGV;

help() if $opt_help or not defined $mode;

sub help {
    die "Usage: texttool.pl <command>

Where 'command' is one of:
  load         Runs the following four commands in order:
    popstruct  Populate lang data from text[-local].dat into db
    poptext    Populate text in specified languages into database.
    copyfaq    If site is translating FAQ, copy FAQ data into trans area
    loadcrumbs Load crumbs from ljcrumbs.pl and ljcrumbs-local.pl.
    makeusable Setup internal indexes necessary after loading text
  dumptext     Dump lang text based on text[-local].dat information
  check        Check validity of text[-local].dat files
  wipedb       Remove all language/text data from database, including crumbs.
  wipecrumbs   Remove all crumbs from the database, leaving other text alone.
  newitems     Search files in htdocs, cgi-bin, & bin and insert
               necessary text item codes in database.
  remove       takes two extra arguments: domain name and code, and removes
               that code and its text in all languages

Optionally:
    --local-lang=..     If given, works on local site files too

    --all
                        When loading texts, and no language is
                        specified, load all languages

    --force-override
                        Force overriding existing keys when loading texts
                        from disk.

    --force-popstruct
                        Force updating/replacing languages and language domains
                        if they are found to be unchanged

    --process-deadphrases
                        Process data found in deadphrases.dat and
                        deadphrases-local.dat; this is disabled by default
                        because these data are outdated.

Examples:
    texttool.pl load en en_LJ
    texttool.pl --all load
";
}

## make sure $LJHOME is set so we can load & run everything
unless ( -d $ENV{'LJHOME'} ) {
    die "LJHOME environment variable is not set, or is not a directory.\n"
        . "You must fix this before you can run this database update script.";
}

require 'ljlib.pl';
use LJ::Lang;
require 'weblib.pl';

my %dom_id;       # number -> {}
my %dom_code;     # name   -> {}
my %lang_id;      # number -> {}
my %lang_code;    # name   -> {}
my @lang_domains;

my $set = sub {
    my ( $hash, $key, $val, $errmsg ) = @_;
    die "$errmsg$key\n" if exists $hash->{$key};
    $hash->{$key} = $val;
};

foreach my $scope ( "general", "local" ) {
    my $file = $scope eq "general" ? "text.dat" : "text-local.dat";
    my $ffile = "$ENV{'LJHOME'}/bin/upgrading/$file";
    unless ( -e $ffile ) {
        next if $scope eq "local";
        die "$file file not found; odd: did you delete it?\n";
    }
    open( F, $ffile ) or die "Can't open file: $file: $!\n";
    while (<F>) {
        s/\s+$//;
        s/^\#.+//;
        next unless /\S/;
        my @vals = split( /:/, $_ );
        my $what = shift @vals;

        # language declaration
        if ( $what eq "lang" ) {
            my $lang = {
                'scope'      => $scope,
                'lnid'       => $vals[0],
                'lncode'     => $vals[1],
                'lnname'     => $vals[2],
                'parentlnid' => 0,          # default.  changed later.
                'parenttype' => 'diff',
            };
            $lang->{'parenttype'} = $vals[3] if defined $vals[3];
            if ( defined $vals[4] ) {
                unless ( exists $lang_code{ $vals[4] } ) {
                    die "Can't declare language $lang->{'lncode'} "
                        . "with missing parent language $vals[4].\n";
                }
                $lang->{'parentlnid'} = $lang_code{ $vals[4] }->{'lnid'};
            }
            $set->(
                \%lang_id, $lang->{'lnid'}, $lang,
                "Language already defined with ID: "
            );
            $set->(
                \%lang_code, $lang->{'lncode'}, $lang,
                "Language already defined with code: "
            );
        }

        # domain declaration
        if ( $what eq "domain" ) {
            my $dcode = $vals[1];
            my ( $type, $args ) = split( m!/!, $dcode );
            my $dom = {
                'scope' => $scope,
                'dmid'  => $vals[0],
                'type'  => $type,
                'args'  => $args || "",
            };
            $set->(
                \%dom_id, $dom->{'dmid'}, $dom,
                "Domain already defined with ID: "
            );
            $set->(
                \%dom_code, $dcode, $dom,
                "Domain already defined with parameters: "
            );
        }

        # langdomain declaration
        if ( $what eq "langdomain" ) {
            my $ld = {
                'lnid' => (
                    exists $lang_code{ $vals[0] }
                    ? $lang_code{ $vals[0] }->{'lnid'}
                    : die "Undefined language: $vals[0]\n"
                ),
                'dmid' => (
                    exists $dom_code{ $vals[1] }
                    ? $dom_code{ $vals[1] }->{'dmid'}
                    : die "Undefined domain: $vals[1]\n"
                ),
                'dmmaster' => $vals[2] ? "1" : "0",
            };
            push @lang_domains, $ld;
        }
    }
    close F;
}

if ( $mode eq "check" ) {
    print "all good.\n";
    exit 0;
}

## make sure we can connect
my $dbh = LJ::get_dbh("master");
my $sth;
unless ($dbh) {
    die "Can't connect to the database.\n";
}
$dbh->{RaiseError} = 1;

# indenter
my $idlev = 0;
my $out   = sub {
    my @args = @_;
    while (@args) {
        my $a = shift @args;
        if    ( $a eq "+" ) { $idlev++; }
        elsif ( $a eq "-" ) { $idlev--; }
        elsif ( $a eq "x" ) {
            $a = shift @args;
            die "  " x $idlev . $a . "\n";
        }
        else { print "  " x $idlev, $a, "\n"; }
    }
};

my @good = qw(
    load popstruct poptext dumptext dumptextcvs newitems wipedb
    makeusable copyfaq remove wipecrumbs loadcrumbs
);

popstruct()    if $mode eq "popstruct"  or $mode eq "load";
poptext(@ARGV) if $mode eq "poptext"    or $mode eq "load";
copyfaq()      if $mode eq "copyfaq"    or $mode eq "load";
loadcrumbs()   if $mode eq "loadcrumbs" or $mode eq "load";
makeusable()   if $mode eq "makeusable" or $mode eq "load";
dumptext( $1, @ARGV ) if $mode =~ /^dumptext(cvs)?$/;
newitems()   if $mode eq "newitems";
wipedb()     if $mode eq "wipedb";
wipecrumbs() if $mode eq "wipecrumbs";
remove(@ARGV) if $mode eq "remove" and scalar(@ARGV) == 2;
help() unless grep { $mode eq $_ } @good;
exit 0;

sub makeusable {
    $out->( "Making usable...", '+' );
    my $rec = sub {
        my ( $lang, $rec ) = @_;
        my $l = $lang_code{$lang};
        $out->( "x", "Bogus language: $lang" ) unless $l;

        my @children = sort { $a->{'lncode'} cmp $b->{'lncode'} }
            grep { $_->{'parentlnid'} == $l->{'lnid'} } values %lang_code;

        foreach my $cl (@children) {
            my %need;

            # push downwards everything that has some valid text in
            # some language (< 4)
            $sth = $dbh->prepare(
                qq{
                    SELECT dmid, itid, txtid
                    FROM ml_latest
                    WHERE lnid=$l->{'lnid'} AND staleness < 4
                }
            );
            $sth->execute;
            while ( my ( $dmid, $itid, $txtid ) = $sth->fetchrow_array ) {
                $need{"$dmid:$itid"} = $txtid;
            }

            $sth = $dbh->prepare(
                qq{
                    SELECT dmid, itid, txtid
                    FROM ml_latest
                    WHERE lnid=$cl->{'lnid'}
                }
            );
            $sth->execute;
            while ( my ( $dmid, $itid, $txtid ) = $sth->fetchrow_array ) {
                delete $need{"$dmid:$itid"};
            }

            if ( %need && !$opt_verbose ) {
                my $count = scalar keys %need;
                $out->("[$l->{'lncode'} => $cl->{'lncode'}] $count items");
            }

            foreach my $k ( sort keys %need ) {
                my ( $dmid, $itid ) = split( /:/, $k );
                my $txtid = $need{$k};
                my $stale = $cl->{'parenttype'} eq "diff" ? 3 : 0;
                $dbh->do(
                    qq{
                        INSERT INTO ml_latest
                        (lnid, dmid, itid, txtid, chgtime, staleness)
                        VALUES
                        ($cl->{'lnid'}, $dmid, $itid, $txtid, NOW(), $stale)
                    }
                );
                die $dbh->errstr if $dbh->err;

                $out->("[$l->{'lncode'} => $cl->{'lncode'}] $itid")
                    if $opt_verbose;
            }
            $rec->( $cl->{'lncode'}, $rec );
        }
    };
    $rec->( "en", $rec );
    $out->( "-",  "done." );
}

sub copyfaq {
    my $faqd = LJ::Lang::get_dom("faq");
    my $ll   = LJ::Lang::get_root_lang($faqd);
    unless ($ll) { return; }

    my $domid = $faqd->{'dmid'};

    $out->( "Copying FAQ...", '+' );

    my %existing;
    $sth = $dbh->prepare(
        qq{
            SELECT i.itcode
            FROM ml_items i, ml_latest l
            WHERE
                l.lnid=$ll->{'lnid'} AND
                l.dmid=$domid        AND
                l.itid=i.itid        AND
                i.dmid=$domid
        }
    );
    $sth->execute;
    $existing{$_} = 1 while $_ = $sth->fetchrow_array;

    # faq category
    $sth = $dbh->prepare("SELECT faqcat, faqcatname FROM faqcat");
    $sth->execute;
    while ( my ( $cat, $name ) = $sth->fetchrow_array ) {
        next if exists $existing{"cat.$cat"};
        my $opts = { 'childrenlatest' => 1 };
        LJ::Lang::set_text( $dbh, $domid, $ll->{'lncode'}, "cat.$cat", $name,
            $opts );
    }

    # faq items
    $sth = $dbh->prepare("SELECT faqid, question, answer, summary FROM faq");
    $sth->execute;
    while ( my ( $faqid, $q, $a, $s ) = $sth->fetchrow_array ) {
        next
            if exists $existing{"$faqid.1question"}
                and exists $existing{"$faqid.2answer"}
                and exists $existing{"$faqid.3summary"};
        my $opts = { 'childrenlatest' => 1 };
        LJ::Lang::set_text( $dbh, $domid, $ll->{'lncode'}, "$faqid.1question",
            $q, $opts );
        LJ::Lang::set_text( $dbh, $domid, $ll->{'lncode'}, "$faqid.2answer",
            $a, $opts );
        LJ::Lang::set_text( $dbh, $domid, $ll->{'lncode'}, "$faqid.3summary",
            $s, $opts );
    }

    $out->( '-', "done." );
}

sub wipedb {
    $out->( "Wiping DB...", '+' );
    foreach (qw(domains items langdomains langs latest text)) {
        $out->("deleting from $_");
        $dbh->do("DELETE FROM ml_$_");
    }
    $out->( "-", "done." );
}

sub wipecrumbs {
    $out->( 'Wiping DB of all crumbs...', '+' );

    # step 1: get all items that are crumbs. [from ml_items]
    my $genid = $dom_code{'general'}->{'dmid'};
    my @crumbs;
    my $sth = $dbh->prepare(
        qq{
            SELECT itcode
            FROM ml_items
            WHERE dmid = $genid AND itcode LIKE 'crumb.\%'
        }
    );
    $sth->execute;

    while ( my ($itcode) = $sth->fetchrow_array ) {

        # push onto list
        push @crumbs, $itcode;
    }

    # step 2: remove the items that have these unique dmid/itids
    foreach my $code (@crumbs) {
        $out->("deleting $code");
        remove( "general", $code );
    }

    # done
    $out->( '-', 'done.' );
}

sub loadcrumbs {
    $out->( 'Loading all crumbs into DB...', '+' );

    # get domain id of 'general' and language id of 'en'
    my $genid = $dom_code{'general'}->{'dmid'};
    my $loclang = $LJ::LANGS[0] || 'en';

    # list of crumbs
    my @crumbs;
    foreach ( keys %LJ::CRUMBS_LOCAL ) { push @crumbs, $_; }
    foreach ( keys %LJ::CRUMBS )       { push @crumbs, $_; }

    # begin iterating, order doesn't matter...
    foreach my $crumbkey (@crumbs) {
        my $crumb = LJ::get_crumb($crumbkey);
        my $local = $LJ::CRUMBS_LOCAL{$crumbkey} ? 1 : 0;

        # see if it exists
        my $itid = $dbh->selectrow_array(
            qq{
                SELECT itid
                FROM ml_items
                WHERE dmid = $genid AND itcode = 'crumb.$crumbkey'
            }
        ) + 0;

        unless ($itid) {
            $out->("inserting crumb.$crumbkey");
            my $lang = $local ? $loclang : 'en';
            LJ::Lang::set_text( $genid, $lang, "crumb.$crumbkey",
                $crumb->[0] );
        }
    }

    # done
    $out->( '-', 'done.' );
}

sub popstruct {
    $out->( "Populating structure...", '+' );

    my $languages_changed = 0;
    my $langdata          = $dbh->selectall_arrayref(
        'SELECT * FROM ml_langs',
        { 'Slice' => {} },
    );

    my %langid_present;
    foreach my $langrow (@$langdata) {
        $langid_present{ $langrow->{'lnid'} } = 1;
        my $l = $lang_id{ $langrow->{'lnid'} };

        $languages_changed ||= !$l;
        $l                 ||= {};

        foreach my $key (qw( lncode lnname parenttype parentlnid )) {
            $languages_changed ||= ( $l->{$key} ne $langrow->{$key} );
        }

        last if $languages_changed;
    }

    if ( grep { !$langid_present{$_} } keys %lang_id ) {
        $languages_changed = 1;
    }

    if ( $languages_changed || $opt_force_popstruct ) {
        $out->( 'Languages:', '+' );
        foreach my $l ( values %lang_id ) {
            $out->("$l->{'lnname'} (lncode=$l->{'lncode'})");
            $dbh->do(
                qq{
                    REPLACE INTO ml_langs
                    (lnid, lncode, lnname, parenttype, parentlnid)
                    VALUES (?, ?, ?, ?, ?)
                }, undef,
                $l->{'lnid'},       $l->{'lncode'}, $l->{'lnname'},
                $l->{'parenttype'}, $l->{'parentlnid'},
            );
        }
        $out->('-');
    }
    else {
        $out->(   'Languages seem to be unchanged, not changing '
                . 'anything without --force-popstruct' );
    }

    my $domains_changed = 0;
    my $domdata         = $dbh->selectall_arrayref(
        'SELECT * FROM ml_domains',
        { 'Slice' => {} },
    );

    my %domid_present;
    foreach my $domrow (@$domdata) {
        $domid_present{ $domrow->{'dmid'} } = 1;
        my $l = $dom_id{ $domrow->{'dmid'} };

        $domains_changed ||= !$l;
        $l               ||= {};

        foreach my $key (qw( type args )) {
            $domains_changed ||= ( $l->{$key} ne $domrow->{$key} );
        }

        last if $domains_changed;
    }

    if ( grep { !$domid_present{$_} } keys %dom_id ) {
        $domains_changed = 1;
    }

    if ( $domains_changed || $opt_force_popstruct ) {
        $out->( 'Domains:', '+' );
        foreach my $d ( values %dom_id ) {
            $out->("$d->{'type'}\[$d->{'args'}\]");
            $dbh->do(
                'REPLACE INTO ml_domains (dmid, type, args) VALUES (?, ?, ?)',
                undef, $d->{'dmid'}, $d->{'type'}, $d->{'args'},
            );
        }
        $out->('-');
    }
    else {
        $out->(   'Domains seem to be unchanged, not changing '
                . 'anything without --force-popstruct' );
    }

    $out->('Inserting/updating language domains ...');
    foreach my $ld (@lang_domains) {
        $dbh->do(
            qq{
                INSERT IGNORE INTO ml_langdomains
                (lnid, dmid, dmmaster)
                VALUES (?, ?, ?)
            }, undef,
            $ld->{'lnid'}, $ld->{'dmid'}, $ld->{'dmmaster'}
        );
    }
    $out->( "-", "done." );
}

sub poptext {
    my @langs = @_;
    unless (@langs) {
        if ($opt_all) {
            @langs = keys %lang_code;
        }
        else {
            die "No languages to load are specified.\n"
                . "Warning: most language files except en.dat "
                . "and en_LJ.dat are obsolete.\n"
                . "Either run 'texttool.pl load en en_LJ' to "
                . "load up-to-date files,\n"
                . "or 'texttool.pl --all load' if you really want "
                . "to load texts in all languages.\n";
        }
    }

    $out->('Populating text (reading all these files may take a while)...');
    $out->('  hint: --verbose will output filenames') unless $opt_verbose;
    $out->('+');

    # learn about base files
    my %source;    # langcode -> absfilepath
    foreach my $lang (@langs) {
        my $file = "$ENV{'LJHOME'}/bin/upgrading/${lang}.dat";
        next if $opt_only && $lang ne $opt_only;
        next unless -e $file;
        $source{$file} = [ $lang, '', "bin/upgrading/${lang}.dat" ];
    }

    # learn about local files
    chdir "$ENV{LJHOME}" or die "Failed to chdir to \$LJHOME.\n";
    my @textfiles = `find htdocs/ -name '*.text' -or -name '*.text.local'`;
    chomp @textfiles;
    foreach my $tf (@textfiles) {
        my $is_local = $tf =~ /\.local$/;
        my $lang = "en";
        if ($is_local) {
            $lang = $LJ::DEFAULT_LANG;
            die "uh, what is this .local file?" unless $lang ne "en";
        }
        my $pfx = $tf;
        $pfx =~ s!^htdocs/!!;
        $pfx =~ s!\.text(\.local)?$!!;
        $pfx = "/$pfx";
        $source{"$ENV{'LJHOME'}/$tf"} = [ $lang, $pfx, $tf ];
    }

    my %existing_item;    # langid -> code -> 1

    foreach my $file ( sort keys %source ) {
        my ( $lang, $pfx, $filename_short ) = @{ $source{$file} };

        $out->("reading $filename_short...") if $opt_verbose;
        my $ldf = LJ::LangDatFile->new($file);

        my $l = $lang_code{$lang} or die "unknown language '$lang'";

        my $addcount = 0;

        my $msgprefix = "[$filename_short, lang=$lang]";

        $ldf->foreach_key(
            sub {
                my $code = shift;

                my %metadata = $ldf->meta($code);
                my $text     = $ldf->value($code);

                if ( $code =~ /^[.]/ ) {
                    unless ($pfx) {
                        die "Code in file $filename_short can't start "
                            . "with a dot: $code";
                    }

                    $code = "$pfx$code";
                }

                # load existing items for target language
                unless ( exists $existing_item{ $l->{'lnid'} } ) {
                    $existing_item{ $l->{'lnid'} } = {};
                    my $sth = $dbh->prepare(
                        qq{
                            SELECT i.itcode, t.text
                            FROM ml_latest l, ml_items i, ml_text t
                            WHERE
                                i.dmid  = 1       AND
                                l.dmid  = 1       AND
                                i.itid  = l.itid  AND
                                l.lnid  = ?       AND
                                t.lnid  = l.lnid  AND
                                t.txtid = l.txtid AND
                                i.dmid  = i.dmid  AND
                                t.dmid  = i.dmid
                        }
                    );
                    $sth->execute( $l->{lnid} );
                    die $sth->errstr if $sth->err;
                    while ( my ( $code, $oldtext ) = $sth->fetchrow_array ) {
                        $existing_item{ $l->{'lnid'} }->{ lc($code) } =
                            $oldtext;
                    }
                }

                # Remove last '\r' char from loaded from files
                # text before compare. In database text stored
                # without this '\r', LJ::Lang::set_text remove
                # it before update database.
                $text =~ s/\r//;

                ## do not update existing texts in DB by default.
                ## --force-override flag allows to disable this restriction.
                return
                    if exists $existing_item{ $l->{'lnid'} }->{$code}
                        and not $force_override;

                my $old_text = $existing_item{ $l->{'lnid'} }->{$code};

                unless ( $old_text eq $text ) {
                    $addcount++;
                    if ($old_text) {
                        $out->("$msgprefix $code: $old_text => $text");
                    }
                    else {
                        $out->("$msgprefix $code: setting to $text");
                    }

                    # if the text is changing, the staleness is at least 1
                    my $staleness = $metadata{'staleness'} + 0 || 1;

                    my $res = LJ::Lang::set_text(
                        1,
                        $l->{'lncode'},
                        $code, $text,
                        {   'staleness'      => $staleness,
                            'notes'          => $metadata{'notes'},
                            'changeseverity' => 2,
                            'userid'         => 0,
                        }
                    );

                    unless ($res) {
                        $out->( 'x', "ERROR: " . LJ::Lang::last_error() );
                    }
                }
            }
        );

        if ( $addcount > 0 ) {
            $out->("added $addcount from $filename_short");
        }
    }
    $out->( "-", "done." );

    # dead phrase removal
    if ($opt_process_deadphrases) {
        $out->( "Removing dead phrases...", '+' );
        foreach my $file ( "deadphrases.dat", "deadphrases-local.dat" ) {
            my $ffile = "$ENV{'LJHOME'}/bin/upgrading/$file";
            next unless -s $ffile;
            $out->("File: $file");
            open( DP, $ffile ) or die;
            while ( my $li = <DP> ) {
                $li =~ s/\#.*//;
                next unless $li =~ /\S/;
                $li =~ s/\s+$//;
                my ( $dom, $it ) = split( /\s+/, $li );
                next unless exists $dom_code{$dom};
                my $dmid = $dom_code{$dom}->{'dmid'};

                my @items;
                if ( $it =~ s/\*$/\%/ ) {
                    my $sth = $dbh->prepare(
                        qq{
                            SELECT itcode
                            FROM ml_items
                            WHERE dmid=? AND itcode LIKE ?
                        }
                    );
                    $sth->execute( $dmid, $it );
                    push @items, $_ while $_ = $sth->fetchrow_array;
                }
                else {
                    @items = ($it);
                }

                foreach (@items) {
                    remove( $dom, $_, 1 );
                }
            }
            close DP;
        }
        $out->( '-', "Done." );
    }
}

sub dumptext {
    my $to_cvs = shift;
    my @langs  = @_;
    unless (@langs) { @langs = keys %lang_code; }

    $out->( 'Dumping text...', '+' );
    foreach my $lang (@langs) {
        $out->("$lang");
        my $l = $lang_code{$lang};

        my %fh_map = ();    # filename => filehandle

        # the part "t.lnid=$l->{'lnid'}" is added to ensure that
        # we only export mappings that aren't inherited
        my $sth = $dbh->prepare(
            qq{
                SELECT i.itcode, t.text, l.staleness, i.notes
                FROM ml_items i, ml_latest l, ml_text t
                WHERE
                    l.lnid=$l->{'lnid'} AND
                    l.dmid=1            AND
                    i.dmid=1            AND
                    l.itid=i.itid       AND
                    t.dmid=1            AND
                    t.txtid=l.txtid     AND
                    t.lnid=$l->{'lnid'}
                ORDER BY i.itcode
            }
        );
        $sth->execute;
        die $dbh->errstr if $dbh->err;

        my $writeline = sub {
            my ( $fh, $k, $v ) = @_;

            # kill any \r since they shouldn't be there anyway
            $v =~ s/\r//g;

            # print to .dat file
            if ( $v =~ /\n/ ) {
                $v =~ s/\n\./\n\.\./g;
                print $fh "$k<<\n$v\n.\n";
            }
            else {
                print $fh "$k=$v\n";
            }
        };

        while ( my ( $itcode, $text, $staleness, $notes ) =
            $sth->fetchrow_array )
        {
            if ( $itcode =~ m!\.bml/! || $itcode =~ /[\s=]/ ) {
                warn "Skipping item code '$itcode'";
                next;
            }

            my $langdat_file =
                LJ::Lang::langdat_file_of_lang_itcode( $lang, $itcode,
                $to_cvs );
            $itcode =
                LJ::Lang::itcode_for_langdat_file( $langdat_file, $itcode );

            my $fh = $fh_map{$langdat_file};
            unless ($fh) {

                # the dir might not exist in some cases, so if it doesn't
                # we'll create a zero-byte file to overwrite
                # -- yeah, this is really gross
                unless ( -e $langdat_file ) {
                    system( "install", "-D", "/dev/null", $langdat_file );
                }

                my $openres = open( $fh, ">$langdat_file" );
                unless ($openres) {
                    die "unable to open langdat file: "
                        . "$langdat_file ($lang, $itcode, $to_cvs, $!)";
                }

                $fh_map{$langdat_file} = $fh;

                # print utf-8 encoding header
                $fh->print(";; -*- coding: utf-8 -*-\n");
            }

            $writeline->( $fh, "$itcode|staleness", $staleness )
                if $staleness;
            $writeline->( $fh, "$itcode|notes", $notes )
                if $notes =~ /\S/;
            $writeline->( $fh, $itcode, $text );

            # newline between record sets
            print $fh "\n";
        }

        # close filehandles now
        foreach my $file ( keys %fh_map ) {
            close $fh_map{$file} or die "unable to close: $file ($!)";
        }
    }
    $out->( '-', 'done.' );
}

sub newitems {
    $out->( "Searching for referenced text codes...", '+' );
    my $top = $ENV{'LJHOME'};
    my @files;
    push @files, qw(htdocs cgi-bin bin);
    my %items;    # $scope -> $key -> 1;
    while (@files) {
        my $file  = shift @files;
        my $ffile = "$top/$file";
        next unless -e $ffile;
        if ( -d $ffile ) {
            $out->("dir: $file");
            opendir( MD, $ffile ) or die "Can't open $file";
            while ( my $f = readdir(MD) ) {
                next
                    if $f eq "."
                        || $f eq ".."
                        || $f =~ /^\.\#/
                        || $f =~ /(\.png|\.gif|~|\#)$/;
                unshift @files, "$file/$f";
            }
            closedir MD;
        }
        if ( -f $ffile ) {
            my $scope = "local";
            $scope = "general" if -e "$top/cvs/livejournal/$file";

            open( F, $ffile ) or die "Can't open $file";
            my $line = 0;
            while (<F>) {
                $line++;
                while (/BML::ml\([\"\'](.+?)[\"\']/g) {
                    $items{$scope}->{$1} = 1;
                }
                while (/\(=_ML\s+(.+?)\s+_ML=\)/g) {
                    my $code = $1;
                    if ( $code =~ /^\./ && $file =~ m!^htdocs/! ) {
                        $code = "$file$code";
                        $code =~ s!^htdocs!!;
                    }
                    $items{$scope}->{$code} = 1;
                }
            }
            close F;
        }
    }

    $out->(
        sprintf(
            "%d general and %d local found.",
            scalar keys %{ $items{'general'} },
            scalar keys %{ $items{'local'} }
        )
    );

    # [ General ]
    my %e_general;    # code -> 1
    $out->("Checking which general items already exist in database...");
    my $sth = $dbh->prepare(
        qq{
            SELECT i.itcode
            FROM ml_items i, ml_latest l
            WHERE l.dmid=1 AND l.lnid=1 AND i.dmid=1 AND i.itid=l.itid
        }
    );
    $sth->execute;

    while ( my $it = $sth->fetchrow_array ) { $e_general{$it} = 1; }
    $out->( sprintf( "%d found", scalar keys %e_general ) );

    foreach my $it ( keys %{ $items{'general'} } ) {
        next if exists $e_general{$it};
        my $res =
            LJ::Lang::set_text( $dbh, 1, "en", $it, undef,
            { 'staleness' => 4 } );
        $out->("Adding general: $it ... $res");
    }

    if ($opt_local_lang) {
        my $ll = $lang_code{$opt_local_lang};
        die "Bogus --local-lang argument\n" unless $ll;
        die "Local-lang '$ll->{'lncode'}' parent isn't 'en'\n"
            unless $ll->{'parentlnid'} == 1;
        $out->("Checking which local items already exist in database...");

        my %e_local;
        $sth = $dbh->prepare(
            qq{
                SELECT i.itcode
                FROM ml_items i, ml_latest l
                WHERE
                    l.dmid=1             AND
                    l.lnid=$ll->{'lnid'} AND
                    i.dmid=1             AND
                    i.itid=l.itid
            }
        );
        $sth->execute;
        while ( my $it = $sth->fetchrow_array ) { $e_local{$it} = 1; }
        $out->( sprintf( "%d found\n", scalar keys %e_local ) );

        foreach my $it ( keys %{ $items{'local'} } ) {
            next if exists $e_general{$it};
            next if exists $e_local{$it};
            my $res =
                LJ::Lang::set_text( $dbh, 1, $ll->{'lncode'}, $it, undef,
                { 'staleness' => 4 } );
            $out->("Adding local: $it ... $res");
        }
    }
    $out->( '-', 'done.' );
}

sub remove {
    my ( $dmcode, $itcode, $no_error ) = @_;
    my $dmid;
    if ( exists $dom_code{$dmcode} ) {
        $dmid = $dom_code{$dmcode}->{'dmid'};
    }
    else {
        $out->( "x", "Unknown domain code $dmcode." );
    }

    my $qcode = $dbh->quote($itcode);
    my $itid  = $dbh->selectrow_array(
        "SELECT itid FROM ml_items WHERE dmid=$dmid AND itcode=$qcode");
    return if $no_error && !$itid;
    $out->( "x", "Unknown item code $itcode." ) unless $itid;

    # need to delete everything from: ml_items ml_latest ml_text

    my $affected =
        $dbh->do("DELETE FROM ml_items WHERE dmid=$dmid AND itid=$itid");

    # we're only outputting something if this is something
    # significant, according to ml_items
    if ( $affected > 0 ) {
        $out->("Removing item $itcode from domain $dmcode ($itid)...");
    }

    my $txtids = "";
    my $sth    = $dbh->prepare(
        "SELECT txtid FROM ml_latest WHERE dmid=$dmid AND itid=$itid");
    $sth->execute;
    while ( my $txtid = $sth->fetchrow_array ) {
        $txtids .= "," if $txtids;
        $txtids .= $txtid;
    }
    $dbh->do("DELETE FROM ml_latest WHERE dmid=$dmid AND itid=$itid");
    $dbh->do("DELETE FROM ml_text WHERE dmid=$dmid AND txtid IN ($txtids)")
        if $txtids;
}
