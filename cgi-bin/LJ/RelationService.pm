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

    if ($class->_load_alt_api('read', $type)) {
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

    if ($class->_load_alt_api('read', $type)) {
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

    if ($class->_load_alt_api('read', $type)) {
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

    if ($class->_load_alt_api('update')) {
        my $alt = $class->alt_api($u);
        if ($alt){
            $alt->create_relation_to($u, $friend, $type, %opts);
        }
    }

    my $interface = $class->relation_api($u);
    return $interface->create_relation_to($u, $friend, $type, %opts);
}


sub remove_relation_to {
    my $class  = shift;
    my $u      = shift;
    my $friend = shift;
    my $type   = shift;

    $u = LJ::want_user($u) unless $u eq '*';
    $friend = LJ::want_user($friend) unless $friend eq '*';
    
    return undef unless $type and $u and $friend;
    return undef if $u eq '*' and $friend eq '*';

    if ($class->_load_alt_api('update')) {
        my $alt = $class->alt_api($u, $friend, $type);
        if ($alt){
            $alt->remove_relation_to($u, $friend, $type);
        }
    }
    my $interface = $class->relation_api($u);
    return $interface->remove_relation_to($u, $friend, $type);
}

sub is_relation_to {
    my $class  = shift;
    my $u      = shift;
    my $friend = shift;
    my $type   = shift;
    my %opts   = @_;
    
    $u = LJ::want_user($u);
    $friend = LJ::want_user($friend);
    
    return undef unless $u && $friend && $type;

    if ($class->_load_alt_api('read', $type)) {
        my $alt = $class->alt_api($u);
        if ($alt) {
            $alt->is_relation_to($u, $friend, $type, %opts);
        }
    }

    my $interface = $class->relation_api($u);
    return $interface->is_relation_to($u, $friend, $type, %opts);    
}

sub get_groupmask {
    my $class  = shift;
    my $u      = shift;
    my $friend = shift;
    my %opts   = @_;
    
    my $type = $opts{type} || 'F';
    
    $u = LJ::want_user($u);
    $friend = LJ::want_user($friend);
    
    return 0 unless $u && $friend && $type;

    if ($class->_load_alt_api('read', $type)) {
        my $alt = $class->alt_api($u);
        if ($alt) {
            $alt->get_groupmask($u, $friend, $type, %opts);
        }
    }

    my $interface = $class->relation_api($u);
    return $interface->get_groupmask($u, $friend, %opts);    
}

sub delete_and_purge_completely {
    my $class  = shift;
    my $u      = shift;
    my %opts   = @_;
    
    $u = LJ::want_user($u);
    
    return unless $u;

    if ($class->_load_alt_api('write', 'F')) {
        my $alt = $class->alt_api($u);
        if ($alt) {
            $alt->delete_and_purge_completely($u, %opts);
        }
    }

    my $interface = $class->relation_api($u);
    return $interface->delete_and_purge_completely($u, %opts);    
}

sub clear_rel_multi {
    my $class = shift;
    my $edges = shift;
    
    return undef unless ref $edges eq 'ARRAY';

    if ($class->_load_alt_api('write', 'B')) {
        my $alt = $class->alt_api();
        if ($alt) {
            $alt->clear_rel_multi($edges);
        }
    }

    my $interface = $class->relation_api();
    return $interface->clear_rel_multi($edges);
}

sub set_rel_multi {
    my $class = shift;
    my $edges = shift;
    
    return undef unless ref $edges eq 'ARRAY';

    if ($class->_load_alt_api('write', 'B')) {
        my $alt = $class->alt_api();
        if ($alt) {
            $alt->set_rel_multi($edges);
        }
    }

    my $interface = $class->relation_api();
    return $interface->set_rel_multi($edges);
}

1;
