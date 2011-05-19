
# LiveJournal Browse object.
#

package LJ::Browse;
use strict;
use Carp qw/ croak cluck /;

my %singletons = (); # catid => singleton
my @cat_cols = qw( catid pretty_name url_path parentcatid vert_id );
my @prop_cols = qw( children top_children in_nav featured );

#
# Constructors
#

sub new
{
    my $class = shift;

    my $n_arg   = scalar @_;
    croak("wrong number of arguments")
        unless $n_arg && ($n_arg % 2 == 0);

    my %opts = @_;

    my $catid = delete $opts{catid};
    croak("need to supply catid") unless defined $catid;

    croak("unknown parameters: " . join(", ", keys %opts))
        if %opts;

    # do we have a singleton for this category?
    {
        my $cached = $singletons{$catid};
        return $cached if $cached;
    }

    my $self = bless {} => $class;
    $self->{catid} = $catid;

    # save the singleton if it doesn't exist
    $singletons{$catid} = $self;

    return $self;
}
*instance = \&new;

# Create a new category
sub create {
    my $class = shift;
    my $self  = bless {};

    my $n_arg   = scalar @_;
    croak("wrong number of arguments")
        unless $n_arg && ($n_arg % 2 == 0);

    my %opts = @_;
    foreach my $f (qw(url_path pretty_name parentcatid in_nav)) {
        $self->{$f} = delete $opts{$f} if exists $opts{$f};
    }
    my $topcat = undef;
    $topcat = delete $opts{topcat} if exists $opts{topcat};

    my $vertical = undef;
    $vertical = delete $opts{'vertical'} if exists $opts{'vertical'};

    croak("need to supply display name") unless defined $self->{pretty_name};
    croak("need to supply URL path") unless defined $self->{url_path};

    croak("unknown parameters: " . join(", ", keys %opts))
        if %opts;

    my $dbh = LJ::get_db_writer()
        or die "unable to contact global db master to create category";

    # there cannot be an existing row with the same url_path and parentcatid
    my $parentcaturl = '';
    my $parent;
    if ($self->{parentcatid}) {
        $parent = LJ::Browse->load_by_id($self->{parentcatid});
        $parentcaturl = $parent->uri;
    }
    my $existcat = LJ::Browse->load_by_url("/browse" . $parentcaturl . $self->{url_path}, $vertical);
    croak("Category exists already") if $existcat;

    $dbh->do("INSERT INTO category SET url_path=?, pretty_name=?, parentcatid=?, vert_id=?",
             undef, $self->{url_path}, $self->{pretty_name}, $self->{parentcatid} || 0, $vertical ? $vertical->vert_id : 0);
    die $dbh->errstr if $dbh->err;
    my $catid = $dbh->{mysql_insertid};

    my $tm = $self->typemap;
    # Handle children prop
    if ($self->{parentcatid}) {
        $dbh->do("INSERT INTO categoryprop SET catid=?, propid=?, propval=?",
                 undef, $self->{parentcatid}, $tm->class_to_typeid('children'),
                 $catid);
        die $dbh->errstr if $dbh->err;
    }

    # Handle top_children prop
    if ($self->{parentcatid} && $topcat) {
        $dbh->do("INSERT INTO categoryprop SET catid=?, propid=?, propval=?",
                 undef, $self->{parentcatid}, $tm->class_to_typeid('top_children'),
                 $catid);
        die $dbh->errstr if $dbh->err;
    }

    # Handle in_nav prop
    if ($self->{in_nav}) {
        $dbh->do("INSERT INTO categoryprop SET catid=?, propid=?, propval=?",
                 undef, $catid, $tm->class_to_typeid('in_nav'), $self->{in_nav});
        die $dbh->errstr if $dbh->err;
    }

    # Remove data from cache
    if ($parent) {
        $parent->clear_props_memcache;
    } else {
        LJ::MemCache::delete("category_top2");
    }

    $self = $class->new( catid => $catid );
    $self->clear_memcache;
    return $self;
}

sub delete {
    my $self = shift;

    my $dbh = LJ::get_db_writer()
        or die "unable to contact global db master to delete category";

    die "category cannot be deleted while sub-categories exist"
        if ($self->children);

    my $parent;
    $parent = LJ::Browse->load_by_id($self->{parentcatid})
        if ($self->{parentcatid});

    foreach my $table (qw(categoryprop category)) {
        $dbh->do("DELETE FROM $table WHERE catid=?", undef, $self->{catid});
        die $dbh->errstr if $dbh->err;
    }

    # delete category from other category props
    if ($parent) {
        my $tm = $self->typemap;
        $dbh->do("DELETE FROM categoryprop WHERE propval=? AND (propid=? OR propid=?)",
            undef, $self->{catid}, $tm->class_to_typeid('children'),
            $tm->class_to_typeid('top_children'));
        $parent->clear_props_memcache;
        $parent->clear_memcache;
    # if top-level category clear top-level category cache
    } else {
        LJ::MemCache::delete("category_top2");
    }

    # clear memcache of the category and its props
    $self->clear_props_memcache;
    $self->clear_memcache;

    delete $singletons{$self->{catid}};

    return 1;
}

sub load_by_id {
    my $class = shift;
    my $catid = shift;

    my $c = $class->new( catid => $catid );
    $c->preload_rows;

    return $c;
}

sub load_from_uri_cache {
    my $class = shift;
    my $uri = shift;

    my $reqcache = $LJ::REQ_GLOBAL{caturi}->{$uri};
    if ($reqcache) {
        my $c = $class->new( catid => $reqcache->{catid} );
        $c->absorb_row($reqcache);

        return $c;
    }

   # check memcache for data
   my $memval = $LJ::VERTICALS_FORCE_USE_MASTER ? undef : LJ::MemCache::get($class->memkey_caturi($uri));
   if ($memval) {
       my $c = $class->new( catid => $memval->{catid} );
       $c->absorb_row($memval);
       $LJ::REQ_GLOBAL{caturi}->{$uri} = $memval;

       return $c;
   }

   return undef;
}

# returns a browse object of the category with the given URI,
# or undef if a category with that URI doesn't exist
# TODO Have this load all categories found in the full URI
sub load_by_uri {
    my $class = shift;
    my $uri = shift;
    my $full_uri = shift;
    my $parent = shift;
    my $vertical = shift;

    return undef unless ($uri && $full_uri);
    $uri = "/" . $uri unless ($uri =~ /^\/.+/);
    $full_uri = "/" . $full_uri unless ($full_uri =~ /^\/.+/);

    ## Add to memkey full_uri "vertical" if category is in a vertical
    $full_uri = "/vertical" . $full_uri if $vertical;

    my $c = $class->load_from_uri_cache($full_uri);
    return $c if $c;

    # For now use Hash in Config file
    my $dbh = $LJ::VERTICALS_FORCE_USE_MASTER ? LJ::get_db_writer() : LJ::get_db_reader();
    die "unable to contact global db slave to load category"
        unless $dbh;

    my $parent_check = '';
    if ($parent) {
        $parent_check = " AND parentcatid=" . $parent;
    }

    # not in memcache; load from db
    my $vertical_check = $vertical ? " AND vert_id = " . $vertical->vert_id : " AND vert_id = 0";
    my $sth = $dbh->prepare("SELECT * FROM category WHERE url_path = ?" . $parent_check . $vertical_check);
    $sth->execute($uri);
    die $dbh->errstr if $dbh->err;

    if (my $row = $sth->fetchrow_hashref) {
        my $c = $class->new( catid => $row->{catid});
        $c->absorb_row($row);
        $c->set_memcache($full_uri);
        $LJ::REQ_GLOBAL{caturi}->{$full_uri} = $c;

        return $c;
    }

    # name does not exist in db
    return undef;
}

sub load_all {
    my $class    = shift;
    my $vertical = shift;

    my $dbh = $LJ::VERTICALS_FORCE_USE_MASTER ? LJ::get_db_writer() : LJ::get_db_reader();
    die "unable to contact global db slave to load categories"
        unless $dbh;

    my $vert_id = $vertical ? $vertical->vert_id : 0;
    my $where = " WHERE vert_id = $vert_id ";

    my $cats = $LJ::VERTICALS_FORCE_USE_MASTER ? undef : LJ::MemCache::get( $class->memkey_catall(vertical => $vertical) );

    unless ($cats && scalar @$cats) {
        $cats = $dbh->selectall_arrayref(
                "SELECT * FROM category" . $where,
                { Slice => {} }
        );
        die $dbh->errstr if $dbh->err;

        LJ::MemCache::set( $class->memkey_catall(vertical => $vertical) => $cats, 3600 );
    }

    return () unless $cats && scalar @$cats;

    my @categories = ();
    foreach my $cat (@$cats) {
        my $c = $class->load_by_id($cat->{catid});
        $c->set_memcache;

        push @categories, $c;
    }

    return @categories;
}

sub load_top_level {
    my $class = shift;

    my @cats;
    # check memcache for data
    my $memval = $LJ::VERTICALS_FORCE_USE_MASTER ? undef : LJ::MemCache::get("category_top2");
    if ($memval) {
        foreach my $id (@$memval) {
            my $c = $class->new( catid => $id );

            push @cats, $c if $c;
        }

        return sort { lc $a->display_name cmp lc $b->display_name } @cats;
    }

    my $dbh = $LJ::VERTICALS_FORCE_USE_MASTER ? LJ::get_db_writer() : LJ::get_db_reader();
    die "unable to contact global db slave to load categories"
        unless $dbh;

    my $sth = $dbh->prepare("SELECT * FROM category WHERE parentcatid IS NULL");
    $sth->execute;
    die $dbh->errstr if $dbh->err;

    my $catids;
    while (my $row = $sth->fetchrow_hashref) {
        my $c = $class->new( catid => $row->{catid} );
        $c->absorb_row($row);
        $c->set_memcache;

        push @{$catids}, $row->{catid};
        push @cats, $c if $c;
    }
    LJ::MemCache::set("category_top2", $catids, 3600);

    # Subcategories
    #
    # The top page is heavy, lighten its load by preparing all the subcategories
    # for preloading
    $cats[0]->preload_props if $cats[0];
    my %subcats;
    # Get all the subcategories without duplicates
    foreach my $cat (@cats) {
        foreach my $child (@{$cat->{children}}) {
            $subcats{$child} = 1 if $child;
        }
    }
    # create the base object foreach subcat
    foreach my $cat (keys %subcats) {
        my $c = $class->new( catid => $cat );
    }

    return @cats;
}

# Top level categories to appear in navigation
sub load_for_nav {
    my $class = shift;

    my $should_see_nav = LJ::run_hook('remote_should_see_category_nav');
    return () unless !defined $should_see_nav || $should_see_nav;

    if ($LJ::CACHED_CATEGORIES_FOR_NAV){
        return @$LJ::CACHED_CATEGORIES_FOR_NAV;
    }

    my @categories = ();
    foreach my $cat ($class->load_top_level) {
        next unless $cat and $cat->in_nav;
        push @categories, $cat;
    }

    $LJ::CACHED_CATEGORIES_FOR_NAV = [];
    foreach my $c (sort { $a->in_nav cmp $b->in_nav } @categories) {
        push @$LJ::CACHED_CATEGORIES_FOR_NAV, {
            id => $c->catid,
            pretty_name => $c->display_name,
            url => $c->url,
        };
    }
    
    return @$LJ::CACHED_CATEGORIES_FOR_NAV;
}

# given a valid URL for a category, returns the Category object associated with it
# valid URLs can be the special URL defined in config or just /browse/categoryname/
sub load_by_url {
    my $class    = shift;
    my $url      = shift;
    my $vertical = shift;

    $url =~ /^(?:$LJ::SITEROOT)?(\/.+)$/;
    my $path = $1;
    $path =~ s/\/?(?:\?.*)?$//; # trailing slash and any get args
    $path =~ s/tag\/.*$//;      # remove search string
    $path =~ s/\/index\.bml$//; # remove bml page

    my $v = LJ::Vertical->load_by_url ($url);
    if ($v) {
        ## we are in vertical
        my $v_path = $v->uri;
        $path =~ s/$v_path//;
        $path =~ s/vertical/browse/;
    }

    # 4 possibilities:
    # /browse
    # /browse/topcategory/
    # /browse/topcategory/subcategory/[subcategory]
    if ($path =~ /^\/browse\/(.+)$/) {
        my $p = $1;
        my $category;

        # check cache now for full URI
        my $check_uri = "/" . $p;
        $check_uri = "/vertical" . $check_uri if $vertical;
        my $c = $class->load_from_uri_cache($check_uri);
        return $c if $c;

        if ($p) {
            my @cats = split /\//, $p;
            my $parent_id;
            my $partial_uri;
            foreach my $cat (@cats) {
                $partial_uri .= "/" . $cat;
                $category = $class->load_by_uri($cat, $partial_uri, $parent_id, $vertical);
                return undef unless $category;
                $parent_id = $category->catid;
            }
        }
        return $category;
    }

    return undef;
}

#
# Singleton accessors and helper methods
#

sub reset_singletons {
    %singletons = ();
}

sub all_singletons {
    my $class = shift;

    return values %singletons;
}

sub unloaded_singletons {
    my $class = shift;

    return grep { ! $_->{_loaded_row} } $class->all_singletons;
}

sub unloaded_prop_singletons {
    my $class = shift;

    return grep { ! $_->{_loaded_props} } $class->all_singletons;
}


#
# Loaders
#

sub memkey_catall {
    my $class = shift;
    my %args  = @_;

    my $v = $args{'vertical'};

    return [ $v, "catall3:".$v->vert_id ] if $v;
    return "cat:all2";
}

sub memkey_catid {
    my $self = shift;
    my $id = shift;

    return [ $id, "cat3:$id" ] if $id;
    return [ $self->{catid}, "cat3:$self->{catid}" ];
}

sub memkey_catid_props {
    my $self = shift;
    my $id = shift;

    return [ $id, "cat3:props:$id" ] if $id;
    return [ $self->{catid}, "cat3:props:$self->{catid}" ];
}

sub memkey_catid_journals {
    my $self = shift;
    my $id = shift;

    return [ $id, "cat3:journals:$id" ] if $id;
    return [ $self->{catid}, "cat3:journals:$self->{catid}" ];
}

sub memkey_caturi {
    my $self = shift;
    my $uri = shift;

    return "caturi3:$uri";
}

sub set_memcache {
    my $self = shift;
    my $uri = shift;

    return unless $self->{_loaded_row};

    my $val = { map { $_ => $self->{$_} } @cat_cols };
    LJ::MemCache::set( $self->memkey_catid() => $val, 3600 );
    LJ::MemCache::set( $self->memkey_caturi($uri) => $val, 3600 ) if $uri;

    return;
}

sub set_prop_memcache {
    my $self = shift;

    return unless $self->{_loaded_props};

    my $val = { map { $_ => $self->{$_} } @prop_cols };
    LJ::MemCache::set( $self->memkey_catid_props => $val, 3600 );

    return;
}

sub set_journals_memcache {
    my $self = shift;

    return unless $self->{_loaded_journals};

    my $val = { communities => $self->{communities} };
    LJ::MemCache::set( $self->memkey_catid_journals => $val, 3600 );

    return;
}

sub clear_memcache {
    my $self = shift;
    my $uri = $self->uri;

    LJ::MemCache::delete($self->memkey_catid);
    LJ::MemCache::delete($self->memkey_caturi($uri));
    LJ::MemCache::delete($self->memkey_catall(vertical => $self->vertical ? $self->vertical : undef));

    return;
}

sub clear_props_memcache {
    my $self = shift;

    LJ::MemCache::delete($self->memkey_catid_props);
    $self->{_loaded_props} = undef;

    return;
}

sub clear_journals_memcache {
    my $self = shift;

    LJ::MemCache::delete($self->memkey_catid_journals);
    $self->{_loaded_journals} = undef;

    return;
}


sub absorb_row {
    my ($self, $row) = @_;

    $self->{$_} = $row->{$_} foreach @cat_cols;
    $self->{_loaded_row} = 1;

    return 1;
}

sub absorb_prop_row {
    my ($self, $row) = @_;

    $self->{$_} = $row->{$_} foreach @prop_cols;
    $self->{_loaded_props} = 1;

    return 1;
}

sub absorb_journals_row {
    my ($self, $row) = @_;

    $self->{communities} = $row->{communities};
    $self->{_loaded_journals} = 1;

    return 1;
}

sub preload_rows {
    my $self = shift;
    return 1 if $self->{_loaded_row};

    my @to_load = $self->unloaded_singletons;
    my %need = map { $_->{catid} => $_ } @to_load;

    my @mem_keys = map { $_->memkey_catid } @to_load;
    my $memc = $LJ::VERTICALS_FORCE_USE_MASTER ? undef : LJ::MemCache::get_multi(@mem_keys);

    # now which of the objects to load did we get a memcache key for?
    foreach my $obj (@to_load) {
        my $row = $memc->{"cat3:$obj->{catid}"};
        next unless $row;

        $obj->absorb_row($row);

        $obj->preload_children;

        $obj->set_memcache;

        $singletons{$obj->{catid}} = $obj;

        delete $need{$obj->{catid}};
    }

    my @vals = keys %need;
    return 1 unless @vals;

    # now hit the db for what was left
    my $dbh = $LJ::VERTICALS_FORCE_USE_MASTER ? LJ::get_db_writer() : LJ::get_db_reader();
    die "unable to contact global db slave to load category"
        unless $dbh;

    my $bind = LJ::bindstr(@vals);
    my $sth = $dbh->prepare("SELECT * FROM category WHERE catid IN ($bind)");
    $sth->execute(@vals);

    while (my $row = $sth->fetchrow_hashref) {

        # what singleton does this DB row represent?
        my $obj = $need{$row->{catid}};
        $obj = __PACKAGE__->new( catid => $row->{catid}) unless $obj;

        # and update singleton (request cache)
        $obj->absorb_row($row);

        $obj->preload_children;

        # set in memcache
        $obj->set_memcache;

        # update request cache
        $singletons{$row->{catid}} = $obj;

        # and delete from %need for error reporting
        delete $need{$obj->{catid}};

    }

    # weird, catids that we couldn't find in memcache or db?
    $_->{_loaded_row} = 1 foreach values %need;
    #warn "unknown category: " . join(",", keys %need) if %need;

    # now memcache and request cache are both updated, we're done
    return 1;
}

sub preload_children {
    my $self = shift;

    my $dbh = $LJ::VERTICALS_FORCE_USE_MASTER ? LJ::get_db_writer() : LJ::get_db_reader ();

    my $sth = $dbh->prepare ("SELECT * FROM category WHERE parentcatid = ?");
    $sth->execute($self->catid);

    my @children = ();
    while (my $row = $sth->fetchrow_hashref) {
        push @children, $row->{catid};
    }
    $self->{children} = \@children;
}

sub preload_props {
    my $self = shift;

    my @to_load = $self->unloaded_prop_singletons;
    my %need = map { $_->{catid} => $_ } @to_load;

    my @mem_keys = map { $_->memkey_catid_props } @to_load;
    my $memc = $LJ::VERTICALS_FORCE_USE_MASTER ? undef : LJ::MemCache::get_multi(@mem_keys);

    # now which of the objects to load did we get a memcache key for?
    foreach my $obj (@to_load) {
        my $row = $memc->{"cat3:props:$obj->{catid}"};
        next unless $row;

        $obj->absorb_prop_row($row);
        delete $need{$obj->{catid}};
    }

    my @vals = keys %need;
    return 1 unless @vals;

    # now hit the db for what was left
    my $dbh = LJ::get_db_reader()
        or die "unable to contact global db slave to load category";

    my $bind = LJ::bindstr(@vals);
    my $sth = $dbh->prepare("SELECT * FROM categoryprop WHERE catid IN ($bind)");
    $sth->execute(@vals);
    my $tm = $self->typemap;
    my %prow;
    while (my $row = $sth->fetchrow_hashref) {
        my $propname = $tm->typeid_to_class($row->{propid});
        my $propval = $row->{propval};
        my $catid = $row->{catid};
        if ($propname eq 'in_nav') {
            #$self->{$propname} = $propval;
            $prow{$catid}->{$propname} = $propval;
        } else {
            #push @{$self->{$propname}}, $propval;
            push @{$prow{$catid}->{$propname}}, $propval;
        }
    }

    foreach my $catid (keys %prow) {
        # what singleton does this DB row represent?
        my $obj = $need{$catid};

        # and update singleton (request cache)
        $obj->absorb_prop_row($prow{$catid});

        #set in memcache
        $obj->set_prop_memcache;
    }

    # now memcache and request cache are both updated, we're done
    return 1;

}

sub load_props {
    my $self = shift;

    $self->preload_props unless $self->{_loaded_props};

    # check memcache for data
    my $memval = $LJ::VERTICALS_FORCE_USE_MASTER ? undef : LJ::MemCache::get($self->memkey_catid_props());
    if ($memval) {
        $self->absorb_prop_row($memval);
        return;
    }

    my $dbh = LJ::get_db_reader()
        or die "unable to contact global db slave to load category";

    my $sth = $dbh->prepare("SELECT * FROM categoryprop WHERE catid=?");
    $sth->execute($self->catid);
    my $tm = $self->typemap;
    my $prow;
    while (my $row = $sth->fetchrow_hashref) {
        my $propname = $tm->typeid_to_class($row->{propid});
        my $propval = $row->{propval};
        if ($propname eq 'in_nav') {
            #$self->{$propname} = $propval;
            $prow->{$propname} = $propval;
        } else {
            #push @{$self->{$propname}}, $propval;
            push @{$prow->{$propname}}, $propval;
        }
    }
    $self->absorb_prop_row($prow);
    # set in memcache
    $self->set_prop_memcache;

}

sub load_communities {
    my $self = shift;
    my %args = @_;

    # check memcache for data
    my $memval = $LJ::VERTICALS_FORCE_USE_MASTER ? undef : LJ::MemCache::get($self->memkey_catid_journals());
    if ($memval) {
        $self->absorb_journals_row($memval);
        return;
    }

    my $dbh = $LJ::VERTICALS_FORCE_USE_MASTER ? LJ::get_db_writer() : LJ::get_db_reader();
    die "unable to contact global db slave to load category"
        unless $dbh;

    my @cats = ( $self->catid );
    if ($args{'is_need_child'}) {
        ## get communities from child category too. need for Info (Admin Page), for example
        my $vertical = $args{'vertical'};
        my $where = $vertical ? " AND vert_id = " . $vertical->vert_id : '';
        my $sth = $dbh->prepare("SELECT catid FROM category WHERE parentcatid = ? $where");
        $sth->execute($self->catid);
        while (my $row = $sth->fetchrow_hashref) {
            push @cats, $row->{'catid'};
        }
    }

    my @ph = map { '?' } @cats;
    my $sth = $dbh->prepare("SELECT * FROM categoryjournals WHERE catid IN (".(join ",", @ph).")");
    $sth->execute(@cats);
    my $jrow;
    while (my $row = $sth->fetchrow_hashref) {
        push @{$jrow->{communities}}, $row->{journalid};
    }

    $self->absorb_journals_row($jrow);
    $self->set_journals_memcache;
}

#
# Accessors
#
#

sub vertical {
    my $self = shift;

    return undef unless $self->vert_id;

    return LJ::Vertical->load_by_id ($self->vert_id);
}

sub children {
    my $self = shift;
    my %opts = @_;
    my $just_top = $opts{top_children};

    $self->preload_rows unless $self->{_loaded_row};

    # If top_children flag is set, just return the top sub-categories
    my $children = $just_top ?
                   $self->{top_children} :
                   $self->{children};
    my @child_cats = map { __PACKAGE__->load_by_id($_) } @$children;

    return sort { lc $a->display_name cmp lc $b->display_name } @child_cats ? @child_cats : ();
}

sub top_children {
    my $self = shift;

    return $self->children(( top_children => 1 ));
}

sub in_nav {
    my $self = shift;

    $self->load_props unless $self->{_loaded_props};

    return $self->{in_nav};
}

# right now a vertical has only one parent
sub parent {
    my $self = shift;

    return undef unless $self->parentid;
    return LJ::Browse->load_by_id($self->parentid);
}

# returns path of the parent categories
sub path {
    my $c = shift;
    my $p = '';
    my $v = undef;
    if ($c->parent) {
        $p = $c->parent->url_path . $p;
        $p = path($c->parent) . $p;
    } else {
        $v = $c->vert_id ? LJ::Vertical->load_by_id ($c->vert_id) : undef;
    }

    return $v ? $v->uri . $p : $p;
}

# returns full URL for a category
sub url {
    my $self     = shift;

    my $base = $self->vert_id ? "$LJ::SITEROOT/vertical" : "$LJ::SITEROOT/browse";

    return $base . $self->uri . "/";
}

# returns the URI below "/browse"
sub uri {
    my $self = shift;

    return $self->path . $self->url_path;
}

# returns HTML for the page heading
sub title_html {
    my $self = shift;
    my $ret = $self->display_name;

    my $cat = $self->parent;
    while ($cat) {
        $ret = "<a href='" . $cat->url . "'><strong>" .
               $cat->display_name . "</strong></a> &gt; " .
               $ret;
        $cat = $cat->parent;
    }

    return $ret;
}

sub delete_post {
    my $class = shift;
    my %args = @_;

    my $post = $args{'post_id'};
    my ($jitemid, $commid) = $post =~ m#^(\d+)-(\d+)$#; ##

    my $dbh = LJ::get_db_reader ();
    my $res = $dbh->do ("UPDATE category_recent_posts SET is_deleted = 1 WHERE journalid = ? AND jitemid = ?", undef, $commid, $jitemid);

    ## Need to delete linked keywords from key_map
    $res = $dbh->do ("DELETE FROM vertical_keymap WHERE journalid = ? AND jitemid = ?", undef, $commid, $jitemid);

    return 1;
}

sub count_posts {
    my $class  = shift;
    my %args   = @_;

    my $comms    = $args{'comms'};
    my $limit    = $args{'page_size'};
    my $search   = $args{'search_str'};
    my $vertical = $args{'vertical'};

    my $comm_list = join ",", @$comms;
    my $dbh = LJ::get_db_reader();
    if ($comm_list) {
        my $count = $dbh->selectrow_arrayref (
            "SELECT count(journalid) FROM category_recent_posts 
                WHERE journalid IN ($comm_list) 
                    AND is_deleted = 0 
                ORDER BY timecreate DESC",
            { Slice => {} }
        );
        return $count->[0];
    }

    return 0;
}

sub search_posts {
    my $class  = shift;
    my %args   = @_;

    my $comms    = $args{'comms'};
    my $limit    = $args{'page_size'};
    my $search   = $args{'search_str'};
    my $vertical = $args{'vertical'};

    ## remove trailing spaces
    $search =~ s/^\s+(.*?)$/$1/;
    $search =~ s/(.*?)\s+?$/$1/;

    my @entries = ();
    my $comm_list = join ",", @$comms;
    my $dbh = LJ::get_db_reader();
    if (bytes::length($search)) {
        my $where = $vertical ? " AND km.vert_id = " . $vertical->vert_id . " AND " : "";
        my @search_words = map { "SELECT '%".$_."%' AS cond" } split /\s+/, $search;
        $search = join " UNION ALL ", @search_words;
        my $posts = $dbh->selectall_arrayref (
            "SELECT journalid, jitemid
                FROM vertical_keymap km
                WHERE 
                $where
                kw_id IN (
                    SELECT kw_id
                        FROM vertical_keywords kw
                        WHERE EXISTS (
                            SELECT 1 
                                FROM (
                                    $search
                                ) c 
                            WHERE kw.keyword LIKE cond
                        )
                    )",
            { Slice => {} }
        ) || [];
        my @found_posts = ();
        foreach my $post (@$posts) {
            my $post_ids = $dbh->selectall_arrayref (
                "SELECT journalid, jitemid 
                    FROM category_recent_posts 
                    WHERE journalid IN ($comm_list) 
                        AND journalid = ? 
                        AND jitemid = ? 
                        AND is_deleted = 0 
                    ORDER BY timecreate DESC 
                    LIMIT $limit", 
                { Slice => {} }, $post->{journalid}, $post->{jitemid}
            );
            push @found_posts, @$post_ids if $post_ids;
        }
        @entries =
            grep {
                ## Filter off suspended entries, deleted communities, suspended posters
                if ($_ && $_->valid) {
                    my $poster = $_->poster;
                    $_->is_suspended || $_->journal->is_deleted || ($poster && $poster->is_suspended) ? 0 : 1;
                } else {
                    0;
                }
            }
            map { LJ::Entry->new ($_->{journalid}, jitemid => $_->{jitemid}) }      ## Create LJ::Entry object
            grep { $_->{journalid} }                                                ## remove SEO posts
            @found_posts;
    } else {
        if ($comm_list) {
            my $post_ids = $dbh->selectall_arrayref (
                "SELECT * FROM category_recent_posts 
                    WHERE journalid IN ($comm_list) 
                        AND is_deleted = 0 
                    ORDER BY timecreate DESC 
                    LIMIT $limit", 
                { Slice => {} }
            );
            @entries =
                grep {
                    ## Filter off suspended entries, deleted communities, suspended posters
                    if ($_ && $_->valid) {
                        my $poster = $_->poster;
                        $_->is_suspended || $_->journal->is_deleted || ($poster && $poster->is_suspended) ? 0 : 1;
                    } else {
                        0;
                    }
                }
                map { LJ::Entry->new ($_->{journalid}, jitemid => $_->{jitemid}) }
                @$post_ids;
        }
    }
    return @entries;
}

# Return a list of communities found in a category
# Returns User objects
sub communities {
    my $self = shift;
    my %args = @_;

    $self->load_communities ( %args ) unless ($args{'is_need_child'} && $self->{_loaded_journals});

    my $comms = $self->{communities};
    my $cusers = LJ::load_userids(@$comms);

    # This sort code is equivalent to this:
    #
    #   return
    #       sort { lc $a->username cmp lc $b->username }
    #           grep { $_ }
    #               (values %$cusers);
    #
    # but in code below for each of cusers we get function lc( $_->username() ) only once.
    # For some of 200 elements of array lc( $_->username() ) was called
    # up to 20-25 times during sort.

    return                                  # 6. return result
        map {$_->[1]}                       # 5. get a cargo from temporary containers
            sort {$a->[0] cmp $b->[0]}      # 4. sort it by a sort-keys
                map {[lc $_->username, $_]} # 3. create list of [ sort-key, cargo-to-sort ]
                    grep { $_ }             # 2. remove empties from it, we don't want to die() on $_->username
                        (values %$cusers);  # 1. get communities list
}

# Returns a list of top/featured communities
# Returns userids
sub top_communities {
    my $self = shift;
    $self->load_props unless $self->{_loaded_props};

    my $comms = $self->{'featured'};
    return $comms ? @$comms : undef;
}

# Takes a list of userids and adds them to a category
sub add_community {
    my $self = shift;
    my $uid  = shift;
    my $opts = shift;

    my $tags             = $opts->{'tags'};
    my $not_need_approve = $opts->{'not_need_approve'} || 0;

    my $dbh = LJ::get_db_writer()
        or die "unable to contact global db master to create category";

    ## Add community to category
    my $res = $dbh->do("REPLACE INTO categoryjournals VALUES (?,?)", undef,
             $self->catid, $uid);
    die $dbh->errstr if $dbh->err;

    LJ::Browse->add_approved_community( comm  => LJ::want_user($uid),
                                        mod_u => LJ::get_remote(),
                                        catid => $self->catid, )
        unless $not_need_approve;

    $self->clear_journals_memcache;

    ## Add tags for added community if vertical selected
    my $v = $self->vertical;
    $v->save_tags (is_seo => 0, tags => [ map { { tag => $_, journalid => $uid } } @$tags ] ) if $v;

    return 1;
}

# Takes a list of userids and removes them from a category
sub remove_communities {
    my $self = shift;
    my @uids = @_;

    my $dbh = LJ::get_db_writer()
        or die "unable to contact global db master to create category";

    foreach my $uid (@uids) {
        $dbh->do("DELETE FROM categoryjournals WHERE catid = ? AND journalid = ?", undef,
                 $self->catid, $uid);
        die $dbh->errstr if $dbh->err;

        LJ::Browse->remove_community( comm  => LJ::want_user($uid),
                                      mod_u => LJ::get_remote(),
                                      catid => $self->catid,
                                    );
    }

    $self->clear_journals_memcache;

    return 1;
}

## Return "path" for selected category
## catobj -> par_catobj -> par_par_catobj -> etc... (array)
## Param: arrayref to save "path"
sub get_parent_path {
    my $c = shift;
    my $cat_path = shift;

    my $parent = $c->parent;

    push @$cat_path, $c;

    return 0 unless $parent;

    return $parent->get_parent_path ($cat_path);
}

sub build_select_tree {
    my ($class, $parent, $cats_ref, $selected_cat, $text, $i, $n) = @_;

    $i ||= 0;

    return $text unless $cats_ref;

    my @categories = @$cats_ref;
    @categories = grep { ($_->parent == $parent) } grep { $_ } @categories;

    return $text unless scalar @categories;

    my @path_ = ();
    $selected_cat->get_parent_path (\@path_) if $selected_cat;
    my %path = map { $_->catid => 1 } @path_;
    my @sel_cat = grep { $path{$_->catid} } @categories;

    my @caturls = map { { text => $_->{pretty_name}, value => $_->catid } } @categories;
    @caturls = sort { $a->{text} cmp $b->{text} } @caturls;

    $text .= "<tr><td>Category</td>";
    $text .= "<td>" . LJ::html_select({
                name => "catid$i\_$n", style => "width:100%;",
                selected => $sel_cat[0] ? $sel_cat[0]->catid : '' },
                { text => LJ::Lang::ml('vertical.admin.add_category.btn'),
                value => '' },
                @caturls
    ) . "</td>";
    $text .= "<td>" . LJ::html_submit('select_c', 'Select Category') . "</td>";
    $text .= "</tr>";

    if ($sel_cat[0]) {
        my @children = $sel_cat[0]->children;
        $text = $class->build_select_tree($sel_cat[0], \@children, $selected_cat, $text, ++$i, $n);
    }

    return $text;
}

# get the typemap for categoryprop
sub typemap {
    my $self = shift;

    return LJ::Typemap->new(
        table       => 'categoryproplist',
        classfield  => 'name',
        idfield     => 'propid',
    );
}

sub _get_set {
    my $self = shift;
    my $key  = shift;

    if ($_[0]) { # setter case
        # TODO enable setting values
        
        my $val = shift;

        my $dbh = LJ::get_db_writer()
            or die "unable to contact global db master to load category";

        $dbh->do("UPDATE category SET $key=? WHERE catid=?",
                 undef, $val, $self->{catid});

        die $dbh->errstr if $dbh->err;

        $self->clear_memcache;

        return $self->{$key} = $val;
    }

    # getter case
    $self->preload_rows unless $self->{_loaded_row};

    return $self->{$key};
}

sub catid          { shift->_get_set('catid')                 }
sub display_name   { shift->_get_set('pretty_name')           }
sub url_path       { shift->_get_set('url_path')              }
sub parentid       { shift->_get_set('parentcatid' => $_[0] ) }
sub vert_id        { shift->_get_set('vert_id' => $_[0] )     }


# Community Moderation

sub submit_community {
    my $class = shift;
    my %opts = @_;

    my $c = delete $opts{comm} || undef;
    my $u = delete $opts{submitter} || undef;
    my $catid = delete $opts{catid} || undef;
    my $status = delete $opts{status} || 'P';

    # need a journal user object
    croak "invalid user object[c]" unless LJ::isu($c);
    # need a user object for submitter
    croak "invalid user object[u]" unless LJ::isu($u);
    # need a category
    my $cat = undef;
    $cat = LJ::Browse->load_by_id($catid) if defined $catid;

    die "invalid category" unless $cat;

    return if ($class->_is_community_in_pending($c->userid, $cat->catid));

    my $dbh = LJ::get_db_writer()
        or die "unable to contact global db master to create category";

    $dbh->do("REPLACE INTO categoryjournals_pending (jid, submitid, catid," .
             " status, modid, lastupdate) VALUES " .
             "(?,?,?,?, NULL, UNIX_TIMESTAMP())", undef, $c->userid,
             $u->userid, $cat->catid, $status);
    die $dbh->errstr if $dbh->err;

    return;
}

sub add_approved_community {
    my $class = shift;
    my %opts = @_;

    my $c = delete $opts{comm} || undef;
    my $mod = delete $opts{mod_u} || undef;
    my $catid = delete $opts{catid} || undef;
    my $status = delete $opts{status} || 'A';

    # need a journal user object
    croak "invalid user object[c]" unless LJ::isu($c);
    # need a user object for moderator
    croak "invalid user object[u]" unless LJ::isu($mod);

    # need a category
    my $cat = undef;
    $cat = LJ::Browse->load_by_id($catid) if defined $catid;

    die "invalid category" unless $cat;

    my $dbh = LJ::get_db_writer()
        or die "unable to contact global db master to create category";

    $dbh->do("REPLACE INTO categoryjournals_pending (jid, submitid, catid," .
             " status, modid, lastupdate) VALUES " .
             "(?, NULL,?,?,?, UNIX_TIMESTAMP())", undef, $c->userid,
             $cat->catid, $status, $mod->userid );
    die $dbh->errstr if $dbh->err;

    return;
}

sub remove_community {
    my $class = shift;
    my %opts = @_;

    my $c = delete $opts{comm} || undef;
    my $u = delete $opts{submitter} || undef;
    my $mod = delete $opts{mod_u} || undef;
    my $catid = delete $opts{catid} || undef;
    my $pendid = delete $opts{pendid} || undef;

    croak "invalid user object[c]" unless LJ::isu($c);
    croak "invalid user object[u]" unless (LJ::isu($u) || LJ::isu($mod));

    # need a category if we don't have pendid
    my $cat;
    unless ($pendid) {
        croak "need category ID" unless $catid;
        $cat = LJ::Browse->load_by_id($catid);
        die "invalid category" unless $cat;
    }

    my $dbh = LJ::get_db_writer()
        or die "unable to contact global db master to create category";

    # Null out the value for submitid or modid, depending on who did the last
    # update.
    if ($u && $pendid) {
        $dbh->do("UPDATE categoryjournals_pending SET status=?, " .
                 "submitid=?, modid=NULL, lastupdate=UNIX_TIMESTAMP() " .
                 "WHERE pendid=?", undef,
                 'R', $u->userid, $pendid);
    } elsif ($mod && $cat && $c) {
        $dbh->do("UPDATE categoryjournals_pending SET status=?, " .
                 "submitid=NULL, modid=?, lastupdate=UNIX_TIMESTAMP() " .
                 "WHERE catid=? AND jid=? AND status IN ('P','A')", undef,
                 'R', $mod->userid, $cat->catid, $c->userid);
    } else {
        croak "missing arguments";
    }
    die $dbh->errstr if $dbh->err;

    return;
}

sub deny_communities {
    my $class = shift;
    my @pendids = @_;

    my $mod_u = LJ::get_remote();
    die "invalid user" unless $mod_u;

    my $dbh = LJ::get_db_writer()
        or die "unable to contact global db master to create category";

    $dbh->do("UPDATE categoryjournals_pending SET status=?, " .
             "modid=?, lastupdate=UNIX_TIMESTAMP() WHERE pendid IN(".join(",", @pendids).")", undef,
             'D', $mod_u->userid);
    die $dbh->errstr if $dbh->err;

    return;
}

sub approve_communities {
    my $self = shift;
    my @ids = @_;

    my $mod_u = LJ::get_remote();
    die "invalid user" unless $mod_u;

    my $dbh = LJ::get_db_writer()
        or die "unable to contact global db master to create category";

    my @pendids;
    foreach my $id (@ids) {
        $dbh->do("REPLACE INTO categoryjournals VALUES (?,?)", undef,
                 $self->catid, @{$id}[0]);
        die $dbh->errstr if $dbh->err;

        push @pendids, @{$id}[1];
    }

    # Update moderation table
    $dbh->do("UPDATE categoryjournals_pending SET status=?, " .
             "modid=?, lastupdate=UNIX_TIMESTAMP() WHERE pendid IN(".join(",", @pendids).")", undef,
             'A', $mod_u->userid);
    die $dbh->errstr if $dbh->err;

    $self->clear_journals_memcache;

    return 1;
}



# Status can be: (P)ending, (A)pproved, (D)enied, (R)emoved
sub get_communities {
    my $class = shift;
    my %opts = @_;
    my $c = $opts{comm};
    my @status = @{$opts{status}};

    # Default to Pending status
    my $status_sql = "'P'";
    # Use status argument if passed in
    if (@status) {
        $status_sql = join("','", @status);
        $status_sql = "'" . $status_sql . "'";
    }

    # allow read from master, used when listings were just changed
    my $dbr = $opts{use_master} ? LJ::get_db_writer() : LJ::get_db_reader()
        or die "unable to contact global db reader to get category submissions";
    my $sth;

    if ($c) {
        $sth = $dbr->prepare("SELECT * FROM categoryjournals_pending where " .
                                "jid=? AND status IN ($status_sql)");
        $sth->execute($c->userid);
    } else {
        $sth = $dbr->prepare("SELECT * FROM categoryjournals_pending where " .
                                "status IN ($status_sql)");
        $sth->execute();
    }
    die $dbr->errstr if $dbr->err;

    my @listings;
    while (my $row = $sth->fetchrow_hashref) {
        push @listings, { pendid     => $row->{pendid},
                          jid        => $row->{jid},
                          submitid   => $row->{submitid},
                          catid      => $row->{catid},
                          status     => $row->{status},
                          lastupdate => $row->{lastupdate},
                          modid      => $row->{modid},
                         };

    }

    return @listings;
}

sub get_submitted_communities {
    my $class = shift;
    my %opts = @_;
    my @status = ('P','A','D');
    $opts{status} = \@status;

    return $class->get_communities(%opts);
}

sub get_pending_communities {
    my $class = shift;
    my %opts = @_;
    my @status = ('P');
    $opts{status} = \@status;

    return $class->get_communities(%opts);
}

# is a community already in a category in the moderation table
sub _is_community_in_pending {
    my $class = shift;
    my ($jid, $catid) = @_;

    die "missing argument" unless ($jid && $catid);

    my $dbh = LJ::get_db_writer()
        or die "unable to contact global db master to create category";

    my $sth = $dbh->prepare("SELECT pendid FROM categoryjournals_pending " .
                    "WHERE status IN ('P','A','D') AND jid=? AND catid=?");
    $sth->execute($jid, $catid);
    die $dbh->errstr if $dbh->err;

    while (my $row = $sth->fetchrow_hashref) {
        return 1 if $row;
    }

    return 0;
}

1;
