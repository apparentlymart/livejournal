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
    if ($msg =~ /Can\'t call method.*on an undefined value/) {
        return "Sorry, database temporarily unavailable.";
    }
    chomp $msg;
    $msg .= " \@ $LJ::SERVER_NAME" if $LJ::SERVER_NAME;
    warn "$msg\n";
    return "<b>[Error: $msg]</b>";
}) unless $LJ::IS_DEV_SERVER;

if ($LJ::UNICODE) {
    BML::set_config("DefaultContentType", "text/html; charset=utf-8");
}

# register BML multi-language hook
BML::register_hook("ml_getter", \&LJ::Lang::get_text);

# include file handling
BML::register_hook('include_getter', sub {
    my ($file, $source) = @_;
    return 0 unless $LJ::FILEEDIT_VIA_DB || $LJ::FILEEDIT_VIA_DB{$file};

    # we handle, so first if memcache...
    my $val = LJ::MemCache::get("includefile:$file");

    # straight database hit
    unless ($val) {
        my $dbh = LJ::get_db_writer();
        $val = $dbh->selectrow_array("SELECT inctext FROM includetext ".
                                     "WHERE incname=?", undef, $file);
        LJ::MemCache::set("includefile:$file", $val);
    }

    # return the value and that we handled this
    $$source = $val;    
    return 1;
});

1;
