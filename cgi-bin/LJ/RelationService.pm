package LJ::RelationService;
use strict;

use LJ::ExtBlock;
use LJ::JSON;

use LJ::RelationService::RSAPI;
use LJ::RelationService::MysqlAPI;

use Data::Dumper;

sub _load_alt_api {
    my $class  = shift;
    my $method = shift;
    my $type   = shift;

    return 0 unless LJ::is_enabled('send_test_load_to_rs2');

    my $ext_block = LJ::ExtBlock->load_by_id('lj11_params');
    my $values = $ext_block ? LJ::JSON->from_json($ext_block->blocktext) : {};
    
    if ($type eq 'F') {
        return 0 unless $values->{rs_enable_type_f};
    } else {
        return 0 unless $values->{rs_enable_type_other};
    }
    
    my $rate = ($method eq 'read')   ? $values->{rs_ratio_read} :
               ($method eq 'update') ? $values->{rs_ratio_update} : 0;
    
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
    my $type  = shift;
    my %opts  = @_;
    
    $u = LJ::want_user($u);
    $opts{offset} ||= 0;
    $opts{limit}  ||= 50000;

    if ($class->_load_alt_api('read', $type)){
        my $alt = $class->alt_api($u);
        if ($alt) {
            $alt->find_relation_destinations($u, $type, %opts);
        }
    }

    my $interface = $class->relation_api($u);
    return $interface->find_relation_destinations($u, $type, %opts);
   
}

## findRelationSources
sub find_relation_sources {
    my $class = shift;
    my $u     = shift;
    my $type  = shift;
    my %opts  = @_;

    $u = LJ::want_user($u);
    $opts{offset} ||= 0;
    $opts{limit}  ||= 50000;

    if ($class->_load_alt_api('read', $type)){
        my $alt = $class->alt_api($u);
        if ($alt) {
            $alt->find_relation_sources($u, $type, %opts);
        }
    }

    my $interface = $class->relation_api($u);
    return $interface->find_relation_sources($u, $type, %opts);
   
}

sub load_relation_destinations {
    my $class = shift;
    my $u     = shift;
    my $type  = shift;
    my %opts  = @_;

    $u = LJ::want_user($u);
    $opts{offset} ||= 0;
    $opts{limit}  ||= 50000;

    if ($class->_load_alt_api('read', $type)){
        my $alt = $class->alt_api($u);
        if ($alt) {
            $alt->load_relation_destinations($u, $type, %opts);
        }
    }

    my $interface = $class->relation_api($u);
    return $interface->load_relation_destinations($u, $type, %opts);
}

sub create_relation_to {
    my $class  = shift;
    my $u      = shift;
    my $friend = shift;
    my $type   = shift;
    my %opts   = @_;
    
    $u = LJ::want_user($u);
    $friend = LJ::want_user($friend);
    
    return undef unless $type and $u and $friend;

    if ($class->_load_alt_api('update')){
        my $alt = $class->alt_api($u);
        if ($alt){
            $alt->create_relation_to($u, $friend, $type, %opts);
        }
    }

    my $interface = $class->relation_api($u);
    return $interface->create_relation_to($u, $friend, $type, %opts);
}


sub remove_relation_to {
    my $class = shift;
    my $u     = shift;

    $u = LJ::want_user($u);
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
