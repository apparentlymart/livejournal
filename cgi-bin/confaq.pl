#!/usr/bin/perl
#

package LJ::Con;

$cmd{'faqcat'}->{'handler'} = \&faqcat;

sub faqcat
{
    # add <catkey> <catname> <catorder>
    #    REPLACE INTO faqcat (faqcat, faqcatname, catorder) VALUES ($catkey, $catname, $catorder)
    # delete <catkey>
    #    DELETE FROM faqcat WHERE faqcat = $catkey
    # list
    #    SELECT * FROM faqcat ORDER BY sortorder
    # move <faqcat> {"up"|"down"}
    #    two UPDATEs faqcat SET catorder$catorder WHERE faqcat = $catkey
    
    my ($dbh, $remote, $args, $out) = @_;
    my $command = $args->[1];

    ## the following commands doesn't require any priv.

    if ($command eq "list") {
        my %catdefined;
        my $sth = $dbh->prepare("SELECT faqcat, faqcatname, catorder FROM faqcat ORDER BY catorder");
        $sth->execute;
        push @$out, [ "", sprintf("%-20s %-45s %s", "catkey", "catname", "order" ) ];
        push @$out, [ "", "-"x76 ];
        while (my ($faqcat, $faqcatname, $catorder) = $sth->fetchrow_array)
        {
            $catdefined{$faqcat} = 1;
            push @$out, [ "", sprintf("%-20s %-45s %5d", 
                $faqcat, 
                $faqcatname,
                $catorder ) ];
        }
        $sth->finish;

        push @$out, [ "", "" ];
        push @$out, [ "", "catkeys currently in use:" ];
        push @$out, [ "", "-------------------------" ];

        $sth = $dbh->prepare("SELECT faqcat, COUNT(*) FROM faq GROUP BY 1");
        $sth->execute;
        while (my ($faqcat, $count) = $sth->fetchrow_array)
        {
            my $state = $catdefined{$faqcat} ? "" : "error";
            push @$out, [ $state, sprintf("%-15s by %5d", $faqcat, $count) ];
        }
        $sth->finish;

        return 1;
    }

    if ($command eq "showused") {
        my $sth = $dbh->prepare("SELECT faqcat, faqcatname, catorder FROM faqcat ORDER BY catorder");
        $sth->execute;
        push @$out, [ "", sprintf("%-20s %-45s %3d", "catkey", "catname", "order" ) ];
        push @$out, [ "", "-"x76 ];
        while (my ($faqcat, $faqcatname, $catorder) = $sth->fetchrow_array)
        {
            push @$out, [ "", sprintf("%-20s %-45s %3d", 
                $faqcat, 
                $faqcatname,
                $catorder ) ];
        }
        return 1;
    }

    ### everything from here on down requires the "faqcat" priv.

    unless ($remote->{'priv'}->{'faqcat'}) 
    {
        push @$out, [ "error", "$remote->{'user'}, you are not authorized to use this command." ];
        return 0;
    }


    if ($command eq "delete") {
        my $catkey = $dbh->quote($args->[2]);
        my $sth = $dbh->prepare("DELETE FROM faqcat WHERE faqcat=$catkey");
        $sth->execute;
        if ($sth->rows) {
            push @$out, [ "info", "Category Deleted" ];
        } else {
            push @$out, [ "info", "Category didn't exist to be deleted." ];
        }
        return 1;
    }

    if ($command eq "add") {
        my $catkey = $dbh->quote($args->[2]);
        my $catname = $dbh->quote($args->[3]);
        my $catorder = ($args->[4])+0;

        my $faqd = LJ::Lang::get_dom("faq");
        my $rlang = LJ::Lang::get_root_lang($faqd);
        unless ($rlang) { undef $faqd; }
        if ($faqd) {
            LJ::Lang::set_text($dbh, $faqd->{'dmid'}, $rlang->{'lncode'},
                               "cat.$args->[2]", $args->[3], { 'changeseverity' => 1 });
        }

        my $sth = $dbh->prepare("REPLACE INTO faqcat (faqcat, faqcatname, catorder) ".
                                "VALUES ($catkey, $catname, $catorder)");
        $sth->execute;
        push @$out, [ "info", "Catagory added/changed." ];
        return 1;
    }

    if ($command eq "move") {
        my $catkey = $args->[2];
        my $dir = $args->[3];
        unless ($dir eq "up" || $dir eq "down") {
            push @$out, [ "error", "Direction argument must be up or down." ];
            return 0;
        }

        my %pre;       # catkey -> key before
        my %post;      # catkey -> key after
        my %catorder;  # catkey -> order

        my $sth = $dbh->prepare("SELECT faqcat, catorder FROM faqcat ORDER BY catorder");
        $sth->execute;
        my $last;
        while (my ($key, $order) = $sth->fetchrow_array) {
            push @cats, $key;
            $catorder{$key} = $order;
            $post{$last} = $key;
            $pre{$key} = $last;
            $last = $key;
        }

        my %new;    # catkey -> new order
        if ($dir eq "up" && $pre{$catkey}) {
            $new{$catkey} = $catorder{$pre{$catkey}};
            $new{$pre{$catkey}} = $catorder{$catkey};
        }
        if ($dir eq "down" && $post{$catkey}) {
            $new{$catkey} = $catorder{$post{$catkey}};
            $new{$post{$catkey}} = $catorder{$catkey};
        }
        if (%new) {
            foreach my $n (keys %new) {
                my $qk = $dbh->quote($n);
                my $co = $new{$n}+0;
                $dbh->do("UPDATE faqcat SET catorder=$co WHERE faqcat=$qk");
            }
            push @$out, [ "info", "Category order changed" ];
            return 1;
        } 

        push @$out, [ "info", "Category can't move $dir anymore." ];
        return 1;
    } 

    push @$out, [ "error", "No Such option \'$command\'" ];
    return 0;
}

1;


