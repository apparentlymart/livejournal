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
my $opt_skip = "";
my $opt_help = 0;
my $cluster = 0;   # by default, upgrade master.
my $opt_listtables;
my $opt_forcebuild = 0;
my $opt_compiletodisk = 0;
exit 1 unless
GetOptions("runsql" => \$opt_sql,
           "drop" => \$opt_drop,
           "populate" => \$opt_pop,
           "confirm=s" => \$opt_confirm,
           "cluster=i" => \$cluster,
           "skip=s" => \$opt_skip,
           "help" => \$opt_help,
           "listtables" => \$opt_listtables,
           "forcebuild|fb" => \$opt_forcebuild,
           "ctd" => \$opt_compiletodisk,
           );

if ($opt_help) {
    die "Usage: update-db.pl
  -r  --runsql       Actually do the SQL, instead of just showing it.
  -p  --populate     Populate the database with the latest required base data.
  -d  --drop         Drop old unused tables (default is to never)
      --cluster <n>  Upgrade cluster number <n> (default is global cluster)
  -l  --listtables   Print used tables, one per line.
";
}

## make sure $LJHOME is set so we can load & run everything
unless (-d $ENV{'LJHOME'}) {
    die "LJHOME environment variable is not set, or is not a directory.\n".
        "You must fix this before you can run this database update script.";
}
require "$ENV{'LJHOME'}/cgi-bin/ljlib.pl";

## make sure we can connect
my $dbh = $cluster ? LJ::get_cluster_master($cluster) : LJ::get_dbh("master");
unless ($dbh) {
    die "Can't connect to the database (clust\#$cluster), so I can't update it.\n";
}

my $sth;
my %table_exists;   # $table -> 1
my %table_unknown;  # $table -> 1
my %table_create;   # $table -> $create_sql
my %table_drop;     # $table -> 1
my %post_create;    # $table -> [ [ $action, $what ]* ]
my %coltype;        # $table -> { $col -> $type }
my @alters;
my %clustered_table; # $table -> 1

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

foreach my $t (sort keys %table_create) {
    delete $table_drop{$t} if ($table_drop{$t});
    print "$t\n" if $opt_listtables;
}
exit if $opt_listtables;

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
    # S1
    print "Populating public system styles (S1):\n";
    require "$ENV{'LJHOME'}/bin/upgrading/s1style-rw.pl";
    my $ss = s1styles_read();
    foreach my $uniq (sort keys %$ss) {
        print "  $uniq: ";
        my $s = $ss->{$uniq};
        my $existing = $dbh->selectrow_array(q{
            SELECT styleid FROM style WHERE
                user='system' AND type=? AND styledes=?
            }, undef, $s->{'type'}, $s->{'styledes'});

        # update
        if ($existing) {
            if ($LJ::DONT_TOUCH_STYLES) {
                print "skipping\n";
                next;
            }
            $dbh->do(qq{ UPDATE style SET formatdata=?, is_embedded=?,
                         is_colorfree=?, lastupdate=? WHERE styleid=$existing },
                     undef, map { $s->{$_} } qw(formatdata is_embedded is_colorfree lastupdate));
            die $dbh->errstr if $dbh->err;
            print "updated \#$existing\n";
            next;
        }
                
        # insert new
        $dbh->do(q{ INSERT INTO style (user, styledes, type, formatdata, 
                                       is_public, is_embedded, is_colorfree, 
                                       lastupdate) VALUES ('system',?,?,?,'Y',?,?,?) },
                 undef, map { $s->{$_} } qw(styledes type formatdata is_embedded
                                            is_colorfree lastupdate));
        die $dbh->errstr if $dbh->err;
        print "added\n";
    }

    # S2
    print "Populating public system styles (S2):\n";
    {
        my $LD = "s2layers"; # layers dir

        # get the system account
        my $su = LJ::load_user($dbh, "system");
        unless ($su) {
            die "No system user found.  Run \$LJHOME/bin/upgrading/make-system.pl\n";
        }
        my $sysid = $su->{'userid'};
    
        # find existing re-distributed layers that are in the database
        # and their styleids.
        my $existing = LJ::S2::get_public_layers($sysid);

        chdir "$ENV{'LJHOME'}/bin/upgrading" or die;
        my %layer;    # maps redist_uniq -> { 'type', 'parent' (uniq), 'id' (s2lid) }
        foreach my $file ("s2layers.dat", "s2layers-local.dat")
        {
            next unless -e $file;
            open (SL, $file) or die;
            while (<SL>)
            {
                s/\#.*//; s/^\s+//; s/\s+$//;
                next unless /\S/;
                my ($base, $type, $parent) = split;
                
                if ($type ne "core" && ! defined $layer{$parent}) {
                    die "'$base' references unknown parent '$parent'\n";
                }
                
                my $s2source;
                open (L, "$LD/$base.s2") or die "Can't open file: $base.s2\n";
                while (<L>) { $s2source .= $_; }
                close L;
                
                my $id = $existing->{$base} ? $existing->{$base}->{'s2lid'} : 0;
                unless ($id) {
                    my $parentid = 0;
                    $parentid = $layer{$parent}->{'id'} unless $type eq "core";
                    # allocate a new one.
                    $dbh->do("INSERT INTO s2layers (s2lid, b2lid, userid, type) ".
                             "VALUES (NULL, $parentid, $sysid, ?)", undef, $type);
                    die $dbh->errstr if $dbh->err;
                    $id = $dbh->{'mysql_insertid'};
                    if ($id) {
                        $dbh->do("INSERT INTO s2info (s2lid, infokey, value) VALUES (?,'redist_uniq',?)",
                                 undef, $id, $base);
                    }
                }
                die "Can't generate ID for '$base'" unless $id;

                $layer{$base} = {
                    'type' => $type,
                    'parent' => $parent,
                    'id' => $id,
                };
                
                my $parid = $layer{$parent}->{'id'};
                print "$base($id) is $type";
                if ($parid) { print ", parent = $parent($parid)"; };
                print "\n";
                
                # see if source changed
                my $md5_source = Digest::MD5::md5_hex($s2source);
                my $md5_exist = $dbh->selectrow_array("SELECT MD5(s2code) FROM s2source WHERE s2lid=?", undef, $id);
                
                # skip compilation if source is unchanged and parent wasn't rebuilt.
                next if $md5_source eq $md5_exist && ! $layer{$parent}->{'built'} && ! $opt_forcebuild;

                # we're going to go ahead and build it.
                $layer{$base}->{'built'} = 1;

                # compile!
                my $lay = {
                    's2lid' => $id,
                    'userid' => $sysid,
                    'b2lid' => $parid,
                    'type' => $type,
                };
                my $error = "";
                my $compiled;
                die $error unless LJ::S2::layer_compile($lay, \$error, { 
                    's2ref' => \$s2source, 
                    'redist_uniq' => $base,
                    'compiledref' => \$compiled,
                });

                if ($opt_compiletodisk) {
                    open (CO, ">$LD/$base.pl") or die;
                    print CO $compiled;
                    close CO;
                }

                # put raw S2 in database.
                $dbh->do("REPLACE INTO s2source (s2lid, s2code) ".
                         "VALUES ($id, ?)", undef, $s2source);
                die $dbh->errstr if $dbh->err;            
                
            }
            close SL;
        }
    }
    
    # base data
    foreach my $file ("base-data.sql", "base-data-local.sql") {
        my $ffile = "$ENV{'LJHOME'}/bin/upgrading/$file";
        next unless -e $ffile;
        print "Populating database with $file.\n";
        open (BD, $ffile) or die "Can't open $file file\n";
        while (my $q = <BD>)
        {
            chomp $q;  # remove newline
            next unless ($q =~ /^(REPLACE|INSERT|UPDATE)/);
            chop $q;  # remove semicolon
            $dbh->do($q);
            if ($dbh->err) {
                print "$q\n";
                die "#  ERROR: " . $dbh->errstr . "\n";
            }
        }
        close (BD);
    }

    print "\nRemember to also run:\n  bin/upgrading/texttool.pl load\n\n";
}


print "# Done.\n";

sub skip_opt
{
    return $opt_skip;
}

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
    return if $cluster && ! defined $clustered_table{$table};

    do_sql($sql);

    # columns will have changed, so clear cache:
    clear_table_columns($table);
}

sub create_table
{
    my $table = shift;
    return if $cluster && ! defined $clustered_table{$table};

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
    return if $cluster && ! defined $clustered_table{$table};

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

sub mark_clustered
{
    foreach (@_) {
        $clustered_table{$_} = 1;
    }
}

sub register_tablecreate
{
    my ($table, $create) = @_;
    # we now know of it
    delete $table_unknown{$table};

    return if $cluster && ! defined $clustered_table{$table};

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

sub table_relevant
{
    my $table = shift;
    return 1 unless $cluster;
    return 1 if $clustered_table{$table};
    return 0;
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

    return 1 if ($opt_sql && ($opt_confirm eq "all" or
                              $opt_confirm eq $area));

    print STDERR "To proceeed with the necessary changes, rerun with -r --confirm=$area\n";
    return 0;
}



