#!/usr/bin/perl
#

use strict;
use vars qw($dbh %maint);
use LWP::UserAgent;
use XML::RSS;
require "$ENV{'LJHOME'}/cgi-bin/ljprotocol.pl";

$maint{'synsuck'} = sub
{
    my $dbs = LJ::get_dbs();
    my $dbh = $dbs->{'dbh'};
    my $dbr = $dbs->{'reader'};
    my $sth;
    
    my $ua =  LWP::UserAgent->new("timeout" => 10);

    $sth = $dbh->prepare("SELECT u.user, s.userid, s.synurl, s.lastmod, s.etag ".
                         "FROM useridmap u, syndicated s ".
                         "WHERE u.userid=s.userid AND ".
                         "s.checknext < NOW() ORDER BY s.checknext");
    $sth->execute;
    while (my ($user, $userid, $synurl, $lastmod, $etag) = $sth->fetchrow_array)
    {
        my $delay = sub {
            my $hours = shift;
            $dbh->do("UPDATE syndicated SET checknext=DATE_ADD(NOW(), ".
                     "INTERVAL $hours DAY) WHERE userid=$userid");
        };

        print "Synsuck: $user ($synurl)\n";

        my $req = HTTP::Request->new("GET", $synurl);
        $req->header('If-Modified-Since', LJ::time_to_http($lastmod))
            if $lastmod;
        $req->header('If-None-Match', $etag)
            if $etag;

        my ($content, $too_big);
        my $res = $ua->request($req, sub {
            if (length($content) > 1024*150) { $too_big = 1; return; }
            $content .= $_[0];
        }, 4096);
        if ($too_big) { $delay->(24); next; }

        # check if not modified
        if ($res->status_line() =~ /^304/) {
            print "  not modified.\n";
            $delay->(6);
            next;
        }

        my $rss = new XML::RSS;
        $rss->parse($content);

        # lame check to see if parse failed:
        unless (ref $rss->{'items'} eq "ARRAY") { $delay->(24); next; }

        my @items = reverse @{$rss->{'items'}};

        # take most recent 20
        splice(@items, 0, @items-20) if @items > 20;
        
        # post these items
        my $newcount = 0;
        foreach my $it (@items) {
            my $dig = LJ::md5_struct($it)->b64digest;
            next if $dbh->selectrow_array("SELECT COUNT(*) FROM synitem WHERE ".
                                          "userid=$userid AND item=?", undef,
                                          $dig);
            $newcount++;
            print "$dig - $it->{'title'}\n";
            $it->{'description'} =~ s/^\s+//;
            $it->{'description'} =~ s/\s+$//;
            
            my @now = localtime();
            my $req = {
                'username' => $user,
                'ver' => 1,
                'subject' => $it->{'title'},
                'event' => "$it->{'link'}\n\n$it->{'description'}",
                'year' => $now[5]+1900,
                'mon' => $now[4]+1,
                'day' => $now[3],
                'hour' => $now[2],
                'min' => $now[1],
            };
            my $flags = {
                'nopassword' => 1,
            };

            my $err;
            my $res = LJ::Protocol::do_request($dbs, "postevent", $req, \$err, $flags);
            if ($res && ! $err) {
                sleep 1; # so 20 items in a row don't get the same logtime second value, so they sort correctly
                $dbh->do("INSERT INTO synitem (userid, item, dateadd) VALUES (?,?,NOW())",
                         undef, $userid, $dig);
            } else {
                print "  Error: $err\n";
            }
        }

        my $r_lastmod = LJ::http_to_time($res->header('Last-Modified'));
        my $r_etag = $res->header('ETag');

        # decide when to poll next (in minutes). 
        # FIXME: this is super lame.  (use hints in RSS file!)
        my $int = $newcount ? 30 : 60*6;
 
        $dbh->do("UPDATE syndicated SET checknext=DATE_ADD(NOW(), INTERVAL $int MINUTE), ".
                 "lastcheck=NOW(), lastmod=?, etag=? WHERE userid=$userid", undef,
                 $r_lastmod, $r_etag);

    }
};

1;
