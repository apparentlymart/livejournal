#!/usr/bin/perl
#

package Apache::LiveJournal;

use strict;
use Apache::Constants qw(:common REDIRECT HTTP_NOT_MODIFIED);
use Apache::File ();
use CGI;

my %RQ;       # per-request data
my %USERPIC;  # conf related to userpics

# init handler.
sub handler
{
    my $r = shift;

    $r->set_handlers(PerlTransHandler => [ \&trans ]);
    $r->push_handlers(PerlCleanupHandler => sub { %RQ = (); });
    
    $USERPIC{'cache_dir'} = "$ENV{'LJHOME'}/htdocs/userpics";
    $USERPIC{'use_disk_cache'} = -d $USERPIC{'cache_dir'};

    return OK;
}

sub trans
{
    my $r = shift;
    my $uri = $r->uri;
    my $host = $r->header_in("Host");

    LJ::start_request();

    return trans_userpic($r, $1) if $uri =~ m!^/userpic/(\d+)$!;

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

        %RQ = %$opts;
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

    return FORBIDDEN if $uri =~ m!^/userpics!;
    return DECLINED;
}

sub trans_userpic
{
    my $r = shift;
    my $picid = shift;

    # we can safely do this without checking since we never re-use
    # picture IDs and don't let the contents get modified
    return HTTP_NOT_MODIFIED if $r->header_in('If-Modified-Since');

    $RQ{'picid'} = $picid;

    my @dirs_make;
    my $file;
    if ($picid =~ /^\d*(\d\d)(\d\d\d)$/) {
        push @dirs_make, ("$USERPIC{'cache_dir'}/$2",
                          "$USERPIC{'cache_dir'}/$2/$1");
        $file = "$USERPIC{'cache_dir'}/$2/$1/$picid";
    } else {
        my $mod = sprintf("%03d", $picid % 1000);
        push @dirs_make, "$USERPIC{'cache_dir'}/$mod";
        $file = "$USERPIC{'cache_dir'}/$mod/p$picid";
    }

    if ($USERPIC{'use_disk_cache'}) {
        foreach (@dirs_make) {
            next if -d $_;
            mkdir $_, 0777;
        }
    }

    # set both, so we can compared later if they're the same,
    # and thus know if directories were created (if not,
    # apache will give us a pathinfo)
    $RQ{'userpicfile'} = $file;
    $r->filename($file);

    $r->handler("perl-script");
    $r->push_handlers(PerlHandler => \&content_userpic);
    return OK;
}

sub content_userpic
{
    my $r = shift;
    my $file = $r->filename;

    my $picid = $RQ{'picid'};

    # will we try to use disk cache?
    my $disk_cache = $USERPIC{'use_disk_cache'} && 
        $file eq $RQ{'userpicfile'};

    my ($pic, $data, $lastmod);
    my $need_cache;

    my $mime = "image/jpeg";
    my $set_mime = sub {
        my $data = shift;
        if ($data =~ /^GIF/) { $mime = "image/gif"; }
        elsif ($data =~ /^\x89PNG/) { $mime = "image/png"; }
    };
    my $size;

    my $send_headers = sub {
        $r->content_type($mime);
        $r->header_out("Content-length", $size);
        $r->header_out("Expires", LJ::time_to_http(time()+3000000));
        $r->header_out("Cache-Control", "no-transform");
        $r->header_out("Last-Modified", LJ::time_to_http($lastmod));
        $r->send_http_header();
    };

    # try to get it from disk if in disk-cache mode
    if ($disk_cache) {
        if (-s $r->finfo) {
            $lastmod = (stat _)[9];
            $size = -s _;
            my $fh = Apache::File->new($file);
            my $magic;
            read($fh, $magic, 4);
            $set_mime->($magic);
            $send_headers->();
            $r->print($magic);
            $r->send_fd($fh);
            $fh->close();
            return OK;
        } else {
            $need_cache = 1;
        }
    }

    # else, get it from db.
    unless ($data) {
        my $dbr = LJ::get_dbh("slave", "master");
        my $query = "SELECT p.state, p.userid, p.contenttype, UNIX_TIMESTAMP(p.picdate) ".
            "AS 'lastmod', u.clusterid, u.dversion FROM userpic p, user u WHERE ".
            "p.picid=$picid AND u.userid=p.userid";
        $pic = $dbr->selectrow_hashref($query);
        return NOT_FOUND unless $pic;

        $lastmod = $pic->{'lastmod'};
        if ($pic->{'dversion'} >= 2) {
            my $dbb = LJ::get_cluster_reader($pic->{'clusterid'});
            return SERVER_ERROR unless $dbb;
            $data = $dbb->selectrow_array("SELECT imagedata FROM userpicblob2 WHERE ".
                                          "userid=$pic->{'userid'} AND picid=$picid");
        } else {
            $data = $dbr->selectrow_array("SELECT imagedata FROM userpicblob WHERE ".
                                          "picid=$picid");
        }
    }

    return NOT_FOUND unless $data;

    if ($need_cache && open (F, ">$file")) {
        print F $data;
        close F;
    }

    $set_mime->($data);
    $size = length($data);
    $send_headers->();
    $r->print($data);
    return OK;
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

    if ($RQ{'vhost'} eq "users" && 
        $uri eq "/robots.txt") 
    {
        my $u = { 'user' => $RQ{'user'} };
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
	'args' => $RQ{'args'},
	'vhost' => $RQ{'vhost'},
	'env' => \%ENV,
    };

    my $user = $RQ{'user'};
    my $html = LJ::make_journal($dbs, $user, $RQ{'mode'},
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

    $r->content_type($opts->{'contenttype'});
    $r->header_out("Cache-Control", "private, proxy-revalidate");
    $r->header_out("Vary", "Accept-Encoding, Cookie");
    $r->header_out("Content-length", length($html));
    $r->send_http_header();
    $r->print($html);

    return OK;

}

1;
