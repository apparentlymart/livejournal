#!/usr/bin/perl
#

package LJ::Con;

$cmd{'tp_topedit'}->{'handler'} = \&tp_topedit;
$cmd{'tp_topcreate'}->{'handler'} = \&tp_topcreate;
$cmd{'tp_catedit'}->{'handler'} = \&tp_catedit;
$cmd{'tp_catcreate'}->{'handler'} = \&tp_catcreate;
$cmd{'tp_itemedit'}->{'handler'} = \&tp_itemedit;

sub tp_itemedit
{
    my ($dbh, $remote, $args, $out) = @_;
    my $error = 0;

    unless (scalar(@$args) == 4) {
        $error = 1;
        push @$out, [ "error", "This command takes exactly 3 arguments.  Consult the reference." ];
    }
    
    unless ($remote->{'priv'}->{'topicmanager'}) {
        $error = 1;
        push @$out, [ "error", "$remote->{'user'}, you are not authorized to use this command." ];
    }

    return 0 if ($error);

    my ($topid, $itemid, $status) = ($args->[1], $args->[2], $args->[3]);
    unless ($topid =~ /^\d+$/) {
        $error = 1;
        push @$out, [ "error", "Topic ID must be a positive integer." ];
    }
    unless ($itemid =~ /^\d+$/) {
        $error = 1;
        push @$out, [ "error", "Item ID must be a positive integer." ];
    }
    unless ($status eq "on" || $status eq "off" ||
            $status eq "new" || $status eq "deny")
    {
        $error = 1;
        push @$out, [ "error", "Unknown status value." ];
    }
    
    return 0 if ($error);    

    my $qtopid = $dbh->quote($topid);
    my $qitemid = $dbh->quote($itemid);
    my $qstatus = $dbh->quote($status);
    my $sth = $dbh->prepare("INSERT INTO topic_map (tptopid, itemid, status) VALUES ($qtopid, $qitemid, 'new')");
    $sth->execute;
    $sth = $dbh->prepare("UPDATE topic_map SET status=$qstatus WHERE tptopid=$qtopid AND itemid=$qitemid");
    $sth->execute;
    if ($dbh->err) {
        push @$out, [ "error", $dbh->errstr ];
        return 0;
    }
    my $topid = $dbh->{'mysql_insertid'};
    push @$out, [ "info", "$itemid set to $status" ];
    return 1;
}

sub tp_topcreate
{
    my ($dbh, $remote, $args, $out) = @_;
    my $error = 0;
    
    unless (scalar(@$args) == 3 || scalar(@$args) == 4) {
        $error = 1;
        push @$out, [ "error", "This command takes 2 or 3 arguments.  Consult the reference." ];
    }
    
    unless ($remote->{'priv'}->{'topicmanager'}) {
        $error = 1;
        push @$out, [ "error", "$remote->{'user'}, you are not authorized to use this command." ];
    }

    return 0 if ($error);

    my ($catid, $name, $des) = ($args->[1], $args->[2], $args->[3]);
    unless ($catid =~ /^\d+$/) {
        $error = 1;
        push @$out, [ "error", "Category ID must be a positive integer." ];
    }
    unless ($name =~ /\S/) {
        $error = 1;
        push @$out, [ "error", "Topic name must contain non-whitespace." ];
    }
    
    return 0 if ($error);    

    my $qname = $dbh->quote($name);
    my $qdes = $dbh->quote($des);
    my $sth = $dbh->prepare("INSERT INTO topic_list (tptopid, tpcatid, topname, des, timeenter, status) VALUES (NULL, $catid, $qname, $qdes, UNIX_TIMESTAMP(), 'on')");
    $sth->execute;
    if ($dbh->err) {
        push @$out, [ "error", $dbh->errstr ];
        return 0;
    }
    my $topid = $dbh->{'mysql_insertid'};
    push @$out, [ "info", "New topic \"$name\" has topic ID of $topid" ];
    return 1;
}

sub tp_topedit 
{
    my ($dbh, $remote, $args, $out) = @_;
    my $error = 0;
    
    unless (scalar(@$args) == 4) {
        $error = 1;
        push @$out, [ "error", "This command takes exactly 3 arguments.  Consult the reference." ];
    }
    
    unless ($remote->{'priv'}->{'topicmanager'}) {
        $error = 1;
        push @$out, [ "error", "$remote->{'user'}, you are not authorized to use this command." ];
    }

    return 0 if ($error);

    my ($topid, $prop, $value) = ($args->[1], $args->[2], $args->[3]);
    unless ($topid =~ /^\d+$/) {
        $error = 1;
        push @$out, [ "error", "Topic ID must be a positive integer." ];
    }

    my $col;

    if ($prop eq "name") {
        $col = "topname";
    } elsif ($prop eq "des") {
        $col = "des";
    } elsif ($prop eq "catid") {
        $col = "tpcatid";
        unless ($value =~ /^\d+$/) {
            $error = 1;
            push @$out, [ "error", "Category ID must be a positive integer" ];
        }
    } elsif ($prop eq "status") {
        $col = "status";
        unless ($value eq "new" || $value eq "off" || $value eq "on" || $value eq "deny") {
            $error = 1;
            push @$out, [ "error", "Unknown status value \"$value\".  Consult the reference." ];
        }
    } else {
        $error = 1;
        push @$out, [ "error", "Unknown property \"$prop\".  Consult the reference." ];
    }
    
    return 0 if ($error);    

    my $qval = $dbh->quote($value);
    my $sth = $dbh->prepare("UPDATE topic_list SET $col=$qval WHERE tptopid=$topid");
    $sth->execute;
    if ($dbh->err) {
        push @$out, [ "error", $dbh->errstr ];
        return 0;
    }
    my $rows = $sth->rows;

    if ($rows) {
        push @$out, [ "info", "Success" ];
    } else {
        push @$out, [ "info", "Query performed, but property already had that value." ];
    }
    return 1;
}

sub tp_catcreate
{
    my ($dbh, $remote, $args, $out) = @_;
    my $error = 0;
    
    unless (scalar(@$args) == 3 || scalar(@$args) == 4) {
        $error = 1;
        push @$out, [ "error", "This command takes 2 or 3 arguments.  Consult the reference." ];
    }
    
    unless ($remote->{'priv'}->{'topicmanager'}) {
        $error = 1;
        push @$out, [ "error", "$remote->{'user'}, you are not authorized to use this command." ];
    }

    return 0 if ($error);

    my ($parent, $name, $sort) = ($args->[1], $args->[2], $args->[3]);
    $sort ||= "alpha";
    unless ($parent =~ /^\d+$/) {
        $error = 1;
        push @$out, [ "error", "Parent category ID must be a positive integer." ];
    }
    unless ($name =~ /\S/) {
        $error = 1;
        push @$out, [ "error", "Category name must contain non-whitespace." ];
    }
    unless ($sort eq "alpha" || $sort eq "date") {
        $error = 1;
        push @$out, [ "error", "Invalid sort value.  Consult the reference." ];
    }
    
    return 0 if ($error);    

    my $qname = $dbh->quote($name);
    my $qsort = $dbh->quote($sort);
    my $sth = $dbh->prepare("INSERT INTO topic_cats (tpcatid, parent, catname, status, topicsort) VALUES (NULL, $parent, $qname, 'on', $qsort)");
    $sth->execute;
    if ($dbh->err) {
        push @$out, [ "error", $dbh->errstr ];
        return 0;
    }
    my $topid = $dbh->{'mysql_insertid'};
    push @$out, [ "info", "New category \"$name\" has topic ID of $topid" ];
    return 1;
}

sub tp_catedit
{
    my ($dbh, $remote, $args, $out) = @_;
    my $error = 0;
    
    unless (scalar(@$args) == 4) {
        $error = 1;
        push @$out, [ "error", "This command takes exactly 3 arguments.  Consult the reference." ];
    }
    
    unless ($remote->{'priv'}->{'topicmanager'}) {
        $error = 1;
        push @$out, [ "error", "$remote->{'user'}, you are not authorized to use this command." ];
    }

    return 0 if ($error);

    my ($catid, $prop, $value) = ($args->[1], $args->[2], $args->[3]);
    unless ($catid =~ /^\d+$/) {
        $error = 1;
        push @$out, [ "error", "Category ID must be a positive integer." ];
    }

    my $col;

    if ($prop eq "name") {
        $col = "catname";
    } elsif ($prop eq "parent") {
        $col = "parent";
        unless ($value =~ /^\d+$/) {
            $error = 1;
            push @$out, [ "error", "Parent category ID must be a positive integer" ];
        }
    } elsif ($prop eq "status") {
        $col = "status";
        unless ($value eq "off" || $value eq "on") {
            $error = 1;
            push @$out, [ "error", "Unknown status value \"$value\".  Consult the reference." ];
        }
    } elsif ($prop eq "sort") {
        $col = "topicsort";
        unless ($value eq "alpha" || $value eq "date") {
            $error = 1;
            push @$out, [ "error", "Unknown status value \"$value\".  Consult the reference." ];
        }
    } else {
        $error = 1;
        push @$out, [ "error", "Unknown property \"$prop\".  Consult the reference." ];
    }
    
    return 0 if ($error);    

    my $qval = $dbh->quote($value);
    my $sth = $dbh->prepare("UPDATE topic_cats SET $col=$qval WHERE tpcatid=$catid");
    $sth->execute;
    if ($dbh->err) {
        push @$out, [ "error", $dbh->errstr ];
        return 0;
    }
    my $rows = $sth->rows;

    if ($rows) {
        push @$out, [ "info", "Success" ];
    } else {
        push @$out, [ "info", "Query performed, but property already had that value." ];
    }
    return 1;
}

1;
