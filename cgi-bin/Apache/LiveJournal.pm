#!/usr/bin/perl
#

package Apache::LiveJournal;

use strict;
use Apache::Constants qw(:common REDIRECT HTTP_NOT_MODIFIED HTTP_MOVED_PERMANENTLY M_TRACE);
use Apache::File ();
use lib "$ENV{'LJHOME'}/cgi-bin";
use Apache::LiveJournal::PalImg;
use LJ::S2;

BEGIN {
    $LJ::OPTMOD_ZLIB = eval "use Compress::Zlib (); 1;";
    $LJ::OPTMOD_XMLRPC = eval "use XMLRPC::Transport::HTTP (); 1;";

    require "$ENV{'LJHOME'}/cgi-bin/ljlib.pl";
    require "$ENV{'LJHOME'}/cgi-bin/ljviews.pl";
    require "$ENV{'LJHOME'}/cgi-bin/ljprotocol.pl";
    if (%LJ::FOTOBILDER_IP) {
        use Apache::LiveJournal::Interface::FotoBilder;
    }
}

my %RQ;       # per-request data
my %USERPIC;  # conf related to userpics
my %REDIR;

$USERPIC{'cache_dir'} = "$ENV{'LJHOME'}/htdocs/userpics";
$USERPIC{'use_disk_cache'} = -d $USERPIC{'cache_dir'};
$USERPIC{'symlink'} = eval { symlink('',''); 1; };

# redirect data.
open (REDIR, "$ENV{'LJHOME'}/cgi-bin/redirect.dat");
while (<REDIR>) {
    next unless (/^(\S+)\s+(\S+)/);
    my ($src, $dest) = ($1, $2);
    $REDIR{$src} = $dest;
}
close REDIR;

my @req_hosts;  # client IP, and/or all proxies, real or claimed

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
                                             "Apache::LiveJournal::db_logger",
                                             "LJ::end_request", ]);

    # if we're behind a lite mod_proxy front-end, we need to trick future handlers
    # into thinking they know the real remote IP address.  problem is, it's complicated
    # by the fact that mod_proxy did nothing, requiring mod_proxy_add_forward, then
    # decided to do X-Forwarded-For, then did X-Forwarded-Host, so we have to deal
    # with all permutations of versions, hence all the ugliness:
    @req_hosts = ($r->connection->remote_ip);
    if (my $forward = $r->header_in('X-Forwarded-For'))
    {
        my (@hosts, %seen);
        foreach (split(/\s*,\s*/, $forward)) {
            next if $seen{$_}++;
            push @hosts, $_;
            push @req_hosts, $_;
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
    return DECLINED if $r->main;  # don't deal with subrequests

    my $uri = $r->uri;
    my $args = $r->args;
    my $args_wq = $args ? "?$args" : "";
    my $host = $r->header_in("Host");
    my $hostport = ($host =~ s/:\d+$//) ? $& : "";

    # disable TRACE (so scripts on non-LJ domains can't invoke
    # a trace to get the LJ cookies in the echo)
    return FORBIDDEN if $r->method_number == M_TRACE;

    # let foo.com still work, but redirect to www.foo.com
    if ($LJ::DOMAIN_WEB && $r->method eq "GET" &&
        $host eq $LJ::DOMAIN && $LJ::DOMAIN_WEB ne $LJ::DOMAIN) 
    {
        my $url = "$LJ::SITEROOT$uri";
        $url .= "?" . $args if $args;
        return redir($r, $url);
    }

    LJ::start_request();
    LJ::procnotify_check();
    foreach (@req_hosts) {
        return FORBIDDEN if LJ::sysban_check('ip', $_);
    }
    return FORBIDDEN if LJ::run_hook("forbid_request", $r);

    my %GET = $r->args;

    # anti-squatter checking
    if ($LJ::ANTI_SQUATTER && $r->method eq "GET") {
        my $ref = $r->header_in("Referer");
        if ($ref && index($ref, $LJ::SITEROOT) != 0) {
            # FIXME: this doesn't anti-squat user domains yet
            if ($uri !~ m!^/404!) {  
                # So hacky!  (see note below)
                $LJ::SQUAT_URL = "http://$host$uri$args_wq";
            } else {
                # then Apache's 404 handler takes over and we get here
                # FIXME: why??  why doesn't it just work to return OK
                # the first time with the handlers pushed?  nothing
                # else requires this chicanery!
                $r->handler("perl-script");
                $r->push_handlers(PerlHandler => \&anti_squatter);
            }
            return OK;
        }
    }

    my $journal_view = sub { 
        my $opts = shift;
        $opts ||= {};

        my $orig_user = $opts->{'user'};
        $opts->{'user'} = LJ::canonical_username($opts->{'user'});

        if ($opts->{'mode'} eq "info") {
            return redir($r, "$LJ::SITEROOT/userinfo.bml?user=$opts->{'user'}");
        }

        %RQ = %$opts;

        # redirect communities to /community/<name>
        my $dbr = LJ::get_db_reader();
        my $u = LJ::load_user($dbr, $opts->{'user'});
        if ($u && $u->{'journaltype'} eq "C" && 
            ($opts->{'vhost'} eq "" || $opts->{'vhost'} eq "tilde")) {
            my $newurl = $uri;
            $newurl =~ s!^/(users/|~)\Q$orig_user\E!!;
            $newurl = "$LJ::SITEROOT/community/$opts->{'user'}$newurl$args_wq";
            return redir($r, $newurl);
        }

        # redirect case errors in username
        if ($orig_user ne lc($orig_user)) {
            my $url = LJ::journal_base($opts->{'user'}, $opts->{'vhost'}) .
                "/$opts->{'mode'}$opts->{'pathextra'}$args_wq";
            return redir($r, $url);
        }

        $r->handler("perl-script");
        $r->push_handlers(PerlHandler => \&journal_content);
        return OK;
    };

    my $determine_view = sub {
        my ($user, $vhost, $uuri) = @_;
        my $mode = undef;
        my $pe;

        if ($uuri =~ m!^/(\d+)\.html$!) {
            if ($GET{'mode'} eq "reply" || $GET{'replyto'}) {
                $mode = "reply";
            } else {
                $mode = "entry";
            }
        } elsif ($uuri =~ m!^/(\d\d\d\d)(?:/(\d\d)(?:/(\d\d))?)?(/?)$!) {
            my ($year, $mon, $day, $slash) = ($1, $2, $3, $4);
            unless ($slash) {
                return redir($r, "http://$host$hostport$uri/");
            }

            # the S1 ljviews code looks at $opts->{'pathextra'}, because
            # that's how it used to do it, when the pathextra was /day[/yyyy/mm/dd]
            $pe = $uuri;
            
            if (defined $day) {
                $mode = "day";
            } elsif (defined $mon) {
                $mode = "month";
            } else {
                $mode = "calendar";
            }

        } elsif ($uuri =~ m!
                 /([a-z\_]+)?           # optional /<viewname>
                 (.*)                   # path extra: /FriendGroup, for example
                 !x && ($1 eq "" || defined $LJ::viewinfo{$1}))
        {
            ($mode, $pe) = ($1, $2);
            $mode ||= "" unless length $pe;  # if no pathextra, then imply 'lastn'

            # redirect old-style URLs to new versions:
            if ($mode =~ /day|calendar/ && $pe =~ m!^/\d\d\d\d!) {
                my $newuri = $uri;
                $newuri =~ s!$mode/(\d\d\d\d)!$1!;
                return redir($r, "http://$host$hostport$newuri");
            }

        } elsif (($vhost eq "users" || $vhost =~ /^other:/) &&
                 $uuri eq "/robots.txt") {
            $mode = "robots_txt";
        }

        return undef unless defined $mode;
        return $journal_view->({'vhost' => $vhost,
                                'mode' => $mode,
                                'args' => $args,
                                'pathextra' => $pe,
                                'user' => $user });
    };

    # user domains
    if ($LJ::USER_VHOSTS && 
        $host =~ /^([\w\-]{1,15})\.\Q$LJ::USER_DOMAIN\E$/ &&
        $1 ne "www") 
    {
        my $user = $1;
        my $mode;
        my $view = $determine_view->($user, "users", $uri);
        return $view if defined $view;
        return 404;
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
        return 404 unless $user;

        my $view = $determine_view->($user, "other:$host$hostport", $uri);
        return $view if defined $view;
        return 404;
    }

    # userpic
    return userpic_trans($r, $1, $2) if $uri =~ m!^/userpic/(\d+)(?:/(\d+))?$!;

    # front page journal
    if ($LJ::FRONTPAGE_JOURNAL) {
        my $view = $determine_view->($LJ::FRONTPAGE_JOURNAL, "front", $uri);
        return $view if defined $view;
    }

    # normal (non-domain) journal view
    if ($uri =~ m!
        ^/(users\/|community\/|\~)  # users/community/tilde
        (\w{1,15})                  # mandatory username
        (.*)?                       # rest
        !x)
    {
        my ($part1, $user, $rest) = ($1, $2, $3);
        unless (length $rest) {
            # FIXME: redirect to add slash
            # but for now, let it work:
            $rest = "/" unless length $rest;
        }
        
        my $vhost = { 'users/' => '', 'community/' => 'community',
                      '~' => 'tilde' }->{$part1};

        my $view = $determine_view->($user, $vhost, $rest);
        return $view if defined $view;
        return DECLINED;
    }

    # protocol support
    if ($uri =~ m!^/(?:interface(/flat|/xmlrpc|/fotobilder)?)|cgi-bin/log\.cgi!) {
        my $int = $1 || "/flat";
        $r->handler("perl-script");
        if ($int eq "/fotobilder") {
            return 403 unless $LJ::FOTOBILDER_IP{$r->connection->remote_ip};
            $r->push_handlers(PerlHandler => \&Apache::LiveJournal::Interface::FotoBilder::handler);
            return OK;
        }
        $RQ{'interface'} = $int eq "/flat" ? "flat" : "xmlrpc";
        $r->push_handlers(PerlHandler => \&interface_content);
        return OK;
    }

    # customview
    if ($uri =~ m!^/customview\.cgi!) {
        $r->handler("perl-script");
        $r->push_handlers(PerlHandler => \&customview_content);
        return OK;
    }

    if ($uri =~ m!^/palimg/!) {
        $r->handler("perl-script");
        $r->push_handlers(PerlHandler => \&Apache::LiveJournal::PalImg::handler);
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

    # approve
    if ($uri =~ m!^/approve/(\w+\.\w+)!) {
        return redir($r, "$LJ::SITEROOT/approve.bml?$1");
    }

    return FORBIDDEN if $uri =~ m!^/userpics!;
    return DECLINED;
}

sub userpic_trans
{
    my $r = shift;
    my $picid = shift;
    my $userid = shift(@_) + 0;

    # we can safely do this without checking since we never re-use
    # picture IDs and don't let the contents get modified
    return HTTP_NOT_MODIFIED if $r->header_in('If-Modified-Since');
    return HTTP_NOT_MODIFIED if $r->header_in('If-None-Match') eq "$picid-$userid";

    $RQ{'picid'} = $picid;
    $RQ{'pic-userid'} = $userid;

    my $file_extra;
    if ($userid) {
        $file_extra = "-$userid";
    } else {
        # userpics without the trailing /<userid> need to be coming
        # from the proper domain
        my $ref = $r->header_in("Referer");
        return 404 if $ref && $ref !~ m!^http://(\w+\.)?\Q$LJ::DOMAIN\E/!i;
    }

    my @dirs_make;
    my $file;
    if ($picid =~ /^\d*(\d\d)(\d\d\d)$/) {
        push @dirs_make, ("$USERPIC{'cache_dir'}/$2",
                          "$USERPIC{'cache_dir'}/$2/$1");
        $file = "$USERPIC{'cache_dir'}/$2/$1/$picid$file_extra";
    } else {
        my $mod = sprintf("%03d", $picid % 1000);
        push @dirs_make, "$USERPIC{'cache_dir'}/$mod";
        $file = "$USERPIC{'cache_dir'}/$mod/p$picid$file_extra";
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
    my $userid = $RQ{'pic-userid'}+0;

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
        $r->header_out("ETag", "$picid-$userid");
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
        return NOT_FOUND if $userid && $pic->{'userid'} != $userid;

        $lastmod = $pic->{'lastmod'};

        my $dbb = LJ::get_cluster_reader($pic->{'clusterid'});
        return SERVER_ERROR unless $dbb;
        $data = $dbb->selectrow_array("SELECT imagedata FROM userpicblob2 WHERE ".
                                      "userid=$pic->{'userid'} AND picid=$picid");
    }

    return NOT_FOUND unless $data;

    if ($need_cache) {
        # make $realfile /userpic-userid, and $file /userpic
        my $realfile = $file;
        unless ($file =~ s/-\d+$//) { 
            $realfile .= "-$pic->{'userid'}"; 
        }
        
        # delete short file on Unix if it exists
        unlink $file if $USERPIC{'symlink'} && -f $file;

        # write real file.
        open (F, ">$realfile"); print F $data; close F;

        # make symlink, or duplicate file (if on Windows)
        my $symtarget = $realfile;  $symtarget =~ s!.+/!!;
        unless (eval { symlink($symtarget, $file) }) {
            open (F, ">$file"); print F $data; close F;
        }
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

    my %GET = $r->args;

    if ($RQ{'mode'} eq "robots_txt")
    {
        my $u = LJ::load_user($RQ{'user'});
        LJ::load_user_props($u, "opt_blockrobots");
        $r->content_type("text/plain");
        $r->send_http_header();
        $r->print("User-Agent: *\n");
        if ($u->{'opt_blockrobots'}) {
            $r->print("Disallow: /\n");
        }
        return OK;
    }

    my $criterr = 0;
    my $remote = LJ::get_remote(undef, \$criterr);

    # check for faked cookies here, since this is pretty central.
    if ($criterr) {
        $r->content_type("text/html");
        $r->send_http_header();
        $r->print("Invalid cookies.  Try <a href='$LJ::SITEROOT/logout.bml'>logging out</a> and then logging back in.\n");
        return OK;
    }

    # LJ::make_journal() will set this flag if the user's
    # style system is unable to handle the requested
    # view (S1 can't do EntryPage or MonthPage), in which
    # case it's our job to invoke the legacy BML page.
    my $handle_with_bml = 0;

    my %headers = ();
    my $opts = {
        'r' => $r,
	'headers' => \%headers,
	'args' => $RQ{'args'},
        'getargs' => \%GET,
	'vhost' => $RQ{'vhost'},
        'pathextra' => $RQ{'pathextra'},
        's2id' => $GET{'s2id'},
        'header' => {
            'If-Modified-Since' => $r->header_in("If-Modified-Since"),
        },
        'handle_with_bml_ref' => \$handle_with_bml,
    };

    my $user = $RQ{'user'};
    my $html = LJ::make_journal($user, $RQ{'mode'}, $remote, $opts);

    return redir($r, $opts->{'redir'}) if $opts->{'redir'};
    return $opts->{'handler_return'} if defined $opts->{'handler_return'};

    # if LJ::make_journal() indicated it can't handle the request:
    if ($handle_with_bml) {
        my $args = $r->args;
        my $args_wq = $args ? "?$args" : "";

        # can't show BML on user domains... redirect them
        if ($RQ{'vhost'} eq "users" && ($RQ{'mode'} eq "entry" || 
                                        $RQ{'mode'} eq "reply" || 
                                        $RQ{'mode'} eq "month")) 
        {
            my $u = LJ::load_user($RQ{'user'});
            my $base = "$LJ::SITEROOT/users/$RQ{'user'}";
            $base = "$LJ::SITEROOT/community/$RQ{'user'}" if $u && $u->{'journaltype'} eq "C";
            return redir($r, "$base$uri$args_wq");
        }

        if ($RQ{'mode'} eq "entry" || $RQ{'mode'} eq "reply") {
            my $filename = $RQ{'mode'} eq "entry" ? 
                "$LJ::HOME/htdocs/talkread.bml" :
                "$LJ::HOME/htdocs/talkpost.bml";
            $r->notes("_journal" => $RQ{'user'});
            $r->notes("bml_filename" => $filename);
            return Apache::BML::handler($r);
        }

        if ($RQ{'mode'} eq "month") {
            my $filename = "$LJ::HOME/htdocs/view/index.bml";
            $r->notes("_journal" => $RQ{'user'});
            $r->notes("bml_filename" => $filename);
            return Apache::BML::handler($r);
        }
    }

    my $status = $opts->{'status'} || "200 OK";
    $opts->{'contenttype'} ||= $opts->{'contenttype'} = "text/html";
    if ($opts->{'contenttype'} =~ m!^text/! &&
        $LJ::UNICODE && $opts->{'contenttype'} !~ /charset=/) {
        $opts->{'contenttype'} .= "; charset=utf-8";
    }

    if ($opts->{'badargs'}) 
    {
        # No special information to give to the user, so just let
        # Apache handle the 404
        return 404;
    }
    elsif ($opts->{'baduser'}) 
    {
	$status = "404 Unknown User";
	$html = "<h1>Unknown User</h1><p>There is no user <b>$user</b> at $LJ::SITENAME.</p>";
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

    my $do_gzip = $LJ::DO_GZIP && $LJ::OPTMOD_ZLIB;
    $do_gzip = 0 if $do_gzip && $opts->{'contenttype'} !~ m!^text/html!;
    $do_gzip = 0 if $do_gzip && $r->header_in("Accept-Encoding") !~ /gzip/;
    my $length = length($html);
    $do_gzip = 0 if $length < 500;

    if ($do_gzip) {
        my $pre_len = $length;
        $r->notes("bytes_pregzip" => $pre_len);
        $html = Compress::Zlib::memGzip($html);
        $length = length($html);
        $r->header_out('Content-Encoding', 'gzip');
        $r->header_out('Vary', 'Accept-Encoding');
    }

    $r->header_out("Content-length", $length);
    $r->send_http_header();
    $r->print($html) unless $r->header_only;
    return OK;
}

sub customview_content
{
    my $r = shift;

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
	$remote = LJ::get_remote(undef, \$criterr);
    }

    my $data = (LJ::make_journal($user, "", $remote,
				 { "nocache" => $FORM{'nocache'}, 
				   "vhost" => "customview",
				   "nooverride" => $nooverride,
				   "styleid" => $styleid,
                                   "saycharset" => $charset,
                                   "args" => scalar $r->args,
                                   "getargs" => \%FORM,
                                   "r" => $r,
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
        return 404 unless $LJ::OPTMOD_XMLRPC;
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

    my %out = ();
    my %FORM = ();
    my $content;
    $r->read($content, $r->header_in("Content-Length"));
    LJ::decode_url_string($content, \%FORM);
    
    # the protocol needs the remote IP in just one place, where tracking is done.
    $ENV{'_REMOTE_IP'} = $r->connection()->remote_ip();
    LJ::do_request(\%FORM, \%out);

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

    my $uri = $r->uri;
    my $ctype = $rl->content_type;

    return if $ctype =~ m!^image/! and $LJ::DONT_LOG_IMAGES;
    return if $uri =~ m!^/(img|userpic)/! and $LJ::DONT_LOG_IMAGES;

    my $dbl = LJ::get_dbh("logs");
    return unless $dbl;

    $ctype =~ s/;.*//;  # strip charset

    my $now = time();
    my @now = localtime($now);
    my $table = sprintf("access%04d%02d%02d%02d", $now[5]+1900,
                        $now[4]+1, $now[3], $now[2]);
    
    unless ($LJ::CACHED_LOG_CREATE{"$dbl-$table"}) {
        $dbl->do("CREATE TABLE IF NOT EXISTS $table (".
                 "whn TIMESTAMP(14) NOT NULL,".
                 "server VARCHAR(30),".
                 "addr VARCHAR(15) NOT NULL,".
                 "ljuser VARCHAR(15),".
                 "journalid INT UNSIGNED,". # userid of what's being looked at
                 "codepath VARCHAR(80),".  # protocol.getevents / s[12].friends / bml.update / bml.friends.index
                 "anonsess INT UNSIGNED,". 
                 "langpref VARCHAR(5),".
                 "method VARCHAR(10) NOT NULL,".
                 "uri VARCHAR(255) NOT NULL,".
                 "args VARCHAR(255),".
                 "status SMALLINT UNSIGNED NOT NULL,".
                 "ctype VARCHAR(30),".
                 "bytes MEDIUMINT UNSIGNED NOT NULL,".
                 "browser VARCHAR(100),".
                 "clientver VARCHAR(100),".
                 "secs TINYINT UNSIGNED,".
                 "ref VARCHAR(200))");
        $LJ::CACHED_LOG_CREATE{"$dbl-$table"} = 1;
    }

    my $var = {
        'server' => $LJ::SERVER_NAME,
        'addr' => $r->connection->remote_ip,
        'ljuser' => $rl->notes('ljuser'),
        'journalid' => $rl->notes('journalid'),
        'codepath' => $rl->notes('codepath'),
        'anonsess' => $rl->notes('anonsess'),
        'langpref' => $rl->notes('langpref'),
        'clientver' => $rl->notes('clientver'),
        'method' => $r->method,
        'uri' => $uri,
        'args' => scalar $r->args,
        'status' => $rl->status,
        'ctype' => $ctype,
        'bytes' => $rl->bytes_sent,
        'browser' => $r->header_in("User-Agent"),
        'secs' => $now - $r->request_time(),
        'ref' => $r->header_in("Referer"),
    };

    my $delayed = $LJ::IMMEDIATE_LOGGING ? "" : "DELAYED";
    $dbl->do("INSERT $delayed INTO $table (" . join(',', keys %$var) . ") ".
             "VALUES (" . join(',', map { $dbl->quote($var->{$_}) } keys %$var) . ")");

    $dbl->disconnect if $LJ::DISCONNECT_DB_LOG;
}

sub anti_squatter
{
    my $r = shift;
    $r->push_handlers(PerlHandler => sub {
        my $r = shift;
        $r->content_type("text/html");
        $r->send_http_header();
        $r->print("<html><head><title>Dev Server Warning</title>",
                  "<style> body { border: 20px solid red; padding: 30px; margin: 0; font-family: sans-serif; } ",
                  "h1 { color: #500000; }",
                  "</style></head>",
                  "<body><h1>Warning</h1><p>This server is for development and testing only.  ",
                  "Accounts are subject to frequent deletion.  Don't use this machine for anything important.</p>",
                  "<form method='post' action='/misc/ack-devserver.bml' style='margin-top: 1em'>",
                  LJ::html_hidden("dest", "$LJ::SQUAT_URL"),
                  LJ::html_submit(undef, "Acknowledged"),
                  "</form></body></html>");
        return OK;
    });
    
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
    my $res = LJ::Protocol::do_request($method, $req, \$error);
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
