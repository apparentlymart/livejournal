#!/usr/bin/perl
#

package Apache::LiveJournal;

use strict;
use Apache::Constants qw(:common REDIRECT HTTP_NOT_MODIFIED
                         HTTP_MOVED_PERMANENTLY HTTP_MOVED_TEMPORARILY
                         M_TRACE M_OPTIONS);
use Apache::File ();
use lib "$ENV{'LJHOME'}/cgi-bin";
use Apache::LiveJournal::PalImg;
use LJ::S2;
use LJ::Blob;
use Apache::LiveJournal::Interface::Blogger;
use Apache::LiveJournal::Interface::AtomAPI;
use Apache::LiveJournal::Interface::S2;

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
my $GTop;     # GTop object (created if $LJ::LOG_GTOP is true)

# Mapping of MIME types to image types understood by the blob functions.
my %MimeTypeMap = (
    'image/gif' => 'gif',
    'image/jpeg' => 'jpg',
    'image/png' => 'png',
);
my %MimeTypeMapd6 = (
    'G' => 'gif',
    'J' => 'jpg',
    'P' => 'png',
);

$USERPIC{'cache_dir'} = "$ENV{'LJHOME'}/htdocs/userpics";
$USERPIC{'use_disk_cache'} = -d $USERPIC{'cache_dir'};
$USERPIC{'symlink'} = eval { symlink('',''); 1; };

# redirect data.
foreach my $file ('redirect.dat', 'redirect-local.dat') {
    open (REDIR, "$ENV{'LJHOME'}/cgi-bin/$file") or next;
    while (<REDIR>) {
        next unless (/^(\S+)\s+(\S+)/);
        my ($src, $dest) = ($1, $2);
        $REDIR{$src} = $dest;
    }
    close REDIR;
}

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

    # only perform this once in case of internal redirects
    if ($r->is_initial_req) {
        $r->push_handlers(PerlCleanupHandler => sub { %RQ = () });
        $r->push_handlers(PerlCleanupHandler => "Apache::LiveJournal::db_logger");
        $r->push_handlers(PerlCleanupHandler => "LJ::end_request");
        $r->push_handlers(PerlCleanupHandler => "Apache::DebateSuicide");

        if ($LJ::TRUST_X_HEADERS) {
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
        }

        # reload libraries that might've changed
        if ($LJ::IS_DEV_SERVER && !$LJ::DISABLED{'module_reload'}) {
            my %to_reload;
            while (my ($file, $mod) = each %LJ::LIB_MOD_TIME) {
                my $cur_mod = (stat($file))[9];
                next if $cur_mod == $mod;
                $to_reload{$file} = 1;
            }
            my @key_del;
            foreach (my ($key, $file) = each %INC) {
                push @key_del, $key if $to_reload{$file};
            }
            delete $INC{$_} foreach @key_del;

            foreach my $file (keys %to_reload) {
                print STDERR "Reloading $file...\n";
                my %reloaded;
                local $SIG{__WARN__} = sub {
                    if ($_[0] =~ m/^Subroutine (\S+) redefined at /)
                    {
                        warn @_ if ($reloaded{$1}++);
                    } else {
                        warn(@_);
                    }
                };
                my $good = do $file;
                if ($good) {
                    $LJ::LIB_MOD_TIME{$file} = (stat($file))[9];
                } else {
                    die "Failed to reload module [$file] due to error: $@\n";
                }
            }
        }

        LJ::work_report_start();
    }

    $r->set_handlers(PerlTransHandler => [ \&trans ]);

    return OK;
}

sub redir {
    my ($r, $url, $code) = @_;
    $r->content_type("text/html");
    $r->header_out(Location => $url);

    if ($LJ::DEBUG{'log_redirects'}) {
        $r->log_error("redirect to $url from: " . join(", ", caller(0)));
    }
    return $code || REDIRECT;
}

# send the user to the URL for them to get their domain session cookie
sub remote_domsess_bounce {
    my $r = Apache->request;
    return redir($r, LJ::remote_bounce_url(), HTTP_MOVED_TEMPORARILY);
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

    # set to 500 so people don't cache this error message
    my $body = "<h1>$LJ::SERVER_DOWN_SUBJECT</h1>$LJ::SERVER_DOWN_MESSAGE<!-- " . ("x" x 1024) . " -->";
    $r->status_line("503 Server Maintenance");
    $r->content_type("text/html");
    $r->header_out("Content-length", length $body);
    $r->send_http_header();

    $r->print($body);
    return OK;
}

sub blocked_bot
{
    my $r = shift;

    $r->status_line("403 Denied");
    $r->content_type("text/html");
    $r->send_http_header();
    my $subject = $LJ::BLOCKED_BOT_SUBJECT || "403 Denied";
    my $message = $LJ::BLOCKED_BOT_MESSAGE || "You don't have permission to view this page.";
    $r->print("<h1>$subject</h1>$message");
    return OK;
}

sub trans
{
    my $r = shift;
    return DECLINED if ! $r->is_main || $r->method_number == M_OPTIONS;  # don't deal with subrequests or OPTIONS

    my $uri = $r->uri;
    my $args = $r->args;
    my $args_wq = $args ? "?$args" : "";
    my $host = $r->header_in("Host");
    my $hostport = ($host =~ s/:\d+$//) ? $& : "";

    # disable TRACE (so scripts on non-LJ domains can't invoke
    # a trace to get the LJ cookies in the echo)
    return FORBIDDEN if $r->method_number == M_TRACE;

    # If the configuration says to log statistics and GTop is available, mark
    # values before the request runs so it can be turned into a delta later
    if ( $LJ::LOG_GTOP && $LJ::HAVE_GTOP ) {
        $GTop ||= new GTop;
        $r->pnotes( 'gtop_cpu' => $GTop->cpu );
        $r->pnotes( 'gtop_mem' => $GTop->proc_mem($$) );
    }

    LJ::start_request();
    LJ::procnotify_check();
    S2::set_domain('LJ');

    my $lang = $LJ::DEFAULT_LANG || $LJ::LANGS[0];
    BML::set_language($lang, \&LJ::Lang::get_text);

    my $is_ssl = $LJ::IS_SSL = LJ::run_hook("ssl_check", {
        r => $r,
    });

    # handle uniq cookies
    if ($LJ::UNIQ_COOKIES && $r->is_initial_req) {

        # if cookie exists, check for sysban
        my ($uniq, $uniq_time, $uniq_extra);
        if (Apache->header_in("Cookie") =~ /\bljuniq\s*=\s*([a-zA-Z0-9]{15}):(\d+)(.*)/) {
            ($uniq, $uniq_time, $uniq_extra) = ($1, $2, $3);
            $r->notes("uniq" => $uniq);
            if (LJ::sysban_check('uniq', $uniq) && index($uri, $LJ::BLOCKED_BOT_URI) != 0) {
                $r->handler("perl-script");
                $r->push_handlers(PerlHandler => \&blocked_bot );
                return OK;
            };
        }

        # if no cookie, create one.  if older than a day, revalidate
        my $now = time();
        my $DAY = 3600*24;
        if (! $uniq || $now - $uniq_time > $DAY) {
            $uniq ||= LJ::rand_chars(15);

            my $uniq_value = "$uniq:$now";
            $uniq_value    = LJ::run_hook('transform_ljuniq_value',
                                          { value => $uniq_value,
                                            extra => $uniq_extra }) || $uniq_value;

            # set uniq cookies for all cookie_domains
            my @domains = ref $LJ::COOKIE_DOMAIN ? @$LJ::COOKIE_DOMAIN : ($LJ::COOKIE_DOMAIN);
            foreach my $dom (@domains) {
                $r->err_headers_out->add("Set-Cookie" =>
                                         "ljuniq=$uniq_value; " .
                                         "expires=" . LJ::time_to_cookie($now + $DAY*60) . "; " .
                                         ($dom ? "domain=$dom; " : "") . "path=/");
            }
        }
    }

    # only allow certain pages over SSL
    if ($is_ssl) {
        if ($uri =~ m!^/interface/!) {
            # handled later
        } elsif ($LJ::SSLDOCS && $uri !~ m!(\.\.|\%|\.\/)!) {
            my $file = "$LJ::SSLDOCS/$uri";
            unless (-e $file) {
                # no such file.  send them to the main server if it's a GET.
                return $r->method eq 'GET' ? redir($r, "$LJ::SITEROOT$uri$args_wq") : 404;
            }
            if (-d _) { $file .= "/index.bml"; }
            $file =~ s!/{2,}!/!g;
            $r->filename($file);
            $LJ::IMGPREFIX = "/img";
            $LJ::STATPREFIX = "/stc";
            return OK;
        } else {
            return FORBIDDEN;
        }
    } else {
        $LJ::IMGPREFIX = $LJ::IMGPREFIX_BAK;
        $LJ::STATPREFIX = $LJ::STATPREFIX_BAK;
    }

    # let foo.com still work, but redirect to www.foo.com
    if ($LJ::DOMAIN_WEB && $r->method eq "GET" &&
        $host eq $LJ::DOMAIN && $LJ::DOMAIN_WEB ne $LJ::DOMAIN)
    {
        my $url = "$LJ::SITEROOT$uri";
        $url .= "?" . $args if $args;
        return redir($r, $url);
    }

    # check for sysbans on ip address
    foreach my $ip (@req_hosts) {
        if (LJ::sysban_check('ip', $ip) && index($uri, $LJ::BLOCKED_BOT_URI) != 0) {
            $r->handler("perl-script");
            $r->push_handlers(PerlHandler => \&blocked_bot );
            return OK;
        }
    }
    if (LJ::run_hook("forbid_request", $r) && index($uri, $LJ::BLOCKED_BOT_URI) != 0) {
        $r->handler("perl-script");
        $r->push_handlers(PerlHandler => \&blocked_bot );
        return OK;
    }

    # see if we should setup a minimal scheme based on the initial part of the
    # user-agent string; FIXME: maybe this should do more than just look at the
    # initial letters?
    if (my $ua = $r->header_in('User-Agent')) {
        if (($ua =~ /^([a-z]+)/i) && $LJ::MINIMAL_USERAGENT{$1}) {
            $r->notes('use_minimal_scheme' => 1);
            $r->notes('bml_use_scheme' => $LJ::MINIMAL_BML_SCHEME);
        }
    }

    # now we know that the request is going to succeed, so do some checking if they have a defined
    # referer.  clients and such don't, so ignore them.
    my $referer = $r->header_in("Referer");
    if ($referer && $r->method eq 'POST' && !LJ::check_referer('', $referer)) {
       $r->log_error("REFERER WARNING: POST to $uri from $referer");
    }

    my %GET = $r->args;

    if ($LJ::IS_DEV_SERVER && $GET{'as'} =~ /^\w{1,15}$/) {
        my $ru = LJ::load_user($GET{'as'});
        if ($ru) {
            LJ::set_remote($ru);
        }
    }

    # anti-squatter checking
    if ($LJ::DEBUG{'anti_squatter'} && $r->method eq "GET") {
        my $ref = $r->header_in("Referer");
        if ($ref && index($ref, $LJ::SITEROOT) != 0) {
            # FIXME: this doesn't anti-squat user domains yet
            if ($uri !~ m!^/404!) {
                # So hacky!  (see note below)
                $LJ::SQUAT_URL = "http://$host$hostport$uri$args_wq";
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

    my $bml_handler = sub {
        my $filename = shift;
        $r->handler("perl-script");
        $r->notes("bml_filename" => $filename);
        $r->push_handlers(PerlHandler => \&Apache::BML::handler);
        return OK;
    };

    my $journal_view = sub {
        my $opts = shift;
        $opts ||= {};

        my $orig_user = $opts->{'user'};
        $opts->{'user'} = LJ::canonical_username($opts->{'user'});

        if ($opts->{'mode'} eq "info") {
            my $u = LJ::load_user($opts->{user})
                or return 404;
            my $mode = $GET{mode} eq 'full' ? '?mode=full' : '';
            return redir($r, $u->profile_url . $mode);
        }

        if ($opts->{'mode'} eq "profile") {
            my $remote = LJ::get_remote();
            my $burl = LJ::remote_bounce_url();
            return remote_domsess_bounce() if LJ::remote_bounce_url();

            $r->notes("_journal" => $opts->{'user'});

            # this is the notes field that all other s1/s2 pages use.
            # so be consistent for people wanting to read it.
            # _journal above is kinda deprecated, but we'll carry on
            # its behavior of meaning "whatever the user typed" to be
            # passed to the userinfo BML page, whereas this one only
            # works if journalid exists.
            if (my $u = LJ::load_user($opts->{user})) {
                $r->notes("journalid" => $u->{userid});
            }

            my $file = $LJ::PROFILE_BML_FILE || "userinfo.bml";
            if ($args =~ /\bver=(\w+)\b/) {
                $file = $LJ::ALT_PROFILE_BML_FILE{$1} if $LJ::ALT_PROFILE_BML_FILE{$1};
            }
            return $bml_handler->("$LJ::HOME/htdocs/$file");
        }

        if ($opts->{'mode'} eq "update") {
            my $u = LJ::load_user($opts->{user})
                or return 404;

            return redir($r, "$LJ::SITEROOT/update.bml?usejournal=".$u->{'user'});
        }

        %RQ = %$opts;

        # redirect communities to /community/<name>
        my $u = LJ::load_user($opts->{'user'});
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

        if ($opts->{mode} eq "data" && $opts->{pathextra} =~ m!^/(\w+)(/.*)?!) {
            my $remote = LJ::get_remote();
            my $burl = LJ::remote_bounce_url();
            return remote_domsess_bounce() if LJ::remote_bounce_url();

            my ($mode, $path) = ($1, $2);
            if ($mode eq "customview") {
                $r->handler("perl-script");
                $r->push_handlers(PerlHandler => \&customview_content);
                return OK;
            }
            if (my $handler = LJ::run_hook("data_handler:$mode", $RQ{'user'}, $path)) {
                $r->handler("perl-script");
                $r->push_handlers(PerlHandler => $handler);
                return OK;
            }
        }

        $r->handler("perl-script");
        $r->push_handlers(PerlHandler => \&journal_content);
        return OK;
    };

    my $determine_view = sub {
        my ($user, $vhost, $uuri) = @_;
        my $mode = undef;
        my $pe;
        my $ljentry;

        # if favicon, let filesystem handle it, for now, until
        # we have per-user favicons.
        return DECLINED if $uuri eq "/favicon.ico";

        if ($uuri eq "/__setdomsess") {
            return redir($r, LJ::Session->setdomsess_handler($r));
        }

        if ($uuri =~ /^.*\b__rpc_delcomment$/) {
            return $bml_handler->("$LJ::HOME/htdocs/delcomment.bml");
        }

        if ($uuri =~ /^.*\b__rpc_talkscreen$/) {
            return $bml_handler->("$LJ::HOME/htdocs/talkscreen.bml");
        }

        if ($uuri =~ /^.*\b__rpc_ctxpopup$/) {
            return $bml_handler->("$LJ::HOME/htdocs/tools/endpoints/ctxpopup.bml");
        }

        if ($uuri =~ /^.*\b__rpc_changerelation$/) {
            return $bml_handler->("$LJ::HOME/htdocs/tools/endpoints/changerelation.bml");
        }

        if ($uuri =~ /^.*\b__rpc_userpicselect$/) {
            return $bml_handler->("$LJ::HOME/htdocs/tools/endpoints/getuserpics.bml");
        }

        if ($uuri =~ /^.*\b__rpc_controlstrip$/) {
            return $bml_handler->("$LJ::HOME/htdocs/tools/endpoints/controlstrip.bml");
        }

        if ($uuri =~ /^.*\b__rpc_esn_inbox$/) {
            return $bml_handler->("$LJ::HOME/htdocs/tools/endpoints/esn_inbox.bml");
        }

        if ($uuri =~ m#^/(\d+)\.html$#) {
            if ($GET{'mode'} eq "reply" || $GET{'replyto'}) {
                $mode = "reply";
            } else {
                $mode = "entry";
            }
        } elsif ($uuri =~ m#^/(\d\d\d\d)(?:/(\d\d)(?:/(\d\d))?)?(/?)$#) {
            my ($year, $mon, $day, $slash) = ($1, $2, $3, $4);
            unless ($slash) {
                my $u = LJ::load_user($user)
                    or return 404;
                my $proper = $u->journal_base . "/$year";
                $proper .= "/$mon" if defined $mon;
                $proper .= "/$day" if defined $day;
                $proper .= "/";
                return redir($r, $proper);
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
            if ($mode =~ /^day|calendar$/ && $pe =~ m!^/\d\d\d\d!) {
                my $newuri = $uri;
                $newuri =~ s!$mode/(\d\d\d\d)!$1!;
                return redir($r, "http://$host$hostport$newuri");
            } elsif ($mode eq 'rss') {
                # code 301: moved permanently, update your links.
                return redir($r, LJ::journal_base($user) . "/data/rss$args_wq", 301);
            } elsif ($mode eq 'pics' && $LJ::REDIRECT_ALLOWED{$LJ::FB_DOMAIN}) {
                # redirect to a user's gallery
                my $url = "$LJ::FB_SITEROOT/$user";
                return redir($r, $url);
            } elsif ($mode eq 'tag') {
                return redir($r, "http://$host$hostport$uri/") unless $pe;
                if ($pe eq '/') {
                    # tag list page
                    $mode = 'tag';
                    $pe = undef;
                } else {
                    # filtered lastn page
                    $mode = 'lastn';

                    # prepend /tag so that lastn knows to do tag filtering
                    $pe = "/tag$pe";
                }
            }
        } elsif (($vhost eq "users" || $vhost =~ /^other:/) &&
                 $uuri eq "/robots.txt") {
            $mode = "robots_txt";
        } else {
            my $key = $uuri;
            $key =~ s!^/!!;
            my $u = LJ::load_user($user)
                or return 404;

            my ($type, $nodeid) =
                $LJ::DISABLED{'named_permalinks'} ? () :
                $u->selectrow_array("SELECT nodetype, nodeid FROM urimap WHERE journalid=? AND uri=?",
                                    undef, $u->{userid}, $key);
            if ($type eq "L") {
                $ljentry = LJ::Entry->new($u, ditemid => $nodeid);
                if ($GET{'mode'} eq "reply" || $GET{'replyto'}) {
                    $mode = "reply";
                } else {
                    $mode = "entry";
                }
            }

        }

        return undef unless defined $mode;

        # Now that we know ourselves to be at a sensible URI, redirect renamed
        # journals. This ensures redirects work sensibly for all valid paths
        # under a given username, without sprinkling redirects everywhere.
        my $u = LJ::load_user($user);
        if ($u && $u->{'journaltype'} eq 'R' && $u->{'statusvis'} eq 'R') {
            LJ::load_user_props($u, 'renamedto');
            return redir($r, LJ::journal_base($u->{'renamedto'}, $vhost) . $uuri . $args_wq, 301)
                if $u->{'renamedto'} ne '';
        }

        return $journal_view->({
            'vhost' => $vhost,
            'mode' => $mode,
            'args' => $args,
            'pathextra' => $pe,
            'user' => $user,
            'ljentry' => $ljentry,
        });
    };

    # flag if we hit a domain that was configured as a "normal" domain
    # which shouldn't be inspected for its domain name.  (for use with
    # Akamai and other CDN networks...)
    my $skip_domain_checks = 0;

    # user domains
    if (($LJ::USER_VHOSTS || $LJ::ONLY_USER_VHOSTS) &&
        $host =~ /^([\w\-]{1,15})\.\Q$LJ::USER_DOMAIN\E$/ &&
        $1 ne "www" &&

        # 1xx: info, 2xx: success, 3xx: redirect, 4xx: client err, 5xx: server err
        # let the main server handle any errors
        $r->status < 400)
    {
        my $user = $1;

        # see if the "user" is really functional code
        my $func = $LJ::SUBDOMAIN_FUNCTION{$user};

        if ($func eq "normal") {
            # site admin wants this domain to be ignored and treated as if it
            # were "www", so set this flag so the custom "OTHER_VHOSTS" check
            # below fails.
            $skip_domain_checks = 1;

        } elsif ($func eq "cssproxy") {

            return $bml_handler->("$LJ::HOME/htdocs/extcss/index.bml");

        } elsif ($func eq 'portal') {
            # if this is a "portal" subdomain then prepend the portal URL
            return redir($r, "$LJ::SITEROOT/portal/");

        } elsif (ref $func eq "ARRAY" && $func->[0] eq "changehost") {

            return redir($r, "http://$func->[1]$uri$args_wq");

        } elsif ($uri =~ m!^/(?:talkscreen|delcomment)\.bml!) {
            # these URLs need to always work for the javascript comment management code
            # (JavaScript can't do cross-domain XMLHttpRequest calls)
            return DECLINED;

        } elsif ($func eq "journal") {

            unless ($uri =~ m!^/(\w{1,15})(/.*)?$!) {
                return DECLINED if $uri eq "/favicon.ico";
                my $redir = LJ::run_hook("journal_subdomain_redirect_url",
                                         $host, $uri);
                return redir($r, $redir) if $redir;
                return 404;
            }
            ($user, $uri) = ($1, $2);
            $uri ||= "/";

            # redirect them to their canonical URL if on wrong host/prefix
            if (my $u = LJ::load_user($user)) {
                my $canon_url = $u->journal_base;
                unless ($canon_url =~ m!^http://$host!i || $LJ::DEBUG{'user_vhosts_no_wronghost_redirect'}) {
                    return redir($r, "$canon_url$uri$args_wq");
                }
            }

            my $view = $determine_view->($user, "safevhost", $uri);
            return $view if defined $view;

        } elsif ($func eq 'adserver') {

            return $bml_handler->("$LJ::HOME/htdocs/misc/adserver.bml");

        } elsif ($func) {
            my $code = {
                'userpics' => \&userpic_trans,
                'files' => \&files_trans,
            };
            return $code->{$func}->($r) if $code->{$func};
            return 404;  # bogus ljconfig
        } else {
            my $view = $determine_view->($user, "users", $uri);
            return $view if defined $view;
            return 404;
        }
    }

    # custom used-specified domains
    if ($LJ::OTHER_VHOSTS && !$skip_domain_checks &&
        $host ne $LJ::DOMAIN_WEB &&
        $host ne $LJ::DOMAIN && $host =~ /\./ &&
        $host =~ /[^\d\.]/)
    {
        my $dbr = LJ::get_db_reader();
        my $checkhost = lc($host);
        $checkhost =~ s/^www\.//i;
        $checkhost = $dbr->quote($checkhost);
        # FIXME: memcache this?
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
    return userpic_trans($r) if $uri =~ m!^/userpic/!;

    # front page journal
    if ($LJ::FRONTPAGE_JOURNAL) {
        my $view = $determine_view->($LJ::FRONTPAGE_JOURNAL, "front", $uri);
        return $view if defined $view;
    }

    # normal (non-domain) journal view
    if (
        $uri =~ m!
        ^/(users\/|community\/|\~)  # users/community/tilde
        ([^/]*)                     # potential username
        (.*)?                       # rest
        !x)
    {
        my ($part1, $user, $rest) = ($1, $2, $3);

        # get what the username should be
        my $cuser = LJ::canonical_username($user);
        return DECLINED unless length($cuser);

        my $srest = $rest || '/';

        # need to redirect them to canonical version
        if ($LJ::ONLY_USER_VHOSTS && ! $LJ::DEBUG{'user_vhosts_no_old_redirect'}) {
            # FIXME: skip two redirects and send them right to __setdomsess with the right
            #        cookie-to-be-set arguments.  below is the easy/slow route.
            my $u = LJ::load_user($cuser)
                or return 404;
            my $base = $u->journal_base;
            return redir($r, "$base$srest$args_wq", correct_url_redirect_code());
        }

        # redirect to canonical username and/or add slash if needed
        return redir($r, "http://$host$hostport/$part1$cuser$srest$args_wq")
            if $cuser ne $user or not $rest;

        my $vhost = { 'users/' => '', 'community/' => 'community',
                      '~' => 'tilde' }->{$part1};

        my $view = $determine_view->($user, $vhost, $rest);
        return $view if defined $view;
    }

    # custom interface handler
    if ($uri =~ m!^/interface/(\w+)$!) {
        my $inthandle = LJ::run_hook("interface_handler", {
            int         => $1,
            r           => $r,
            bml_handler => $bml_handler,
        });
        return $inthandle if defined $inthandle;
    }

    # protocol support
    if ($uri =~ m!^/(?:interface/(\w+))|cgi-bin/log\.cgi!) {
        my $int = $1 || "flat";
        $r->handler("perl-script");
        if ($int eq "fotobilder") {
            return 403 unless $LJ::FOTOBILDER_IP{$r->connection->remote_ip};
            $r->push_handlers(PerlHandler => \&Apache::LiveJournal::Interface::FotoBilder::handler);
            return OK;
        }
        if ($int =~ /^flat|xmlrpc|blogger|atom(?:api)?$/) {
            $RQ{'interface'} = $int;
            $RQ{'is_ssl'} = $is_ssl;
            $r->push_handlers(PerlHandler => \&interface_content);
            return OK;
        }
        if ($int eq "s2") {
            $r->push_handlers(PerlHandler => \&Apache::LiveJournal::Interface::S2::handler);
            return OK;
        }
        return 404;
    }

    # some RPC stuff
    if ($uri =~ /^.*\b__rpc_delcomment$/) {
        return $bml_handler->("$LJ::HOME/htdocs/delcomment.bml");
    }

    if ($uri =~ /^.*\b__rpc_talkscreen$/) {
        return $bml_handler->("$LJ::HOME/htdocs/talkscreen.bml");
    }

    if ($uri =~ /^.*\b__rpc_ctxpopup$/) {
        return $bml_handler->("$LJ::HOME/htdocs/tools/endpoints/ctxpopup.bml");
    }

    if ($uri =~ /^.*\b__rpc_changerelation$/) {
        return $bml_handler->("$LJ::HOME/htdocs/tools/endpoints/changerelation.bml");
    }

    if ($uri =~ /^.*\b__rpc_userpicselect$/) {
        return $bml_handler->("$LJ::HOME/htdocs/tools/endpoints/getuserpics.bml");
    }

    if ($uri =~ /^.*\b__rpc_esn_inbox$/) {
        return $bml_handler->("$LJ::HOME/htdocs/tools/endpoints/esn_inbox.bml");
    }

    # customview (get an S1 journal by number)
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
        if ($r->args) {
            $new .= ($new =~ /\?/ ? "&" : "?");
            $new .= $r->args;
        }
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
    return 404 unless $r->uri =~ m!^/(?:userpic/)?(\d+)/(\d+)$!;
    my ($picid, $userid) = ($1, $2);

    $r->notes("codepath" => "img.userpic");

    # redirect to the correct URL if we're not at the right one
    my $host = $r->header_in("Host");
    my $curr = "http://$host";
    my $canon = "$LJ::USERPIC_ROOT/$picid/$userid";
    return redir($r, $canon) unless $canon =~ /^\Q$curr\E/i;

    # we can safely do this without checking since we never re-use
    # picture IDs and don't let the contents get modified
    return HTTP_NOT_MODIFIED if $r->header_in('If-Modified-Since');

    $RQ{'picid'} = $picid;
    $RQ{'pic-userid'} = $userid;

    if ($USERPIC{'use_disk_cache'}) {
        my @dirs_make;
        my $file;

        if ($picid =~ /^\d*(\d\d)(\d\d\d)$/) {
            push @dirs_make, ("$USERPIC{'cache_dir'}/$2",
                              "$USERPIC{'cache_dir'}/$2/$1");
            $file = "$USERPIC{'cache_dir'}/$2/$1/$picid-$userid";
        } else {
            my $mod = sprintf("%03d", $picid % 1000);
            push @dirs_make, "$USERPIC{'cache_dir'}/$mod";
            $file = "$USERPIC{'cache_dir'}/$mod/p$picid-$userid";
        }

        foreach (@dirs_make) {
            next if -d $_;
            mkdir $_, 0777;
        }

        # set both, so we can compared later if they're the same,
        # and thus know if directories were created (if not,
        # apache will give us a pathinfo)
        $RQ{'userpicfile'} = $file;
        $r->filename($file);
    }

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

    my ($data, $lastmod);
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
        $r->header_out("Content-length", $size+0);
        $r->header_out("Cache-Control", "no-transform");
        $r->header_out("Last-Modified", LJ::time_to_http($lastmod));
        $r->send_http_header();
    };

    # Load the user object and pic and make sure the picture is viewable
    my $u = LJ::load_userid($userid);
    return NOT_FOUND unless $u && $u->{'statusvis'} !~ /[XS]/;

    my %upics;
    LJ::load_userpics(\%upics, [ $u, $picid ]);
    my $pic = $upics{$picid} or return NOT_FOUND;
    return NOT_FOUND if $pic->{'userid'} != $userid || $pic->{state} eq 'X';

    # Read the mimetype from the pichash if dversion 7
    $mime = { 'G' => 'image/gif',
              'J' => 'image/jpeg',
              'P' => 'image/png', }->{$pic->{fmt}};

    ### Handle reproxyable requests

    # For dversion 7+ and mogilefs userpics, follow this path
    if ($pic->{location} eq 'M' ) {  # 'M' for mogilefs
        my $key = $u->mogfs_userpic_key( $picid );

        if ( !$LJ::REPROXY_DISABLE{userpics} &&
             $r->header_in('X-Proxy-Capabilities') &&
             $r->header_in('X-Proxy-Capabilities') =~ m{\breproxy-file\b}i )
        {
            my $memkey = [$picid, "mogp.up.$picid"];

            my $zone = $r->header_in('X-MogileFS-Explicit-Zone') || undef;
            $memkey->[1] .= ".$zone" if $zone;

            my $paths = LJ::MemCache::get($memkey);
            unless ($paths) {
                my @paths = LJ::mogclient()->get_paths( $key, { noverify => 1, zone => $zone });
                $paths = \@paths;
                LJ::MemCache::add($memkey, $paths, 3600) if @paths;
            }

            # reproxy url
            if ($paths->[0] =~ m/^http:/) {
                $r->header_out('X-REPROXY-CACHE-FOR', "3600; Last-Modified Content-Type");
                $r->header_out('X-REPROXY-URL', join(' ', @$paths));
            }

            # reproxy file
            else {
                $r->header_out('X-REPROXY-FILE', $paths->[0]);
            }

            $send_headers->();
        }

        else {
            my $data = LJ::mogclient()->get_file_data( $key );
            return NOT_FOUND unless $data;
            $size = length $$data;
            $send_headers->();
            $r->print( $$data ) unless $r->header_only;
        }

        return OK;
    }

    # dversion < 7 reproxy file path
    if ( !$LJ::REPROXY_DISABLE{userpics} &&
         exists $LJ::PERLBAL_ROOT{userpics} &&
         $r->header_in('X-Proxy-Capabilities') &&
         $r->header_in('X-Proxy-Capabilities') =~ m{\breproxy-file\b}i )
    {
        # Get the blobroot and load the pic hash
        my $root = $LJ::PERLBAL_ROOT{userpics};

        # Now ask the blob lib for the path to send to the reproxy
        my $fmt = ($u->{'dversion'} > 6) ? $MimeTypeMapd6{ $pic->{fmt} } : $MimeTypeMap{ $pic->{contenttype} };
        my $path = LJ::Blob::get_rel_path( $root, $u, "userpic", $fmt, $picid );

        $r->header_out( 'X-REPROXY-FILE', $path );
        $send_headers->();

        return OK;
    }

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
        $lastmod = $pic->{'picdate'};

        if ($LJ::USERPIC_BLOBSERVER) {
            my $fmt = ($u->{'dversion'} > 6) ? $MimeTypeMapd6{ $pic->{fmt} } : $MimeTypeMap{ $pic->{contenttype} };
            $data = LJ::Blob::get($u, "userpic", $fmt, $picid);
        }

        unless ($data) {
            my $dbb = LJ::get_cluster_reader($u);
            return SERVER_ERROR unless $dbb;
            $data = $dbb->selectrow_array("SELECT imagedata FROM userpicblob2 WHERE ".
                                          "userid=$pic->{'userid'} AND picid=$picid");
        }
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

sub files_trans
{
    my $r = shift;
    return 404 unless $r->uri =~ m!^/(\w{1,15})/(\w+)(/\S+)!;
    my ($user, $domain, $rest) = ($1, $2, $3);

    if (my $handler = LJ::run_hook("files_handler:$domain", $user, $rest)) {
        $r->notes("codepath" => "files.$domain");
        $r->handler("perl-script");
        $r->push_handlers(PerlHandler => $handler);
        return OK;
    }
    return 404;
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

    # handle HTTP digest authentication
    if ($GET{'auth'} eq 'digest' ||
        $r->header_in("Authorization") =~ /^Digest/) {
        my $res = LJ::auth_digest($r);
        unless ($res) {
            $r->content_type("text/html");
            $r->send_http_header();
            $r->print("<b>Digest authentication failed.</b>");
            return OK;
        }
    }

    my $criterr = 0;

    my $remote = LJ::get_remote({
        criterr      => \$criterr,
    });

    return remote_domsess_bounce() if LJ::remote_bounce_url();

    # check for faked cookies here, since this is pretty central.
    if ($criterr) {
        $r->status_line("500 Invalid Cookies");
        $r->content_type("text/html");
        # reset all cookies
        foreach my $dom (@LJ::COOKIE_DOMAIN_RESET) {
            my $cookiestr = 'ljsession=';
            $cookiestr .= '; expires=' . LJ::time_to_cookie(1);
            $cookiestr .= $dom ? "; domain=$dom" : '';
            $cookiestr .= '; path=/; HttpOnly';
            Apache->request->err_headers_out->add('Set-Cookie' => $cookiestr);
        }

        $r->send_http_header();
        $r->print("Invalid cookies.  Try <a href='$LJ::SITEROOT/logout.bml'>logging out</a> and then logging back in.\n");
        $r->print("<!-- xxxxxxxxxxxxxxxxxxxxxxxx -->\n") for (0..100);
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
        'header' => {
            'If-Modified-Since' => $r->header_in("If-Modified-Since"),
        },
        'handle_with_bml_ref' => \$handle_with_bml,
        'ljentry' => $RQ{'ljentry'},
    };

    $r->notes("view" => $RQ{'mode'});
    my $user = $RQ{'user'};
    my $html = LJ::make_journal($user, $RQ{'mode'}, $remote, $opts);

    return redir($r, $opts->{'redir'}) if $opts->{'redir'};
    return $opts->{'handler_return'} if defined $opts->{'handler_return'};

    # if LJ::make_journal() indicated it can't handle the request:
    if ($handle_with_bml) {
        my $args = $r->args;
        my $args_wq = $args ? "?$args" : "";

        # historical: can't show BML on user domains... redirect them.  nowadays
        # not a big deal, but debug option retained for other sites w/ old BML schemes
        if ($LJ::DEBUG{'no_bml_on_user_domains'}
            && $RQ{'vhost'} eq "users" && ($RQ{'mode'} eq "entry" ||
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

    # Set to 1 if the code should generate junk to help IE
    # display a more meaningful error message.
    my $generate_iejunk = 0;

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
        $generate_iejunk = 1;
    }
    elsif ($opts->{'badfriendgroup'})
    {
        # give a real 404 to the journal owner
        if ($remote && $remote->{'user'} eq $user) {
            $status = "404 Friend group does not exist";
            $html = "<h1>Not Found</h1>" .
                    "<p>The friend group you are trying to access does not exist.</p>";

        # otherwise be vague with a 403
        } else {
            # send back a 403 and don't reveal if the group existed or not
            $status = "403 Friend group does not exist, or is not public";
            $html = "<h1>Denied</h1>" .
                    "<p>Sorry, the friend group you are trying to access does not exist " .
                    "or is not public.</p>\n";

            $html .= "<p>You're not logged in.  If you're the owner of this journal, " .
                     "<a href='$LJ::SITEROOT/login.bml'>log in</a> and try again.</p>\n"
                         unless $remote;
        }

        $generate_iejunk = 1;

    } elsif ($opts->{'suspendeduser'}) {
        $status = "403 User suspended";
        $html = "<h1>Suspended User</h1>" .
                "<p>The content at this URL is from a suspended user.</p>";

        $generate_iejunk = 1;
    }

    unless ($html) {
        $status = "500 Bad Template";
        $html = "<h1>Error</h1><p>User <b>$user</b> has messed up their journal template definition.</p>";
        $generate_iejunk = 1;
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

    $r->content_type($opts->{'contenttype'});
    $r->header_out("Cache-Control", "private, proxy-revalidate");

    $html .= ("<!-- xxxxxxxxxxxxxxxxxxxxxxxxxxxx -->\n" x 100) if $generate_iejunk;

    # Parse the page content for any temporary matches
    # defined in local config
    if (my $cb = $LJ::TEMP_PARSE_MAKE_JOURNAL) {
        $cb->(\$html);
    }

    my $do_gzip = $LJ::DO_GZIP && $LJ::OPTMOD_ZLIB;
    if ($do_gzip) {
        my $ctbase = $opts->{'contenttype'};
        $ctbase =~ s/;.*//;
        $do_gzip = 0 unless $LJ::GZIP_OKAY{$ctbase};
        $do_gzip = 0 if $r->header_in("Accept-Encoding") !~ /gzip/;
    }
    my $length = length($html);
    $do_gzip = 0 if $length < 500;

    if ($do_gzip) {
        my $pre_len = $length;
        $r->notes("bytes_pregzip" => $pre_len);
        $html = Compress::Zlib::memGzip($html);
        $length = length($html);
        $r->header_out('Content-Encoding', 'gzip');
    }
    # Let caches know that Accept-Encoding will change content
    $r->header_out('Vary', 'Accept-Encoding');

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

    my $cur_journal = LJ::Session->domain_journal;
    my $user = LJ::canonical_username($FORM{'username'} || $FORM{'user'} || $cur_journal);
    my $styleid = $FORM{'styleid'} + 0;
    my $nooverride = $FORM{'nooverride'} ? 1 : 0;

    if ($LJ::ONLY_USER_VHOSTS && $cur_journal ne $user) {
        my $u = LJ::load_user($user)
            or return 404;
        my $safeurl = $u->journal_base . "/data/customview?";
        my %get_args = %FORM;
        delete $get_args{'user'};
        delete $get_args{'username'};
        $safeurl .= join("&", map { LJ::eurl($_) . "=" . LJ::eurl($get_args{$_}) } keys %get_args);
        return redir($r, $safeurl);
    }

    my $remote;
    if ($FORM{'checkcookies'}) {
        $remote = LJ::get_remote();
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

sub correct_url_redirect_code {
    if ($LJ::CORRECT_URL_PERM_REDIRECT) {
        return Apache::Constants::HTTP_MOVED_PERMANENTLY();
    }
    return Apache::Constants::REDIRECT();
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

    if ($RQ{'interface'} eq "blogger") {
        return 404 unless $LJ::OPTMOD_XMLRPC;
    my $pkg = "Apache::LiveJournal::Interface::Blogger";
        my $server = XMLRPC::Transport::HTTP::Apache
            -> on_action(sub { die "Access denied\n" if $_[2] =~ /:|\'/ })
            -> dispatch_with({ 'blogger' => $pkg })
            -> dispatch_to($pkg)
            -> handle($r);
        return OK;
    }

    if ($RQ{'interface'} =~ /atom(?:api)?/) {
        # the interface package will set up all headers and
        # print everything
        Apache::LiveJournal::Interface::AtomAPI::handle($r);
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
        my $key = $_;
        my $val = $out{$_};
        $key =~ y/\r\n//d;
        $val =~ y/\r\n//d;
        $r->print($key, "\n", $val, "\n");
        if ($key ne $_ || $val ne $out{$_}) {
            print STDERR "Stripped spurious newline in $FORM{mode} protocol request for $FORM{user}: $_ => $out{$_}\n";
        }
    }

    return OK;
}

sub db_logger
{
    my $r = shift;
    my $rl = $r->last;

    $r->pnotes('did_lj_logging' => 1);

    my $uri = $r->uri;
    my $ctype = $rl->content_type;

    if ($LJ::DONT_LOG_IMAGES) {
        return if $ctype =~ m!^image/!;
        return if $uri =~ m!^/(img|userpic)/!;
    }

    my $skip_db = 0;
    if (defined $LJ::LOG_PERCENTAGE && rand(100) > $LJ::LOG_PERCENTAGE) {
        $skip_db = 1;
    }

    my $dbl = $skip_db ? undef : LJ::get_dbh("logs");
    my @dinsertd_socks;

    my $now = time;
    my @now = localtime($now);

    foreach my $hostport (@LJ::DINSERTD_HOSTS) {
        next if $LJ::CACHE_DINSERTD_DEAD{$hostport} > $now - 15;

        my $sock =
            $LJ::CACHE_DINSERTD_SOCK{$hostport} ||=
            IO::Socket::INET->new(PeerAddr => $hostport,
                                  Proto    => 'tcp',
                                  Timeout  => 1,
                                  );

        if ($sock) {
            delete $LJ::CACHE_DINSERTD_DEAD{$hostport};
            push @dinsertd_socks, [ $hostport, $sock ];
        } else {
            delete $LJ::CACHE_DINSERTD_SOCK{$hostport};
            $LJ::CACHE_DINSERTD_DEAD{$hostport} = $now;
        }
    }

    # allow for a callback specified in ljconfig which allows
    # us to do arbitrary things during this logging phase
    my $cb = ref $LJ::CB_PRE_LOG eq 'CODE' ? $LJ::CB_PRE_LOG : undef;

    # why go on if we have nowhere to log to?
    return unless $dbl || @dinsertd_socks || $cb;

    $ctype =~ s/;.*//;  # strip charset

    # Send out DBI profiling information
    if ( $LJ::DB_LOG_HOST && $LJ::HAVE_DBI_PROFILE ) {
        my ( $host, $dbh );

        while ( ($host,$dbh) = each %LJ::DB_REPORT_HANDLES ) {
            $host =~ s{^(.*?);.*}{$1};

            # For testing: append a random character to simulate different
            # connections.
            if ( $LJ::IS_DEV_SERVER ) {
                $host .= "_" . substr( "abcdefghijklmnopqrstuvwxyz", int rand(26), 1 );
            }

            # From DBI::Profile:
            #   Profile data is stored at the `leaves' of the tree as references
            #   to an array of numeric values. For example:
            #   [
            #     106,                    # count
            #     0.0312958955764771,     # total duration
            #     0.000490069389343262,   # first duration
            #     0.000176072120666504,   # shortest duration
            #     0.00140702724456787,    # longest duration
            #     1023115819.83019,       # time of first event
            #     1023115819.86576,       # time of last event
            #   ]

            # The leaves are stored as values in the hash keyed by statement
            # because LJ::get_dbirole_dbh() sets the profile to
            # "2/DBI::Profile". The 2 part is the DBI::Profile magic number
            # which means split the times by statement.
            my $data = $dbh->{Profile}{Data};

            # Make little arrayrefs out of the statement and longest
            # running-time for this handle so they can be sorted. Then sort them
            # by running-time so the longest-running one can be send to the
            # stats collector.
            my @times =
                sort { $a->[0] <=> $b->[0] }
                map  {[ $data->{$_}[4], $_ ]} keys %$data;

            # ( host, class, time, notes )
            LJ::blocking_report( $host, 'db', @{$times[0]} );
        }
    }

    my $table = sprintf("access%04d%02d%02d%02d", $now[5]+1900,
                        $now[4]+1, $now[3], $now[2]);

    if ($dbl && ! $LJ::CACHED_LOG_CREATE{"$table"}++) {
        my $index = "INDEX(whn),";
        my $delaykeywrite = "DELAY_KEY_WRITE = 1";
        my $sql;
        my $gen_sql = sub {
            $sql = "(".
                "whn TIMESTAMP(14) NOT NULL, $index".
                "server VARCHAR(30),".
                "addr VARCHAR(15) NOT NULL,".
                "ljuser VARCHAR(15),".
                "remotecaps INT UNSIGNED,".
                "journalid INT UNSIGNED,". # userid of what's being looked at
                "journaltype CHAR(1),".   # journalid's journaltype
                "remoteid INT UNSIGNED,". # remote user's userid
                "codepath VARCHAR(80),".  # protocol.getevents / s[12].friends / bml.update / bml.friends.index
                "anonsess INT UNSIGNED,".
                "langpref VARCHAR(5),".
                "uniq VARCHAR(15),".
                "method VARCHAR(10) NOT NULL,".
                "uri VARCHAR(255) NOT NULL,".
                "args VARCHAR(255),".
                "status SMALLINT UNSIGNED NOT NULL,".
                "ctype VARCHAR(30),".
                "bytes MEDIUMINT UNSIGNED NOT NULL,".
                "browser VARCHAR(100),".
                "clientver VARCHAR(100),".
                "secs TINYINT UNSIGNED,".
                "ref VARCHAR(200),".
                "pid SMALLINT UNSIGNED,".
                "cpu_user FLOAT UNSIGNED,".
                "cpu_sys FLOAT UNSIGNED,".
                "cpu_total FLOAT UNSIGNED,".
                "mem_vsize INT,".
                "mem_share INT,".
                "mem_rss INT,".
                "mem_unshared INT) $delaykeywrite";
        };

        $gen_sql->();
        $dbl->do("CREATE TABLE IF NOT EXISTS $table $sql");

        # too many keys specified.  (archive table engine)
        if ($dbl->err == 1069) {
            $index = "";
            $gen_sql->();
            $dbl->do("CREATE TABLE IF NOT EXISTS $table $sql");
        }

        $r->log_error("error creating log table ($table): Error is: " .
                      $dbl->err . ": ". $dbl->errstr) if $dbl->err;
    }

    my $remote = eval { LJ::load_user($rl->notes('ljuser')) };
    my $remotecaps = $remote ? $remote->{caps} : undef;
    my $remoteid   = $remote ? $remote->{userid} : 0;

    my $ju = eval { LJ::load_userid($rl->notes('journalid')) };

    my $var = {
        'whn' => sprintf("%04d%02d%02d%02d%02d%02d", $now[5]+1900, $now[4]+1, @now[3, 2, 1, 0]),
        'server' => $LJ::SERVER_NAME,
        'addr' => $r->connection->remote_ip,
        'ljuser' => $rl->notes('ljuser'),
        'remotecaps' => $remotecaps,
        'remoteid'   => $remoteid,
        'journalid' => $rl->notes('journalid'),
        'journaltype' => $ju ? $ju->{journaltype} : "",
        'codepath' => $rl->notes('codepath'),
        'anonsess' => $rl->notes('anonsess'),
        'langpref' => $rl->notes('langpref'),
        'clientver' => $rl->notes('clientver'),
        'uniq' => $r->notes('uniq'),
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

    # If the configuration says to log statistics and GTop is available, then
    # add those data to the log
    # The GTop object is only created once per child:
    #   Benchmark: timing 10000 iterations of Cached GTop, New Every Time...
    #   Cached GTop: 2.06161 wallclock secs ( 1.06 usr +  0.97 sys =  2.03 CPU) @ 4926.11/s (n=10000)
    #   New Every Time: 2.17439 wallclock secs ( 1.18 usr +  0.94 sys =  2.12 CPU) @ 4716.98/s (n=10000)
  STATS: {
        if ( $LJ::LOG_GTOP && $LJ::HAVE_GTOP ) {
            $GTop ||= new GTop or last STATS;

            my $startcpu = $r->pnotes( 'gtop_cpu' ) or last STATS;
            my $endcpu = $GTop->cpu                 or last STATS;
            my $startmem = $r->pnotes( 'gtop_mem' ) or last STATS;
            my $endmem = $GTop->proc_mem( $$ )      or last STATS;
            my $cpufreq = $endcpu->frequency        or last STATS;

            # Map the GTop values into the corresponding fields in a slice
            @$var{qw{pid cpu_user cpu_sys cpu_total mem_vsize mem_share mem_rss mem_unshared}} = (
                $$,
                ($endcpu->user - $startcpu->user) / $cpufreq,
                ($endcpu->sys - $startcpu->sys) / $cpufreq,
                ($endcpu->total - $startcpu->total) / $cpufreq,
                $endmem->vsize - $startmem->vsize,
                $endmem->share - $startmem->share,
                $endmem->rss - $startmem->rss,
                $endmem->size - $endmem->share,
               );
        }
    }

    # run callback with the hash we've constructed above
    $cb->($var) if $cb;

    if ($dbl) {
        my $ins = sub {
            my $delayed = $LJ::IMMEDIATE_LOGGING ? "" : "DELAYED";
            $dbl->do("INSERT $delayed INTO $table (" . join(',', keys %$var) . ") ".
                     "VALUES (" . join(',', map { $dbl->quote($var->{$_}) } keys %$var) . ")");
        };

        # support for widening the schema at runtime.  if we detect a bogus column,
        # we just don't log that column until the next (wider) table is made at next
        # hour boundary.
        $ins->();
        while ($dbl->err && $dbl->errstr =~ /Unknown column \'(\w+)/) {
            my $col = $1;
            delete $var->{$col};
            $ins->();
        }

        $dbl->disconnect if $LJ::DISCONNECT_DB_LOG;
    }

    if (@dinsertd_socks) {
        $var->{_table} = $table;
        my $string = "INSERT " . Storable::freeze($var) . "\r\n";
        my $len = "\x01" . substr(pack("N", length($string) - 2), 1, 3);
        $string = $len . $string;

        foreach my $rec (@dinsertd_socks) {
            my $sock = $rec->[1];
            print $sock $string;
            my $rin;
            my $res;
            vec($rin, fileno($sock), 1) = 1;
            $res = <$sock> if select($rin, undef, undef, 0.3);
            delete $LJ::CACHE_DINSERTD_SOCK{$rec->[0]} unless $res =~ /^OK\b/;
        }
    }


    # Now clear the profiling data for each handle we're profiling at the last
    # possible second to avoid the next request's data being skewed by
    # requests that happen above.
    if ( $LJ::DB_LOG_HOST && $LJ::HAVE_DBI_PROFILE ) {
        for my $dbh ( values %LJ::DB_REPORT_HANDLES ) {
            # DBI::Profile-recommended way of resetting profile data
            $dbh->{Profile}{Data} = undef;
        }
        %LJ::DB_REPORT_HANDLES = ();
    }
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
    if (ref $req eq "HASH") {
        foreach my $key ('subject', 'event') {
            # get rid of the UTF8 flag in scalars
            $req->{$key} = pack('C*', unpack('C*', $req->{$key}))
                if $req->{$key};
        }
    }
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
