#!/usr/bin/perl -w
use strict;
use Getopt::Long;

#
# This script downloads CKEditor source tarball, builds it and installs
#

my $version  = '3.6.2';
my $build    = join('/', $ENV{'LJHOME'}, qw{ build });
my $ljsource = join('/', $ENV{'LJHOME'}, qw{ htdocs js ck });
my $clean    = 0;
my $deploy   = 0;
my $options  = GetOptions(
    'version=s' => \$version,
    'build=s'   => \$build,
    'deploy'    => \$deploy,
    'clean'     => \$clean,
);

my $source = join($version, 'http://download.cksource.com/CKEditor/CKEditor/CKEditor%20', '/ckeditor_', '.tar.gz');

unless ( -d $build ) {
    warn "Build directory $build not found";
    mkdir $build or die "Failed to create directory $build: $!";
}

chdir $build or die "Failed to change directory to $build: $!";

`wget $source -O ckeditor-$version.tar.gz` unless -f "ckeditor-$version.tar.gz";

die 'Failed to fetch tarball' if $?;

`tar xpf ckeditor-$version.tar.gz`;
`mv ckeditor/* ./`;
`rm -rf ckeditor`;

die "LJ source directory $ljsource not found" unless -d $ljsource;

my $files = join ' ', map {
    s{//} {/}g;
    $_;
} map {
    join('/', $ljsource, $_)
} map {
    split "\n"
} <<'';
config.js
ckeditor.pack
ckpackager.jar
global.js
skins
plugins

print `cp -vur $files ./`;

`grep -v "'plugins/" < ckeditor.pack > ckeditor-dev.pack`;

print `java -jar ckpackager.jar ckeditor-dev.pack`;
print `mv ckeditor.js ckeditor-dev.js`;

print `java -jar ckpackager.jar ckeditor.pack`;

die 'Build failed' if $?;
print "Build complete\n";

print "Clean up\n" if $clean;
`rm -rf \$(ls | grep -Pv '(?:ckeditor(?:-dev)?.js|ckeditor(.*).tar.gz)')` if $clean;

if ( -f 'ckeditor.js' and -f 'ckeditor-dev.js' ) {
    print `cp -v ckeditor.js ckeditor-dev.js $ljsource` if $deploy;
} else {
    die 'Build failed';
}

print "Done\n";
