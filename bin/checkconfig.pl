#!/usr/bin/perl
#

my @errors;
my $err = sub {
    return unless @_;
    die "Problem:\n" . join('', map { "  * $_\n" } @_);
};

############################################################################
print "[Checking for Perl Modules....]\n";
############################################################################

my %modules = (
               "DBI" => { 'deb' => 'libdbi-perl',  },
               "DBD::mysql" => { 'deb' => 'libdbd-mysql-perl', },
               "Digest::MD5" => { 'deb' => 'libdigest-md5-perl', },
               "Image::Size" => { 'deb' => 'libimage-size-perl', },
               "MIME::Lite" => { 'deb' => 'libmime-lite-perl', },
               "MIME::Words" => { 'deb' => 'libmime-perl', },
               "Compress::Zlib" => {
                   'deb' => 'libcompress-zlib-perl',
                   'opt' => 'When available, turn on $LJ::DO_GZIP to cut bandwidth usage in half.',
               },
               "MIME::Base64" => { 'deb' => 'libmime-base64-perl' },
               "URI::URL" => { 'deb' => 'liburi-perl' },
               "HTML::Tagset" => { 'deb' => 'libhtml-tagset-perl' },
               "HTML::Parser" => { 'deb' => 'libhtml-parser-perl', },
               "LWP::Simple" => { 'deb' => 'libwww-perl', },
               "LWP::UserAgent" => { 'deb' => 'libwww-perl', },
               "GD::Graph" => { 
                   'deb' => 'libgd-graph-perl', 
                   'opt' => 'Required to make graphs for the statistics page.',
               },
               "Mail::Address" => { 'deb' => 'libmailtools-perl', },
               "Proc::ProcessTable" => { 
                   'deb' => 'libproc-process-perl', 
                   'opt' => "Better reliability for starting daemons necessary for high-traffic installations.",
               },
               "SOAP::Lite" => { 
                   'deb' => 'libsoap-lite-perl', 
                   'opt' => 'Required for XML-RPC support.',
               },
               "Unicode::MapUTF8" => { 'deb' => 'libunicode-maputf8-perl', },
               );

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
    }
}
if (@debs && -e '/etc/debian_version') {
    print STDERR "\n# apt-get install ", join(' ', @debs), "\n\n";
}

$err->(@errors);

############################################################################
print "[Checking LJ Environment...]\n";
############################################################################

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

############################################################################
print "[Checking Database...]\n";
############################################################################

my $dbh = LJ::get_dbh("master");
unless ($dbh) {
    $err->("Couldn't get master database handle.");
}
foreach my $c (@LJ::CLUSTERS) {
    my $dbc = LJ::get_cluster_master($c);
    next if $dbc;
    $err->("Couldn't get db handle for cluster \#$c");
}

print "All good.\n";
print "NOTE: checkconfig.pl doesn't check everything yet\n";


