#!/usr/bin/perl
#

package Apache::LiveJournal;

use strict;
use Apache::Constants qw(:common REDIRECT);
use Apache::File ();
use CGI;

my $journal_view;

sub trans
{
    my $r = shift;
    my $uri = $r->uri;
    my $host = $r->header_in("Host");

    LJ::start_request();

    my $redir = sub {
        my $url = shift;
        $r->content_type("text/html");
        $r->header_out(Location => $url);
        return REDIRECT;
    };
    
    my $journal_view = sub { 
        my $opts = shift;
        $opts ||= {};

        if ($opts->{'user'} ne lc($opts->{'user'})) {
            my $url = LJ::journal_base(lc($opts->{'user'}), $opts->{'vhost'}) .
                "/$opts->{'mode'}$opts->{'args'}";
            return $redir->($url);
        }

        $opts->{'user'} = LJ::canonical_username($opts->{'user'});

        if ($opts->{'mode'} eq "info") {
            return $redir->("$LJ::SITEROOT/userinfo.bml?user=$opts->{'user'}");
        }

        $journal_view = $opts;
        $r->handler("perl-script");
        $r->push_handlers(PerlHandler => \&journal_content);
        return OK;
    };

    if ($LJ::USER_VHOSTS && 
        $host =~ /^([\w\-]{1,15})\.\Q$LJ::USER_DOMAIN\E(:\d+)?$/ &&
        $1 ne "www") 
    {
        my $user = $1;
        return $journal_view->({'vhost' => 'users',
                                'mode' => $1,
                                'args' => $2,
                                'user' => $user, })
            if $uri =~ m!/(\w+)?([^\?]*)!;
        return $journal_view->(undef); # undef
    }

    if ($LJ::DOMAIN_PREPEND_WWW &&
        $host =~ /^\Q$LJ::DOMAIN\E(:\d+)?$/) 
    {
        $r->content_type("text/html");
        $r->header_out(Location => "$LJ::SITEROOT$uri");
        return REDIRECT;
    }

    # normal (non-domain) journal view
    if ($uri =~ m!
        ^/(users\/|community\/|\~)  # users/community/tilde
        (\w{1,15})                  # mandatory username
        (?:/(\w+)?)?                # optional /<viewname>
        ([^\?]*)                    # extra args
        !x && ($3 eq "" || defined $LJ::viewinfo{$3}))
    {
        my $vhost = { 'users/' => '', 'community/' => 'community',
                      '~' => 'tilde' }->{$1};
        return $journal_view->({'vhost' => $vhost,
                                'mode' => $3,
                                'args' => $4,
                                'user' => $2, });
    }

    return DECLINED;
}

sub content
{
    my $r = shift;
    my $uri = $r->uri;
    return DECLINED if $uri =~ /dev/;
    
    $r->content_type("text/html; charset=utf-8");
    $r->send_http_header();
    $r->print("$uri; " . $r->header_in("Host"));

    return OK;

}

sub journal_content
{
    my $r = shift;
    my $uri = $r->uri;

    my $dbs = LJ::get_dbs();

    if ($journal_view->{'vhost'} eq "users" && 
        $uri eq "/robots.txt") 
    {
        my $u = { 'user' => $journal_view->{'user'} };
        LJ::load_user_props($dbs, $u, "opt_blockrobots");
        $r->content_type("text/plain");
        $r->send_http_header();
        $r->print("User-Agent: *\n");
        if ($u->{'opt_blockrobots'}) {
            $r->print("Disallow: /\n");
        }
        return OK;
    }

    my $cgi = new CGI();
    my $criterr = 0;
    my $remote = LJ::get_remote($dbs, \$criterr, $cgi);

    # check for faked cookies here, since this is pretty central.
    if ($criterr) {
        $r->content_type("text/html");
        $r->send_http_header();
        $r->print("Invalid cookies.  Try <a href='$LJ::SITEROOT/logout.bml'>logging out</a> and then logging back in.\n");
        return OK;
    }

    my %headers = ();
    my $opts = {
	'headers' => \%headers,
	'args' => $journal_view->{'args'},
	'vhost' => $journal_view->{'vhost'},
	'env' => \%ENV,
    };

    my $user = $journal_view->{'user'};
    my $html = LJ::make_journal($dbs, $user, $journal_view->{'mode'},
                                $remote, $opts);

    my $status = $opts->{'status'} || "200 OK";
    unless ($opts->{'contenttype'}) {
        $opts->{'contenttype'} = "text/html";
        if ($LJ::UNICODE) {
            $opts->{'contenttype'} .= "; charset=utf-8";
        }
    }

    if ($opts->{'badargs'}) 
    {
	$status = "404 Not Found";
	$html = "<H1>Not Found</H1>Unknown page or arguments.";
    }
    elsif ($opts->{'baduser'}) 
    {
	$status = "404 Unknown User";
	$html = "<H1>Unknown User</H1>There is no user <b>$user</b> at $LJ::SITENAME.";
    }

    unless ($html) {
	$html = "<h1>Error</h1><p>User <b>$user</b> has messed up their journal template definition.</p>";
    }
    
    $r->status_line($status);
    foreach my $hname (keys %headers) {
        if (ref($headers{$hname}) && ref($headers{$hname}) eq "ARRAY") {
            foreach (@{$headers{$hname}}) {
                $r->header_out($hname, $_);
            }
        } else {
            $r->header_out($hname, $headers{$hname});
        }
    }

    if ($opts->{'nocontent'}) {
        $r->send_http_header();
        return OK;
    }

    $r->header_out("Content-type", $opts->{'contenttype'});
    $r->header_out("Cache-Control", "private, proxy-revalidate");
    $r->header_out("Vary", "Accept-Encoding, Cookie");
    $r->header_out("Content-length", length($html));
    $r->send_http_header();
    $r->print($html);

    return OK;

}

1;
