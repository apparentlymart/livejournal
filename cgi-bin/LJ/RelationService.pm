package LJ::RelationService;

#############################################
#
#   NEED OPTIMIZATION FOR PROCESS CACHE !!!
#
#############################################

use strict;
use warnings;

# Internal modules
use LJ::JSON;
use LJ::Request;
use LJ::ExtBlock;
use LJ::RelationService::RSAPI;
use LJ::RelationService::MysqlAPI;

my %singletons = ();

sub reset_singletons {
    %singletons = ();
}

sub _load_rs_api {
    my $class  = shift;
    my $method = shift;
    my $type   = shift;

    return 0 unless LJ::is_enabled('send_test_load_to_rs2');

    my $values = LJ::Request->is_inited ? $singletons{'__lj11_params_value'} : 0;
    unless ($values) {
        my $ext_block = LJ::ExtBlock->load_by_id('lj11_params');
        $values = $ext_block ? LJ::JSON->from_json($ext_block->blocktext) : {};
        $singletons{'__lj11_params_value'} = $values;
    }
    
    if ($type && $type eq 'F') {
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

sub rs_api {
    my $class = shift;
    return "LJ::RelationService::RSAPI";
}

sub mysql_api {
    my $class = shift;
    return "LJ::RelationService::MysqlAPI";
}

sub create_relation_to {
    my $class  = shift;
    my $u      = shift;
    my $target = shift;
    my $type   = shift;
    my %opts   = @_;
    
    $u      = LJ::want_user($u);
    $target = LJ::want_user($target);
    
    return undef unless $u;
    return undef unless $type;
    return undef unless $target;

    if ($class->_load_rs_api('update')) {
        if (my $alt = $class->rs_api) {
            $alt->create_relation_to($u, $target, $type, %opts);
        }
    }

    my $interface = $class->mysql_api;
    my $result    = $interface->create_relation_to($u, $target, $type, %opts);

    return $result;
}


sub remove_relation_to {
    my $class  = shift;
    my $u      = shift;
    my $target = shift;
    my $type   = shift;

    $u      = LJ::want_user($u) unless $u eq '*';
    $target = LJ::want_user($target) unless $target eq '*';
    
    return undef unless $u;
    return undef unless $type;
    return undef unless $target;
    return undef if $u eq '*' and $target eq '*';

    if ($class->_load_rs_api('update')) {
        if (my $alt = $class->rs_api) {
            $alt->remove_relation_to($u, $target, $type);
        }
    }

    my $interface = $class->mysql_api;
    my $result    = $interface->remove_relation_to($u, $target, $type);

    return $result;
}

sub is_relation_to {
    my $class  = shift;
    my $u      = shift;
    my $target = shift;
    my $type   = shift;
    my %opts   = @_;

    return undef unless $u;
    return undef unless $type;
    return undef unless $target;

    unless (UNIVERSAL::isa($u, 'LJ::User') && UNIVERSAL::isa($target, 'LJ::User')) {
        $u      = LJ::want_user($u);
        $target = LJ::want_user($target);

        return undef unless $u;
        return undef unless $type;
        return undef unless $target;
    }

    if ($class->_load_rs_api('read', $type)) {
        if (my $alt = $class->rs_api) {
            $alt->is_relation_to($u, $target, $type, %opts);
        }
    }

    my $interface = $class->mysql_api;
    my $result    = $interface->is_relation_to($u, $target, $type, %opts);   

    return $result;
}

sub is_relation_type_to {
    my $class  = shift;
    my $u      = shift;
    my $target = shift;
    my $types  = shift;
    my %opts   = @_;
    
    $u      = LJ::want_user($u);
    $target = LJ::want_user($target);
    
    return undef unless $u;
    return undef unless $types;
    return undef unless $target;

    unless (ref $types eq 'ARRAY') {
        $types = [$types];
    }

    if ($class->_load_rs_api('read', $types)) {
        if (my $alt = $class->rs_api) {
            $alt->is_relation_type_to($u, $target, $types, %opts);
        }
    }

    my $interface = $class->mysql_api;
    my $result    = $interface->is_relation_type_to($u, $target, $types, %opts);

    return $result;
}

sub find_relation_destinations {
    my $class = shift;
    my $u     = shift;
    my $type  = shift;
    my %opts  = @_;
    
    $u = LJ::want_user($u);

    return unless $u;

    $opts{offset} ||= 0;
    $opts{limit}  ||= 50000;

    if ($class->_load_rs_api('read', $type)) {
        if (my $alt = $class->rs_api) {
            $alt->find_relation_destinations($u, $type, %opts);
        }
    }

    my $interface = $class->mysql_api;
    my @result    = $interface->find_relation_destinations($u, $type, %opts);

    return @result;
}

sub find_relation_sources {
    my $class = shift;
    my $u     = shift;
    my $type  = shift;
    my %opts  = @_;

    $u = LJ::want_user($u);

    return unless $u;

    $opts{offset} ||= 0;
    $opts{limit}  ||= 50000;

    if ($class->_load_rs_api('read', $type)) {
        if (my $alt = $class->rs_api) {
            $alt->find_relation_sources($u, $type, %opts);
        }
    }

    my $interface = $class->mysql_api;
    my @result    = $interface->find_relation_sources($u, $type, %opts);

    return @result;
}

sub load_relation_destinations {
    my $class = shift;
    my $u     = shift;
    my $type  = shift;
    my %opts  = @_;

    $u = LJ::want_user($u);

    return undef unless $u;

    $opts{offset} ||= 0;
    $opts{limit}  ||= 50000;

    if ($class->_load_rs_api('read', $type)) {
        if (my $alt = $class->rs_api) {
            $alt->load_relation_destinations($u, $type, %opts);
        }
    }

    my $interface = $class->mysql_api;
    my $result    = $interface->load_relation_destinations($u, $type, %opts);

    return $result;
}

sub get_groupmask {
    my $class  = shift;
    my $u      = shift;
    my $target = shift;
    my %opts   = @_;
    
    $u      = LJ::want_user($u);
    $target = LJ::want_user($target);

    return 0 unless $u;
    return 0 unless $target;

    if ($class->_load_rs_api('read', 'F')) {
        if (my $alt = $class->rs_api) {
            $alt->find_relation_attributes($u, $target, 'F', %opts);
        }
    }

    my $interface = $class->mysql_api;
    my $result    = $interface->find_relation_attributes($u, $target, 'F', %opts);

    unless ($result) {
        return 0;
    }

    $result->{groupmask} ||= 1;

    return $result->{groupmask};
}

sub get_filtermask {
    my $class  = shift;
    my $u      = shift;
    my $target = shift;
    my %opts   = @_;

    return 0 unless $u;
    return 0 unless $target;

    if ($class->_load_rs_api('read', 'R')) {
        if (my $alt = $class->rs_api) {
            $alt->find_relation_attributes($u, $target, 'R', %opts);
        }
    }

    my $interface = $class->mysql_api;
    my $result    = $interface->find_relation_attributes($u, $target, 'R', %opts);

    unless ($result) {
        return 0;
    }

    $result->{filtermask} ||= 1;

    return $result->{filtermask};
}

sub delete_and_purge_completely {
    my $class  = shift;
    my $u      = shift;
    my %opts   = @_;
    
    $u = LJ::want_user($u);
    
    return unless $u;

    if ($class->_load_rs_api('update', 'F')) {
        if (my $alt = $class->rs_api) {
            $alt->delete_and_purge_completely($u, %opts);
        }
    }

    my $interface = $class->mysql_api;
    my $result    = $interface->delete_and_purge_completely($u, %opts);

    return $result;
}

sub clear_rel_multi {
    my $class = shift;
    my $edges = shift;
    
    return undef unless ref $edges eq 'ARRAY';

    if ($class->_load_rs_api('update', 'B')) {
        if (my $alt = $class->rs_api) {
            $alt->clear_rel_multi($edges);
        }
    }

    my $interface = $class->mysql_api();
    my $result    = $interface->clear_rel_multi($edges);

    return $result;
}

sub set_rel_multi {
    my $class = shift;
    my $edges = shift;
    
    return undef unless ref $edges eq 'ARRAY';

    if ($class->_load_rs_api('update', 'B')) {
        if (my $alt = $class->rs_api) {
            $alt->set_rel_multi($edges);
        }
    }

    my $interface = $class->mysql_api;
    my $result    = $interface->set_rel_multi($edges);

    return $result;
}

sub find_relation_attributes {
    my $class  = shift;
    my $u      = shift;
    my $target = shift;
    my $type   = shift;
    my %opts   = @_;
    
    $u      = LJ::want_user($u);
    $target = LJ::want_user($target);

    return undef unless $u;
    return undef unless $type;
    return undef unless $target;

    if ($class->_load_rs_api('read', $type)) {
        if (my $alt = $class->rs_api) {
            $alt->find_relation_attributes($u, $target, $type, %opts);
        }
    }

    my $interface = $class->mysql_api;
    my $result    = $interface->find_relation_attributes($u, $target, $type, %opts);

    return $result;
}

sub update_relation_attributes {
    my $class  = shift;
    my $u      = shift;
    my $target = shift;
    my $type   = shift;
    my %opts   = @_;

    return 0 unless $u;
    return 0 unless $type;
    return 0 unless $target;

    if ($class->_load_rs_api('update', $type)) {
        if (my $alt = $class->rs_api) {
            $alt->update_relation_attributes($u, $target, $type, %opts);
        }
    }

    my $interface = $class->mysql_api;
    my $result    = $interface->update_relation_attributes($u, $target, $type, %opts);

    return $result;
}

# Special methods which destroy architectural logic but are necessary for productivity

sub update_relation_attribute_mask_for_all {
    my $class = shift;
    my $u     = shift;
    my $type  = shift;
    my %opts  = @_;

    return 0 unless $u;
    return 0 unless $type;

    if ($class->_load_rs_api('update', $type)) {
        if (my $alt = $class->rs_api) {
            $alt->update_relation_attribute_mask_for_all($u, $type, %opts);
        }
    }

    my $interface = $class->mysql_api;
    my $result    = $interface->update_relation_attribute_mask_for_all($u, $type, %opts);

    return $result;
}

1;