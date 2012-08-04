package LJ::JSON::RPC::Item;

use strict;
use warnings;

use LJ::API::Error;
use LJ::API::RpcAuth;

#
# json request and response jpc 2.0
#

sub new {
    my ($class, $uri, $data) = @_;
    my $self = bless {}, $class;

    if ($data->{'fatal'}) {
        $self->{'fatal'} = $data->{'fatal'};
        return $self;
    }

    my $jsonrpc = $data->{'jsonrpc'};
    my $method  = $data->{'method'};
    my $params  = $data->{'params'};

    if (exists $data->{'id'}) {
        $self->{'id'} = $data->{'id'};
    }

    if (!$params || ref $params ne 'HASH') { 
        $self->{'fatal'} = { 'error_code'    => -32602, 
                             'error_message' => 'Invalid params' };
        return $self;
    }

    #
    # Check for auth information
    #
    my $access = LJ::API::RpcAuth->rpc_access($uri, $params);
    $self->{'fatal'} = $access->{'error'};
    if ($self->{'fatal'}) {
        return $self;
    }

    if (!$method || !$jsonrpc || $jsonrpc ne '2.0') { 
        $self->{'fatal'} = { 'error_code'    => -32600, 
                             'error_message' => 'Invalid Request' };
        return $self;                             
    }

    $self->{'uri'}         = $uri;
    $self->{'method'}      = $method;
    $self->{'params'}      = $params;
    $self->{'access_type'} = $access->{'type'};
 
    return $self;
}


#
# When a rpc call encounters an error, the Response Object MUST contain 
# the error member with a value that is a Object with the following members:
# - code 
# - message
# - data
#
sub __construct_error_object {
    LJ::API::Error->get_error;
}

sub response {
    my ($self, $options) = @_;

    my $result = $options->{'result'};
    my $error  = $options->{'error'};
    my $fatal  = $self->{'fatal'};
    
    return if ($self->is_notitification && !$fatal);
    
    my $resp = { 'jsonrpc' => '2.0' };
            
    if ($result && $error) {
        # internal error
        $fatal = { 'error_code'    => -32603, 
                   'error_message' => 'Internal error' };
    }

    ############################################################################
    # result
    ############################################################################
    #
    # This member is REQUIRED on success.
    # This member MUST NOT exist if there was an error invoking the method.
    # The value of this member is determined by the method invoked on the Server.
    #
    ############################################################################
    if ($result) {
        my $remote = LJ::get_remote();
        my @params_vars = keys %{$self->{'params'}};

        my $access_type = $self->{'access_type'};
        if ($access_type && $access_type eq 'auth_token') {
            if ($remote) {
                my $auth = LJ::Auth->ajax_auth_token($remote, 
                                                     $self->{'uri'}, 
                                                     \@params_vars);
                $result->{'auth_token'} = $auth;
            } else {
                my $auth = LJ::Auth->sessionless_auth_token($self->{'uri'});
                $result->{'auth_token'} = $auth;
            }
        }

        $resp->{'result'} = $result; 
    }
 
    ############################################################################
    # error
    ############################################################################
    #
    # When a rpc call encounters an error, the Response Object MUST contain
    # the error member with a value that is a Object with the following members:
    # - code
    # - message
    # - data
    #
    #############################################################################
    if ($error || $fatal) {
        if ($fatal) {
             $error = $fatal;
        }
        
        my %error_data = ( 'code'    => $error->{'error_code'},
                           'message' => $error->{'error_message'}, );
       
        if ($error->{'data'}) {
            $error_data{'data'} = $error->{'data'};
        }

        $resp->{'error'} = \%error_data;
    }

    ##############################################################################
    # id
    ##############################################################################
    #
    # This member is REQUIRED.
    # It MUST be the same as the value of the id member in the Request Object.
    # If there was an error in detecting the id in the Request object 
    # (e.g. Parse error/Invalid Request), it MUST be Null.
    #
    ##############################################################################
    $resp->{'id'} = $self->{'id'};

    return $resp;
}

sub error {
    my ($self) = @_;
    return $self->{'fatal'};
}

sub method {
    my ($self) = @_;
    return $self->{'method'};
}

sub params {
    my ($self) = @_;
    return $self->{'params'};
}

sub is_notitification {
    my ($self) = @_;
    return !(exists $self->{'id'});
}

1;
