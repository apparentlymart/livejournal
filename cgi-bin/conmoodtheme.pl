#!/usr/bin/perl
#

package LJ::Con;

$cmd{'moodtheme_create'}->{'handler'} = \&moodtheme_create;
$cmd{'moodtheme_public'}->{'handler'} = \&moodtheme_public;
$cmd{'moodtheme_setpic'}->{'handler'} = \&moodtheme_setpic;
$cmd{'moodtheme_list'}->{'handler'} = \&moodtheme_list;

sub moodtheme_list
{
    my ($dbh, $remote, $args, $out) = @_;
    
    if (scalar(@$args) > 2) {
        push @$out, [ "error", "This command takes only 1 optional argument.  Consult the reference." ];
        return 0;
    }

    my ($id) = ($args->[1]+0);
    my $sth;

    if ($id) {

        $sth = $dbh->prepare("SELECT m.mood, md.moodid, md.picurl, md.width, md.height FROM moodthemedata md, moods m WHERE md.moodid=m.moodid AND md.moodthemeid=$id ORDER BY m.mood");
        $sth->execute;
        while (my ($mood, $moodid, $picurl, $w, $h) = $sth->fetchrow_array) {
            push @$out, [ "", sprintf("%-20s %2dx%2d %s", "$mood ($moodid)", $w, $h, $picurl) ];
        }
        return 1;
    }

    push @$out, [ "", sprintf("%3s %4s %-15s %-25s %s", "pub", "id# ", "owner", "theme name", "des") ];
    push @$out, [ "", "-"x80 ];
    my $passes = 1;
    if ($remote) { $passes=2; }
    for (my $pass=1; $pass<=$passes ; $pass++) {
        if ($pass==1) {
            push @$out, [ "info", "Public themes:" ];
            $sth = $dbh->prepare("SELECT mt.moodthemeid, u.user, mt.is_public, mt.name, mt.des FROM moodthemes mt, user u WHERE mt.ownerid=u.userid AND mt.is_public='Y' ORDER BY mt.moodthemeid");
        } else {
            push @$out, [ "info", "Your themes:" ];
            $sth = $dbh->prepare("SELECT mt.moodthemeid, u.user, mt.is_public, mt.name, mt.des FROM moodthemes mt, user u WHERE mt.ownerid=u.userid AND mt.ownerid=$remote->{'userid'} ORDER BY mt.moodthemeid");
        }
        $sth->execute;
        if ($dbh->err) { push @$out, [ "error", $dbh->errstr ]; };
        while (my ($id, $user, $pub, $name, $des) = $sth->fetchrow_array) {
            push @$out, [ "", sprintf("%3s %4s %-15s %-25s %s", $pub ? " X " : "", $id, $user, $name, $des) ];
        }
    }

    return 1;
}

sub moodtheme_create
{
    my ($dbh, $remote, $args, $out) = @_;
    
    unless (scalar(@$args) == 3) {
        push @$out, [ "error", "This command takes exactly 2 arguments.  Consult the reference." ];
        return 0;
    }

    unless ($remote) {
        push @$out, [ "error", "You have to be logged in to use this command." ];
        return 0;
    }

    my $u = LJ::load_userid($remote->{'userid'});
    unless (LJ::get_cap($u, "moodthemecreate")) {
        push @$out, [ "error", "Sorry, your account type doesn't let you create new mood themes." ];
        return 0;
    }

    my ($name, $des) = ($args->[1], $args->[2]);
    my $qname = $dbh->quote($name);
    my $qdes = $dbh->quote($des);

    $sth = $dbh->prepare("INSERT INTO moodthemes (ownerid, name, des, is_public) VALUES ($remote->{'userid'}, $qname, $qdes, 'N')");
    $sth->execute;
    my $mtid = $dbh->{'mysql_insertid'};
    push @$out, [ "info", "Success.  Your new moodthemeid = $mtid" ];
}

sub moodtheme_public
{
    my ($dbh, $remote, $args, $out) = @_;
    
    unless ($remote->{'priv'}->{'moodthememanager'}) {
        push @$out, [ "error", "$remote->{'user'}, you are not authorized to use this command." ];
        return 0;
    }

    unless (scalar(@$args) == 3) {
        push @$out, [ "error", "This command takes exactly 2 arguments.  Consult the reference." ];
        return 0;
    }

    my ($themeid, $setting) = ($args->[1], $args->[2]);

    unless ($setting eq 'Y' || $setting eq 'N') {
        push @$out, [ "error", "Setting must be either 'Y' or 'N'." ];
        return 0;
    }

    $themeid += 0;
    
    my $sth;
    $sth = $dbh->prepare("SELECT is_public FROM moodthemes WHERE moodthemeid=$themeid");
    $sth->execute;
    my ($old_value) = $sth->fetchrow_array;
    unless ($old_value) {
        push @$out, [ "error", "This theme doesn't seem to exist." ];
        return 0;
    }

    if ($old_value eq $setting) {
        push @$out, [ "info", "Public setting not changed (already set to '$setting')" ];
        return 1;
    }

    my $qsetting = $dbh->quote($setting);
    $dbh->do("UPDATE moodthemes SET is_public=$qsetting WHERE moodthemeid=$themeid");

    push @$out, [ "info", "Public setting changed." ];
}

sub moodtheme_setpic
{
    my ($dbh, $remote, $args, $out) = @_;
    
    unless (scalar(@$args) == 6) {
        push @$out, [ "error", "This command takes exactly 5 arguments.  Consult the reference." ];
        return 0;
    }

    unless ($remote) {
        push @$out, [ "error", "You have to be logged in to use this command." ];
        return 0;
    }

    my $u = LJ::load_userid($remote->{'userid'});
    unless (LJ::get_cap($u, "moodthemecreate")) {
        push @$out, [ "error", "Sorry, your account type doesn't let you modify mood themes." ];
        return 0;
    }

    my ($themeid, $moodid, $picurl, $width, $height) =
        ($args->[1], $args->[2], $args->[3], $args->[4], $args->[5]);

    $themeid += 0;

    my $sth;
    $sth = $dbh->prepare("SELECT ownerid FROM moodthemes WHERE moodthemeid=$themeid");
    $sth->execute;
    my ($owner) = $sth->fetchrow_array;
    if ($owner != $remote->{'userid'}) {
        push @$out, [ "error", "You do not own this theme." ];
        return 0;
    }

    $width += 0;
    $height += 0;
    $moodid += 0;
    if (!$picurl || $width==0 || $height==0) {
        $dbh->do("DELETE FROM moodthemedata WHERE moodthemeid=$themeid AND moodid=$moodid");
        LJ::MemCache::delete([$themeid, "moodthemedata:$themeid"]);
        push @$out, [ "info", "Data deleted for theme=$themeid, moodid=$moodid." ];
        return 1;
    }

    my $qpicurl = $dbh->quote($picurl);
    $dbh->do("REPLACE INTO moodthemedata (moodthemeid, moodid, picurl, width, height) VALUES ($themeid, $moodid, $qpicurl, $width, $height)");
    LJ::MemCache::delete([$themeid, "moodthemedata:$themeid"]);
    if ($dbh->err) { push @$out, [ "error", $dbh->errstr ]; }
    
    push @$out, [ "", "Data inserted for theme=$themeid, moodid=$moodid." ];
    return 1;

}


