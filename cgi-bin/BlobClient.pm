#!/usr/bin/perl
# vim:ts=4 sw=4 et:

use strict;
use BlobClient::Remote;
use BlobClient::Local;

package BlobClient;

sub new {
    my ($class, $args) = @_;
    my $self = {};
    $self->{path} = $args->{path};
    $self->{path} =~ s!/$!!;
    bless $self, ref $class || $class;
    return $self;
}

sub _make_path {
    my ($cid, $uid, $domain, $fmt, $bid) = @_;
    die "bogus domain" unless $domain =~ /^\w{1,40}$/;
    die "bogus format" unless $fmt =~ /^\w{1,10}$/;

    sprintf("%07d", $uid) =~ /^(\d+)(\d\d\d)(\d\d\d)$/;
    my ($uid1, $uid2, $uid3) = ($1, $2, $3);
    
    sprintf("%04d", $bid) =~ /^(\d+)(\d\d\d)$/;
    my ($bid1, $bid2) = ($1, $2);
    return join('/', int($cid), $uid1, $uid2, $uid3, $domain, $bid1, $bid2) . ".$fmt";
}

sub make_path {
    my $self = shift;
    return $self->{path} . '/' . _make_path(@_);
}

# derived classes will override this.
sub is_dead {
    return 0;
}

1;
