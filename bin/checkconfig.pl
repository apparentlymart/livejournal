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

my @modules = qw(
                 DBI
                 DBD::mysql
                 Digest::MD5
                 Image::Size
                 MIME::Lite
                 Compress::Zlib
                 MIME::Base64
                 URI::URL
                 HTML::Tagset
                 HTML::Parser
                 LWP::Simple
                 LWP::UserAgent
                 GD
                 GD::Graph
                 GD::Text
                 Mail::Address
                 Proc::ProcessTable
                 SOAP::Lite
                 Unicode::MapUTF8
                 );

foreach my $mod (@modules) {
    my $rv = eval "use $mod;";
    if ($@) {
        push @errors, "Missing perl module: $mod";
    }
}
$err->(@errors);

############################################################################
print "[Checking LJ Environment...]\n";
############################################################################

$err->("\$LJHOME environment variable not set.")
    unless $ENV{'LJHOME'};
$err->("\$LJHOME directory doesn't exist ($ENV{'LJHOME'})")
    unless -d $ENV{'LJHOME'};
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
    $err->("Couldn't get db handle for cluster \#$c");
}

print "All good.\n";
print "NOTE: checkconfig.pl doesn't check everything yet\n";


