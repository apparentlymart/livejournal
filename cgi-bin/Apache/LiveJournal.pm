#!/usr/bin/perl
#

package Apache::LiveJournal;

use strict;
no warnings 'uninitialized';

use LJ::Request;
use lib "$ENV{LJHOME}/cgi-bin";

# needed to call S2::set_domain() so early:
use LJ::S2;

use Digest::MD5 qw/md5_hex/;

use Class::Autouse qw(
                      LJ::Blob
                      Apache::LiveJournal::Interface::Blogger
                      Apache::LiveJournal::Interface::AtomAPI
                      Apache::LiveJournal::Interface::S2
                      Apache::LiveJournal::Interface::ElsewhereInfo
                      Apache::LiveJournal::PalImg
                      Apache::LiveJournal::Interface::Api
                      LJ::ModuleCheck
                      LJ::AccessLogSink
                      LJ::AccessLogRecord
                      LJ::AccessLogSink::Database
                      LJ::AccessLogSink::DInsertd
                      LJ::AccessLogSink::DBIProfile
                      );

# these aren't lazily loaded in the typical call-a-package-method way,
# but rather we just use Class::Autouse to bring them in during mod_perl
# load.  in non-apache mode, they're loaded via LJ::ModuleCheck->have
use Class::Autouse qw(
                      Compress::Zlib
                      LJ::URI
                      );

use LJ::TimeUtil;
use Apache::WURFL;
use Digest::MD5 qw/md5_base64/;

BEGIN {
    $LJ::OPTMOD_ZLIB = eval { require Compress::Zlib; 1;};

    require "ljlib.pl";
    require "ljviews.pl";
    require "ljprotocol.pl";
    if (%LJ::FOTOBILDER_IP) {
        use Apache::LiveJournal::Interface::FotoBilder;
    }
}

my %RQ;       # per-request data
my %USERPIC;  # conf related to userpics
my %REDIR;

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
    my $class = ();
    my $r     = shift; #

    LJ::Request->free();
    LJ::Request->init($r);

    $class = __PACKAGE__ unless $class;

    if ($LJ::SERVER_TOTALLY_DOWN) {
        LJ::Request->handler("perl-script");
        LJ::Request->set_handlers(PerlHandler => [ \&totally_down_content ]);
        return LJ::Request::OK;
    }

    # only perform this once in case of internal redirects
    if (LJ::Request->is_initial_req) {
        LJ::Request->set_handlers(PerlCleanupHandler => [
                                                            sub { %RQ = () },
                                                            "Apache::LiveJournal::db_logger",
                                                            "LJ::end_request",
                                                            "Apache::DebateSuicide"
                                                        ]);

        if ($LJ::TRUST_X_HEADERS) {
            # if we're behind a lite mod_proxy front-end, we need to trick future handlers
            # into thinking they know the real remote IP address.  problem is, it's complicated
            # by the fact that mod_proxy did nothing, requiring mod_proxy_add_forward, then
            # decided to do X-Forwarded-For, then did X-Forwarded-Host, so we have to deal
            # with all permutations of versions, hence all the ugliness:
            @req_hosts = (LJ::Request->remote_ip);
            if (my $forward = LJ::Request->header_in('X-Forwarded-For'))
            {
                my (@hosts, %seen);
                foreach (split(/\s*,\s*/, $forward)) {
                    next if $seen{$_}++;
                    push @hosts, $_;
                    push @req_hosts, $_;
                }
                if (@hosts) {
                    my $real = shift @hosts;
                    LJ::Request->remote_ip($real);
                }
                LJ::Request->header_in('X-Forwarded-For', join(", ", @hosts));
            }

            # and now, deal with getting the right Host header
            if ($_ = LJ::Request->header_in('X-Host')) {
                LJ::Request->header_in('Host', $_);
            } elsif ($_ = LJ::Request->header_in('X-Forwarded-Host')) {
                LJ::Request->header_in('Host', $_);
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
                LJ::clear_hooks($file);

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
                    die "Failed to reload module [$file] (ret=$good) due to error: \$\!=$!, \$\@=$@";
                }
            }
        }

        LJ::work_report_start();
    }

    LJ::Request->set_handlers(PerlTransHandler => [ \&trans ]);

    return LJ::Request::OK;
}

sub redir {
    # TODO: remove debug code
    if (@_ == 3){
        require Carp;
        Carp::cluck("get 3 args instead of 2");
        shift @_; # assumes the first arg is a Apache->request obj.
    }

    my ($url, $code) = @_;
    if ($LJ::DEBUG{'log_redirects'}) {
        LJ::Request->log_error("redirect to $url from: " . join(", ", caller(0)));
    }
    return LJ::Request->redirect($url, $code);
}

# send the user to the URL for them to get their domain session cookie
sub remote_domsess_bounce {
    return redir(LJ::remote_bounce_url(), LJ::Request::HTTP_MOVED_TEMPORARILY);
}

sub totally_down_content
{
    my $uri = LJ::Request->uri;

    if ($uri =~ m!^/interface/flat! || $uri =~ m!^/cgi-bin/log\.cg!) {
        LJ::Request->content_type("text/plain");
        LJ::Request->send_http_header();
        LJ::Request->print("success\nFAIL\nerrmsg\n$LJ::SERVER_DOWN_MESSAGE");
        return LJ::Request::OK;
    }

    if ($uri =~ m!^/customview.cgi!) {
        LJ::Request->content_type("text/html");
        LJ::Request->send_http_header();
        LJ::Request->print("<!-- $LJ::SERVER_DOWN_MESSAGE -->");
        return LJ::Request::OK;
    }

    LJ::Request->pnotes ('error' => 'e500');
    LJ::Request->pnotes ('remote' => LJ::get_remote());

    # set to 500 so people don't cache this error message
    my $body = "<h1>$LJ::SERVER_DOWN_SUBJECT</h1>$LJ::SERVER_DOWN_MESSAGE<!-- " . ("x" x 1024) . " -->";
    LJ::Request->status_line("503 Server Maintenance");
    LJ::Request->content_type("text/html");
    LJ::Request->header_out("Content-length", length $body);
    LJ::Request->send_http_header();

    LJ::Request->print($body);
    return LJ::Request::OK;
}

sub blocked_bot
{
    LJ::Request->status(LJ::Request::HTTP_PRECONDITION_FAILED);
    LJ::Request->content_type("text/html");
    LJ::Request->send_http_header();

    my ($ip, $uniq);
    if ($LJ::BLOCKED_BOT_INFO) {
        $ip = LJ::get_remote_ip();
        $uniq = LJ::UniqCookie->current_uniq;
    }

    my $subject = LJ::Lang::get_text(undef, 'error.banned.bot.subject') || $LJ::BLOCKED_BOT_SUBJECT || "403 Denied";
    my $message = LJ::Lang::get_text(undef, 'error.banned.bot.message', undef, { ip => $ip, uniq => $uniq } );

    unless ($message) {
        $message = $LJ::BLOCKED_BOT_MESSAGE || "You don't have permission to view this page.";
        $message .= " $uniq @ $ip" if $LJ::BLOCKED_BOT_INFO;
    }

    LJ::Request->print("<h1>$subject</h1>$message");
    return LJ::Request::HTTP_PRECONDITION_FAILED;
}

sub trans
{
    {
        my $r = shift;
        LJ::Request->init($r);
    }

    return LJ::Request::DECLINED
        if ! LJ::Request->is_main || LJ::Request->method_number == LJ::Request->M_OPTIONS;  # don't deal with subrequests or OPTIONS

    my $uri  = LJ::Request->uri;

    my $args = LJ::Request->args;
    my $args_wq = $args ? "?$args" : "";
    my $host = LJ::Request->header_in("Host");
    $host =~ s/(:\d+)$//;
    my ($hostport) = $1 || "";
    $host =~ s/\.$//; ## 'www.livejournal.com.' is a valid DNS hostname

    $host = $LJ::DOMAIN_WEB unless LJ::Request::request->{r}->is_initial_req;

    # disable TRACE (so scripts on non-LJ domains can't invoke
    # a trace to get the LJ cookies in the echo)
    if (LJ::Request->method_number == LJ::Request::M_TRACE) {
        LJ::Request->pnotes ('error' => 'baduser');
        LJ::Request->pnotes ('remote' => LJ::get_remote());
        return LJ::Request::FORBIDDEN;
    }

    # If the configuration says to log statistics and GTop is available, mark
    # values before the request runs so it can be turned into a delta later
    if (my $gtop = LJ::gtop()) {
        LJ::Request->pnotes( 'gtop_cpu' => $gtop->cpu );
        LJ::Request->pnotes( 'gtop_mem' => $gtop->proc_mem($$) );
    }

    LJ::start_request();
    LJ::procnotify_check();
    S2::set_domain('LJ');

    # add server mark
    my ($aws_id) = $LJ::HARDWARE_SERVER_NAME =~ /\-(.+)$/;
    LJ::Request->header_out("X-AWS-Id" => $aws_id || 'unknown');

    my $lang = $LJ::DEFAULT_LANG || $LJ::LANGS[0];
    BML::set_language($lang, \&LJ::Lang::get_text);

    my $is_ssl = $LJ::IS_SSL = LJ::run_hook("ssl_check");

    my $bml_handler = sub {
        my $filename = shift;

        LJ::Request->handler("perl-script");
        LJ::Request->notes("bml_filename" => $filename);
        LJ::Request->set_handlers(PerlHandler => \&Apache::BML::handler);
        return LJ::Request::OK;
    };

    if (LJ::Request->is_initial_req) {
        # delete cookies if there are any we want gone
        if (my $cookie = $LJ::DEBUG{"delete_cookie"}) {
            LJ::Session::set_cookie($cookie => 0, delete => 1, domain => $LJ::DOMAIN, path => "/");
        }

        # handle uniq cookies
        if ($LJ::UNIQ_COOKIES) {

            # this will ensure that we have a correct cookie value
            # and also add it to $r->notes
            LJ::UniqCookie->ensure_cookie_value;

              # apply sysban block if applicable
              if (LJ::UniqCookie->sysban_should_block) {
                  LJ::Request->handler("perl-script");
                  LJ::Request->set_handlers(PerlHandler => \&blocked_bot );
                  return LJ::Request::OK;
              }
          }
    } else {
        # on error we do internal redirect to error page
        LJ::Request->pnotes ('error' => 'e404');
        LJ::Request->pnotes ('remote' => LJ::get_remote());
        if (LJ::Request->status == 404) {
            my $fn = $LJ::PAGE_404 || "404-error.html";
            return $bml_handler->("$LJ::HOME/htdocs/" . $fn);
        }
    }

    # check for sysbans on ip address
    # Don't block requests against the bot URI, if defined
    unless ( $LJ::BLOCKED_BOT_URI && index( $uri, $LJ::BLOCKED_BOT_URI ) == 0 ) {
        foreach my $ip (@req_hosts) {
            if (LJ::sysban_check('ip', $ip)) {
                LJ::Request->handler("perl-script");
                LJ::Request->set_handlers(PerlHandler => \&blocked_bot);
                return LJ::Request::OK;
            }
        }
        if (LJ::run_hook("forbid_request")) {
            LJ::Request->handler("perl-script");
            LJ::Request->set_handlers(PerlHandler => \&blocked_bot);
            return LJ::Request::OK
        }
    }
    
    if(LJ::Request->headers_in->{Accept} eq 'application/xrds+xml'){
        LJ::Request->header_out('X-XRDS-Location' => 'http://api.' . $LJ::DOMAIN .'/xrds');
    }
    
    # only allow certain pages over SSL
    if ($is_ssl) {
        if ($uri =~ m!^/interface/! || $uri =~ m!^/__rpc_!) {
            # handled later
        } elsif ($LJ::SSLDOCS && $uri !~ m!(\.\.|\%|\.\/)!) {
            if ($uri =~ m#^/img/userinfo.gif#) {
                my $remote = LJ::get_remote();
                if ($remote) {
                    my $custom_userhead = $remote->custom_usericon;
                    require URI;
                    my $uri = URI->new ($custom_userhead);
                    my $res = send_files ($uri->path);
                    LJ::Request->content_type ("image/gif");
                    return ($res == LJ::Request::OK) ? LJ::Request::DONE : $res;
                }
            }

            my $file = "$LJ::SSLDOCS/$uri";
            unless (-e $file) {
                # no such file.  send them to the main server if it's a GET.
                return LJ::Request->method eq 'GET' ? redir("$LJ::SITEROOT$uri$args_wq") : 404;
            }
            if (-d _) { $file .= "/index.bml"; }
            $file =~ s!/{2,}!/!g;
            LJ::Request->filename($file);
            $LJ::IMGPREFIX = "/img";
            $LJ::STATPREFIX = "/stc";
            return LJ::Request::OK
        } else {
            return LJ::Request::FORBIDDEN;
        }
    } elsif (LJ::run_hook("set_alternate_statimg")) {
        # do nothing, hook did it.
    } else {
        $LJ::DEBUG_HOOK{'pre_restore_bak_stats'}->() if $LJ::DEBUG_HOOK{'pre_restore_bak_stats'};
        $LJ::IMGPREFIX = $LJ::IMGPREFIX_BAK;
        $LJ::STATPREFIX = $LJ::STATPREFIX_BAK;
        $LJ::USERPIC_ROOT = $LJ::USERPICROOT_BAK if $LJ::USERPICROOT_BAK;
    }

    # let foo.com still work, but redirect to www.foo.com
    if ($LJ::DOMAIN_WEB && LJ::Request->method eq "GET" &&
        $host eq $LJ::DOMAIN && $LJ::DOMAIN_WEB ne $LJ::DOMAIN)
    {
        my $url = "$LJ::SITEROOT$uri";
        $url .= "?" . $args if $args;
        return redir($url);
    }

    # see if we should setup a minimal scheme based on the initial part of the
    # user-agent string; FIXME: maybe this should do more than just look at the
    # initial letters?
    if (my $ua = LJ::Request->header_in('User-Agent')) {
        if (($ua =~ /^([a-z]+)/i) && $LJ::MINIMAL_USERAGENT{$1}) {
            LJ::Request->notes('use_minimal_scheme' => 1);
            LJ::Request->notes('bml_use_scheme' => $LJ::MINIMAL_BML_SCHEME);
        }
    }

    # Redirect to mobile version if needed.
    my $new_url = Apache::WURFL->redirect4mobile( host => $host, uri => $uri, );
    return redir($new_url, LJ::Request::HTTP_MOVED_PERMANENTLY) if $new_url;

    # now we know that the request is going to succeed, so do some checking if they have a defined
    # referer.  clients and such don't, so ignore them.
    my $referer = LJ::Request->header_in("Referer");
    if ($referer && LJ::Request->method eq 'POST' && !LJ::check_referer('', $referer)) {
       ## uncomment log statement after adding some code in this if-block.
       ## LJ::Request->log_error("REFERER WARNING: POST to $uri from $referer");
       ## ...
    }

    my %GET = LJ::Request->args;

    if ($LJ::IS_DEV_SERVER && $GET{'as'} =~ /^\w{1,15}$/) {
        my $ru = LJ::load_user($GET{'as'});
        LJ::set_remote($ru); # might be undef, to allow for "view as logged out"
    }

    # anti-squatter checking
    if ($LJ::DEBUG{'anti_squatter'} && LJ::Request->method eq "GET") {
        my $ref = LJ::Request->header_in("Referer");
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
                LJ::Request->handler("perl-script");
                LJ::Request->set_handlers(PerlHandler => \&anti_squatter);
            }
            return LJ::Request::OK
        }
    }

    # is this the embed module host
    if ($LJ::EMBED_MODULE_DOMAIN && $host =~ /$LJ::EMBED_MODULE_DOMAIN$/) {
        return $bml_handler->("$LJ::HOME/htdocs/tools/embedcontent.bml");
    }

    # allow html pages (with .html extention) in user domains and in common www. domain.
    if ($uri =~ m|\A\/__html(\/.+\.html)\z|){
        LJ::Request->uri($1);
        return LJ::Request::DECLINED
    }

    ## TODO: handler/hooks like below must be modular/chainable/extendable
    if (my $redirect_url = LJ::run_hook("should_redirect", $host, $uri, \%GET)) {
        return redir($redirect_url);
    }

    my $journal_view = sub {
        my $opts = shift;
        $opts ||= {};

        my $orig_user = $opts->{'user'};
        $opts->{'user'} = LJ::canonical_username($opts->{'user'});

        my $remote = LJ::get_remote();
        my $u = LJ::load_user($orig_user);

        # do redirects:
        # -- communities to the right place
        # -- uppercase usernames
        # -- users with hyphens/underscores, except users from external domains (see table 'domains')
        if ($u && $u->is_community) {
            if ($opts->{'vhost'} =~ /^(?:users||tilde)$/ ||
                $orig_user ne lc($orig_user) ||
                $orig_user =~ /[_-]/ && $u && $u->journal_base !~ m!^http://$host!i && $opts->{'vhost'} !~ /^other:/) {
    
                my $newurl = $uri;
    
                # if we came through $opts->{vhost} eq "users" path above, then
                # the s/// below will not match and there will be a leading /,
                # so the s/// leaves a leading slash as well so that $newurl is
                # consistent for the concatenation before redirect
                $newurl =~ s!^/(users/|community/|~)\Q$orig_user\E!/!;
                $newurl = LJ::journal_base($u) . "$newurl$args_wq";
                return redir($newurl);
            } 
            
            LJ::run_hook('vertical_tags', $remote, $u);
        }

        # check if this entry or journal contains adult content
        if (LJ::is_enabled('content_flag')) {
            # force remote to be checked
            my $burl = LJ::remote_bounce_url();
            return remote_domsess_bounce() if LJ::remote_bounce_url();

            my $entry = $opts->{ljentry};
            my $poster;

            my $adult_content = "none";
            if ($u && $entry) {
                $adult_content = $entry->adult_content_calculated || $u->adult_content_calculated;
                $poster = $entry->poster;
            } elsif ($u) {
                $adult_content = $u->adult_content_calculated;
            }

            # we should show the page (no interstitial) if:
            # the remote user owns the journal we're viewing OR
            # the remote user posted the entry we're viewing
            my $should_show_page = $remote && ($remote->can_manage($u) || ($entry && $remote->equals($poster)));

            my %journal_pages = (
                friends => 1,
                calendar => 1,
                month => 1,
                day => 1,
                tag => 1,
                entry => 1,
                reply => 1,
                lastn => 1,
            );
            my $is_journal_page = !$opts->{mode} || $journal_pages{$opts->{mode}};

            if ($adult_content ne "none" && $is_journal_page && !$should_show_page) {
                my $returl = LJ::eurl("http://$host" . LJ::Request->uri . "$args_wq");

                LJ::Request->notes("journalid" => $u->{userid}) if $u;

                LJ::ContentFlag->check_adult_cookie($returl, \%BMLCodeBlock::POST, "concepts");
                LJ::ContentFlag->check_adult_cookie($returl, \%BMLCodeBlock::POST, "explicit");

                my $cookie = $BML::COOKIE{LJ::ContentFlag->cookie_name($adult_content)};

                # if they've confirmed that they're over 18, then they're over 14 too
                if ($adult_content eq "concepts" && !$cookie) {
                    $cookie = 1 if $BML::COOKIE{LJ::ContentFlag->cookie_name("explicit")};
                }

                # logged in users with defined ages are blocked from content that's above their age level
                # logged in users without defined ages and logged out users are given confirmation pages (unless they have already confirmed)
                if ($remote) {
                    if (($adult_content eq "explicit" && $remote->is_minor) || ($adult_content eq "concepts" && $remote->is_child)) {
                        LJ::Request->args("user=" . LJ::eurl($opts->{'user'}));
                        return $bml_handler->(LJ::ContentFlag->adult_interstitial_path(type => "${adult_content}_blocked"));
                    } elsif (!$remote->best_guess_age && !$cookie) {
                        LJ::Request->args("ret=$returl&user=" . LJ::eurl($opts->{'user'}));
                        return $bml_handler->(LJ::ContentFlag->adult_interstitial_path(type => $adult_content));
                    }
                } elsif (!$remote && !$cookie) {
                    LJ::Request->args("ret=$returl&user=" . LJ::eurl($opts->{'user'}));
                    return $bml_handler->(LJ::ContentFlag->adult_interstitial_path(type => $adult_content));
                }
            }
        }

        if ($opts->{'mode'} eq "info") {
            my $u = LJ::load_user($opts->{user})
                or return LJ::Request::NOT_FOUND;
            my $mode = $GET{mode} eq 'full' ? '?mode=full' : '';
            return redir($u->profile_url . $mode);
        }

        if ($opts->{'mode'} eq "profile") {
            my $burl = LJ::remote_bounce_url();
            return remote_domsess_bounce() if LJ::remote_bounce_url();

            LJ::Request->notes("_journal" => $opts->{'user'});

            # this is the notes field that all other s1/s2 pages use.
            # so be consistent for people wanting to read it.
            # _journal above is kinda deprecated, but we'll carry on
            # its behavior of meaning "whatever the user typed" to be
            # passed to the userinfo BML page, whereas this one only
            # works if journalid exists.
            if (my $u = LJ::load_user($opts->{user})) {
                LJ::Request->notes("journalid" => $u->{userid});
            } else {
                LJ::Request->pnotes ('error' => 'baduser');
                LJ::Request->pnotes ('remote' => LJ::get_remote());
                return LJ::Request::NOT_FOUND;
            }

            my $file = LJ::run_hook("profile_bml_file");
            $file ||= $LJ::PROFILE_BML_FILE || "userinfo.bml";
            if ($args =~ /\bver=(\w+)\b/) {
                $file = $LJ::ALT_PROFILE_BML_FILE{$1} if $LJ::ALT_PROFILE_BML_FILE{$1};
            }
            return $bml_handler->("$LJ::HOME/htdocs/$file");
        }

        if ($opts->{'mode'} eq "wishlist") {

            if (my $u = LJ::load_user($opts->{user})) {
                LJ::Request->notes("journalid" => $u->{userid});
            } else {
                LJ::Request->pnotes ('error' => 'baduser');
                LJ::Request->pnotes ('remote' => LJ::get_remote());
                return LJ::Request::NOT_FOUND;
            }

            return $bml_handler->("$LJ::HOME/htdocs/wishlist.bml");
        }

        if ($opts->{'mode'} eq "update") {
            my $u = LJ::load_user($opts->{user})
                or return LJ::Request::NOT_FOUND;

            return redir("$LJ::SITEROOT/update.bml?usejournal=".$u->{'user'});
        }

        %RQ = %$opts;

        if ($opts->{mode} eq "data" && $opts->{pathextra} =~ m!^/(\w+)(/.*)?!) {
            my $remote = LJ::get_remote();
            my $burl = LJ::remote_bounce_url();
            return remote_domsess_bounce() if LJ::remote_bounce_url();

            my ($mode, $path) = ($1, $2);
            if ($mode eq "customview") {
                LJ::Request->handler("perl-script");
                LJ::Request->set_handlers(PerlHandler => \&customview_content);
                return LJ::Request::OK
            }
            if (my $handler = LJ::run_hook("data_handler:$mode", $RQ{'user'}, $path)) {
                LJ::Request->handler("perl-script");
                LJ::Request->set_handlers(PerlHandler => $handler);
                return LJ::Request::OK
            }
        }

        LJ::Request->handler("perl-script");
        LJ::Request->set_handlers(PerlHandler => \&journal_content);
        return LJ::Request::OK
    };

    my $determine_view = sub {
        my ($user, $vhost, $uuri) = @_;
        my $mode = undef;
        my $pe;
        my $ljentry;

        # if favicon, let filesystem handle it, for now, until
        # we have per-user favicons.
        return LJ::Request::DECLINED if $uuri eq "/favicon.ico";

        # see if there is a modular handler for this URI
        my $ret = LJ::URI->handle($uuri);
        return $ret if defined $ret;

        if ($uuri eq "/__setdomsess") {
            return redir(LJ::Session->setdomsess_handler());
        }

        if ($uuri =~ m#^/(\d+)\.html$#) { #
            my $u = LJ::load_user($user);
            unless ($u) {
                LJ::Request->pnotes ('error' => 'baduser');
                LJ::Request->pnotes ('remote' => LJ::get_remote());
                return LJ::Request::NOT_FOUND;
            }

            $ljentry = LJ::Entry->new($u, ditemid => $1);
            if ($GET{'mode'} eq "reply" || $GET{'replyto'} || $GET{'edit'}) {
                $mode = "reply";
            } else {
                $mode = "entry";
            }

        } elsif ($uuri =~ m#^/(\d\d\d\d)(?:/(\d\d)(?:/(\d\d))?)?(/?)$#) {
            my ($year, $mon, $day, $slash) = ($1, $2, $3, $4);
            unless ($slash) {
                my $u = LJ::load_user($user)
                    or return LJ::Request::NOT_FOUND;
                my $proper = $u->journal_base . "/$year";
                $proper .= "/$mon" if defined $mon;
                $proper .= "/$day" if defined $day;
                $proper .= "/";
                return redir($proper);
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
                return redir(LJ::journal_base($user) . $newuri);
            } elsif ($mode eq 'rss') {
                # code 301: moved permanently, update your links.
                return redir(LJ::journal_base($user) . "/data/rss$args_wq", 301);
            } elsif ($mode eq 'pics' && $LJ::REDIRECT_ALLOWED{$LJ::FB_DOMAIN}) {
                # redirect to a user's gallery
                my $url = "$LJ::FB_SITEROOT/$user";
                return redir($url);
            } elsif ($mode eq 'tag') {

                # tailing slash on here to prevent a second redirect after this one
                return redir(LJ::journal_base($user) . "$uri/") unless $pe;
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
            } elsif ($mode eq 'security') {
                # tailing slash on here to prevent a second redirect after this one
                return redir(LJ::journal_base($user) . "$uri/") unless $pe;
                if ($pe eq '/') {
                    # do a 404 for now
                    LJ::request->pnotes ('error' => 'e404');
                    LJ::Request->pnotes ('remote' => LJ::get_remote());
                    return LJ::Request::NOT_FOUND;
                } else {
                    # filtered lastn page
                    $mode = 'lastn';

                    # prepend /security so that lastn knows to do security filtering
                    $pe = "/security$pe";
                }
            }
        } elsif (($vhost eq "users" || $vhost =~ /^other:/) &&
                 $uuri eq "/robots.txt") {
            $mode = "robots_txt";
        } else {
            my $key = $uuri;
            $key =~ s!^/!!;
            my $u = LJ::load_user($user);
            unless ($u) {
                LJ::Request->pnotes ('error' => 'baduser');
                LJ::Request->pnotes ('remote' => LJ::get_remote());
                return LJ::Request::NOT_FOUND;
            }

            my ($type, $nodeid) =
                $LJ::DISABLED{'named_permalinks'} ? () :
                $u->selectrow_array("SELECT nodetype, nodeid FROM urimap WHERE journalid=? AND uri=?",
                                    undef, $u->{userid}, $key);
            if ($type eq "L") {
                $ljentry = LJ::Entry->new($u, ditemid => $nodeid);
                if ($GET{'mode'} eq "reply" || $GET{'replyto'} || $GET{'edit'}) {
                    $mode = "reply";
                } else {
                    $mode = "entry";
                }
            }

        }

        unless (defined $mode) {
            LJ::Request->pnotes ('error' => 'e404');
            LJ::Request->pnotes ('remote' => LJ::get_remote());
            return LJ::Request::NOT_FOUND;
        }

        # Now that we know ourselves to be at a sensible URI, redirect renamed
        # journals. This ensures redirects work sensibly for all valid paths
        # under a given username, without sprinkling redirects everywhere.
        my $u = LJ::load_user($user);
        if ($u && $u->{'journaltype'} eq 'R' && $u->{'statusvis'} eq 'R') {
            LJ::load_user_props($u, 'renamedto');
            my $renamedto = $u->{'renamedto'};
            if ($renamedto ne '') {
                my $redirect_url = ($renamedto =~ m!^https?://!) ? $renamedto : LJ::journal_base($renamedto, $vhost) . $uuri . $args_wq;
                return redir($redirect_url, 301);
            }
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
        LJ::Request->status < 400)
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
            return redir("$LJ::SITEROOT/portal/");

        } elsif ($func eq 'support') {
            return redir("$LJ::SITEROOT/support/");

        } elsif (ref $func eq "ARRAY" && $func->[0] eq "changehost") {

            return redir("http://$func->[1]$uri$args_wq");

        } elsif ($uri =~ m!^/(?:talkscreen|delcomment)\.bml!) {
            # these URLs need to always work for the javascript comment management code
            # (JavaScript can't do cross-domain XMLHttpRequest calls)
            return LJ::Request::DECLINED

        } elsif ($func eq "journal") {
            
# Temporary block. Just for one-time verification. LJSUP-7700
            if ($uri eq '/yandex_58d720848324d318.txt') {
                LJ::Request->handler("perl-script");
                LJ::Request->set_handlers(PerlHandler => sub{ return LJ::Request::OK; });
                return LJ::Request::OK;
            } 
# end of temporary block            
            elsif ($uri !~ m!^/(\w{1,15})(/.*)?$!) {
                return LJ::Request::DECLINED if $uri eq "/favicon.ico";
                my $redir = LJ::run_hook("journal_subdomain_redirect_url",
                                         $host, $uri);
                return redir($redir) if $redir;
                LJ::Request->pnotes ('error' => 'baduser');
                LJ::Request->pnotes ('remote' => LJ::get_remote());
                return LJ::Request::NOT_FOUND;
            }
            ($user, $uri) = ($1, $2);
            $uri ||= "/";

            # redirect them to their canonical URL if on wrong host/prefix
            if (my $u = LJ::load_user($user)) {
                my $canon_url = $u->journal_base;
                unless ($canon_url =~ m!^http://$host!i || $LJ::DEBUG{'user_vhosts_no_wronghost_redirect'}) {
                    return redir("$canon_url$uri$args_wq");
                }
            }

            my $view = $determine_view->($user, "safevhost", $uri);
            return $view if defined $view;
        } elsif ($func eq 'api') {
            Apache::LiveJournal::Interface::Api->load;
            LJ::Request->handler("perl-script");
            LJ::Request->push_handlers(PerlHandler => \&Apache::LiveJournal::Interface::Api::handler);
            return LJ::Request::OK;
        
            LJ::Request->pnotes ('error' => 'e404');
            LJ::Request->pnotes ('remote' => LJ::get_remote());
            return LJ::Request::NOT_FOUND;
        } elsif ($func eq "games") {
            LJ::get_remote();
            return redir(LJ::Session->setdomsess_handler()) if LJ::Request->uri eq "/__setdomsess";

            return LJ::URI->bml_handler($LJ::AJAX_URI_MAP{$1}) if (LJ::Request->uri =~ /^\/__rpc_((?:ljapp|lj_times).*)$/);

    	    return remote_domsess_bounce() if LJ::remote_bounce_url();
            return $bml_handler->("$LJ::HOME/htdocs/games/game.bml");
        } elsif ($func) {
            my $code = {
                'userpics' => \&userpic_trans,
                'files' => \&files_trans,
            };
            return $code->{$func}->(LJ::Request->r) if $code->{$func};
            LJ::Request->pnotes ('error' => 'e404');
            LJ::Request->pnotes ('remote' => LJ::get_remote());
            return LJ::Request::NOT_FOUND;  # bogus ljconfig
        } else {
            ##
            my $u = LJ::load_user($user);
            LJ::set_active_journal($u) if $u;

            my $view = $determine_view->($user, "users", $uri);
            return $view if defined $view;
            LJ::Request->pnotes ('error' => 'e404');
            LJ::Request->pnotes ('remote' => LJ::get_remote());
            return LJ::Request::NOT_FOUND;
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
        unless ($user) {
            LJ::Request->pnotes ('error' => 'baduser');
            LJ::Request->pnotes ('remote' => LJ::get_remote());
            return LJ::Request::NOT_FOUND;
        }

        my $view = $determine_view->($user, "other:$host$hostport", $uri);
        return $view if defined $view;
        LJ::Request->pnotes ('error' => 'baduser');
        LJ::Request->pnotes ('remote' => LJ::get_remote());
        return LJ::Request::NOT_FOUND;
    }

    # userpic
    return userpic_trans() if $uri =~ m!^/userpic/!;

    # front page journal
    if ($LJ::FRONTPAGE_JOURNAL) {
        my $view = $determine_view->($LJ::FRONTPAGE_JOURNAL, "front", $uri);
        return $view if defined $view;
    }

    # normal (non-domain) journal view
    if (
        $uri =~ m!
        ^/(users\/|community\/|\~)  # users/community/tilde
        ([^/]+)                     # potential username
        (.*)?                       # rest
        !x && $uri !~ /\.bml/)
    {
        my ($part1, $user, $rest) = ($1, $2, $3);

        # get what the username should be
        my $cuser = LJ::canonical_username($user);
        return LJ::Request::DECLINED unless length($cuser);

        my $srest = $rest || '/';

        # need to redirect them to canonical version
        if ($LJ::ONLY_USER_VHOSTS && ! $LJ::DEBUG{'user_vhosts_no_old_redirect'}) {
            # FIXME: skip two redirects and send them right to __setdomsess with the right
            #        cookie-to-be-set arguments.  below is the easy/slow route.
            my $u = LJ::load_user($cuser);
            unless ($u) {
                LJ::Request->pnotes ('error' => 'baduser');
                LJ::Request->pnotes ('remote' => LJ::get_remote());
                return LJ::Request::NOT_FOUND;
            }
            my $base = $u->journal_base;
            return redir("$base$srest$args_wq", correct_url_redirect_code());
        }

        # redirect to canonical username and/or add slash if needed
        return redir("http://$host$hostport/$part1$cuser$srest$args_wq")
            if $cuser ne $user or not $rest;

        my $vhost = { 'users/' => '', 'community/' => 'community',
                      '~' => 'tilde' }->{$part1};

        my $view = $determine_view->($user, $vhost, $rest);
        return $view if defined $view;
    }

    # custom interface handler
    if ($uri =~ m!^/interface/([\w\-]+)$!) {
        my $inthandle = LJ::run_hook("interface_handler", {
            int         => $1,
            bml_handler => $bml_handler,
        });
        return $inthandle if defined $inthandle;
    }

    # protocol support
    if ($uri =~ m!^/(?:interface/(\w+))|cgi-bin/log\.cgi!) {
        my $int = $1 || "flat";
        LJ::Request->handler("perl-script");
        if ($int eq "fotobilder") {
            unless ($LJ::FOTOBILDER_IP{LJ::Request->remote_ip}) {
                LJ::Request->pnotes ('error' => 'baduser');
                LJ::Request->pnotes ('remote' => LJ::get_remote());
                return LJ::Request::FORBIDDEN;
            }
            LJ::Request->set_handlers(PerlHandler => \&Apache::LiveJournal::Interface::FotoBilder::handler);
            return LJ::Request::OK
        }
        if ($int =~ /^flat|xmlrpc|blogger|elsewhere_info|atom(?:api)?$/) {
            $RQ{'interface'} = $int;
            $RQ{'is_ssl'} = $is_ssl;
            LJ::Request->set_handlers(PerlHandler => \&interface_content);
            return LJ::Request::OK
        }
        if ($int eq "s2") {
            Apache::LiveJournal::Interface::S2->load;
            LJ::Request->set_handlers(PerlHandler => \&Apache::LiveJournal::Interface::S2::handler);
            return LJ::Request::OK
        }
        LJ::Request->pnotes ('error' => 'e404');
        LJ::Request->pnotes ('remote' => LJ::get_remote());
        return LJ::Request::NOT_FOUND;
    }

    # see if there is a modular handler for this URI
    my $ret = LJ::URI->handle($uri);
    return $ret if defined $ret;

    # customview (get an S1 journal by number)
    if ($uri =~ m!^/customview\.cgi!) {
        LJ::Request->handler("perl-script");
        LJ::Request->set_handlers(PerlHandler => \&customview_content);
        return LJ::Request::OK;
    }

    if ($uri =~ m!^/palimg/!) {
        Apache::LiveJournal::PalImg->load;
        LJ::Request->handler("perl-script");
        LJ::Request->set_handlers(PerlHandler => \&Apache::LiveJournal::PalImg::handler);
        return LJ::Request::OK;
    }

    # redirected resources
    if ($REDIR{$uri}) {
        my $new = $REDIR{$uri};
        if (LJ::Request->args) {
            $new .= ($new =~ /\?/ ? "&" : "?");
            $new .= LJ::Request->args;
        }
        return redir($new, LJ::Request::HTTP_MOVED_PERMANENTLY);
    }

    # confirm
    if ($uri =~ m!^/confirm/(\w+\.\w+)!) {
        return redir("$LJ::SITEROOT/register.bml?$1");
    }

    # approve
    if ($uri =~ m!^/approve/(\w+\.\w+)!) {
        return redir("$LJ::SITEROOT/approve.bml?$1");
    }

    # reject
    if ($uri =~ m!^/reject/(\w+\.\w+\.\d+)!) {
        return redir("$LJ::SITEROOT/reject.bml?$1");
    }

    if ($uri =~ m!^/userpics!) {
        LJ::Request->pnotes ('error' => 'baduser');
        LJ::Request->pnotes ('remote' => LJ::get_remote());
        return LJ::Request::FORBIDDEN;
    }

    # avoid the fakeapache library having to deal with the <Files ~ *.bml> stuff
    # in the modperl_startup.pl http_conf
    if (ref(LJ::Request->r) eq "Test::FakeApache::Request" && $host eq $LJ::DOMAIN_WEB) {
        my $file = "$LJ::HTDOCS$uri";
        $file .= "/index.bml" unless $uri =~ /\.bml$/;
        $file =~ s!/{2,}!/!;
        LJ::Request->notes("bml_filename" => $file);
        return Apache::BML::handler();
    }

    # emulate DirectoryIndex directive
    if ($host =~ m'^www' and
        not defined LJ::Request->filename  # it seems that under Apache v2 'filename' method maps to files only
                                           # and for directories it returns undef.
    ){
        # maps uri to dir
        my $uri = LJ::Request->uri;
        
        ## forbids ANY .. in uri
        if ($uri =~ /\.\./) {
            LJ::Request->pnotes ('error' => 'e404');
            LJ::Request->pnotes ('remote' => LJ::get_remote());
            return LJ::Request::NOT_FOUND;
        }

        if ($uri and -d "$ENV{LJHOME}/htdocs/" . $uri){
            unless ($uri =~ /\/$/) {
                return redir("$LJ::SITEROOT$uri/");
            }

            # index.bml
            my $new_uri  = $uri . "index.bml";
            my $bml_file = "$ENV{LJHOME}/htdocs/" . $uri . "index.bml";
            if (-e $bml_file) {
                LJ::Request->uri($new_uri);
                return $bml_handler->($bml_file);
            }

            # index.html
            my $html_file = "$ENV{LJHOME}/htdocs/" . $uri . "index.html";
            if (-e $html_file){
                return redir($uri . "index.html");
            }
        }
    }
    LJ::Request->pnotes ('error' => 'e404');
    LJ::Request->pnotes ('remote' => LJ::get_remote());
    return LJ::Request::DECLINED
}

sub userpic_trans
{

    if (LJ::Request->uri eq '/crossdomain.xml') {
        LJ::Request->handler("perl-script"); 
        LJ::Request->set_handlers(PerlHandler => \&crossdomain_content); 
        return LJ::Request::OK;
    }
    
    LJ::Request->pnotes (error => 'e404') unless LJ::Request->uri =~ m!^/(?:userpic/)?(\d+)/(\d+)$!;
    return LJ::Request::NOT_FOUND unless LJ::Request->uri =~ m!^/(?:userpic/)?(\d+)/(\d+)$!;
    my ($picid, $userid) = ($1, $2);
    LJ::Request->notes("codepath" => "img.userpic");

    # redirect to the correct URL if we're not at the right one,
    # and unless CDN stuff is in effect...
    unless ($LJ::USERPIC_ROOT ne $LJ::USERPICROOT_BAK) {
        my $host = LJ::Request->header_in("Host");
        unless (    $LJ::USERPIC_ROOT =~ m!^http://\Q$host\E!i || $LJ::USERPIC_ROOT_CDN && $LJ::USERPIC_ROOT_CDN =~ m!^http://\Q$host\E!i
        ) {
            return redir("$LJ::USERPIC_ROOT/$picid/$userid");
        }
    }

    # we can safely do this without checking since we never re-use
    # picture IDs and don't let the contents get modified
    return LJ::Request::HTTP_NOT_MODIFIED if LJ::Request->header_in('If-Modified-Since');

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
        LJ::Request->filename($file);
    }

    LJ::Request->handler("perl-script");
    LJ::Request->set_handlers(PerlHandler => \&userpic_content);
    return LJ::Request::OK
}

sub crossdomain_content 
{
    my $crossdomain = '<?xml version="1.0"?>
<!DOCTYPE cross-domain-policy SYSTEM "http://www.adobe.com/xml/dtds/cross-domain-policy.dtd">
<cross-domain-policy>
    <site-control permitted-cross-domain-policies="master-only"/>
    <allow-access-from domain="*.livejournal.com"/>
    <allow-access-from domain="*.livejournal.ru"/>
    <allow-access-from domain="*.i-jet.ru"/>
</cross-domain-policy>';
    my $r = LJ::Request->request;
    $r->content_type('application/xml');
    $r->status(200);
    $r->send_http_header();
    $r->print($crossdomain);
    return LJ::Request::OK;
}

sub userpic_content
{
    my $file = LJ::Request->filename;

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

    my $MAX_AGE = 86400 * 365; # one year
    my $send_headers = sub {
        my $expires_str = LJ::TimeUtil->time_to_http(time + $MAX_AGE);
        LJ::Request->content_type($mime);
        LJ::Request->header_out("Content-length", $size+0);
        LJ::Request->header_out("Expires", $expires_str);
        LJ::Request->header_out("Cache-Control", "public, max-age=$MAX_AGE");
        LJ::Request->header_out("Last-Modified", LJ::TimeUtil->time_to_http($lastmod));
        LJ::Request->send_http_header();
    };

    # Load the user object and pic and make sure the picture is viewable
    my $u = LJ::load_userid($userid);
    return LJ::Request::NOT_FOUND unless $u && $u->{'statusvis'} !~ /[XS]/;

    my %upics;
    LJ::load_userpics(\%upics, [ $u, $picid ]);
    my $pic = $upics{$picid} or return LJ::Request::NOT_FOUND;
    return LJ::Request::NOT_FOUND if $pic->{'userid'} != $userid || $pic->{state} eq 'X';

    # Read the mimetype from the pichash if dversion 7
    $mime = { 'G' => 'image/gif',
              'J' => 'image/jpeg',
              'P' => 'image/png', }->{$pic->{fmt}};

    ### Handle reproxyable requests

    # For dversion 7+ and mogilefs userpics, follow this path
    if ($pic->{location} eq 'M' ) {  # 'M' for mogilefs
        my $key = $u->mogfs_userpic_key( $picid );

        if ( !$LJ::REPROXY_DISABLE{userpics} &&
             LJ::Request->header_in('X-Proxy-Capabilities') &&
             LJ::Request->header_in('X-Proxy-Capabilities') =~ m{\breproxy-file\b}i )
        {
            my $memkey = [$picid, "mogp.up.$picid"];

            my $zone = LJ::Request->header_in('X-MogileFS-Explicit-Zone') || undef;
            $memkey->[1] .= ".$zone" if $zone;

            my $cache_for = $LJ::MOGILE_PATH_CACHE_TIMEOUT || 3600;

            my $paths = LJ::MemCache::get($memkey);
            unless ($paths) {
                ## connect to storage
                my $mogclient = LJ::mogclient();
                return LJ::Request::NOT_FOUND unless $mogclient;

                my @paths = $mogclient->get_paths($key, { noverify => 1, zone => $zone });
                $paths = \@paths;
                LJ::MemCache::add($memkey, $paths, $cache_for) if @paths;
            }

            # reproxy url
            if ($paths->[0] =~ m/^http:/) {
                LJ::Request->header_out('X-REPROXY-CACHE-FOR', "$cache_for; Last-Modified Content-Type");
                LJ::Request->header_out('X-REPROXY-URL', join(' ', @$paths));
            }

            # reproxy file
            else {
                LJ::Request->header_out('X-REPROXY-FILE', $paths->[0]);
            }

            $send_headers->();
        }

        else {

            my $data = LJ::mogclient()->get_file_data( $key );
            return LJ::Request::NOT_FOUND unless $data;
            $size = length $$data;
            $send_headers->();
            LJ::Request->print( $$data ) unless LJ::Request->header_only;
        }

        return LJ::Request::OK
    }

    # dversion < 7 reproxy file path
    if ( !$LJ::REPROXY_DISABLE{userpics} &&
         exists $LJ::PERLBAL_ROOT{userpics} &&
         LJ::Request->header_in('X-Proxy-Capabilities') &&
         LJ::Request->header_in('X-Proxy-Capabilities') =~ m{\breproxy-file\b}i )
    {
        # Get the blobroot and load the pic hash
        my $root = $LJ::PERLBAL_ROOT{userpics};

        # Now ask the blob lib for the path to send to the reproxy
        eval { LJ::Blob->can("autouse"); };
        my $fmt = ($u->{'dversion'} > 6) ? $MimeTypeMapd6{ $pic->{fmt} } : $MimeTypeMap{ $pic->{contenttype} };
        my $path = LJ::Blob::get_rel_path( $root, $u, "userpic", $fmt, $picid );

        LJ::Request->header_out( 'X-REPROXY-FILE', $path );
        $send_headers->();

        return LJ::Request::OK
    }

    # try to get it from disk if in disk-cache mode
    if ($disk_cache) {
        if (-s LJ::Request->finfo) {
            $lastmod = (stat _)[9];
            $size = -s _;

            # read first 4 bites to determine image format: jpg/gif/png
            open my $fh, "<", $file;
            read($fh, my $magic, 4);
            $set_mime->($magic);
            $send_headers->();
            LJ::Request->print($magic);
            LJ::Request->sendfile($file, $fh); # for Apache v1 needs FileHandle, Apache v2 needs Filename
            close $fh;
            return LJ::Request::OK

        } else {
            $need_cache = 1;
        }
    }

    # else, get it from db.
    unless ($data) {
        $lastmod = $pic->{'picdate'};

        if ($LJ::USERPIC_BLOBSERVER) {
            eval { LJ::Blob->can("autouse"); };
            my $fmt = ($u->{'dversion'} > 6) ? $MimeTypeMapd6{ $pic->{fmt} } : $MimeTypeMap{ $pic->{contenttype} };
            $data = LJ::Blob::get($u, "userpic", $fmt, $picid);
        }

        unless ($data) {
            my $dbb = LJ::get_cluster_reader($u);
            unless ($dbb) {
                LJ::Request->pnotes ('error' => 'e500');
                LJ::Request->pnotes ('remote' => LJ::get_remote());
                return LJ::Request::SERVER_ERROR;
            }
            $data = $dbb->selectrow_array("SELECT imagedata FROM userpicblob2 WHERE ".
                                          "userid=$pic->{'userid'} AND picid=$picid");
        }
    }

    return LJ::Request::NOT_FOUND unless $data;

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
    LJ::Request->print($data) unless LJ::Request->header_only;
    return LJ::Request::OK
}

sub send_files {
    my $uri = shift;

    require LJ::FileStore;
    my $result = LJ::FileStore->get_path_info( path => $uri );

    # file not found
    return LJ::Request::NOT_FOUND unless $result;

    my $size = $result->{content_length};

    if ( !$LJ::REPROXY_DISABLE{files} &&
        LJ::Request->header_in('X-Proxy-Capabilities') &&
        LJ::Request->header_in('X-Proxy-Capabilities') =~ m{\breproxy-file\b}i )
    {
        my $paths = $result->{paths};

        my $cache_for = $LJ::MOGILE_PATH_CACHE_TIMEOUT || 3600;
        # reproxy url
        if ($paths->[0] =~ m/^http:/) {
            LJ::Request->header_out('X-REPROXY-CACHE-FOR', "$cache_for; Last-Modified Content-Type");
            LJ::Request->header_out('X-REPROXY-URL', join(' ', @$paths));
        }

        # reproxy file
        else {
            LJ::Request->header_out('X-REPROXY-FILE', $paths->[0]);
        }

        my $mime_type = $result->{mime_type};
        $mime_type ||= 'image/gif' if $uri =~ m|^/userhead/\d+|; ## default for userheads

        LJ::Request->content_type ($mime_type);
        LJ::Request->header_out("Content-length", $size);
        LJ::Request->header_out("Last-Modified", LJ::TimeUtil->time_to_http ($result->{change_time}));
        ## Add Expires and Cache-Control headers
        if ($uri =~ m|^/userhead/\d+|o){
            ## Userheads are never changed
            my $max_age = 86400 * 365; # one year
            my $expires_str = HTTP::Date::time2str(time + $max_age);
            LJ::Request->header_out("Expires" => $expires_str);
            LJ::Request->header_out("Cache-Control", "no-transform, public, max-age=$max_age");
        } elsif ($uri =~ m|^/vgift/\d+|){
            ## vgifts may be changed.
            my $max_age = 86400 * 2 + 600; # 2 days and 10 minutes
            my $expires_str = HTTP::Date::time2str(time + $max_age);
            LJ::Request->header_out("Expires" => $expires_str);
            LJ::Request->header_out("Cache-Control", "no-transform, public, max-age=$max_age");
        } else {
            ## ... no Expires by defaul
            ## Set Cache-Control only
            LJ::Request->header_out("Cache-Control", "no-transform, public");
        }

        LJ::Request->send_http_header();
        return LJ::Request::OK;
    }
    return LJ::Request::NOT_FOUND;
}

sub files_handler {
    return send_files (LJ::Request->uri);
}

sub files_trans
{
    LJ::Request->uri =~ m!^/(\w{1,15})/(\w+)(/\S+)!;
    my ($user, $domain, $rest) = ($1, $2, $3);

    if ($domain eq 'phonepost') {
        if (my $handler = LJ::run_hook("files_handler:$domain", $user, $rest)) {
            LJ::Request->notes("codepath" => "files.$domain");
            LJ::Request->handler("perl-script");
            LJ::Request->set_handlers(PerlHandler => $handler);
            return LJ::Request::OK
        }
        return LJ::Request::NOT_FOUND;
    } else {
        LJ::Request->handler("perl-script");
        LJ::Request->set_handlers(PerlHandler => \&files_handler);
        return LJ::Request::OK
    }
    return LJ::Request::NOT_FOUND;
}

sub journal_content
{
    my $uri = LJ::Request->uri;
    my %GET = LJ::Request->args;

    if ($RQ{'mode'} eq "robots_txt")
    {
        my $u = LJ::load_user($RQ{'user'});

        LJ::Request->pnotes (error => 'baduser') unless $u;
        return LJ::Request::NOT_FOUND unless $u;

        $u->preload_props("opt_blockrobots", "adult_content", "admin_content_flag");
        LJ::Request->content_type("text/plain");
        LJ::Request->send_http_header();
        my @extra = LJ::run_hook("robots_txt_extra", $u), ();
        LJ::Request->print($_) foreach @extra;
        LJ::Request->print("User-Agent: *\n");
        if ($u->should_block_robots) {
            LJ::Request->print("Disallow: /\n");
        }
        return LJ::Request::OK
    }

    # handle HTTP digest authentication
    if ($GET{'auth'} eq 'digest' ||
        LJ::Request->header_in("Authorization") =~ /^Digest/) {
        my $res = LJ::auth_digest();
        unless ($res) {
            LJ::Request->content_type("text/html");
            LJ::Request->send_http_header();
            LJ::Request->print("<b>Digest authentication failed.</b>");
            return LJ::Request::OK
        }
    }

    my $criterr = 0;

    my $remote = LJ::get_remote({
        criterr      => \$criterr,
    });

    return remote_domsess_bounce() if LJ::remote_bounce_url();

    # check for faked cookies here, since this is pretty central.
    if ($criterr) {
        LJ::Request->pnotes (error => 'e500');
        LJ::Request->status_line("500 Invalid Cookies");
        LJ::Request->content_type("text/html");
        # reset all cookies
        foreach my $dom (@LJ::COOKIE_DOMAIN_RESET) {
            my $cookiestr = 'ljsession=';
            $cookiestr .= '; expires=' . LJ::TimeUtil->time_to_cookie(1);
            $cookiestr .= $dom ? "; domain=$dom" : '';
            $cookiestr .= '; path=/; HttpOnly';
            LJ::Request->request->err_headers_out->add('Set-Cookie' => $cookiestr);
        }

        LJ::Request->send_http_header();
        LJ::Request->print("Invalid cookies.  Try <a href='$LJ::SITEROOT/logout.bml'>logging out</a> and then logging back in.\n");
        LJ::Request->print("<!-- xxxxxxxxxxxxxxxxxxxxxxxx -->\n") for (0..100);
        return LJ::Request::OK
    }


    # LJ::make_journal() will set this flag if the user's
    # style system is unable to handle the requested
    # view (S1 can't do EntryPage or MonthPage), in which
    # case it's our job to invoke the legacy BML page.
    my $handle_with_bml = 0;

    my %headers = ();
    my $opts = {
        'r'         => LJ::Request->r,
        'headers'   => \%headers,
        'args'      => $RQ{'args'},
        'getargs'   => \%GET,
        'vhost'     => $RQ{'vhost'},
        'pathextra' => $RQ{'pathextra'},
        'header'    => {
            'If-Modified-Since' => LJ::Request->header_in("If-Modified-Since"),
        },
        'handle_with_bml_ref' => \$handle_with_bml,
        'ljentry' => $RQ{'ljentry'},
    };

    LJ::Request->notes("view" => $RQ{'mode'});
    my $user = $RQ{'user'};

    my $html = LJ::make_journal($user, $RQ{'mode'}, $remote, $opts);
    # Allow to add extra http-header or even modify html
    LJ::run_hooks("after_journal_content_created", $opts, \$html);

    return redir($opts->{'redir'}) if $opts->{'redir'};
    
    if (defined $opts->{'handler_return'}) {
        if ($opts->{'handler_return'} =~ /^(\d+)/) {
            return $1;
        } else {
            return LJ::Request::DECLINED;
        }
    }

    # if LJ::make_journal() indicated it can't handle the request:
    if ($handle_with_bml) {
        my $args = LJ::Request->args;
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
            return redir("$base$uri$args_wq");
        }

        if ($RQ{'mode'} eq "entry" || $RQ{'mode'} eq "reply") {
            my $filename = $RQ{'mode'} eq "entry" 
                ? ( $GET{talkread2}
                    ? "$LJ::HOME/htdocs/talkread2.bml"
                    : "$LJ::HOME/htdocs/talkread.bml"
                )
                : "$LJ::HOME/htdocs/talkpost.bml";
            LJ::Request->notes("_journal" => $RQ{'user'});
            LJ::Request->notes("bml_filename" => $filename);
            return Apache::BML::handler();
        }

        if ($RQ{'mode'} eq "month") {
            my $filename = "$LJ::HOME/htdocs/view/index.bml";
            LJ::Request->notes("_journal" => $RQ{'user'});
            LJ::Request->notes("bml_filename" => $filename);
            return Apache::BML::handler();
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
        LJ::Request->pnotes (error => 'e404');
        return LJ::Request::NOT_FOUND;
    }
    elsif ($opts->{'baduser'})
    {
        $status = "404 Unknown User";
        $html = "<h1>Unknown User</h1><p>There is no user <b>$user</b> at <a href='$LJ::SITEROOT'>$LJ::SITENAME.</a></p>";
        $generate_iejunk = 1;
        LJ::Request->pnotes ('error'  => 'baduser' );
        return LJ::Request::NOT_FOUND;
    }
    elsif ($opts->{'badfriendgroup'})
    {
        # give a real 404 to the journal owner
        if ($remote && $remote->{'user'} eq $user) {
            LJ::Request->pnotes ('error' => 'e404');
            $status = "404 Friend group does not exist";
            $html = "<h1>Not Found</h1>" .
                    "<p>The friend group you are trying to access does not exist.</p>";
            LJ::Request->pnotes ('remote' => LJ::get_remote());
            return LJ::Request::NOT_FOUND;

        # otherwise be vague with a 403
        } else {
            # send back a 403 and don't reveal if the group existed or not
            LJ::Request->pnotes ('error' => 'e404');
            $status = "403 Friend group does not exist, or is not public";
            $html = "<h1>Denied</h1>" .
                    "<p>Sorry, the friend group you are trying to access does not exist " .
                    "or is not public.</p>\n";

            $html .= "<p>You're not logged in.  If you're the owner of this journal, " .
                     "<a href='$LJ::SITEROOT/login.bml'>log in</a> and try again.</p>\n"
                         unless $remote;
            LJ::Request->pnotes ('remote' => LJ::get_remote());
            return LJ::Request::FORBIDDEN;
        }

        $generate_iejunk = 1;

    } elsif ($opts->{'suspendeduser'}) {
        LJ::Request->pnotes ('error' => 'suspended');
        $status = "403 User suspended";
        $html = "<h1>Suspended User</h1>" .
                "<p>The content at this URL is from a suspended user.</p>";
        LJ::Request->pnotes ('remote' => LJ::get_remote());
        return LJ::Request::FORBIDDEN;

        $generate_iejunk = 1;

    } elsif ($opts->{'suspendedentry'}) {
        LJ::Request->pnotes ('error' => 'suspended_post');
        $status = "403 Entry suspended";
        $html = "<h1>Suspended Entry</h1>" .
                "<p>The entry at this URL is suspended.  You cannot reply to it.</p>";
        LJ::Request->pnotes ('remote' => LJ::get_remote());
        return LJ::Request::FORBIDDEN;

        $generate_iejunk = 1;

    } elsif ($opts->{'readonlyremote'} || $opts->{'readonlyjournal'}) {
        LJ::Request->pnotes ('error' => 'readonly');
        $status = "403 Read-only user";
        $html = "<h1>Read-Only User</h1>";
        $html .= $opts->{'readonlyremote'} ? "<p>You are read-only.  You cannot post comments.</p>" : "<p>This journal is read-only.  You cannot comment in it.</p>";
        LJ::Request->pnotes ('remote' => LJ::get_remote());
        return LJ::Request::FORBIDDEN;

        $generate_iejunk = 1;
    }

    unless ($html) {
        LJ::Request->pnotes ('error' => 'e500');
        $status = "500 Bad Template";
        $html = "<h1>Error</h1><p>User <b>$user</b> has messed up their journal template definition.</p>";
        $generate_iejunk = 1;
        LJ::Request->pnotes ('remote' => LJ::get_remote());
        return LJ::Request::SERVER_ERROR;
    }

    LJ::Request->status_line($status);
    foreach my $hname (keys %headers) {
        if (ref($headers{$hname}) && ref($headers{$hname}) eq "ARRAY") {
            foreach (@{$headers{$hname}}) {
                LJ::Request->header_out($hname, $_);
            }
        } else {
            LJ::Request->header_out($hname, $headers{$hname});
        }
    }

    LJ::Request->content_type($opts->{'contenttype'});
    LJ::Request->header_out("Cache-Control", "private, proxy-revalidate");

    $html .= ("<!-- xxxxxxxxxxxxxxxxxxxxxxxxxxxx -->\n" x 100) if $generate_iejunk;

    # Parse the page content for any temporary matches
    # defined in local config
    if (my $cb = $LJ::TEMP_PARSE_MAKE_JOURNAL) {
        $cb->(\$html);
    }

    # add crap before </body>
    my $before_body_close = "";
    LJ::run_hooks("insert_html_before_body_close", \$before_body_close);
    LJ::run_hooks("insert_html_before_journalctx_body_close", \$before_body_close);
    {
        my $journalu = LJ::load_user($user);
        my $graphicpreviews_obj = LJ::graphicpreviews_obj();
        $before_body_close .= $graphicpreviews_obj->render($journalu);
    }

    # Insert pagestats HTML and Javascript
    $before_body_close .= LJ::pagestats_obj()->render('journal');

    $html =~ s!</body>!$before_body_close</body>!i if $before_body_close;

    ## GZIP encoding
    ## 1. should we comress response?
    my $do_gzip = $LJ::DO_GZIP && $LJ::OPTMOD_ZLIB;
    my $length = length($html);
    if (LJ::Request->header_in("X-Accept-Encoding") =~ m/gzip/){
    ## X-Accept-Encoding strictly demands gzip encoding
    ## no other measurements
        1;
    } elsif ($do_gzip) {
    ## other weighing
        my $ctbase = $opts->{'contenttype'};
        $ctbase =~ s/;.*//;
        $do_gzip = 0 unless $LJ::GZIP_OKAY{$ctbase};
        $do_gzip = 0 if LJ::Request->header_in("Accept-Encoding") !~ /gzip/;

        $do_gzip = 0 if $length < 500;
    }

    ## 2. perform compression
    if ($do_gzip) {
        my $pre_len = $length;
        LJ::Request->notes("bytes_pregzip" => $pre_len);
        $html = Compress::Zlib::memGzip($html);
        $length = length($html);
        LJ::Request->header_out('Content-Encoding', 'gzip');
    }
    
    # other headers
    my $html_md5 = md5_base64($html);
    LJ::Request->header_out(ETag => $html_md5);
    LJ::Request->header_out('Content-MD5' => $html_md5);

    # Let caches know that Accept-Encoding will change content
    LJ::Request->header_out('Vary', 'Accept-Encoding, ETag');

    # add server mark
    #my ($aws_id) = $LJ::HARDWARE_SERVER_NAME =~ /\-(.+)$/;
    #LJ::Request->header_out("X-AWS-Id" => $aws_id || 'unknown');

    LJ::Request->header_out("Content-length", $length);
    LJ::Request->send_http_header();
    LJ::Request->print($html) unless LJ::Request->header_only;

    return LJ::Request::OK
}

sub customview_content
{
    my %FORM = LJ::Request->args;

    my $charset = "utf-8";

    if ($LJ::UNICODE && $FORM{'charset'}) {
        $charset = $FORM{'charset'};
        if ($charset ne "utf-8" && ! Unicode::MapUTF8::utf8_supported_charset($charset)) {
            LJ::Request->content_type("text/html");
            LJ::Request->send_http_header();
            LJ::Request->print("<b>Error:</b> requested charset not supported.");
            return LJ::Request::OK
        }
    }

    my $ctype = "text/html";
    if ($FORM{'type'} eq "xml") {
        $ctype = "text/xml";
    }

    if ($LJ::UNICODE) {
        $ctype .= "; charset=$charset";
    }

    LJ::Request->content_type($ctype);

    my $cur_journal = LJ::Session->domain_journal;
    my $user = LJ::canonical_username($FORM{'username'} || $FORM{'user'} || $cur_journal);
    my $styleid = $FORM{'styleid'} + 0;
    my $nooverride = $FORM{'nooverride'} ? 1 : 0;

    if ($LJ::ONLY_USER_VHOSTS && $cur_journal ne $user) {
        my $u = LJ::load_user($user)
            or return LJ::Request::NOT_FOUND;
        my $safeurl = $u->journal_base . "/data/customview?";
        my %get_args = %FORM;
        delete $get_args{'user'};
        delete $get_args{'username'};
        $safeurl .= join("&", map { LJ::eurl($_) . "=" . LJ::eurl($get_args{$_}) } keys %get_args);
        return redir($safeurl);
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
                   "args" => scalar LJ::Request->args,
                   "getargs" => \%FORM,
                   "r" => LJ::Request->r,
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

    LJ::Request->header_out("Cache-Control", "must-revalidate");
    LJ::Request->header_out("Content-Length", length($data));
    LJ::Request->send_http_header();
    LJ::Request->print($data) unless LJ::Request->header_only;
    return LJ::Request::OK
}

sub correct_url_redirect_code {
    if ($LJ::CORRECT_URL_PERM_REDIRECT) {
        return LJ::Request::HTTP_MOVED_PERMANENTLY();
    }
    return LJ::Request::REDIRECT();
}

sub interface_content
{
    my $args = LJ::Request->args;

    # simplified code from 'package BML::Cookie' in Apache/BML.pm
    my $cookie_str = LJ::Request->header_in("Cookie");
    if ($cookie_str =~ /\blangpref=(\w{2,10})\/\d+\b/) { # simplified code from BML::decide_language
        my $lang = $1;
        # Attention! LJ::Lang::ml uses BML::ml in web context, so we must do full BML language initialization
        BML::set_language($lang, \&LJ::Lang::get_text);
    }

    if ($RQ{'interface'} eq "xmlrpc") {
        return LJ::Request::NOT_FOUND unless LJ::ModuleCheck->have('XMLRPC::Transport::HTTP');
        my $server = XMLRPC::Transport::HTTP::Apache
            -> on_action(sub { die "Access denied\n" if $_[2] =~ /:|\'/ })
            -> dispatch_to('LJ::XMLRPC')
            -> handle(LJ::Request->r);
        return LJ::Request::OK
    }

    if ($RQ{'interface'} eq "blogger") {
        Apache::LiveJournal::Interface::Blogger->load;
        return LJ::Request::NOT_FOUND unless LJ::ModuleCheck->have('XMLRPC::Transport::HTTP');
        my $pkg = "Apache::LiveJournal::Interface::Blogger";
        my $server = XMLRPC::Transport::HTTP::Apache
            -> on_action(sub { die "Access denied\n" if $_[2] =~ /:|\'/ })
            -> dispatch_with({ 'blogger' => $pkg })
            -> dispatch_to($pkg)
            -> handle(LJ::Request->r);
        return LJ::Request::OK
    }

    if ($RQ{'interface'} =~ /atom(?:api)?/) {
        Apache::LiveJournal::Interface::AtomAPI->load;
        # the interface package will set up all headers and
        # print everything
        Apache::LiveJournal::Interface::AtomAPI::handle(LJ::Request->r);
        return LJ::Request::OK
    }

    if ($RQ{'interface'} =~ /elsewhere_info/) {
        # the interface package will set up all headers and
        # print everything
        Apache::LiveJournal::Interface::ElsewhereInfo->handle(LJ::Request->r);
        return LJ::Request::OK
    }

    if ($RQ{'interface'} ne "flat") {
        LJ::Request->content_type("text/plain");
        LJ::Request->send_http_header;
        LJ::Request->print("Unknown interface.");
        return LJ::Request::OK
    }

    LJ::Request->content_type("text/plain");

    my %out = ();
    my %FORM = LJ::Request->post_params;
    # the protocol needs the remote IP in just one place, where tracking is done.
    $ENV{'_REMOTE_IP'} = LJ::Request->remote_ip();
    LJ::do_request(\%FORM, \%out);

    if ($FORM{'responseenc'} eq "urlenc") {
        LJ::Request->send_http_header;
        foreach (sort keys %out) {
            LJ::Request->print(LJ::eurl($_) . "=" . LJ::eurl($out{$_}) . "&");
        }
        return LJ::Request::OK
    }

    my $length = 0;
    foreach (sort keys %out) {
        $length += length($_)+1;
        $length += length($out{$_})+1;
    }

    LJ::Request->header_out("Content-length", $length);
    LJ::Request->send_http_header;
    foreach (sort keys %out) {
        my $key = $_;
        my $val = $out{$_};
        $key =~ y/\r\n//d;
        $val =~ y/\r\n//d;
        LJ::Request->print($key, "\n", $val, "\n");
    }

    return LJ::Request::OK
}

sub db_logger
{
    LJ::Request->pnotes('did_lj_logging' => 1);

    # these are common enough, it's worth doing it here, early, before
    # constructing the accesslogrecord.
    if ($LJ::DONT_LOG_IMAGES) {
        my $uri = LJ::Request->uri;
        my $ctype = LJ::Request->content_type;
        $ctype =~ s/;.*//;  # strip charset
        return if $ctype =~ m!^image/!;
        return if $uri =~ m!^/(img|userpic)/!;
    }

    my $rec = LJ::AccessLogRecord->new(LJ::Request->r);
    my @sinks = (
                 LJ::AccessLogSink::Database->new,
                 LJ::AccessLogSink::DInsertd->new,
                 LJ::AccessLogSink::DBIProfile->new,
                 );

    if (@LJ::EXTRA_ACCESS_LOG_SINKS) {
        # will convert them to objects from class/ctor-arg arrayrefs
        push @sinks, LJ::AccessLogSink->extra_log_sinks;
    }

    foreach my $sink (@sinks) {
        $sink->log($rec);
    }
}

sub anti_squatter
{
    LJ::Request->set_handlers(PerlHandler => sub {
        LJ::Request->content_type("text/html");
        LJ::Request->send_http_header();
        LJ::Request->print("<html><head><title>Dev Server Warning</title>",
                  "<style> body { border: 20px solid red; padding: 30px; margin: 0; font-family: sans-serif; } ",
                  "h1 { color: #500000; }",
                  "</style></head>",
                  "<body><h1>Warning</h1><p>This server is for development and testing only.  ",
                  "Accounts are subject to frequent deletion.  Don't use this machine for anything important.</p>",
                  "<form method='post' action='/misc/ack-devserver.bml' style='margin-top: 1em'>",
                  LJ::html_hidden("dest", "$LJ::SQUAT_URL"),
                  LJ::html_submit(undef, "Acknowledged"),
                  "</form></body></html>");
        return LJ::Request::OK
    });

}

package LJ::Protocol;
use Encode();

sub xmlrpc_method {
    my $method = shift;
    shift;   # get rid of package name that dispatcher includes.
    my $req = shift;

    # For specified methods
    if ($LJ::XMLRPC_VALIDATION_METHOD{$method}) {
        # Deny access for accounts that have not validated their email
        my $u = LJ::load_user($req->{'username'});
        unless ($u){
            die SOAP::Fault
                ->faultstring("Unknown username.");
        }
        unless ($u->is_validated) {
            die SOAP::Fault
                ->faultstring("Account not validated.");
       }
    }

    if (@_) {
        # don't allow extra arguments
        die SOAP::Fault
            ->faultstring(LJ::Protocol::error_message(202))
            ->faultcode(202);
    }
    my $error = 0;

    ## All our functions take signle hashref as an argument.
    ## Moreover, we use $req->{'props'} for our tracking purposes
    $req = {} unless ref $req eq "HASH"; 

    # get rid of the UTF8 flag in scalars
    while (my ($k, $v) = each %$req) {
        $req->{$k} = Encode::encode_utf8($v) if Encode::is_utf8($v);
    }
    $req->{'props'}->{'interface'} = "xml-rpc";
    
    my $res = LJ::Protocol::do_request($method, $req, \$error);
    if ($error) {
        die SOAP::Fault
            ->faultstring(LJ::Protocol::error_message($error))
            ->faultcode(substr($error, 0, 3));
    }

    # Perl is untyped language and XML-RPC is typed.
    # When library XMLRPC::Lite tries to guess type, it errors sometimes
    # (e.g. string username goes as int, if username contains digits only).
    # As workaround, we can select some elements by it's names
    # and label them by correct types.

    # Key - field name, value - type.
    my %lj_types_map = (
        journalname => 'string',
        name => 'string',
    );

    my $recursive_mark_elements;
    $recursive_mark_elements = sub {
        my $structure = shift;
        my $ref = ref($structure);

        if ($ref eq 'HASH') {
            foreach my $hash_key (keys %$structure) {
                if (exists($lj_types_map{$hash_key})) {
                    $structure->{$hash_key} = SOAP::Data
                            -> type($lj_types_map{$hash_key})
                            -> value($structure->{$hash_key});
                } else {
                    $recursive_mark_elements->($structure->{$hash_key});
                }
            }
        } elsif ($ref eq 'ARRAY') {
            foreach my $idx (@$structure) {
                $recursive_mark_elements->($idx);
            }
        }
    };

    $recursive_mark_elements->($res);

    return $res;
}

package LJ::XMLRPC;

use vars qw($AUTOLOAD);

# pretend we can do everything; AUTOLOAD will handle that
sub can { 1 }

sub AUTOLOAD {
    my $method = $AUTOLOAD;
    $method =~ s/^.*:://;
    ## Without eval/warn/die there will be no error message in our logs,
    ## since XMLRPC::Transport::HTTP::Apache will send the error to client.
    my $res = eval { LJ::Protocol::xmlrpc_method($method, @_) };
    if ($@) { warn "LJ::XMLRPC::$method died: $@"; die $@; }
    return $res;
}

1;
