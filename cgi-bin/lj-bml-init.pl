#!/usr/bin/perl
#

require "$ENV{'LJHOME'}/cgi-bin/ljconfig.pl";

foreach (@LJ::LANGS, @LJ::LANGS_IN_PROGRESS) {
    BML::register_isocode(substr($_, 0, 2), $_);
    BML::register_language($_);
}

# set default path/domain for cookies
BML::set_config("CookieDomain" => $LJ::COOKIE_DOMAIN);
BML::set_config("CookiePath"   => $LJ::COOKIE_PATH);

BML::register_hook("startup", sub {
    my $r = Apache->request;
    my $uri = "bml" . $r->uri;
    unless ($uri =~ s/\.bml$//) {
        $uri .= ".index";
    }
    $uri =~ s!/!.!g;
    $r->notes("codepath" => $uri);
});

BML::register_hook("codeerror", sub {
    my $msg = shift;

    my $err = LJ::errobj($msg)       or return;
    $err->log;

    $msg = $err->as_html;

    # we currently assume that "can't call method..." means
    # a code block tried to do a $dbh->method call, which is
    # often but not always the case.
    #
    # allow overriding of this behavior by appending the
    # show_raw_error=1 get arg to the URI
    if ($msg =~ /Can\'t call method.*on an undefined value/ && ! $LJ::IS_DEV_SERVER) {
        my $r = Apache->request;
        unless ($r && $r->args("show_raw_error")) {
            return $LJ::MSG_DB_UNAVAILABLE ||
                "Sorry, database temporarily unavailable.";
        }
    }

    chomp $msg;
    $msg .= " \@ $LJ::SERVER_NAME" if $LJ::SERVER_NAME;
    warn "$msg\n";
    return "<b>[Error: $msg]</b>";
});

if ($LJ::UNICODE) {
    BML::set_config("DefaultContentType", "text/html; charset=utf-8");
}

# register BML multi-language hook
BML::register_hook("ml_getter", \&LJ::Lang::get_text);

# include file handling
BML::register_hook('include_getter', sub {
    # simply call LJ::load_include, as it does all the work of hitting up
    # memcache/db for us and falling back to disk if necessary...
    my ($file, $source) = @_;
    $$source = LJ::load_include($file);
    return 1;
});

# Allow scheme override to be defined as a code ref or an explicit string value
BML::register_hook('default_scheme_override', sub {
    return undef unless $LJ::SCHEME_OVERRIDE;
    return $LJ::SCHEME_OVERRIDE->() if ref $LJ::SCHEME_OVERRIDE;
    return $LJ::SCHEME_OVERRIDE;
});

1;
