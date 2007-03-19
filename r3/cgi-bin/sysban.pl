#!/usr/bin/perl
#

use strict;

package LJ;

# <LJFUNC>
# name: LJ::sysban_check
# des: Given a 'what' and 'value', checks to see if a ban exists
# args: what, value
# des-what: The ban type
# des-value: The value which triggers the ban
# returns: 1 if a ban exists, 0 otherwise
# </LJFUNC>
sub sysban_check {
    my ($what, $value) = @_;

    # cache if ip ban
    if ($what eq 'ip') {

        my $now = time();
        my $ip_ban_delay = $LJ::SYSBAN_IP_REFRESH || 120; 

        # check memcache first if not loaded
        unless ($LJ::IP_BANNED_LOADED + $ip_ban_delay > $now) {
            my $memval = LJ::MemCache::get("sysban:ip");
            if ($memval) {
                *LJ::IP_BANNED = $memval;
                $LJ::IP_BANNED_LOADED = $now;
            } else {
                $LJ::IP_BANNED_LOADED = 0;
            }
        }
        
        # is it already cached in memory?
        if ($LJ::IP_BANNED_LOADED) {
            return (defined $LJ::IP_BANNED{$value} &&
                    ($LJ::IP_BANNED{$value} == 0 ||     # forever
                     $LJ::IP_BANNED{$value} > time())); # not-expired
        }

        my $dbh = LJ::get_db_writer();
        return undef unless $dbh;

        # build cache from db
        %LJ::IP_BANNED = ();
        my $sth = $dbh->prepare("SELECT value, UNIX_TIMESTAMP(banuntil) FROM sysban " .
                                "WHERE status='active' AND what='ip' " .
                                "AND NOW() > bandate " .
                                "AND (NOW() < banuntil OR banuntil IS NULL)");
        $sth->execute;
        return undef if $dbh->err;
        while (my ($val, $exp) = $sth->fetchrow_array) {
            $LJ::IP_BANNED{$val} = $exp || 0;
        }

        # set in memcache
        LJ::MemCache::set("sysban:ip", \%LJ::IP_BANNED, $ip_ban_delay);
        $LJ::IP_BANNED_LOADED = time();

        # return value to user
        return $LJ::IP_BANNED{$value};
    }

    # cache if uniq ban
    if ($what eq 'uniq') {

        # check memcache first if not loaded
        unless ($LJ::UNIQ_BANNED_LOADED) {
            my $memval = LJ::MemCache::get("sysban:uniq");
            if ($memval) {
                *LJ::UNIQ_BANNED = $memval;
                $LJ::UNIQ_BANNED_LOADED++;
            }
        }

        # is it already cached in memory?
        if ($LJ::UNIQ_BANNED_LOADED) {
            return (defined $LJ::UNIQ_BANNED{$value} &&
                    ($LJ::UNIQ_BANNED{$value} == 0 ||     # forever
                     $LJ::UNIQ_BANNED{$value} > time())); # not-expired
        }

        my $dbh = LJ::get_db_writer();
        return undef unless $dbh;

        # set this now before the query
        $LJ::UNIQ_BANNED_LOADED++;

        # build cache from db
        %LJ::UNIQ_BANNED = ();
        my $sth = $dbh->prepare("SELECT value, UNIX_TIMESTAMP(banuntil) FROM sysban " .
                                "WHERE status='active' AND what='uniq' " .
                                "AND NOW() > bandate " .
                                "AND (NOW() < banuntil OR banuntil IS NULL)");
        $sth->execute();
        return undef $LJ::UNIQ_BANNED_LOADED if $sth->err;
        while (my ($val, $exp) = $sth->fetchrow_array) {
            $LJ::UNIQ_BANNED{$val} = $exp || 0;
        }

        # set in memcache
        my $exp = 60*15; # 15 minutes
        LJ::MemCache::set("sysban:uniq", \%LJ::UNIQ_BANNED, $exp);

        # return value to user
        return $LJ::UNIQ_BANNED{$value};
    }

    # need the db below here
    my $dbh = LJ::get_db_writer();
    return undef unless $dbh;

    # standard check helper
    my $check = sub {
        my ($wh, $vl) = @_;

        return $dbh->selectrow_array(qq{
                SELECT COUNT(*)
                FROM sysban
                WHERE status = 'active'
                  AND what = ?
                  AND value = ?
                  AND NOW() > bandate
                  AND (NOW() < banuntil
                       OR banuntil = 0
                       OR banuntil IS NULL)
            }, undef, $wh, $vl);
    };

    # check both ban by email and ban by domain if we have an email address
    if ($what eq 'email') {
        # short out if this email really is banned directly, or if we can't parse it
        return 1 if $check->('email', $value);
        return 0 unless $value =~ /@(.+)$/;

        # see if this domain is banned
        my @domains = split(/\./, $1);
        return 0 unless scalar @domains >= 2;
        return 1 if $check->('email_domain', "$domains[-2].$domains[-1]");

        # must not be banned
        return 0;
    }

    # non-ip bans come straight from the db
    return $check->($what, $value);
}

# <LJFUNC>
# name: LJ::sysban_note
# des: Inserts a properly-formatted row into statushistory noting that a ban has been triggered
# args: userid?, notes, vars
# des-userid: The userid which triggered the ban, if available
# des-notes: A very brief description of what triggered the ban
# des-vars: A hashref of helpful variables to log, keys being variable name and values being values
# returns: nothing
# </LJFUNC>
sub sysban_note
{
    my ($userid, $notes, $vars) = @_;

    $notes .= ":";
    map { $notes .= " $_=$vars->{$_};" if $vars->{$_} } sort keys %$vars;
    LJ::statushistory_add($userid, 0, 'sysban_trig', $notes);

    return;
}

# <LJFUNC>
# name: LJ::sysban_block
# des: Notes a sysban in statushistory and returns a fake http error message to the user
# args: userid?, notes, vars
# des-userid: The userid which triggered the ban, if available
# des-notes: A very brief description of what triggered the ban
# des-vars: A hashref of helpful variables to log, keys being variable name and values being values
# returns: nothing
# </LJFUNC>
sub sysban_block
{
    my ($userid, $notes, $vars) = @_;

    LJ::sysban_note($userid, $notes, $vars);

    my $msg = <<'EOM';
<html>
<head>
<title>503 Service Unavailable</title>
</head>
<body>
<h1>503 Service Unavailable</h1>
The service you have requested is temporarily unavailable.
</body>
</html>
EOM

    # may not run from web context (e.g. mailgated.pl -> supportlib -> ..)
    eval { BML::http_response(200, $msg); };

    return;
}

1;
