#!/usr/bin/perl
# vim:ts=4 sw=4 et:

package BlobClient::Remote;

use BlobClient;
use LWP::UserAgent;
use vars qw(@ISA);
@ISA = qw(BlobClient);

use strict;

use constant DEBUG => 0;
use constant DEADTIME => 30;

use BlobClient;

sub new {
    my ($class, $args) = @_;
    my $self = $class->SUPER::new($args); 

    $self->{ua} = LWP::UserAgent->new(agent=>'blobclient');

    bless $self, ref $class || $class;
    return $self;
}

sub get {
    my ($self, $cid, $uid, $domain, $fmt, $bid) = @_;
    my $path = make_path(@_);
    print STDERR "Blob::Remote requesting $path\n" if DEBUG;
    my $req = HTTP::Request->new(GET => $path);
    my $res = $self->{ua}->request($req);
    return $res->content if $res->is_success;

    # two types of failure: server dead, or just a 404.
    # a 404 doesn't mean the server is necessarily bad.

    if ($res->code == 500) {
        # server dead.
        $self->{deaduntil} = time() + DEADTIME;
    }
    return undef;
}

sub get_stream {
    my ($self, $cid, $uid, $domain, $fmt, $bid, $callback) = @_;
    my $req = HTTP::Request->new(GET => make_path(@_));
    my $res = $self->{ua}->request($req, $callback, 4096);
    return $res->is_success;
}

sub put {
    my ($self, $cid, $uid, $domain, $fmt, $bid, $content, $errref) = @_;
    my $path = make_path(@_);
    print STDERR "Blob::Remote putting $path with content of length " . length($content) . "\n" if DEBUG;
    my $req = HTTP::Request->new(PUT => $path);
    
    $req->content($content);
    my $res = $self->{ua}->request($req);
    unless ($res->is_success) {
        $$errref = "$path: " . $res->status_line if $errref;
        return 0;
    }
    return 1;
}

sub delete {
    my ($self, $cid, $uid, $domain, $fmt, $bid) = @_;
    my $path = make_path(@_);
    my $req = HTTP::Request->new(DELETE => $path);
    my $res = $self->{ua}->request($req);
    return 0 unless $res->is_success;
    return 1;
}

sub is_dead {
    my $self = shift;
    delete $self->{deaduntil} if $self->{deaduntil} <= time();
    return $self->{deaduntil} > 0;
}

sub make_path { my $self = shift; return $self->SUPER::make_path(@_); }

1;
