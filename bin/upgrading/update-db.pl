#!/usr/bin/perl
#
# This program will bring your LiveJournal database schema up-to-date
#

use strict;
use Getopt::Long;

my $opt_sql = 0;
my $opt_drop = 0;
my $opt_pop = 0;
my $opt_confirm = "";

exit 1 unless
GetOptions("runsql" => \$opt_sql,
	   "drop" => \$opt_drop,
	   "populate" => \$opt_pop,
	   "confirm=s" => \$opt_confirm,
	   );


## make sure $LJHOME is set so we can load & run everything
unless (-d $ENV{'LJHOME'}) {
    die "LJHOME environment variable is not set, or is not a directory.\n".
	"You must fix this before you can run this database update script.";
}
require "$ENV{'LJHOME'}/cgi-bin/ljlib.pl";

## make sure we can connect
my $dbh = LJ::get_dbh("master");
unless ($dbh) {
    die "Can't connect to the database, so I can't update it.\n";
}

my $sth;
my %table_exists;   # $table -> 1
my %table_unknown;  # $table -> 1
my %table_create;   # $table -> $create_sql
my %table_drop;     # $table -> 1
my %post_create;    # $table -> [ [ $action, $what ]* ]
my %coltype;        # $table -> { $col -> $type }
my @alters;

## figure out what tables already exist (but not details of their structure)
$sth = $dbh->prepare("SHOW TABLES");
$sth->execute;
while (my ($table) = $sth->fetchrow_array) {
    $table_exists{$table} = 1;
}
%table_unknown = %table_exists;  # for now, later we'll delete from table_unknown

## very important that local is run first!  (it can define tables that
## the site-wide would drop if it didn't know about them already)

load_datfile("$LJ::HOME/bin/upgrading/update-db-local.pl", 1);
load_datfile("$LJ::HOME/bin/upgrading/update-db-general.pl");

foreach my $t (keys %table_create) {
    delete $table_drop{$t} if ($table_drop{$t});
}

foreach my $t (keys %table_drop) {
    delete $table_unknown{$t};
}

foreach my $t (keys %table_unknown)
{
    print "# Warning: unknown live table: $t\n";
}

## create tables
foreach my $t (keys %table_create)
{
    next if ($table_exists{$t});
    create_table($t); 
}

## drop tables
foreach my $t (keys %table_drop)
{
    next if (! $table_exists{$t});
    drop_table($t); 
}

## do all the alters
foreach my $s (@alters)
{
    $s->($dbh, $opt_sql);
}

if ($opt_pop)
{
    print "Populating database with base data:\n";
    $| = 1;
    open (BD, "$ENV{'LJHOME'}/bin/upgrading/base-data.sql")
	or die ("Can't open base-data.sql file");
    my $lasttable = "";
    while (my $q = <BD>)
    {
	chomp $q;  # remove newline
	next unless ($q =~ /^(REPLACE|INSERT) INTO (\w+).+;/);
	chop $q;  # remove semicolon
	my $type = $1;
	my $table = $2;
	if ($table ne $lasttable) {
	    if ($lasttable) { print "\n"; }
	    print "  $table ";
	    $lasttable = $table;
	}
	$dbh->do($q);
	if ($dbh->err) {
	    if ($type eq "REPLACE") {
		die "#  ERROR: " . $dbh->errstr . "\n";
	    }
	    if ($type eq "INSERT") {
		print "x";
	    }
	} else {
	    print ".";
	}
	
    }
    print "\n";
    close (BD);
}


print "# Done.\n";

sub do_sql
{
    my $sql = shift;
    print "$sql;\n";
    if ($opt_sql) {
	print "# Running...\n";
	$dbh->do($sql);
	if ($dbh->err) {
	    die "#  ERROR: " . $dbh->errstr . "\n";
	}
    }
}

sub try_sql
{
    my $sql = shift;
    print "$sql;\n";
    if ($opt_sql) {
	print "# Non-critical SQL (upgrading only... it might fail)...\n";
	$dbh->do($sql);
	if ($dbh->err) {
	    print "#  Acceptable failure: " . $dbh->errstr . "\n";
	}
    }
}

sub do_alter
{
    my ($table, $sql) = @_;
    do_sql($sql);

    # columns will have changed, so clear cache:
    clear_table_columns($table);
}

sub create_table
{
    my $table = shift;
    do_sql($table_create{$table});

    foreach my $pc (@{$post_create{$table}})
    {
	my @args = @{$pc};
	my $ac = shift @args;
	if ($ac eq "sql") { 
	    print "# post-create SQL\n";
	    do_sql($args[0]); 
	}
	elsif ($ac eq "sqltry") { 
	    print "# post-create SQL (necessary if upgrading only)\n";
	    try_sql($args[0]); 
	}
	else { print "# don't know how to do \$ac = $ac"; }
    }
}

sub drop_table
{
    my $table = shift;
    if ($opt_drop) {
	do_sql("DROP TABLE $table");
    } else {
	print "# Not dropping table $table to be paranoid (use --drop)\n";
    }
}

sub load_datfile
{
    my $file = shift;
    my $local = shift;
    return if ($local && ! -e $file);
    unless (-e $file) {
	die "Can't find database update file at $file\n";
    }
    require $file or die "Can't run $file\n";
}

sub register_tablecreate
{
    my ($table, $create) = @_;

    # we now know of it
    delete $table_unknown{$table};

    unless ($table_exists{$table}) {
	$table_create{$table} = $create;
    } else {
	$table_create{$table} = "--";   # save memory, won't use it.
    }
}

sub register_tabledrop
{
    my ($table) = @_;
    $table_drop{$table} = 1;
}

sub post_create
{
    my $table = shift;
    while (my ($type, $what) = splice(@_, 0, 2)) {
	push @{$post_create{$table}}, [ $type, $what ];
    }
}

sub register_alter
{
    my $sub = shift;
    push @alters, $sub;
}

sub clear_table_columns
{
    my $table = shift;
    delete $coltype{$table};
}

sub load_table_columns
{
    my $table = shift;

    clear_table_columns($table);
    my $sth = $dbh->prepare("DESCRIBE $table");
    $sth->execute;
    while (my ($Field, $Type) = $sth->fetchrow_array)
    {
	$coltype{$table}->{$Field} = $Type;
    }
}

sub column_type
{
    my ($table, $col) = @_;
    load_table_columns($table) unless $coltype{$table};
    my $type = $coltype{$table}->{$col};
    $type ||= "";
    return $type;
}

sub ensure_confirm
{
    my $area = shift;

    return 1 if ($opt_confirm eq "all" or
		 $opt_confirm eq $area);

    print STDERR "To proceeed with the necessary changes, rerun with --confirm=$area\n";
    return 0;
}



