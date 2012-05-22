package LJ::JSON::RPC::Item;

use strict;
use warnings;

use LJ::API::Error;
use LJ::API::Auth;

#
# json request and response jpc 2.0
#

use LJ::JSON;

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

    $self->{'fatal'} = { 'error_code' => -32602, 'error_message' => 'Invalid params' } unless $params;
    $self->{'fatal'} = { 'error_code' => -32602, 'error_message' => 'Invalid params' } if ref $params eq 'ARRAY';
    if ($self->{'fatal'}) {
        return $self;
    }

    my $access = LJ::API::Auth->rpc_access($uri, $params);
    $self->{'fatal'} = $access->{'error'};
    if ($self->{'fatal'}) {
        return $self;
    }
 
    $self->{'access_type'} = $access->{'type'};

    $self->{'fatal'} = { 'error_code' => -32600, 'error_message' => 'Invalid Request' } unless $method;
    $self->{'fatal'} = { 'error_code' => -32600, 'error_message' => 'Invalid Request' } if !$jsonrpc || $jsonrpc ne '2.0';

    if ($self->{'fatal'}) {
        return $self;
    }


    $self->{'uri'}    = $uri;
    $self->{'method'} = $method;
    $self->{'params'} = $params;
    if (exists $data->{'id'}) {
        $self->{'id'}     = $data->{'id'};
    }
 
    return $self,
}


#
# When a rpc call encounters an error, the Response Object MUST contain 
# the error member with a value that is a Object with the following members:
# - code 
# - message
# - data
#
sub __construct_error_object {
    LJ::API::Error->get_error 
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
        $fatal = { 'error_code' => -32603, 'error_message' => 'Internal error' };
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
        $error = $fatal if ($fatal);
        my $error_information;

        my $error_data; 
        if ($error->{'defined'}) {
            my $error_type     = $error->{'error_type'};
            my $error_options  = $error->{'error_options'};

            $error = LJ::API::Error->get_error($error_type, $error_options)->{'error'};
        } 

        my $error_code = $error->{'error_code'};
        my $error_msg  = $error->{'error_message'};

        $error_data->{'code'}   = $error_code;
        $error_data->{'message'}= $error_msg; 
        
        if ($error->{'data'}) {
            $error_data->{'data'} = $error->{'data'};
        }

        $resp->{'error'} = $error_data;
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
