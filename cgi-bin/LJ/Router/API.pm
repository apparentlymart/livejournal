package LJ::Router::API;
use strict;
use warnings;

use LJ::Controller::API::JSON;

sub match_controller {
    if ( LJ::Request->hostname eq $LJ::DOMAIN_WEB ) {
        if ( LJ::Request->uri =~ m!^\/__api\/!ig and 'JSON_rpc' ) {
            LJ::Request->notes( controller  => 'LJ::Controller::API::JSON' );
            return;
        }
    }
}

1;
