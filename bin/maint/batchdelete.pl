#!/usr/bin/perl
#

$maint{'db_batchdelete'} = sub
{
    &connect_db();
    my @ids;

    my %what = (
		'hintfriends' => { 'table' => 'hintfriendsview',
				   'column' => 'hintid',
				   'minbatch' => 150,
				   'maxbatch' => 500,
			       },
		'hintlastn' => { 'table' => 'hintlastnview',
				 'column' => 'hintid',
				 'minbatch' => 100,
				 'maxbatch' => 500,
			     },
		);
		
    
    foreach my $what (sort keys %what)
    {
        print "-I- Loading $what ids that need deleting...\n";
	my $qwhat = $dbh->quote($what);
	$sth = $dbh->prepare("SELECT itsid FROM batchdelete WHERE what=$qwhat");
	$sth->execute;
	@ids = ();
	push @ids, $_ while (($_) = $sth->fetchrow_array);
	my $size = scalar(@ids);
	print "Total is: $size\n";
	if ($size >= $what{$what}->{'minbatch'}) {
	    my $max = $what{$what}->{'maxbatch'};
	    if ($size >= $max) {
		@ids = @ids[0..($max-1)];
	    }
	    $size = scalar(@ids);
	    print "DELETING $size!\n";
	    my $in = join(",", @ids);
	    my $sql = "DELETE FROM $what{$what}->{'table'} WHERE $what{$what}->{'column'} IN ($in)";
	    $dbh->do($sql);
	    $dbh->do("DELETE FROM batchdelete WHERE what=$qwhat AND itsid IN ($in)");
	    print "Done.\n";
	}
    }
    
};

1;
