package LJ::RelationService;

#############################################
#
#   NEED OPTIMIZATION FOR PROCESS CACHE !!!
#
#############################################


use strict;
use warnings;

# External modules
use Data::Dumper;

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
    my $u     = shift;
    return "LJ::RelationService::RSAPI";
}

sub mysql_api {
    my $class = shift;
    my $u     = shift;
    return "LJ::RelationService::MysqlAPI";
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

    if ($class->_load_rs_api('read', $type)) {
        my $alt = $class->rs_api($u);
        if ($alt) {
            $alt->find_relation_destinations($u, $type, %opts);
        }
    }

    my $interface = $class->mysql_api($u);
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

    if ($class->_load_rs_api('read', $type)) {
        if (my $alt = $class->rs_api($u)) {
            $alt->find_relation_sources($u, $type, %opts);
        }
    }

    my $interface = $class->mysql_api($u);
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
        if (my $alt = $class->rs_api($u)) {
            $alt->load_relation_destinations($u, $type, %opts);
        }
    }

    my $interface = $class->mysql_api($u);
    my $result    = $interface->load_relation_destinations($u, $type, %opts);

    delete $singletons{$u->userid};

    return $result;
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

    if ($class->_load_rs_api('update')) {
        my $alt = $class->rs_api($u);
        if ($alt){
            $alt->create_relation_to($u, $friend, $type, %opts);
        }
    }

    my $interface = $class->mysql_api($u);
    my $result    = $interface->create_relation_to($u, $friend, $type, %opts);

    delete $singletons{$u->userid}->{$friend->userid};

    return $result;
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

    if ($class->_load_rs_api('update')) {
        my $alt = $class->rs_api($u, $friend, $type);
        if ($alt){
            $alt->remove_relation_to($u, $friend, $type);
        }
    }
    my $interface = $class->mysql_api($u);
    if ($u ne '*' && UNIVERSAL::isa($u, 'LJ::User')) {
        if  ($friend ne '*' && UNIVERSAL::isa($friend, 'LJ::User')) {
            delete $singletons{$u->userid}->{$friend->userid};
        } else {
            delete $singletons{$u->userid};
        }
    }
    return $interface->remove_relation_to($u, $friend, $type);
}

sub is_relation_to {
    my $class  = shift;
    my $u      = shift;
    my $friend = shift;
    my $type   = shift;
    my %opts   = @_;

    return undef unless $u && $friend && $type;

    unless (UNIVERSAL::isa($u, 'LJ::User') && UNIVERSAL::isa($friend, 'LJ::User')) {
        $u = LJ::want_user($u);
        $friend = LJ::want_user($friend);

        return undef unless $u && $friend && $type;
    }

    if ($class->_load_rs_api('read', $type)) {
        my $alt = $class->rs_api($u);
        if ($alt) {
            $alt->is_relation_to($u, $friend, $type, %opts);
        }
    }

    my $interface = $class->mysql_api($u);
    my $result    = $interface->is_relation_to($u, $friend, $type, %opts);   

    return $result;
}

sub is_relation_type_to {
    my $class  = shift;
    my $u      = shift;
    my $friend = shift;
    my $types  = shift;
    my %opts   = @_;
    
    $u = LJ::want_user($u);
    $friend = LJ::want_user($friend);
    
    return undef unless $u && $friend && $types;
    $types = [ $types ] unless ref $types eq 'ARRAY';

    if ($class->_load_rs_api('read', $types)) {
        my $alt = $class->rs_api($u);
        if ($alt) {
            $alt->is_relation_type_to($u, $friend, $types, %opts);
        }
    }

    my $interface = $class->mysql_api($u);
    return $interface->is_relation_type_to($u, $friend, $types, %opts);    
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

    my $uid = $u->id;
    my $tid = $target->id;

    return 0 unless $uid;
    return 0 unless $tid;

    return $singletons{$uid}->{$tid}->{F}->{groupmask}
        if exists $singletons{$uid}->{$tid}->{F}->{groupmask} && 
                    !%opts && LJ::Request->is_inited;

    if ($class->_load_rs_api('read', 'F')) {
        if (my $alt = $class->rs_api($u)) {
            $alt->find_relation_attributes($u, $target, 'F', %opts);
        }
    }

    my $interface = $class->mysql_api($u);
    my $result    = $interface->find_relation_attributes($u, $target, 'F', %opts);

    unless ($result) {
        return 0;
    }

    $result->{groupmask} ||= 1;

    $singletons{$uid}->{$tid}->{F} = $result;

    return $result->{groupmask};
}

sub get_filtermask {
    my $class  = shift;
    my $u      = shift;
    my $target = shift;
    my %opts   = @_;

    my $uid = $u->id;
    my $tid = $target->id;

    return 0 unless $uid;
    return 0 unless $tid;

    return $singletons{$uid}->{$tid}->{R}->{filtermask}
        if exists $singletons{$uid}->{$tid}->{R}->{filtermask} && 
                    !%opts && LJ::Request->is_inited;

    if ($class->_load_rs_api('read', 'R')) {
        if (my $alt = $class->rs_api($u)) {
            $alt->find_relation_attributes($u, $target, 'R', %opts);
        }
    }

    my $interface = $class->mysql_api($u);
    my $result    = $interface->find_relation_attributes($u, $target, 'R', %opts);

    unless ($result) {
        return 0;
    }

    $result->{filtermask} ||= 1;

    $singletons{$uid}->{$tid}->{R} = $result;

    return $result->{filtermask};
}

sub delete_and_purge_completely {
    my $class  = shift;
    my $u      = shift;
    my %opts   = @_;
    
    $u = LJ::want_user($u);
    
    return unless $u;

    if ($class->_load_rs_api('update', 'F')) {
        my $alt = $class->rs_api($u);
        if ($alt) {
            $alt->delete_and_purge_completely($u, %opts);
        }
    }

    my $interface = $class->mysql_api($u);
    delete $singletons{$u->userid};
    return $interface->delete_and_purge_completely($u, %opts);    
}

sub clear_rel_multi {
    my $class = shift;
    my $edges = shift;
    
    return undef unless ref $edges eq 'ARRAY';

    if ($class->_load_rs_api('update', 'B')) {
        my $alt = $class->rs_api();
        if ($alt) {
            $alt->clear_rel_multi($edges);
        }
    }

    my $interface = $class->mysql_api();
    return $interface->clear_rel_multi($edges);
}

sub set_rel_multi {
    my $class = shift;
    my $edges = shift;
    
    return undef unless ref $edges eq 'ARRAY';

    if ($class->_load_rs_api('update', 'B')) {
        my $alt = $class->rs_api();
        if ($alt) {
            $alt->set_rel_multi($edges);
        }
    }

    my $interface = $class->mysql_api();
    return $interface->set_rel_multi($edges);
}

sub find_relation_attributes {
    my $class  = shift;
    my $u      = shift;
    my $friend = shift;
    my $type   = shift;
    my %opts   = @_;
    
    $u = LJ::want_user($u);
    $friend = LJ::want_user($friend);
    
    return undef unless $u && $friend && $type;

    if ($class->_load_rs_api('read', $type)) {
        my $alt = $class->rs_api($u);
        if ($alt) {
            $alt->find_relation_attributes($u, $friend, $type, %opts);
        }
    }

    my $interface = $class->mysql_api($u);
    return $interface->find_relation_attributes($u, $friend, $type, %opts);    
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
        if (my $alt = $class->rs_api($u)) {
            $alt->update_relation_attributes($u, $target, $type, %opts);
        }
    }

    my $interface = $class->mysql_api($u);
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
        if (my $alt = $class->rs_api($u)) {
            $alt->update_relation_attribute_mask_for_all($u, $type, %opts);
        }
    }

    my $interface = $class->mysql_api($u);
    my $result    = $interface->update_relation_attribute_mask_for_all($u, $type, %opts);

    return $result;
}

1;