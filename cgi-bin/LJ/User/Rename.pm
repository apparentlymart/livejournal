package LJ::User::Rename;
use strict;
use warnings;

## namespace for user-renaming actions

##
## Input: 
##      username 'to'
##      [optional] user object who wants to take the username 'to'
##      [optional] hashref with options
## Output: 1 or 0
##      $opts->{error} is text of error
##
sub can_reuse_account {
    my $to = shift;
    my $u = shift;
    my $opts = shift || {};

    my $tou = LJ::load_user($to);
    
    ## no user - the name can be occupied
    return 1 unless $tou;

    if ($tou->is_expunged) {
        # expunged usernames can be moved away. they're already deleted.
        return 1;
    } elsif ($u && lc($tou->email_raw) eq lc($u->email_raw) && $tou->is_visible && $tou->is_person) {
        if ($tou->password eq $u->password) {
            if (!$tou->is_validated || !$u->is_validated) {
                $opts->{error} = BML::ml('htdocs/rename/use.bml.error.notvalidated');
            } else {
                return 1;
            }
        } else {
            $opts->{error} = BML::ml('htdocs/rename/use.bml.error.badpass');
        }
    } else {
        $opts->{error} = BML::ml('htdocs/rename/use.bml.error.usernametaken');
    }
    return 0;
}

##
## Input:
##  [optional] template name (will be used as prefix)
##  [optional] proposed name (will be used first if not taken)
## Output:
##  free username, or undef in case of errors
##
sub get_unused_name {
    my $tempname = shift;
    my $proposed_name = shift;
    
    my $exname;
    $tempname ||= "ljswap_00";   
    $tempname = substr($tempname, 0, 9) if length($tempname) > 9;
    my $dbh = LJ::get_db_writer();
    for my $i (1..10) {
        # first try the proposed name 
        if ($i == 1 && $proposed_name) {
            $exname = $proposed_name;
        # otherwise we either didn't have one or it's been
        # taken in the meantime?
        } else {
            $exname = "ex_$tempname" . int(rand(999));
        }

        # check to see if this exname already exists
        unless ($dbh->selectrow_array("SELECT COUNT(*) FROM user WHERE user=?",
                                      undef, $exname)) {
            return if $dbh->err;
            return $exname;
        }
        # name existed, try and get another
    }
    return; 
}

##
## input: username 'from', username 'to', [optional] options hashref
## output: true or false 
##      $opts->{error} is text of error
sub basic_rename {
    my ($from, $to, $opts) = @_;

    $opts ||= {};
    ($from, $to) = map { LJ::canonical_username($_) } @_;
    unless ($from ne "" && $to ne "") {
        $opts->{error} = "Empty username";
        return;
    }

    my $u = LJ::load_user($from);
    unless ($u) {
        $opts->{error} = "No such user: $from";
        return;    
    }

    LJ::run_hooks('rename_user', $u, $to);

    my $dbh = LJ::get_db_writer();
    foreach my $table (qw(user useridmap overrides style))
    {
        $dbh->do("UPDATE $table SET user=? WHERE user=?",
                 undef, $to, $from);
        if ($dbh->err) {
            $opts->{error} = "Database error: " . $dbh->errstr;
            return;
        }
    }
    
    ## Done.
    ## From now on, there may be errors but the rename is actually done.

    # deal with cases of renames
    foreach my $col (qw(fromuser touser)) {
        my $sth = $dbh->prepare("UPDATE renames SET $col=? WHERE $col=?");
        $sth->execute($to, $from);
        $opts->{error} = "Database error: " . $dbh->errstr
            if $dbh->err;
    }

    LJ::memcache_kill($u, "userid");
    LJ::MemCache::delete("uidof:$from");
    LJ::MemCache::delete("uidof:$to");

    # don't want either of these usernames to show up as 'hey check what we expunged'
    $dbh->do("DELETE FROM expunged_users WHERE user IN (?, ?)",
             undef, $from, $to);

    LJ::infohistory_add($u, 'username', $from);

    # tell all web machines to clear their caches for this userid/name mapping
    LJ::procnotify_add("rename_user", { 'userid' => $u->{'userid'},
                                        'user' => $u->{'user'} });
    
    LJ::run_hooks("account_changed", { userid => $u->id() });

    ## update or create record in 'renames' table
    if ($opts->{renid}) {
        $dbh->do("UPDATE renames SET userid=?, fromuser=?, touser=?, rendate=NOW() WHERE renid=?",
            undef, $u->{'userid'}, $from, $to, $opts->{renid}
        );
    } else {
        my $token = $opts->{token} || "[unknown]";
        $dbh->do("INSERT INTO renames (token, payid, userid, fromuser, touser, rendate) ".
             "VALUES (?,0,?,?,?,NOW())", undef, $token, $u->{'userid'}, $from, $to,
        );
    }
    $opts->{error} = $dbh->err if $dbh->err;
    
    my @date = localtime(time);
    LJ::Event::SecurityAttributeChanged->new($u ,  { 
        action       => 'account_renamed', 
        old_username => $from, 
        ip           => BML::get_remote_ip(),
        datetime     => sprintf("%02d:%02d %02d/%02d/%04d", @date[2,1], $date[3], $date[4]+1, $date[5]+1900),
    })->fire;

    return 1;
}

1;

