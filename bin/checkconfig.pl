#!/usr/bin/perl
#

my @errors;
my $err = sub {
    return unless @_;
    die "Problem:\n" . join('', map { "  * $_\n" } @_);
};

my %dochecks;   # these are the ones we'll actually do
my @checks = (  # put these in the order they should be checked in
    "modules", 
    "env", 
    "database" 
);
foreach my $check (@checks) { $dochecks{$check} = 1; }

my $only = 0;

arg: foreach my $arg (@ARGV) {
    ($w, $c) = ($arg =~ /^-(no|only)(.*)/) or die "unknown option $arg";
    die "only one '-onlyfoo' option may be specified" if $w eq "only" and $only++;
    foreach my $check (@checks) {
        if ($check eq $c) {
            if ($w eq "only") { %dochecks = ( $check => 1 ); }
            else { $dochecks{$check} = 0 }
            next arg;
        }
    }
    die "unknown check '$c' (known checks: " . join(", ", @checks) . ")\n";
}

my %modules = (
               "DBI" => { 'deb' => 'libdbi-perl',  },
               "DBD::mysql" => { 'deb' => 'libdbd-mysql-perl', },
               "Digest::MD5" => { 'deb' => 'libdigest-md5-perl', },
               "Digest::SHA1" => { 'deb' => 'libdigest-sha1-perl', },
               "Image::Size" => { 'deb' => 'libimage-size-perl', },
               "MIME::Lite" => { 'deb' => 'libmime-lite-perl', },
               "MIME::Words" => { 'deb' => 'libmime-perl', },
               "Compress::Zlib" => { 'deb' => 'libcompress-zlib-perl', },
               "Net::SMTP" => {
                   'deb' => 'libnet-perl',
                   'opt' => "Alternative to piping into sendmail to send mail.",
               },
               "Net::DNS" => {
                   'deb' => 'libnet-dns-perl',
               },
               "MIME::Base64" => { 'deb' => 'libmime-base64-perl' },
               "URI::URL" => { 'deb' => 'liburi-perl' },
               "HTML::Tagset" => { 'deb' => 'libhtml-tagset-perl' },
               "HTML::Parser" => { 'deb' => 'libhtml-parser-perl', },
               "LWP::Simple" => { 'deb' => 'libwww-perl', },
               "LWP::UserAgent" => { 'deb' => 'libwww-perl', },
               "GD" => { 'deb' => 'libgd-perl' },
               "GD::Graph" => {
                   'deb' => 'libgd-graph-perl',
                   'opt' => 'Required to make graphs for the statistics page.',
               },
               "Mail::Address" => { 'deb' => 'libmailtools-perl', },
               "Proc::ProcessTable" => {
                   'deb' => 'libproc-process-perl',
                   'opt' => "Better reliability for starting daemons necessary for high-traffic installations.",
               },
               "RPC::XML" => {
                   'deb' => 'librpc-xml-perl',
                   'opt' => 'Required for outgoing XMLRPC support',
               },
               "SOAP::Lite" => {
                   'deb' => 'libsoap-lite-perl',
                   'opt' => 'Required for XML-RPC support.',
               },
               "Unicode::MapUTF8" => { 'deb' => 'libunicode-maputf8-perl', },
               "Storable" => {
                   'deb' => 'libstorable-perl',
               },
               "XML::RSS" => {
                   'deb' => 'libxml-rss-perl',
                   'opt' => 'Required for retrieving RSS off of other sites (syndication).',
               },
               "XML::Simple" => {
                   'deb' => 'libxml-simple-perl',
                   'ver' => 2.12,
               },
               "String::CRC32" => {
                   'deb' => 'libstring-crc32-perl',
                   'opt' => 'Required for palette-altering of PNG files.  Only necessary if you plan to make your own S2 styles that use PNGs, not GIFs.',
               },
               "Time::HiRes" => { 'deb' => 'libtime-hires-perl' },
               "IO::WrapTie" => { 'deb' => 'libio-stringy-perl' },
               "XML::Atom" => {
                   'deb' => 'libxml-atom-perl',
                   'opt' => 'Required for AtomAPI support.',
               },
               "Math::BigInt::GMP" => {
                   'opt' => 'Aides Crypt::DH so it isn\'t crazy slow.',
               },
               "URI::Fetch" => {
                   'opt' => 'Required for OpenID support.',
               },
               "Crypt::DH" => {
                   'opt' => 'Required for OpenID support.',
               },
               );

sub check_modules {
    print "[Checking for Perl Modules....]\n";

    my @debs;

    foreach my $mod (sort keys %modules) {
        my $rv = eval "use $mod;";
        if ($@) {
            my $dt = $modules{$mod};
            if ($dt->{'opt'}) {
                print STDERR "Missing optional module $mod: $dt->{'opt'}\n";
            } else {
                push @errors, "Missing perl module: $mod";
            }
            push @debs, $dt->{'deb'} if $dt->{'deb'};
            next;
        }

        my $ver_want = $modules{$mod}{ver};
        my $ver_got = $mod->VERSION;
        if ($ver_want && $ver_got && $ver_got < $ver_want) {
            push @errors, "Out of date module: $mod (need $ver_want, $ver_got installed)";
        }
    }
    if (@debs && -e '/etc/debian_version') {
        print STDERR "\n# apt-get install ", join(' ', @debs), "\n\n";
    }

    $err->(@errors);
}

sub check_env {
    print "[Checking LJ Environment...]\n";

    $err->("\$LJHOME environment variable not set.")
        unless $ENV{'LJHOME'};
    $err->("\$LJHOME directory doesn't exist ($ENV{'LJHOME'})")
        unless -d $ENV{'LJHOME'};

    # before ljconfig.pl is called, we want to call the site-local checkconfig,
    # otherwise ljconfig.pl might load ljconfig-local.pl, which maybe load
    # new modules to implement site-specific hooks.
    my $local_config = "$ENV{'LJHOME'}/bin/checkconfig-local.pl";
    if (-e $local_config) {
        my $good = eval { require $local_config; };
        exit 1 unless $good;
    }

    $err->("No ljconfig.pl file found at $ENV{'LJHOME'}/cgi-bin/ljconfig.pl")
        unless -e "$ENV{'LJHOME'}/cgi-bin/ljconfig.pl";

    eval { require "$ENV{'LJHOME'}/cgi-bin/ljlib.pl"; };
    $err->("Failed to load ljlib.pl: $@") if $@;

    # if SMTP_SERVER is set, then Net::SMTP is required, not optional.
    if ($LJ::SMTP_SERVER && ! defined $Net::SMTP::VERSION) {
        $err->("Net::SMTP isn't available, and you have \$LJ::SMTP_SERVER set.");
    }
}

sub check_database {
    print "[Checking Database...]\n";

    require "$ENV{'LJHOME'}/cgi-bin/ljlib.pl";
    my $dbh = LJ::get_dbh("master");
    unless ($dbh) {
        $err->("Couldn't get master database handle.");
    }
    foreach my $c (@LJ::CLUSTERS) {
        my $dbc = LJ::get_cluster_master($c);
        next if $dbc;
        $err->("Couldn't get db handle for cluster \#$c");
    }

    if (%LJ::MOGILEFS_CONFIG && $LJ::MOGILEFS_CONFIG{hosts}) {
        print "[Checking MogileFS client.]\n";
        my $mog = LJ::mogclient();
        die "Couldn't create mogilefs client." unless $mog;
    }
}

foreach my $check (@checks) {
    next unless $dochecks{$check};
    my $cn = "check_".$check;
    &$cn;
}
print "All good.\n";
print "NOTE: checkconfig.pl doesn't check everything yet\n";


