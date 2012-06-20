#!/usr/bin/perl -w
use strict;
use HTML::Template;
use File::Basename;
use Getopt::Long;
use vars qw{ $home $authors $author $extends $path $public $private $name $preview };

chdir dirname $0 or die 'Could not change working directory';

$home    = join('/', $ENV{'LJHOME'}, qw{ htdocs js jquery });
$authors = do 'authors.conf';

ref $authors and ref $authors eq 'HASH' or die 'Invalid authors.conf format';

@ARGV and GetOptions(
    'name=s'    => \$name,
    'author=s'  => \$author, 
    'public=s'  => \$public, 
    'private=s' => \$private, 
    'extends=s' => \$extends, 
    'path=s'    => \$path, 
    'preview'   => \$preview, 
) or die <<"";
LJ Widget Factory\n
Usage $0:
\t--name\t\tWidget name
\t--author\tWidget author username, taken from authors.conf
\t--extends\tParent widget, defaults to jquery.lj.basicWidget.js 
\t--path\t\tRelative path from $home, defaults to ./
\t--public\tComma-separated list of public methods
\t--private\tComma-separated list of private methods
\t--preview\tWrite result to STDOUT

# Check path
-d join('/', $home, $path) or die "Target directory $home/$path not exists" if $path;

# Check name
$name or die "Widget name required";

my $file = join('/', $home, $path? $path : (), "jquery.lj.$name.js");

# Check file
-f $file and die "File $file already exists";

# Check author
if ( $author ) {
    exists $authors->{$author} or die "Author '$author' was not found in authors.conf";

    $author = $authors->{$author};
}

# Check parent widget
if ( $extends ) {
    -f join('/', $home, $extends) or die "Widget '$extends' was not found in $home";
    $extends = basename $extends;
    $extends =~ s{^jquery\.lj\.|\.js$} {}g;
}

# Transform method lists
{
    no strict 'refs';
    $$_ = [map {{ method => $_ }} split m{(?<!\\),}, $$_] foreach grep $$_, qw{ public private };
}

# Generate template
my $template = new HTML::Template
    loop_context_vars => 1,
    filename          => 'widget.tmpl';

$template->param(
    name        => $name,
    author      => $author,
    extends     => $extends,
    has_public  => $public?  1 : 0,
    has_private => $private? 1 : 0,
    public      => $public  || [],
    private     => $private || [],
);

# Write output
if ( $preview ) {
    print $template->output();
} else {
    open WIDGET, '+>', $file or die "Could not create file $file";
    print WIDGET $template->output();
    close WIDGET;
}
