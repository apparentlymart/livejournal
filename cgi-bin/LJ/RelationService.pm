package LJ::RelationService;
use strict;

use LJ::RelationService::MysqlAPI;


sub relation_api {
    my $class = shift;
    my $u     = shift;
    return "LJ::RelationService::MysqlAPI";
}


## findRelationDestinations
sub find_relation_destinations {
    my $class = shift;
    my $u     = shift;

    my $interface = $class->relation_api($u);
    return $interface->find_relation_destinations($u, @_);
   
}

## findRelationSources
sub find_relation_sources {
    my $class = shift;
    my $u     = shift;

    my $interface = $class->relation_api($u);
    return $interface->find_relation_sources($u, @_);
   
}

sub load_relation_destinations {
    my $class = shift;
    my $u     = shift;

    my $interface = $class->relation_api($u);
    return $interface->load_relation_destinations($u, @_);
   
}

1
