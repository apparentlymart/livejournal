#!/usr/bin/perl
#

package Apache::LiveJournal;

use strict;
use Apache::Constants qw(:common REDIRECT HTTP_NOT_MODIFIED HTTP_MOVED_PERMANENTLY);
use Apache::File ();
use XMLRPC::Transport::HTTP ();

require "$ENV{'LJHOME'}/cgi-bin/ljlib.pl";
require "$ENV{'LJHOME'}/cgi-bin/ljviews.pl";
require "$ENV{'LJHOME'}/cgi-bin/ljprotocol.pl";

my %RQ;       # per-request data
my %USERPIC;  # conf related to userpics
my %REDIR;

$USERPIC{'cache_dir'} = "$ENV{'LJHOME'}/htdocs/userpics";
$USERPIC{'use_disk_cache'} = -d $USERPIC{'cache_dir'};

# redirect data.
open (REDIR, "$ENV{'LJHOME'}/cgi-bin/redirect.dat");
while (<REDIR>) {
    next unless (/^(\S+)\s+(\S+)/);
    my ($src, $dest) = ($1, $2);
    $REDIR{$src} = $dest;
}
close REDIR;

# init handler (PostReadRequest)
sub handler
{
    my $r = shift;

    if ($LJ::SERVER_TOTALLY_DOWN) {
        $r->handler("perl-script");
        $r->set_handlers(PerlHandler => [ \&totally_down_content ]);
        return OK;
    }

    $r->set_handlers(PerlTransHandler => [ \&trans ]);
    $r->set_handlers(PerlCleanupHandler => [ sub { %RQ = () },
                                             "Apache::LiveJournal::db_logger" ]);

    # if we're behind a lite mod_proxy front-end, we need to trick future handlers
    # into thinking they know the real remote IP address.  problem is, it's complicated
    # by the fact that mod_proxy did nothing, requiring mod_proxy_add_forward, then
    # decided to do X-Forwarded-For, then did X-Forwarded-Host, so we have to deal
    # with all permutations of versions, hence all the ugliness:
    if (my $forward = $r->header_in('X-Forwarded-For'))
    {
        my (@hosts, %seen);
        foreach (split(/\s*,\s*/, $forward)) {
            next if $seen{$_}++;
            push @hosts, $_;
        }
        if (@hosts) {
            my $real = pop @hosts;
            $r->connection->remote_ip($real);
        }
        $r->header_in('X-Forwarded-For', join(", ", @hosts));
    }
       
    # and now, deal with getting the right Host header
    if ($_ = $r->header_in('X-Host')) {
        $r->header_in('Host', $_);
    } elsif ($_ = $r->header_in('X-Forwarded-Host')) {
        $r->header_in('Host', $_);
    }

    return OK;
}

sub redir
{
    my ($r, $url, $code) = @_;
    $r->content_type("text/html");
    $r->header_out(Location => $url);
    return $code || REDIRECT;
}

sub totally_down_content
{
    my $r = shift;
    my $uri = $r->uri;

    if ($uri =~ m!^/interface/flat! || $uri =~ m!^/cgi-bin/log\.cg!) {
        $r->content_type("text/plain");
	$r->send_http_header();
        $r->print("success\nFAIL\nerrmsg\n$LJ::SERVER_DOWN_MESSAGE");
        return OK;
    }

    if ($uri =~ m!^/customview.cgi!) {
        $r->content_type("text/html");
	$r->send_http_header();
        $r->print("<!-- $LJ::SERVER_DOWN_MESSAGE -->");
        return OK;
    }
    
    # FIXME: ljcom-specific, move to a hook; too lazy now.
    if ($uri =~ m!^/paidaccounts/pp_notify\.bml!) {
        $r->status(SERVER_ERROR);
    }

    $r->content_type("text/html");
    $r->send_http_header();
    $r->print("<h1>$LJ::SERVER_DOWN_SUBJECT</h1>$LJ::SERVER_DOWN_MESSAGE");
    return OK;
}

sub trans
{
    my $r = shift;
    my $uri = $r->uri;
    my $args = $r->args;
    my $args_wq = $args ? "?$args" : "";
    my $host = $r->header_in("Host");
    my $hostport = ($host =~ s/:\d+$//) ? $& : "";

    # let foo.com still work, but redirect to www.foo.com
    if ($LJ::DOMAIN_WEB && $r->method eq "GET" &&
        $host eq $LJ::DOMAIN && $LJ::DOMAIN_WEB ne $LJ::DOMAIN) 
    {
        my $url = "$LJ::SITEROOT$uri";
        $url .= "?" . $args if $args;
        return redir($r, $url);
    }

    LJ::start_request();

    my $journal_view = sub { 
        my $opts = shift;
        $opts ||= {};

        $opts->{'user'} = LJ::canonical_username($opts->{'user'});

        if ($opts->{'mode'} eq "info") {
            return redir($r, "$LJ::SITEROOT/userinfo.bml?user=$opts->{'user'}");
        }

        if ($opts->{'user'} ne lc($opts->{'user'})) {
            my $url = LJ::journal_base(lc($opts->{'user'}), $opts->{'vhost'}) .
                "/$opts->{'mode'}$opts->{'pathextra'}$args_wq";
            return redir($r, $url);
        }

        %RQ = %$opts;
        $r->handler("perl-script");
        $r->push_handlers(PerlHandler => \&journal_content);
        return OK;
    };

    # user domains
    if ($LJ::USER_VHOSTS && 
        $host =~ /^([\w\-]{1,15})\.\Q$LJ::USER_DOMAIN\E$/ &&
        $1 ne "www") 
    {
        my $user = $1;
        return $journal_view->({'vhost' => 'users',
                                'mode' => $1,
                                'pathextra' => $2,
                                'args' => $args,
                                'user' => $user, })
            if $uri =~ m!/(\w+)?(.*)!;
        return $journal_view->(undef);
    }

    # custom used-specified domains
    if ($LJ::OTHER_VHOSTS && $host ne $LJ::DOMAIN_WEB &&
        $host ne $LJ::DOMAIN && $host =~ /\./ &&
        $host =~ /[^\d\.]/)
    {
        my $dbr = LJ::get_dbh("slave", "master");
        my $checkhost = lc($host);
        $checkhost =~ s/^www\.//i;
        $checkhost = $dbr->quote($checkhost);
        my $user = $dbr->selectrow_array(qq{
            SELECT u.user FROM useridmap u, domains d WHERE
            u.userid=d.userid AND d.domain=$checkhost
        });
        return $journal_view->({'vhost' => "other:$host$hostport",
                                'mode' => $1,
                                'pathextra' => $2,
                                'args' => $args,
                                'user' => $user, })
            if $user && $uri =~ m!^/(\w*)(.*)!;
        return $journal_view->(undef);
    }

    # userpic
    return userpic_trans($r, $1) if $uri =~ m!^/userpic/(\d+)$!;

    # front page journal
    if ($LJ::FRONTPAGE_JOURNAL && $uri =~ m!^/(\w+)?(.*)$! &&
        ($1 eq "" || defined $LJ::viewinfo{$1}))
    {
        my ($mode, $pe) = ($1, $2);
        return DECLINED if $pe =~ m!\.bml|\.html$!;
        return $journal_view->({'vhost' => 'front',
                                'mode' => $mode,
                                'args' => $args,
                                'pathextra' => $pe,
                                'user' => $LJ::FRONTPAGE_JOURNAL, });
    }

    # normal (non-domain) journal view
    if ($uri =~ m!
        ^/(users\/|community\/|\~)  # users/community/tilde
        (\w{1,15})                  # mandatory username
        (?:/(\w+)?)?                # optional /<viewname>
        (.*)?                       # path extra: /FriendGroup, for example
        !x && ($3 eq "" || defined $LJ::viewinfo{$3}))
    {
        my ($part1, $user, $mode, $pe) = ($1, $2, $3, $4);
        my $vhost = { 'users/' => '', 'community/' => 'community',
                      '~' => 'tilde' }->{$part1};
        return DECLINED if $vhost eq "community" && $uri =~ m!\.bml|\.html$!;
        return $journal_view->({'vhost' => $vhost,
                                'mode' => $mode,
                                'args' => $args,
                                'pathextra' => $pe,
                                'user' => $user, });
    }

    # protocol support
    if ($uri =~ m!^/(interface(/flat|/xmlrpc)?)|cgi-bin/log\.cgi!) {
        $RQ{'interface'} = $1 ? ($2 eq "/flat" ? "flat" : ($2 eq "/xmlrpc" ? "xmlrpc" : "")) : "flat";
        $r->handler("perl-script");
        $r->push_handlers(PerlHandler => \&interface_content);
        return OK;
    }

    # customview
    if ($uri =~ m!^/customview\.cgi!) {
        $r->handler("perl-script");
        $r->push_handlers(PerlHandler => \&customview_content);
        return OK;
    }

    # redirected resources
    if ($REDIR{$uri}) {
        my $new = $REDIR{$uri};
        if ($r->args) { $new .= "?" . $r->args; }
        return redir($r, $new, HTTP_MOVED_PERMANENTLY);
    }

    # confirm
    if ($uri =~ m!^/confirm/(\w+\.\w+)!) {
        return redir($r, "$LJ::SITEROOT/register.bml?$1");
    }

    return FORBIDDEN if $uri =~ m!^/userpics!;
    return DECLINED;
}

sub userpic_trans
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
    $r->push_handlers(PerlHandler => \&userpic_content);
    return OK;
}

sub userpic_content
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
    $r->print($data) unless $r->header_only;
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

    my $criterr = 0;
    my $remote = LJ::get_remote($dbs, \$criterr);

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
        'pathextra' => $RQ{'pathextra'},
        'header' => {
            'If-Modified-Since' => $r->header_in("If-Modified-Since"),
        },
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
    $r->header_out("Content-length", length($html));
    $r->send_http_header();
    $r->print($html) unless $r->header_only;
    return OK;
}

sub customview_content
{
    my $r = shift;
    my $dbs = LJ::get_dbs();

    my %FORM = $r->args;

    my $charset = "utf-8";
    
    if ($LJ::UNICODE && $FORM{'charset'}) {
        $charset = $FORM{'charset'};
        if ($charset ne "utf-8" && ! Unicode::MapUTF8::utf8_supported_charset($charset)) {
            $r->content_type("text/html");
            $r->send_http_header();
            $r->print("<b>Error:</b> requested charset not supported.");
            return OK;
        }
    }    
    
    my $ctype = "text/html";
    if ($FORM{'type'} eq "xml") {
	$ctype = "text/xml";
    }

    if ($LJ::UNICODE) {
        $ctype .= "; charset=$charset";
    }

    $r->content_type($ctype);

    my $user = $FORM{'username'} || $FORM{'user'};
    my $styleid = $FORM{'styleid'} + 0;
    my $nooverride = $FORM{'nooverride'} ? 1 : 0;

    my $remote;
    if ($FORM{'checkcookies'}) {
	my $criterr = 0;
	$remote = LJ::get_remote($dbs, \$criterr);
    }

    my $data = (LJ::make_journal($dbs, $user, "", $remote,
				 { "nocache" => $FORM{'nocache'}, 
				   "vhost" => "customview",
				   "nooverride" => $nooverride,
				   "styleid" => $styleid,
                                   "saycharset" => $charset,
                                   "args" => scalar $r->args,
			       })
		|| "<b>[$LJ::SITENAME: Bad username, styleid, or style definition]</b>");
    
    if ($FORM{'enc'} eq "js") {
	$data =~ s/\\/\\\\/g;
	$data =~ s/\"/\\\"/g;
	$data =~ s/\n/\\n/g;
	$data =~ s/\r//g;
	$data = "document.write(\"$data\")";
    }

    if ($LJ::UNICODE && $charset ne 'utf-8') {
        $data = Unicode::MapUTF8::from_utf8({-string=>$data, -charset=>$charset});
    }

    $r->header_out("Cache-Control", "must-revalidate");
    $r->header_out("Content-Length", length($data));
    $r->send_http_header();
    $r->print($data) unless $r->header_only;
    return OK;
}

sub interface_content
{
    my $r = shift;
    my $args = $r->args;

    if ($RQ{'interface'} eq "xmlrpc") {
        my $server = XMLRPC::Transport::HTTP::Apache
            -> on_action(sub { die "Access denied\n" if $_[2] =~ /:|\'/ })
            -> dispatch_to('LJ::XMLRPC')
            -> handle($r);
        return OK;
    }

    if ($RQ{'interface'} ne "flat") {
        $r->content_type("text/plain");
        $r->send_http_header;
        $r->print("Unknown interface.");
        return OK;
    }

    $r->content_type("text/plain");

    my $dbs = LJ::get_dbs();
    my $dbh = $dbs->{'dbh'};

    my %out = ();
    my %FORM = ();
    my $content;
    $r->read($content, $r->header_in("Content-Length"));
    LJ::decode_url_string($content, \%FORM);
    
    # the protocol needs the remote IP in just one place, where tracking is done.
    $ENV{'_REMOTE_IP'} = $r->connection()->remote_ip();
    LJ::do_request($dbs, \%FORM, \%out);

    if ($FORM{'responseenc'} eq "urlenc") {
        $r->send_http_header;
        foreach (sort keys %out) {
            $r->print(LJ::eurl($_) . "=" . LJ::eurl($out{$_}) . "&");
        }
        return OK;
    }

    my $length = 0;
    foreach (sort keys %out) {
        $length += length($_)+1;
        $length += length($out{$_})+1;
    }

    $r->header_out("Content-length", $length);
    $r->send_http_header;
    foreach (sort keys %out) {
        $r->print($_, "\n", $out{$_}, "\n");
    }

    return OK;
}

sub db_logger
{
    my $r = shift;
    my $rl = $r->last;

    my $ctype = $rl->content_type;
    return if $ctype =~ m!^image/! and $LJ::DONT_LOG_IMAGES;

    my $dbl = LJ::get_dbh("logs");
    return unless $dbl;

    my @now = localtime();
    my $table = sprintf("access%04d%02d%02d", $now[5]+1900,
                        $now[4]+1, $now[3]);
    
    unless ($LJ::CACHED_LOG_CREATE{"$dbl-$table"}) {
        $dbl->do("CREATE TABLE IF NOT EXISTS $table (".
                 "whn DATETIME NOT NULL,".
                 "server VARCHAR(30),".
                 "addr VARCHAR(15) NOT NULL,".
                 "ljuser VARCHAR(15),".
                 "langpref VARCHAR(5),".
                 "method VARCHAR(10) NOT NULL,".
                 "vhost VARCHAR(80) NOT NULL,".
                 "uri VARCHAR(255) NOT NULL,".
                 "args VARCHAR(255),".
                 "status SMALLINT UNSIGNED NOT NULL,".
                 "ctype VARCHAR(30) NOT NULL,".
                 "bytes MEDIUMINT UNSIGNED NOT NULL,".
                 "browser VARCHAR(100) NOT NULL,".
                 "ref VARCHAR(200))");
        $LJ::CACHED_LOG_CREATE{"$dbl-$table"} = 1;
    }

    my $ua = $r->header_in("User-Agent");
    my $ref = $r->header_in("Referer");

    my $sql = "INSERT DELAYED INTO $table VALUES (NOW(),?,?,?,?,?,?,?,?,?,?,?,?,?)";
    my @vals = ($LJ::SERVER_NAME,
                $r->connection->remote_ip,
                $rl->notes('ljuser'),
                $rl->notes('langpref'),
                $r->method,
                $r->header_in("Host"),
                $r->uri,
                scalar $r->args,
                $rl->status,
                $ctype,
                $rl->bytes_sent,
                $ua,
                $ref);
                
    $dbl->do($sql, undef, @vals);
}

package LJ::Protocol;

sub xmlrpc_method {
    my $method = shift;
    shift;   # get rid of package name that dispatcher includes.
    my $req = shift;

    if (@_) {
        # don't allow extra arguments
        die SOAP::Fault
            ->faultstring(LJ::Protocol::error_message(202))
            ->faultcode(202);
    }
    my $error = 0;
    my $res = LJ::Protocol::do_request_without_db($method, $req, \$error);
    if ($error) {
        die SOAP::Fault
            ->faultstring(LJ::Protocol::error_message($error))
            ->faultcode(substr($error, 0, 3));
    }
    return $res;
}

package LJ::XMLRPC;

use vars qw($AUTOLOAD);

sub AUTOLOAD {
    my $method = $AUTOLOAD;
    $method =~ s/^.*:://;
    LJ::Protocol::xmlrpc_method($method, @_);
}

1;
