#!/usr/bin/perl
#

package ljtopic;

require "$ENV{'LJHOME'}/cgi-bin/ljconfig.pl";

sub no_prefix
{
    my $word = shift;
    $word =~ s/^(a|an|the)\s+//i;
    return $word;
}

sub get_hierarchy
{
    my $dbh = shift;
    my ($opts) = @_;
    my @ret = ();

    ## they have to provide a topid ID or a category ID:
    return unless ($opts->{'topid'} || $opts->{'catid'});

    ## hold the names of topics/categories
    my $cache = (ref $opts->{'cache'} eq "HASH") ? $opts->{'cache'} : {};
    
    if ($opts->{'topid'}) {
	my $tpid = $opts->{'topid'}+0;
	my $it = { 'url' => "$LJ::SITEROOT/topics/?topid=$tpid",
		   'name' => $cache->{'topic'}->{$tpid}->{'name'}, };
	$opts->{'catid'} = $cache->{'topic'}->{$tpid}->{'catid'};
	unless ($cache->{'topic'}->{$tpid}->{'name'}) 
	{
	    my $sth = $dbh->prepare("SELECT tpcatid, topname FROM topic_list WHERE tptopid=$tpid");
	    $sth->execute;
	    my ($catid, $name) = $sth->fetchrow_array;
	    $it->{'name'} = $cache->{'topic'}->{$tpid}->{'name'} = $name;
	    $cache->{'topic'}->{$tpid}->{'catid'} = $catid;
	    $opts->{'catid'} = $catid;
	}
	unshift @ret, $it;
    }

    ## at this point $opts->{'catid'} will be set.

    my $catid = $opts->{'catid'}+0;
    while ($catid)
    {
	my $it = { 'url' => "$LJ::SITEROOT/topics/?catid=$catid",
		   'name' => $cache->{'cat'}->{$catid}->{'name'}, };
	my $nextcat = $cache->{'cat'}->{$catid}->{'parent'};
	
	unless ($it->{'name'}) 
	{
	    my $sth = $dbh->prepare("SELECT parent, catname FROM topic_cats WHERE tpcatid=$catid");
	    $sth->execute;
	    my ($parent, $name) = $sth->fetchrow_array;

	    $nextcat = $cache->{'cat'}->{$catid}->{'parent'} = $parent;
	    $it->{'name'} = $cache->{'cat'}->{$catid}->{'name'} = $name;
	}

	unshift @ret, $it;
	$catid = $nextcat;
    }

    return @ret;
}


1;
