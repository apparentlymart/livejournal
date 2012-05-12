package LJ::API::Namespaces;

use strict;
use warnings;
use LJ::API::Error;
use LJ::API::Repost;
use attributes;

my %namespace_map = (
    'repost' => 'LJ::API::Repost',
);

sub __is_public {
    my ($class, $function) = @_;

    my @attrs = attributes::get($function);

    foreach my $attr (@attrs) {
        if ($attr eq 'method') {
            return 1;
        }
    }

    return 0;
}

sub call {
    my ($class, $method, $data) = @_;

    my ($namespace_name, $function) = split(/\./, $method);
    my $namespace = $namespace_map{$namespace_name || ''};
    
    if (!$namespace || !$function) {
        warn "error invalid_method";
        return LJ::API::Error->get_error('invalid_method');
    }

    my $handler = $namespace->can($function);

    if (!$handler || !$class->__is_public($handler)) {
        return LJ::API::Error->get_error('invalid_method');
    }

    my $result = {};
    
    eval {
        $result = $handler->($namespace, $data);
    };
    
    if ($@) {
        warn $@;
        $result = LJ::API::Error->get_error('unknwon_error');
    }
        
    return $result;

}


