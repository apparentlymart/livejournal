package LJ::API::Error;

use strict;
use warnings;

use LJ::Lang;

my %errors = (
    'unknown_error'        => {  'error_code' => -10000, 
                                 'error_var'  => 'api.error.unknwon_error', },

    'invalid_params'       => { 'error_code' => -32602,
                                'error_text' => 'Invalid params', }, 

    'invalid_data_format'  => { 'error_code' => -10001,
                                'error_var'  => 'api.error.invalid_data_format', },

    'invalid_method'       => { 'error_code' => -32601,
                                'error_text'  => 'Method not found', },

    'entry_not_found'      => { 'error_code' =>  -10002,
                                'error_var'  => 'api.error.entry_not_found', },

);

# reserved: 10001 code for custom error
sub get_error {
    my ($class, $error_type, $options) = @_;
    die "unknwon error" unless $error_type;

    my $error = $errors{$error_type};
    die "unknwon error" unless $error;

    my $lang_var = $error->{'error_var'};
    my $text = $lang_var ? LJ::Lang::ml($lang_var, $options) : $error->{'error_text'};
    
    return { 'error' => { 'error_code'    => $error->{'error_code'},
                          'error_message' => $text, },
           };
}

