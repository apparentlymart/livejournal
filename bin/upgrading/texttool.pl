#!/usr/bin/perl
#
# This program deals with inserting/extracting text/language data
# from the database.
#

use strict;
use Getopt::Long;

my $opt_help = 0;
my $opt_local_lang;
exit 1 unless
GetOptions(
           "help" => \$opt_help,
           "local-lang=s" => \$opt_local_lang,
           );

my $mode = shift @ARGV;

help() if $opt_help or not defined $mode;

sub help
{
    die "Usage: texttool.pl <command>

Where 'command' is one of:
  popstruct    Populate lang data from text[-local].dat into db
  poptext      Populate text from en.dat, etc into database
  dumptext     Dump lang text based on text[-local].dat information
  check        Check validity of text[-local].dat files
  wipedb       Remove all language/text data from database.
  newitems     Search files in htdocs, cgi-bin, & bin and insert
               necessary text item codes in database.

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

popstruct() if $mode eq "popstruct";
poptext() if $mode eq "poptext";
dumptext() if $mode eq "dumptext";
popstruct() if $mode eq "dump";
newitems() if $mode eq "newitems";
wipedb() if $mode eq "wipedb";
help();

sub wipedb
{
    $dbh->do("DELETE FROM ml_$_")
        foreach (qw(domains items langdomains langs latest text));
    exit 0;                 
}

sub popstruct
{
    foreach my $l (values %lang_id) {
        print "Inserting language: $l->{'lnname'}\n";
        $dbh->do("INSERT INTO ml_langs (lnid, lncode, lnname, parenttype, parentlnid) ".
                 "VALUES (" . join(",", map { $dbh->quote($l->{$_}) } qw(lnid lncode lnname parenttype parentlnid)) . ")");
        die "Error: " . $dbh->errstr if $dbh->err;
    }

    foreach my $d (values %dom_id) {
        print "Inserting domain: $d->{'type'}\[$d->{'args'}\]\n";
        $dbh->do("INSERT INTO ml_domains (dmid, type, args) ".
                 "VALUES (" . join(",", map { $dbh->quote($d->{$_}) } qw(dmid type args)) . ")");
        die "Error: " . $dbh->errstr if $dbh->err;
    }

    print "Inserting language domains ...\n";
    foreach my $ld (@lang_domains) {
        $dbh->do("INSERT IGNORE INTO ml_langdomains (lnid, dmid, dmmaster) VALUES ".
                 "(" . join(",", map { $dbh->quote($ld->{$_}) } qw(lnid dmid dmmaster)) . ")");
    }

    print "All done.\n";
    exit 0;
}

sub poptext
{
    foreach my $lang (keys %lang_code)
    {
        print "$lang\n";
        my $l = $lang_code{$lang};
        open (D, "$ENV{'LJHOME'}/bin/upgrading/${lang}.dat")
            or die "Can't find $lang.dat\n";
        my $lnum = 0;
        my ($code, $text);
        while (my $line = <D>) {
            $lnum++;
            if ($line =~ /^(\S+?)=(.*)/) {
                ($code, $text) = ($1, $2);
            } elsif ($line =~ /^(\S+?)\<\<\s*$/) {
                ($code, $text) = ($1, "");
                while (<D>) {
                    last if $_ eq ".\n";
                    s/^\.//;
                    $text .= $_;
                }
                chomp $text;  # remove file new-line (we added it)
            } elsif ($line =~ /\S/) {
                die "$lang.dat:$lnum: Bogus format.\n";
            }

            my $qcode = $dbh->quote($code);
            my $exists = $dbh->selectrow_array("SELECT COUNT(*) FROM ml_latest l, ml_items i ".
                                               "WHERE l.dmid=1 AND i.dmid AND i.itcode=$qcode AND ".
                                               "i.itid=l.itid AND l.lnid=$l->{'lnid'}");
            if (! $exists) {
                print " adding: $code\n";
                my $res = LJ::Lang::set_text($dbh, 1, $lang, $code, $text);
                unless ($res) {
                    die "  ERROR: " . LJ::Lang::last_error() . "\n";
                }
            }
        }
        close D;
    }
    exit 0;
}

sub dumptext
{
    foreach my $lang (keys %lang_code)
    {
        print "$lang\n";
        my $l = $lang_code{$lang};
        open (D, ">$ENV{'LJHOME'}/bin/upgrading/${lang}.dat")
            or die "Can't open $lang.dat\n";
        my $sth = $dbh->prepare("SELECT i.itcode, t.text FROM ".
                                "ml_items i, ml_latest l, ml_text t ".
                                "WHERE l.lnid=$l->{'lnid'} AND l.dmid=1 ".
                                "AND i.dmid=1 AND l.itid=i.itid AND ".
                                "t.dmid=1 AND t.txtid=l.txtid AND ".
                                # only export mappings that aren't inherited:
                                "t.lnid=$l->{'lnid'} ".
                                "ORDER BY i.itcode");
        $sth->execute;
        die $dbh->errstr if $dbh->err;
        while (my ($itcode, $text) = $sth->fetchrow_array) {
            if ($text =~ /\n/) {
                $text =~ s/\n\./\n\.\./g;
                print D "$itcode<<\n$text\n.\n\n";
            } else {
                print D "$itcode=$text\n\n";
            }
        }
        close D;
    }
    exit 1;
}

sub newitems
{
    my $top = $ENV{'LJHOME'};
    my @files;
    push @files, qw(htdocs cgi-bin bin);
    my %items;  # $scope -> $key -> 1;
    print "Searching htdocs/cgi-bin/bin for referenced text codes...\n";
    while (@files)
    {
        my $file = shift @files;
        my $ffile = "$top/$file";
        next unless -e $ffile;
        if (-d $ffile) {
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

    printf("  %d general and %d local found.\n",
           scalar keys %{$items{'general'}},
           scalar keys %{$items{'local'}});

    # [ General ]
    my %e_general;  # code -> 1
    print "Checking which general items already exist in database...\n";
    my $sth = $dbh->prepare("SELECT i.itcode FROM ml_items i, ml_latest l WHERE ".
                            "l.dmid=1 AND l.lnid=1 AND i.dmid=1 AND i.itid=l.itid");
    $sth->execute;
    while (my $it = $sth->fetchrow_array) { $e_general{$it} = 1; }
    printf("  %d found\n", scalar keys %e_general);
    foreach my $it (keys %{$items{'general'}}) {
        next if exists $e_general{$it};
        print "Adding general: $it ...";
        print LJ::Lang::set_text($dbh, 1, "en", $it, "[no text: $it]");
        print "\n";
    }

    if ($opt_local_lang) {
        my $ll = $lang_code{$opt_local_lang};
        die "Bogus --local-lang argument\n" unless $ll;
        die "Local-lang '$ll->{'lncode'}' parent isn't 'en'\n"
            unless $ll->{'parentlnid'} == 1;
        print "Checking which local items already exist in database...\n";

        my %e_local;
        $sth = $dbh->prepare("SELECT i.itcode FROM ml_items i, ml_latest l WHERE ".
                             "l.dmid=1 AND l.lnid=$ll->{'lnid'} AND i.dmid=1 AND i.itid=l.itid");
        $sth->execute;
        while (my $it = $sth->fetchrow_array) { $e_local{$it} = 1; }
        printf("  %d found\n", scalar keys %e_local);
        foreach my $it (keys %{$items{'local'}}) {
            next if exists $e_general{$it};
            next if exists $e_local{$it};
            print "Adding local: $it ...";
            print LJ::Lang::set_text($dbh, 1, $ll->{'lncode'}, $it, "[no text: $it]");
            print "\n";
        }
    }
    
    #use Data::Dumper;
    #print Dumper(\%items);

    exit 0;
}
