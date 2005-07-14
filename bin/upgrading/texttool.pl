#!/usr/bin/perl
#
# This program deals with inserting/extracting text/language data
# from the database.
#

use strict;
use Getopt::Long;

my $opt_help = 0;
my $opt_local_lang;
my $opt_extra;
my $opt_only;
my $opt_override;
my $opt_verbose;
exit 1 unless
GetOptions(
           "help" => \$opt_help,
           "local-lang=s" => \$opt_local_lang,
           "extra=s" => \$opt_extra,
           "override|r" => \$opt_override,
           "verbose" => \$opt_verbose,
           "only=s" => \$opt_only,
           );

my $mode = shift @ARGV;

help() if $opt_help or not defined $mode;

sub help
{
    die "Usage: texttool.pl <command>

Where 'command' is one of:
  load         Runs the following four commands in order:
    popstruct  Populate lang data from text[-local].dat into db
    poptext    Populate text from en.dat, etc into database.
               --extra=<file> specifies an alternative input file
               --override (-v) specifies existing values should be overwritten
                               for all languages.  (for developer use only)
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
                  --local-lang=..  If given, works on local site files too

";
}

## make sure $LJHOME is set so we can load & run everything
unless (-d $ENV{'LJHOME'}) {
    die "LJHOME environment variable is not set, or is not a directory.\n".
        "You must fix this before you can run this database update script.";
}
require "$ENV{'LJHOME'}/cgi-bin/ljlib.pl";
require "$ENV{'LJHOME'}/cgi-bin/ljlang.pl";
require "$ENV{'LJHOME'}/cgi-bin/weblib.pl";

my %dom_id;     # number -> {}
my %dom_code;   # name   -> {}
my %lang_id;    # number -> {}
my %lang_code;  # name   -> {}
my @lang_domains; 

my $set = sub {
    my ($hash, $key, $val, $errmsg) = @_;
    die "$errmsg$key\n" if exists $hash->{$key};
    $hash->{$key} = $val;
};

foreach my $scope ("general", "local")
{
    my $file = $scope eq "general" ? "text.dat" : "text-local.dat";
    my $ffile = "$ENV{'LJHOME'}/bin/upgrading/$file";
    unless (-e $ffile) {
        next if $scope eq "local";
        die "$file file not found; odd: did you delete it?\n";
    }
    open (F, $ffile) or die "Can't open file: $file: $!\n";
    while (<F>) {
        s/\s+$//; s/^\#.+//;
        next unless /\S/;
        my @vals = split(/:/, $_);
        my $what = shift @vals;

        # language declaration
        if ($what eq "lang") {
            my $lang = { 
                'scope'  => $scope,
                'lnid'   => $vals[0],
                'lncode' => $vals[1],
                'lnname' => $vals[2],
                'parentlnid' => 0,   # default.  changed later.
                'parenttype' => 'diff',
            };
            $lang->{'parenttype'} = $vals[3] if defined $vals[3];
            if (defined $vals[4]) {
                unless (exists $lang_code{$vals[4]}) {
                    die "Can't declare language $lang->{'lncode'} with missing parent language $vals[4].\n";
                }
                $lang->{'parentlnid'} = $lang_code{$vals[4]}->{'lnid'};
            }
            $set->(\%lang_id,   $lang->{'lnid'},   $lang, "Language already defined with ID: ");
            $set->(\%lang_code, $lang->{'lncode'}, $lang, "Language already defined with code: ");
        }

        # domain declaration
        if ($what eq "domain") {
            my $dcode = $vals[1];
            my ($type, $args) = split(m!/!, $dcode);
            my $dom = {
                'scope' => $scope,
                'dmid' => $vals[0],
                'type' => $type,
                'args' => $args || "",
            };
            $set->(\%dom_id,   $dom->{'dmid'}, $dom, "Domain already defined with ID: ");
            $set->(\%dom_code, $dcode, $dom, "Domain already defined with parameters: ");
        }

        # langdomain declaration
        if ($what eq "langdomain") {
            my $ld = {
                'lnid' => 
                    (exists $lang_code{$vals[0]} ? $lang_code{$vals[0]}->{'lnid'} : 
                     die "Undefined language: $vals[0]\n"),
                'dmid' =>
                    (exists $dom_code{$vals[1]} ? $dom_code{$vals[1]}->{'dmid'} : 
                     die "Undefined domain: $vals[1]\n"),
                'dmmaster' => $vals[2] ? "1" : "0",
                };
            push @lang_domains, $ld;
        }
    }
    close F;
}

if ($mode eq "check") {
    print "all good.\n";
    exit 0;
}

## make sure we can connect
my $dbh = LJ::get_dbh("master");
my $sth;
unless ($dbh) {
    die "Can't connect to the database.\n";
}

# indenter
my $idlev = 0;
my $out = sub {
    my @args = @_;
    while (@args) {
        my $a = shift @args;
        if ($a eq "+") { $idlev++; }
        elsif ($a eq "-") { $idlev--; }
        elsif ($a eq "x") { $a = shift @args; die "  "x$idlev . $a . "\n"; }
        else { print "  "x$idlev, $a, "\n"; }
    }
};

my @good = qw(load popstruct poptext dumptext newitems wipedb makeusable copyfaq remove
              wipecrumbs loadcrumbs);

popstruct() if $mode eq "popstruct" or $mode eq "load";
poptext(@ARGV) if $mode eq "poptext" or $mode eq "load";
copyfaq() if $mode eq "copyfaq" or $mode eq "load";
loadcrumbs() if $mode eq "loadcrumbs" or $mode eq "load";
makeusable() if $mode eq "makeusable" or $mode eq "load";
dumptext(@ARGV) if $mode eq "dumptext";
newitems() if $mode eq "newitems";
wipedb() if $mode eq "wipedb";
wipecrumbs() if $mode eq "wipecrumbs";
remove(@ARGV) if $mode eq "remove" and scalar(@ARGV) == 2;
help() unless grep { $mode eq $_ } @good;
exit 0;

sub makeusable
{
    $out->("Making usable...", '+');
    my $rec = sub {
        my ($lang, $rec) = @_;
        my $l = $lang_code{$lang};
        $out->("x", "Bogus language: $lang") unless $l;
        my @children = grep { $_->{'parentlnid'} == $l->{'lnid'} } values %lang_code;
        foreach my $cl (@children) {
            $out->("$l->{'lncode'} -- $cl->{'lncode'}");

            my %need;
            # push downwards everything that has some valid text in some language (< 4)
            $sth = $dbh->prepare("SELECT dmid, itid, txtid FROM ml_latest WHERE lnid=$l->{'lnid'} AND staleness < 4");
            $sth->execute;
            while (my ($dmid, $itid, $txtid) = $sth->fetchrow_array) {
                $need{"$dmid:$itid"} = $txtid;
            }
            $sth = $dbh->prepare("SELECT dmid, itid, txtid FROM ml_latest WHERE lnid=$cl->{'lnid'}");
            $sth->execute;
            while (my ($dmid, $itid, $txtid) = $sth->fetchrow_array) {
                delete $need{"$dmid:$itid"};
            }
            while (my $k = each %need) {
                my ($dmid, $itid) = split(/:/, $k);
                my $txtid = $need{$k};
                my $stale = $cl->{'parenttype'} eq "diff" ? 3 : 0;
                $dbh->do("INSERT INTO ml_latest (lnid, dmid, itid, txtid, chgtime, staleness) VALUES ".
                         "($cl->{'lnid'}, $dmid, $itid, $txtid, NOW(), $stale)");
                die $dbh->errstr if $dbh->err;
            }
            $rec->($cl->{'lncode'}, $rec);
        }
    };
    $rec->("en", $rec);
    $out->("-", "done.");
}

sub copyfaq
{
    my $faqd = LJ::Lang::get_dom("faq");
    my $ll = LJ::Lang::get_root_lang($faqd);
    unless ($ll) { return; }

    my $domid = $faqd->{'dmid'};

    $out->("Copying FAQ...", '+');

    my %existing;
    $sth = $dbh->prepare("SELECT i.itcode FROM ml_items i, ml_latest l ".
                         "WHERE l.lnid=$ll->{'lnid'} AND l.dmid=$domid AND l.itid=i.itid AND i.dmid=$domid");
    $sth->execute;
    $existing{$_} = 1 while $_ = $sth->fetchrow_array;

    # faq category
    $sth = $dbh->prepare("SELECT faqcat, faqcatname FROM faqcat");
    $sth->execute;
    while (my ($cat, $name) = $sth->fetchrow_array) {
        next if exists $existing{"cat.$cat"};
        my $opts = { 'childrenlatest' => 1 };
        LJ::Lang::set_text($dbh, $domid, $ll->{'lncode'}, "cat.$cat", $name, $opts);
    }

    # faq items
    $sth = $dbh->prepare("SELECT faqid, question, answer, summary FROM faq");
    $sth->execute;
    while (my ($faqid, $q, $a, $s) = $sth->fetchrow_array) {
        next if
            exists $existing{"$faqid.1question"} and
            exists $existing{"$faqid.2answer"} and
            exists $existing{"$faqid.3summary"};
        my $opts = { 'childrenlatest' => 1 };
        LJ::Lang::set_text($dbh, $domid, $ll->{'lncode'}, "$faqid.1question", $q, $opts);
        LJ::Lang::set_text($dbh, $domid, $ll->{'lncode'}, "$faqid.2answer", $a, $opts);
        LJ::Lang::set_text($dbh, $domid, $ll->{'lncode'}, "$faqid.3summary", $s, $opts);
    }

    $out->('-', "done.");
}

sub wipedb
{
    $out->("Wiping DB...", '+');
    foreach (qw(domains items langdomains langs latest text)) {
        $out->("deleting from $_");
        $dbh->do("DELETE FROM ml_$_");
    }
    $out->("-", "done.");
}

sub wipecrumbs
{
    $out->('Wiping DB of all crumbs...', '+');
    
    # step 1: get all items that are crumbs. [from ml_items]
    my $genid = $dom_code{'general'}->{'dmid'};
    my @crumbs;
    my $sth = $dbh->prepare("SELECT itcode FROM ml_items 
                             WHERE dmid = $genid AND itcode LIKE 'crumb.\%'");
    $sth->execute;
    while (my ($itcode) = $sth->fetchrow_array) {
        # push onto list
        push @crumbs, $itcode;
    }

    # step 2: remove the items that have these unique dmid/itids
    foreach my $code (@crumbs) {
        $out->("deleting $code");
        remove("general", $code);
    }

    # done
    $out->('-', 'done.');
}

sub loadcrumbs
{
    $out->('Loading all crumbs into DB...', '+');

    # get domain id of 'general' and language id of 'en'
    my $genid = $dom_code{'general'}->{'dmid'};
    my $loclang = $LJ::LANGS[0] || 'en';

    # list of crumbs
    my @crumbs;
    foreach (keys %LJ::CRUMBS_LOCAL) { push @crumbs, $_; }
    foreach (keys %LJ::CRUMBS) { push @crumbs, $_; }

    # begin iterating, order doesn't matter...
    foreach my $crumbkey (@crumbs) {
        $out->("inserting crumb.$crumbkey");
        my $crumb = LJ::get_crumb($crumbkey);
        my $local = $LJ::CRUMBS_LOCAL{$crumbkey} ? 1 : 0;
        
        # see if it exists
        my $itid = $dbh->selectrow_array("SELECT itid FROM ml_items
                                          WHERE dmid = $genid AND itcode = 'crumb.$crumbkey'")+0;
        LJ::Lang::set_text($genid, $local ? $loclang : 'en', "crumb.$crumbkey", $crumb->[0])
            unless $itid;
    }

    # done
    $out->('-', 'done.');
}

sub popstruct
{
    $out->("Populating structure...", '+');
    foreach my $l (values %lang_id) {
        $out->("Inserting language: $l->{'lnname'}");
        $dbh->do("INSERT INTO ml_langs (lnid, lncode, lnname, parenttype, parentlnid) ".
                 "VALUES (" . join(",", map { $dbh->quote($l->{$_}) } qw(lnid lncode lnname parenttype parentlnid)) . ")");
    }

    foreach my $d (values %dom_id) {
        $out->("Inserting domain: $d->{'type'}\[$d->{'args'}\]");
        $dbh->do("INSERT INTO ml_domains (dmid, type, args) ".
                 "VALUES (" . join(",", map { $dbh->quote($d->{$_}) } qw(dmid type args)) . ")");
    }

    $out->("Inserting language domains ...");
    foreach my $ld (@lang_domains) {
        $dbh->do("INSERT IGNORE INTO ml_langdomains (lnid, dmid, dmmaster) VALUES ".
                 "(" . join(",", map { $dbh->quote($ld->{$_}) } qw(lnid dmid dmmaster)) . ")");
    }
    $out->("-", "done.");
}

sub poptext
{
    my @langs = @_;
    push @langs, (keys %lang_code) unless @langs;

    $out->("Populating text...", '+');
    my %source;  # lang -> file, or "[extra]" when given by --extra= argument
    if ($opt_extra) {
        $source{'[extra]'} = $opt_extra;
    } else {
        foreach my $lang (@langs) {
            my $file = "$ENV{'LJHOME'}/bin/upgrading/${lang}.dat";
            next if $opt_only && $lang ne $opt_only;
            next unless -e $file;
            $source{$lang} = $file;            
        }
    }

    my %existing_item;  # langid -> code -> 1

    foreach my $source (keys %source)
    {
        $out->("$source", '+');
        my $file = $source{$source};
        open (D, $file)
            or $out->('x', "Can't open $source data file");

        # fixed language in *.dat files, but in extra files
        # it switches as it goes.
        my $l;
        if ($source ne "[extra]") { $l = $lang_code{$source}; }

        my $bml_prefix = "";

        my $addcount = 0;
        my $lnum = 0;
        my ($code, $text);
        my %metadata;
        while (my $line = <D>) {
            $lnum++;
            my $del;
            my $action_line;

            if ($line =~ /^==(LANG|BML):\s*(\S+)/) {
                $out->('x', "Bogus directives in non-extra file.")
                    if $source ne "[extra]";
                my ($what, $val) = ($1, $2);
                if ($what eq "LANG") {
                    $l = $lang_code{$val};
                    $out->('x', 'Bogus ==LANG switch to: $what') unless $l;
                    $bml_prefix = "";
                } elsif ($what eq "BML") {
                    $out->('x', 'Bogus ==BML switch to: $what') 
                        unless $val =~ m!^/.+\.bml$!;
                    $bml_prefix = $val;
                }
            } elsif ($line =~ /^(\S+?)=(.*)/) {
                ($code, $text) = ($1, $2);
                $action_line = 1;
            } elsif ($line =~ /^\!\s*(\S+)/) {
                $del = $code;
                $action_line = 1;
            } elsif ($line =~ /^(\S+?)\<\<\s*$/) {
                ($code, $text) = ($1, "");
                while (<D>) {
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
                $out->('x', "$source:$lnum: Bogus format.");
            }

            if ($code =~ m!^\.!) {
                $out->('x', "Can't use code with leading dot: $code")
                    unless $bml_prefix;
                $code = "$bml_prefix$code";
            }

            if ($code =~ /\|(.+)/) {
                $metadata{$1} = $text;
                next;
            }

            next unless $action_line;

            $out->('x', 'No language defined!') unless $l;

            # load existing items for target language
            unless (exists $existing_item{$l->{'lnid'}}) {
                $existing_item{$l->{'lnid'}} = {};
                my $sth = $dbh->prepare(qq{
                    SELECT i.itcode
                    FROM ml_latest l, ml_items i
                    WHERE i.dmid=1 AND l.dmid=1 AND i.itid=l.itid AND l.lnid=$l->{'lnid'}
                });
                $sth->execute;
                $existing_item{$l->{'lnid'}}->{$_} = 1
                    while $_ = $sth->fetchrow_array;
            }

            # do deletes
            if (defined $del) {
                remove("general", $del) 
                    if delete $existing_item{$l->{'lnid'}}->{$del};
                next;
            }

            # if override is set (development option) then delete
            if ($opt_override && $existing_item{$l->{'lnid'}}->{$code}) {
                remove("general", $code);
                delete $existing_item{$l->{'lnid'}}->{$code};
            }

            unless ($existing_item{$l->{'lnid'}}->{$code}) {
                $addcount++;
                my $staleness = $metadata{'staleness'}+0;
                my $res = LJ::Lang::set_text($dbh, 1, $l->{'lncode'}, $code, $text,
                                             { 'staleness' => $staleness,
                                               'notes' => $metadata{'notes'}, });
                $out->("set: $code") if $opt_verbose;
                unless ($res) {
                    $out->('x', "ERROR: " . LJ::Lang::last_error());
                }
            }
            %metadata = ();
        }
        close D;
        $out->("added: $addcount", '-');
    }
    $out->("-", "done.");

    # dead phrase removal
    $out->("Removing dead phrases...", '+');
    foreach my $file ("deadphrases.dat", "deadphrases-local.dat") {
        my $ffile = "$ENV{'LJHOME'}/bin/upgrading/$file";
        next unless -s $ffile;
        $out->("File: $file");
        open (DP, $ffile) or die;
        while (my $li = <DP>) {
            $li =~ s/\#.*//;
            next unless $li =~ /\S/;
            $li =~ s/\s+$//;
            my ($dom, $it) = split(/\s+/, $li);
            next unless exists $dom_code{$dom};
            my $dmid = $dom_code{$dom}->{'dmid'};
            
            my @items;
            if ($it =~ s/\*$/\%/) {
                my $sth = $dbh->prepare("SELECT itcode FROM ml_items WHERE dmid=? AND itcode LIKE ?");
                $sth->execute($dmid, $it);
                push @items, $_ while $_ = $sth->fetchrow_array;
            } else {
                @items = ($it);
            }
            foreach (@items) {
                remove($dom, $_, 1);
            }
        }
        close DP;
    }
    $out->('-', "Done.");
}

sub dumptext
{
    my @langs = @_;
    unless (@langs) { @langs = keys %lang_code; }

    $out->('Dumping text...', '+');
    foreach my $lang (@langs)
    {
        $out->("$lang");
        my $l = $lang_code{$lang};
        open (D, ">$ENV{'LJHOME'}/bin/upgrading/${lang}.dat")
            or $out->('x', "Can't open $lang.dat");
        print D ";; -*- coding: utf-8 -*-\n";
        my $sth = $dbh->prepare("SELECT i.itcode, t.text, l.staleness, i.notes FROM ".
                                "ml_items i, ml_latest l, ml_text t ".
                                "WHERE l.lnid=$l->{'lnid'} AND l.dmid=1 ".
                                "AND i.dmid=1 AND l.itid=i.itid AND ".
                                "t.dmid=1 AND t.txtid=l.txtid AND ".
                                # only export mappings that aren't inherited:
                                "t.lnid=$l->{'lnid'} ".
                                "ORDER BY i.itcode");
        $sth->execute;
        die $dbh->errstr if $dbh->err;
        my $writeline = sub {
            my ($k, $v) = @_;
            if ($v =~ /\n/) {
                $v =~ s/\n\./\n\.\./g;
                print D "$k<<\n$v\n.\n";
            } else {
                print D "$k=$v\n";
            }
        };
        while (my ($itcode, $text, $staleness, $notes) = $sth->fetchrow_array) {
            $writeline->("$itcode|staleness", $staleness)
                if $staleness;
            $writeline->("$itcode|notes", $notes)
                if $notes =~ /\S/;
            $writeline->($itcode, $text);
            print D "\n";
        }
        close D;
    }
    $out->('-', 'done.');
}

sub newitems
{
    $out->("Searching for referenced text codes...", '+');
    my $top = $ENV{'LJHOME'};
    my @files;
    push @files, qw(htdocs cgi-bin bin);
    my %items;  # $scope -> $key -> 1;
    while (@files)
    {
        my $file = shift @files;
        my $ffile = "$top/$file";
        next unless -e $ffile;
        if (-d $ffile) {
            $out->("dir: $file");
            opendir (MD, $ffile) or die "Can't open $file";
            while (my $f = readdir(MD)) {
                next if $f eq "." || $f eq ".." || 
                    $f =~ /^\.\#/ || $f =~ /(\.png|\.gif|~|\#)$/;
                unshift @files, "$file/$f";
            }
            closedir MD;
        }
        if (-f $ffile) {
            my $scope = "local";
            $scope = "general" if -e "$top/cvs/livejournal/$file";

            open (F, $ffile) or die "Can't open $file";
            my $line = 0;
            while (<F>) {
                $line++;
                while (/BML::ml\([\"\'](.+?)[\"\']/g) {
                    $items{$scope}->{$1} = 1;
                }
                while (/\(=_ML\s+(.+?)\s+_ML=\)/g) {
                    my $code = $1;
                    if ($code =~ /^\./ && $file =~ m!^htdocs/!) {
                        $code = "$file$code";
                        $code =~ s!^htdocs!!;
                    }
                    $items{$scope}->{$code} = 1;
                }
            }
            close F;
        }
    }

    $out->(sprintf("%d general and %d local found.",
                   scalar keys %{$items{'general'}},
                   scalar keys %{$items{'local'}}));

    # [ General ]
    my %e_general;  # code -> 1
    $out->("Checking which general items already exist in database...");
    my $sth = $dbh->prepare("SELECT i.itcode FROM ml_items i, ml_latest l WHERE ".
                            "l.dmid=1 AND l.lnid=1 AND i.dmid=1 AND i.itid=l.itid ");
    $sth->execute;
    while (my $it = $sth->fetchrow_array) { $e_general{$it} = 1; }
    $out->(sprintf("%d found", scalar keys %e_general));
    foreach my $it (keys %{$items{'general'}}) {
        next if exists $e_general{$it};
        my $res = LJ::Lang::set_text($dbh, 1, "en", $it, undef, { 'staleness' => 4 });
        $out->("Adding general: $it ... $res");
    }

    if ($opt_local_lang) {
        my $ll = $lang_code{$opt_local_lang};
        die "Bogus --local-lang argument\n" unless $ll;
        die "Local-lang '$ll->{'lncode'}' parent isn't 'en'\n"
            unless $ll->{'parentlnid'} == 1;
        $out->("Checking which local items already exist in database...");

        my %e_local;
        $sth = $dbh->prepare("SELECT i.itcode FROM ml_items i, ml_latest l WHERE ".
                             "l.dmid=1 AND l.lnid=$ll->{'lnid'} AND i.dmid=1 AND i.itid=l.itid ");
        $sth->execute;
        while (my $it = $sth->fetchrow_array) { $e_local{$it} = 1; }
        $out->(sprintf("%d found\n", scalar keys %e_local));
        foreach my $it (keys %{$items{'local'}}) {
            next if exists $e_general{$it};
            next if exists $e_local{$it};
            my $res = LJ::Lang::set_text($dbh, 1, $ll->{'lncode'}, $it, undef, { 'staleness' => 4 });
            $out->("Adding local: $it ... $res");
        }
    }
    $out->('-', 'done.');
}

sub remove {
    my ($dmcode, $itcode, $no_error) = @_;
    my $dmid;
    if (exists $dom_code{$dmcode}) {
        $dmid = $dom_code{$dmcode}->{'dmid'};
    } else {
        $out->("x", "Unknown domain code $dmcode.");
    }

    my $qcode = $dbh->quote($itcode);
    my $itid = $dbh->selectrow_array("SELECT itid FROM ml_items WHERE dmid=$dmid AND itcode=$qcode");
    return if $no_error && !$itid;
    $out->("x", "Unknown item code $itcode.") unless $itid;

    $out->("Removing item $itcode from domain $dmcode ($itid)...", "+");

    # need to delete everything from: ml_items ml_latest ml_text

    $dbh->do("DELETE FROM ml_items WHERE dmid=$dmid AND itid=$itid");

    my $txtids = "";
    my $sth = $dbh->prepare("SELECT txtid FROM ml_latest WHERE dmid=$dmid AND itid=$itid");
    $sth->execute;
    while (my $txtid = $sth->fetchrow_array) {
        $txtids .= "," if $txtids;
        $txtids .= $txtid;
    }
    $dbh->do("DELETE FROM ml_latest WHERE dmid=$dmid AND itid=$itid");
    $dbh->do("DELETE FROM ml_text WHERE dmid=$dmid AND txtid IN ($txtids)");
    
    $out->("-","done.");
}



