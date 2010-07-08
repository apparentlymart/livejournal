package LJ::User::Rename;
use strict;
use warnings;

use LJ::Request;
use LJ::Event::SecurityAttributeChanged;

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

    if ($u->{'user'} eq $to) {
        $opts->{error} = LJ::Lang::ml('/rename/use.bml.error.same');
        return 0;
    }

    if ($tou->is_expunged) {
        # expunged usernames can be moved away. they're already deleted.
        return 1;
    } elsif ($u && lc($tou->email_raw) eq lc($u->email_raw) && $tou->is_visible && $tou->is_person) {
        if ($tou->password eq $u->password) {
            if (!$tou->is_validated || !$u->is_validated) {
                $opts->{error} = LJ::Lang::ml('/rename/use.bml.error.notvalidated');
            } else {
                return 1;
            }
        } else {
            $opts->{error} = LJ::Lang::ml('/rename/use.bml.error.badpass');
        }
    } else {
        $opts->{error} = LJ::Lang::ml('/rename/use.bml.error.usernametaken');
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
    
    my $exname;
    $tempname ||= "lj_swap_"; # 'ex_lj_swap_00893' is too long - so omit '00'
    $tempname = substr($tempname, 0, 8) if length($tempname) > 8;
    my $dbh = LJ::get_db_writer();
    for my $i (1..10) {
        if ($i == 1) {
            $exname = "ex_$tempname";
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
## Input: 
##      username 'from', 
##      username 'to', 
##      [optional] options hashref
## Options:
##      renid                   - ID of the row to update in 'renames' table (for old rename tokens only)
##      preserve_old_username   - If true, an account with the old username will be created
##      opt_delfriends          - If true, no friends from old name will be transferred to new one
##      opt_delfriendofs        - If true, no friends-of will be transferred
##      opt_redir               - If true and 'preserve_old_username' is true, then
##                                the account created with old username will be 'redirect' flagged.
##                                This option is 'on' by default for non-personal accounts (historically)
##      $opts->{token} || "[unknown]" will be put into 'renames' DB table if $opts->{renid} is false
## Output: 
##      true or false 
##      $opts->{error} is text of error
##
sub basic_rename {
    my ($from, $to, $opts) = @_;

    $opts ||= {};
    ($from, $to) = map { LJ::canonical_username($_) } @_;
    unless ($from ne "") {
        $opts->{error} = "Empty username";
        return;
    }

    my $u = LJ::load_user($from);
    unless ($u) {
        $opts->{error} = "No such user: $from";
        return;    
    }

    my $dbh = LJ::get_db_writer();

    my $actual_rename = sub {
        my ($from, $to) = @_;
        foreach my $table (qw(user useridmap overrides style)) {
            $dbh->do("UPDATE $table SET user=? WHERE user=?",
                     undef, $to, $from);
            return 1 if $dbh->err;
        }
        return 0;
    };

    my $err;
    if ($to) {
        $err = $actual_rename->($from, $to);
    } else { # move away destination name as additional rename step
        for my $i (1..3) {
            $to = get_unused_name($from);
            $err = $actual_rename->($from, $to);
            last unless $err; # renamed ok? fix name!
        }
    }
    if ($err) {
        $opts->{error} = "Database error: " . $dbh->errstr;
        return;
    }
    
    ## Done.
    ## From now on, there may be errors but the rename is actually done.

    LJ::run_hooks('rename_user', $u, $to);

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
    
    $u->kill_session;

    my @date = localtime(time);
    LJ::Event::SecurityAttributeChanged->new($u ,  { 
        action       => 'account_renamed', 
        old_username => $from, 
        ip           => ($opts->{ip} || (LJ::is_web_context() ? LJ::Request->remote_ip() : '127.0.0.1')),
        datetime     => sprintf("%02d:%02d %02d/%02d/%04d", @date[2,1], $date[3], $date[4]+1, $date[5]+1900),
    })->fire;


    if ($u->{journaltype} eq 'P') {
        ## "Remove all users from your Friends list and leave all communities"
        if ($opts->{opt_delfriends}) {
            # delete friends
            my $friends = LJ::get_friends($u, undef, undef, 'force') || {};
            LJ::remove_friend($u, [ keys %$friends ], { 'nonotify' => 1 });
        
            # delete access to post to communities
            LJ::clear_rel('*', $u, 'P');
        
            # delete friend-ofs that are communities
            # TAG:fr:bml_rename_use:get_member_of
            my $users = $dbh->selectcol_arrayref(qq{
                SELECT u.userid FROM friends f, user u 
                    WHERE f.friendid=$u->{'userid'} AND 
                    f.userid=u.userid and u.journaltype <> 'P'
            });
            if ($users && @$users) {
                my $in = join(',', @$users);
                $dbh->do("DELETE FROM friends WHERE friendid=$u->{'userid'} AND userid IN ($in)");
                LJ::memcache_kill($_, "friends") foreach @$users;
            }
        }
    
        ## "Remove everyone from your Friend Of list"
        if ($opts->{'opt_delfriendofs'}) {
            # delete people (only people) who list this user as a friend
            my $users = $dbh->selectcol_arrayref(qq{
                SELECT u.userid FROM friends f, user u 
                    WHERE f.friendid=$u->{'userid'} AND 
                    f.userid=u.userid and u.journaltype = 'P'
            });
            if ($users && @$users) {
                my $in = join(',', @$users);
                $dbh->do("DELETE FROM friends WHERE friendid=$u->{'userid'} AND userid IN ($in)");
                LJ::memcache_kill($_, "friends") foreach @$users;
            }
        }

        # delete friend of memcaching, as either path might have done it
        LJ::MemCache::delete([ $u->{userid}, "friendofs:$u->{userid}" ]);
    }
    
    my $u_old_username;
    if ($opts->{preserve_old_username}) {
        # we need to create an account even in case the user chose to disconnect
        # the old username; the older username is kept deleted for a while
        # so as to 1) not allow strangers to obtain it right after the rename
        # is complete, and 2) to allow the Billing team to fix it if the user
        # has made a mistake; the Billing team uses rename_redir console command,
        # see /admin/console and cgi-bin/LJ/Console/Command/RenameRedir.pm
        $u_old_username = LJ::create_account({
            'user' => $from,
            'password' => '',
            'name' => '[renamed acct]',
        });
        my $alias_changed = $dbh->do("UPDATE email_aliases SET alias=? WHERE alias=?",
                                     undef, "$to\@$LJ::USER_DOMAIN",
                                     "$from\@$LJ::USER_DOMAIN");

        if ($u->{journaltype} ne 'P' || $opts->{'opt_redir'}) {
            LJ::update_user($u_old_username, { raw => "journaltype='R', statusvis='R', statusvisdate=NOW()" });
            LJ::set_userprop($dbh, $u_old_username, "renamedto", $to); # 'from' will point to 'to'
            if ($u->prop('renamedto')) {
                $u->set_prop('renamedto', undef) if $u->prop('renamedto') eq $from; # safeness against circular redirection
            }
            if ($alias_changed > 0) {
                $dbh->do("INSERT INTO email_aliases VALUES (?,?)", undef,
                     "$u->{'user'}\@$LJ::USER_DOMAIN", 
                     $u->email_raw);
            }
        } else {
            LJ::update_user($u_old_username, { journaltype => $u->{journaltype}, raw => "statusvis='D', statusvisdate=NOW()" });
        }
    }   

    return $to;
}

1;

