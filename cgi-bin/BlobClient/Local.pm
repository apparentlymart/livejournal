#!/usr/bin/perl
# vim:ts=4 sw=4 et:

use strict;
use IO::File;
use File::Path;

package BlobClient::Local;

use constant DEBUG => 0;

use BlobClient;
our @ISA = ("BlobClient");

sub new {
    my ($class, $args) = @_;
    my $self = $class->SUPER::new($args); 
    bless $self, ref $class || $class;
    return $self;
}

sub get {
	my ($self, $cid, $uid, $domain, $fmt, $bid) = @_;
    my $fh = new IO::File;
    local $/ = undef;
    my $path = make_path(@_);
    print STDERR "Blob::Local: requesting $path\n" if DEBUG;
    unless (open($fh, '<', $path)) {
        return undef;
    }
    print STDERR "Blob::Local: serving $path\n" if DEBUG;
    my $data = <$fh>;
    close($fh);
    return $data;
}

sub get_stream {
    my ($self, $cid, $uid, $domain, $fmt, $bid, $callback, $errref) = @_;

    my $fh = new IO::File;
    my $path = make_path(@_);
    unless (open($fh, '<', $path)) {
        $$errref = "Error opening '$path'";
        return undef;
    }
    my $data;
    while (read($fh, $data, 4096)) {
        $callback->($data);
    }
    close($fh);
    return 1;
}

sub put {
    my ($self, $cid, $uid, $fmt, $domain, $bid, $content) = @_;

    my $filename = make_path(@_);

    my $dir = File::Basename::dirname($filename);
    eval { File::Path::mkpath($dir, 0, 0775); };
    return undef if $@;

    my $fh = new IO::File;
    unless (open($fh, '>', $filename)) {
        return undef;
    }
    print $fh $content;
    close $fh;

    return 1;
}

sub make_path { my $self = shift; return $self->SUPER::make_path(@_); }

1;
