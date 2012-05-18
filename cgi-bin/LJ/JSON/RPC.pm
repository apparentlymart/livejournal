package LJ::JSON::RPC;

use strict;
use warnings;

use LJ::JSON;
use LJ::JSON::RPC::Item;
use LJ::Response::JSON;

sub new {
    my ($class, $uri, $request) = @_;
    my $self = bless {}, $class;

    eval {
        my $data = LJ::JSON->from_json($request);

        if (ref $data eq 'ARRAY') {
            foreach my $entry (@$data) {
                push @{$self->{'items'}}, { 'item'  => LJ::JSON::RPC::Item->new($uri, $entry), };
            }

            unless (@$data) {
                my $fatal = { 'error_code' => -32600, 'error_message' => 'Invalid Request' };
                $self->{'items'} = { 'item' => LJ::JSON::RPC::Item->new({ 'fatal' =>  $fatal })};
            }
        } else {
            $self->{'items'} = { 'item'   => LJ::JSON::RPC::Item->new($uri, $data),};
        }
    };

    if ($@) {
        warn $@ if $LJ::IS_DEV_SERVER;
        my $fatal = { 'error_code' => -32700, 'error_message' => 'Parse error' };
        $self->{'items'} = { 'item' => LJ::JSON::RPC::Item->new({ 'fatal' =>  $fatal })};
    }

    return $self;
}

sub call {
    my ($self, $callback) = @_;
    my $items = $self->{'items'};

    my $call_info = { 
        'source' => 'jsonrpc',
    };

    if (ref $items eq 'ARRAY') {
        foreach my $entry (@$items) {
            my $item = $entry->{'item'};
            next if $item->error;            

            my $method = $item->method;
            my $params = $item->params;

            $entry->{'result'} = $callback->($method, $params, $call_info);
        }
    } else {
        my $item   = $items->{'item'};
        return if $item->error;

        my $method = $item->method;
        my $params = $item->params;

       $items->{'result'} = $callback->($method, $params, $call_info);
    }
}

sub response {
    my ($self) = @_;
    my $items = $self->{'items'};
    my $resp_data;
    
    if (ref $items eq 'ARRAY') {
        foreach my $entry (@$items) {
            my $item   = $entry->{'item'};
            my $response = $item->response($entry->{'result'});
            push @{$resp_data}, $response if $response;
        }
    } else {
        my $item = $items->{'item'};
        $resp_data = $item->response($items->{'result'});
    }

    my $response = LJ::Response::JSON->new();
    $response->data($resp_data);
    return $response;
}

1;
