package LJ::Controller::API::JSON;
use strict;
use warnings;

use LJ::Lang;
use LJ::Response::CachedTemplate;
use LJ::Response::Error;
use LJ::Response::Redirect;
use LJ::Request;
use Data::Dumper;

use base qw{ LJ::Controller };
use LJ::API::Error;
use LJ::API::Namespaces;
use LJ::JSON::RPC; 

sub process {
    my ($self) = @_;
 
    my $remote = LJ::get_remote();
    my $raw_content = LJ::Request->raw_content;

    my $rpc = LJ::JSON::RPC->new(LJ::Request->uri, $raw_content);
    $rpc->call( sub {
        return LJ::API::Namespaces->call(@_);
    });

    return $rpc->response;
} # process

sub need_res {
}

1;
