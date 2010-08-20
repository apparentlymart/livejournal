package Apache::WURFL;
use strict;

use LJ::WURFL;

my $wurfl;

sub is_mobile {
    my $class = shift;
    my $user_agent = shift;

    if ($LJ::WURFL{'ua_keys_mobile'}) {
        grep { $user_agent =~ /\Q$_\E/i } @{$LJ::WURFL{'ua_keys_mobile'}}
            ? return 1
            : return 0;
    }

    unless ($wurfl) {
        $wurfl = LJ::WURFL->new();
        unless ($wurfl->load($LJ::WURFL{'wireless_storage'})) {
            warn "Error: empty useragents storage, run bin/upgrading/wurfl/bin/wurfl_update.pl";
            return 0;
        }
    }

    return $wurfl->is_mobile($user_agent);
}

my $mobile_domain = 'http://m.livejournal.com';

sub _process_url_args {
    my ($self, $username, $args, $post_id) = @_;

    return "$mobile_domain/read/user/$username" unless $post_id;

    if ($args =~ /mode=reply/) { # replay to entry
        return "$mobile_domain/read/user/$username/$post_id/comments#comments";
    }
    if ($args =~ /view=comments/) { # view comments to entry
        return "$mobile_domain/read/user/$username/$post_id/comments#comments";
    }
    if ($args =~ /thread=(\d+)/) { # comment thread
        my $comment_id = $1;
        return "$mobile_domain/read/user/$username/$post_id/comments/$comment_id#comments";
    }
    if ($args =~ /repyto=(\d+)/) { # reply to comment
        my $comment_id = $1;
        return "$mobile_domain/read/user/$username/$post_id/comments/$comment_id#comments";
    }

    return "$mobile_domain/read/user/$username/$post_id";
}

sub _process_url_args_for_friends {
    my ($self, $username, $args) = @_;

    # Mobile user can see only his own friend page and only when logged in.

    my $remote = LJ::get_remote();
    return '' unless $remote;
    return '' unless LJ::u_equals($remote, LJ::load_user($username));

    if ($args =~ /show=(P|C|Y)/i) { 
        return "$mobile_domain/read/friends/?show=".lc($1);
    }

    return "$mobile_domain/read/friends/";   # just /friends
}

sub map2mobile {
    my $self = shift;
    my %opts = @_;

    my $uri  = $opts{'uri'};
    my $host = $opts{'host'};
    my $args = $opts{'args'};

    if ($host =~ /^([\w\-]+)\.\Q$LJ::DOMAIN\Q/) {
        my $username = $1;
        if ($username eq 'www') { # main lj pages

            if ($uri eq '/')                {   return "$mobile_domain/";       }
            if ($uri =~ /^\/login\.bml/)    {   return "$mobile_domain/login";  }
            if ($uri =~ /^\/update\.bml/)   {   return "$mobile_domain/post";   }

        } else {

            my $func = $LJ::SUBDOMAIN_FUNCTION{$username};
            if ($func eq 'journal') { # it's (syndicated|community|user).livejournal.com/username

                if ($uri =~ /^\/(\w+)\/friends/) {
                    return $self->_process_url_args_for_friends($1, $args);
                }

                if ($uri =~ /^\/(\w+)\/tag\/(.+)/) {
                    # $username = $1; $tagname  = $2;
                    return "$mobile_domain/read/user/$1/tag/$2";
                }

                $uri =~ /^\/(\w+)\/(\d+\.html)?$/;
                # $username = $1; $post_id = int($2); $post_id = 0 if there is not '/NNNNN.html'
                return $self->_process_url_args($1, $args, int($2));

            } elsif (!$func) { # it's username.livejournal.com and we has var $username.

                if ($uri =~ m#^/friends#) {
                    return $self->_process_url_args_for_friends($username, $args);
                }

                if ($uri =~ /^\/tag\/(.+)/) {
                    # $tagname  = $1;
                    return "$mobile_domain/read/user/$username/tag/$1";
                }

                $uri =~ /^\/(\d+\.html)?$/;
                # $post_id = int($1);
                return $self->_process_url_args($username, $args, int($1));
            }
        }
    }

    return '';
}

sub set_our_cookie {
    my $self = shift;
    my $opt  = shift;

    LJ::Request->set_cookie(
        'fullversion'   => $opt,
        'path'          => '/',
        'domain'        => ".$LJ::DOMAIN",
        'http_only'     => 1,
    );
}

sub redirect4mobile {
    my $self = shift;
    my %opts = @_;

    return '' if $LJ::DISABLED{'wurfl_redirect'};

    my $uri         = $opts{'uri'};
    my $host        = $opts{'host'};

    my $args        = $opts{'args'}         = (LJ::Request->args() || '');
    my $cookie      = $opts{'cookie'}       = LJ::Request->cookie("fullversion");
    my $user_agent  = $opts{'user_agent'}   = LJ::Request->header_in('User-Agent');

    # If we get 'fullversion=' arg, set cookie and redirect without this arg.
    if ($args =~ /fullversion=(\w+)/) {
        $self->set_our_cookie($1); LJ::Request->send_cookies();
        $args =~ s/fullversion=(\w+)//;
        $args =~ s/&$//;
        return $uri . ($args ? "?$args" : '');
    }

    # If we get cookie 'fullversion=yes', don't redirect.
    if ($cookie eq 'yes') {
        return '';
    }

    # If we get cookie 'fullversion=no' or device is mobile one,
    # set cookie to future redirections and try to redirect to mobile version.
    if ($cookie eq 'no' || $self->is_mobile($user_agent)) {
        my $new_url = $self->map2mobile(%opts);
        if ($cookie ne 'no') {
            $self->set_our_cookie('no');

            # send cookies right now if we request to redirect.
            LJ::Request->send_cookies() if $new_url;
        }
        return $new_url;
    } else {
        $self->set_our_cookie('yes') if $cookie ne 'yes';
    }

    return '';
}

1;
