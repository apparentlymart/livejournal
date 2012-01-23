package LJ::RelationService;
use strict;

use LJ::ExtBlock;
use LJ::JSON;

use LJ::RelationService::RSAPI;
use LJ::RelationService::MysqlAPI;

my $PARAMS = {};

sub _load_alt_api {
    my $class  = shift;
    my $method = shift;

    return 0 unless LJ::is_enabled('send_test_load_to_rs2');

    my $ext_block = LJ::ExtBlock->load_by_id('lj11_params');
    my $values = $ext_block ? LJ::JSON->from_json($ext_block->blocktext) : {};
    $PARAMS->{rs_ratio_read} = $values->{rs_ratio_read} || 0;
    $PARAMS->{rs_ratio_update} = $values->{rs_ratio_update} || 0;
    
    my $rate = ($method eq 'read')   ? $PARAMS->{rs_ratio_read} :
               ($method eq 'update') ? $PARAMS->{rs_ratio_update} : 0;
    
    return 0 unless $rate;

    ##
    my $val = int rand(100);
    return 1 if $rate > $val;

    return 0;
}


sub relation_api {
    my $class = shift;
    my $u     = shift;
    return "LJ::RelationService::MysqlAPI";
}

sub alt_api {
    my $class = shift;
    my $u     = shift;
    return "LJ::RelationService::RSAPI";
}

## findRelationDestinations
sub find_relation_destinations {
    my $class = shift;
    my $u     = shift;

    if ($class->_load_alt_api('read')){
        my $alt = $class->alt_api($u);
        if ($alt){
            $alt->find_relation_destinations($u, @_);
        }
    }

    my $interface = $class->relation_api($u);
    return $interface->find_relation_destinations($u, @_);
   
}

## findRelationSources
sub find_relation_sources {
    my $class = shift;
    my $u     = shift;

    if ($class->_load_alt_api('read')){
        my $alt = $class->alt_api($u);
        if ($alt){
            $alt->find_relation_sources($u, @_);
        }
    }

    my $interface = $class->relation_api($u);
    return $interface->find_relation_sources($u, @_);
   
}

sub load_relation_destinations {
    my $class = shift;
    my $u     = shift;

    my $interface = $class->relation_api($u);
    return $interface->load_relation_destinations($u, @_);
   
}

sub create_relation_to {
    my $class = shift;
    my $u     = shift;

    if ($class->_load_alt_api('update')){
        my $alt = $class->alt_api($u);
        if ($alt){
            $alt->create_relation_to($u, @_);
        }
    }

    my $interface = $class->relation_api($u);
    return $interface->create_relation_to($u, @_);
}


sub remove_relation_to {
    my $class = shift;
    my $u     = shift;

    if ($class->_load_alt_api('update')){
        my $alt = $class->alt_api($u);
        if ($alt){
            $alt->create_relation_to($u, @_);
        }
    }
    my $interface = $class->relation_api($u);
    return $interface->remove_relation_to($u, @_);
}

1;
