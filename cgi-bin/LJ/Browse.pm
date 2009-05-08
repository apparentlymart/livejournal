
# LiveJournal Browse object.
#

package LJ::Browse;
use strict;
use Carp qw/ croak cluck /;

my %singletons = (); # catid => singleton
my @cat_cols = qw( catid pretty_name url_path parentcatid );
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

    my $self = bless {
        # arguments
        catid     => delete $opts{catid},
    };

    croak("need to supply catid") unless defined $self->{catid};

    croak("unknown parameters: " . join(", ", keys %opts))
        if %opts;

    # do we have a singleton for this category?
    {
        my $catid = $self->{catid};
        return $singletons{$catid} if exists $singletons{$catid};

        # save the singleton if it doesn't exist
        $singletons{$catid} = $self;
    }

    return $self;
}
*instance = \&new;

# TODO Complete and test this method
sub create {
    my $class = shift;
    my $self  = bless {};

    my $n_arg   = scalar @_;
    croak("wrong number of arguments")
        unless $n_arg && ($n_arg % 2 == 0);

    my %opts = @_;

    $self->{url_path} = delete $opts{url_path};

    croak("need to supply URL path") unless defined $self->{url_path};

    croak("unknown parameters: " . join(", ", keys %opts))
        if %opts;

    my $dbh = LJ::get_db_writer()
        or die "unable to contact global db master to create category";

    $dbh->do("INSERT INTO category SET url_path=?",
             undef, $self->{url_path});
    die $dbh->errstr if $dbh->err;

    return $class->new( catid => $dbh->{mysql_insertid} );
}

sub load_by_id {
    my $class = shift;
    my $catid = shift;

    my $c = $class->new( catid => $catid );

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
   my $memval = LJ::MemCache::get($class->memkey_caturi($uri));
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

    return undef unless ($uri && $full_uri);
    $uri = "/" . $uri unless ($uri =~ /^\/.+/);
    $full_uri = "/" . $full_uri unless ($full_uri =~ /^\/.+/);

    my $c = $class->load_from_uri_cache($full_uri);
    return $c if $c;

    # For now use Hash in Config file
    my $dbh = LJ::get_db_reader()
        or die "unable to contact global db slave to load category";

    my $parent_check = '';
    if ($parent) {
        $parent_check = " AND parentcatid=" . $parent;
    }

    # not in memcache; load from db
    my $sth = $dbh->prepare("SELECT * FROM category WHERE url_path = ?" . $parent_check);
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
    my $class = shift;

    my $dbh = LJ::get_db_reader()
        or die "unable to contact global db slave to load categories";

    my $sth = $dbh->prepare("SELECT * FROM category");
    $sth->execute;
    die $dbh->errstr if $dbh->err;

    my @categories;
    while (my $row = $sth->fetchrow_hashref) {
        my $c = $class->new( catid => $row->{catid} );
        $c->absorb_row($row);
        $c->set_memcache;

        push @categories, $c;
    }

    return @categories;
}

sub load_top_level {
    my $class = shift;

    my @cats;
    # check memcache for data
    my $memval = LJ::MemCache::get("category_top");
    if ($memval) {
        foreach my $id (@$memval) {
            my $c = $class->new( catid => $id );

            push @cats, $c if $c;
        }

        return sort { lc $a->display_name cmp lc $b->display_name } @cats;
    }

    my $dbh = LJ::get_db_reader()
        or die "unable to contact global db slave to load categories";

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
    LJ::MemCache::set("category_top", $catids);

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

# TODO Not yet tested
sub load_for_nav {
    my $class = shift;

    my $should_see_nav = LJ::run_hook('remote_should_see_category_nav');
    return () unless !defined $should_see_nav || $should_see_nav;

    if ($LJ::CACHED_CATEGORIES_FOR_NAV){
        return @$LJ::CACHED_CATEGORIES_FOR_NAV;
    }

    my @categories;
    foreach my $cat ($class->load_top_level) {
        next unless $cat->in_nav;
        push @categories, $cat if $cat;
    }

    foreach my $c (sort { $a->in_nav cmp $b->in_nav } @categories) {
        push @$LJ::CACHED_CATEGORIES_FOR_NAV, {
            id => $c->catid,
            pretty_name => $c->display_name,
            url => $c->url_path,
        };
    }

    return @$LJ::CACHED_CATEGORIES_FOR_NAV;
}

# given a valid URL for a category, returns the Category object associated with it
# valid URLs can be the special URL defined in config or just /browse/categoryname/
sub load_by_url {
    my $class = shift;
    my $url = shift;

    $url =~ /^(?:$LJ::SITEROOT)?(\/.+)$/;
    my $path = $1;
    $path =~ s/\/?(?:\?.*)?$//; # remove trailing slash and any get args
    $path =~ s/\/index\.bml$//; # remove bml page

    # 3 possibilities:
    # /browse
    # /browse/topcategory/
    # /browse/topcategory/subcategory/[subcategory]
    if ($path =~ /^\/browse\/(.+)$/) {
        my $p = $1;
        my $category;

        # check cache now for full URI
        my $c = $class->load_from_uri_cache("/" . $p);
        return $c if $c;

        if ($p) {
            my @cats = split /\//, $p;
            my $parent_id;
            my $partial_uri;
            foreach my $cat (@cats) {
                $partial_uri .= "/" . $cat;
                $category = $class->load_by_uri($cat, $partial_uri, $parent_id);
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

sub memkey_catid {
    my $self = shift;
    my $id = shift;

    return [ $id, "cat:$id" ] if $id;
    return [ $self->{catid}, "cat:$self->{catid}" ];
}

sub memkey_catid_props {
    my $self = shift;
    my $id = shift;

    return [ $id, "cat:props:$id" ] if $id;
    return [ $self->{catid}, "cat:props:$self->{catid}" ];
}

sub memkey_catid_journals {
    my $self = shift;
    my $id = shift;

    return [ $id, "cat:journals:$id" ] if $id;
    return [ $self->{catid}, "cat:journals:$self->{catid}" ];
}

sub memkey_caturi {
    my $self = shift;
    my $uri = shift;

    return "caturi:$uri";
}

sub set_memcache {
    my $self = shift;
    my $uri = shift;

    return unless $self->{_loaded_row};

    my $val = { map { $_ => $self->{$_} } @cat_cols };
    LJ::MemCache::set( $self->memkey_catid => $val );
    LJ::MemCache::set( $self->memkey_caturi($uri) => $val ) if $uri;

    return;
}

sub set_prop_memcache {
    my $self = shift;

    return unless $self->{_loaded_props};

    my $val = { map { $_ => $self->{$_} } @prop_cols };
    LJ::MemCache::set( $self->memkey_catid_props => $val );

    return;
}

sub set_journals_memcache {
    my $self = shift;

    return unless $self->{_loaded_journals};

    my $val = { communities => $self->{communities} };
    LJ::MemCache::set( $self->memkey_catid_journals => $val );

    return;
}

sub clear_memcache {
    my $self = shift;

    LJ::MemCache::delete($self->memkey_catid);

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
    my $memc = LJ::MemCache::get_multi(@mem_keys);

    # now which of the objects to load did we get a memcache key for?
    foreach my $obj (@to_load) {
        my $row = $memc->{"cat:$obj->{catid}"};
        next unless $row;

        $obj->absorb_row($row);
        delete $need{$obj->{catid}};
    }

    my @vals = keys %need;
    return 1 unless @vals;

    # now hit the db for what was left
    my $dbh = LJ::get_db_reader()
        or die "unable to contact global db slave to load category";

    my $bind = LJ::bindstr(@vals);
    my $sth = $dbh->prepare("SELECT * FROM category WHERE catid IN ($bind)");
    $sth->execute(@vals);

    while (my $row = $sth->fetchrow_hashref) {

        # what singleton does this DB row represent?
        my $obj = $need{$row->{catid}};
        $obj = __PACKAGE__->new( catid => $row->{catid}) unless $obj;

        # and update singleton (request cache)
        $obj->absorb_row($row);

        # set in memcache
        $obj->set_memcache;

        # and delete from %need for error reporting
        delete $need{$obj->{catid}};

    }

    # weird, catids that we couldn't find in memcache or db?
    warn "unknown category: " . join(",", keys %need) if %need;

    # now memcache and request cache are both updated, we're done
    return 1;
}

sub preload_props {
    my $self = shift;

    my @to_load = $self->unloaded_prop_singletons;
    my %need = map { $_->{catid} => $_ } @to_load;

    my @mem_keys = map { $_->memkey_catid_props } @to_load;
    my $memc = LJ::MemCache::get_multi(@mem_keys);

    # now which of the objects to load did we get a memcache key for?
    foreach my $obj (@to_load) {
        my $row = $memc->{"cat:props:$obj->{catid}"};
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
    my $memval = LJ::MemCache::get($self->memkey_catid_props());
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

    # check memcache for data
    my $memval = LJ::MemCache::get($self->memkey_catid_journals());
    if ($memval) {
        $self->absorb_journals_row($memval);
        return;
    }

    my $dbh = LJ::get_db_reader()
        or die "unable to contact global db slave to load category";

    my $sth = $dbh->prepare("SELECT * FROM categoryjournals WHERE catid=?");
    $sth->execute($self->catid);
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
sub children {
    my $self = shift;
    my %opts = @_;
    my $just_top = $opts{top_children};

    $self->load_props unless $self->{_loaded_props};

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
    if ($c->parent) {
        $p = $c->parent->url_path . $p;
        $p = path($c->parent) . $p;
    }
    return $p;
}

# returns full URL for a category
sub url {
    my $self = shift;

    my $base = "$LJ::SITEROOT/browse";
    my $parent = "";

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

# Return a list of communities found in a category
# Returns User objects
sub communities {
    my $self = shift;
    $self->load_communities unless $self->{_loaded_journals};

    my $comms = $self->{communities};
    my $cusers = LJ::load_userids(@$comms);

    return sort { lc $a->username cmp lc $b->username } (values %$cusers);
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
sub add_communities {
    my $self = shift;
    my @uids = @_;

    my $dbh = LJ::get_db_writer()
        or die "unable to contact global db master to create category";

    foreach my $uid (@uids) {
        $dbh->do("REPLACE INTO categoryjournals VALUES (?,?)", undef,
                 $self->catid, $uid);
        die $dbh->errstr if $dbh->err;
    }

    $self->clear_journals_memcache;

    return 1;
}

# Takes a list of userids and removes them from a category
sub remove_communities {
    my $self = shift;
    my @uids = @_;

    my $dbh = LJ::get_db_writer()
        or die "unable to contact global db master to create category";

    foreach my $uid (@uids) {
        $dbh->do("DELETE FROM categoryjournals WHERE catid=? AND journalid IN (?)", undef,
                 $self->catid, @uids);
        die $dbh->errstr if $dbh->err;
    }

    $self->clear_journals_memcache;

    return 1;
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

    if (@_) { # setter case
        # TODO enable setting values
        return;
        my $val = shift;

        my $dbh = LJ::get_db_writer()
            or die "unable to contact global db master to load category";

        $dbh->do("UPDATE category SET $key=? WHERE catid=?",
                 undef, $self->{catid}, $val);
        die $dbh->errstr if $dbh->err;

        $self->clear_memcache;

        return $self->{$key} = $val;
    }

    # getter case
    $self->preload_rows unless $self->{_loaded_row};

    return $self->{$key};
}

sub catid          { shift->_get_set('catid')              }
sub display_name   { shift->_get_set('pretty_name')        }
sub url_path       { shift->_get_set('url_path')           }
sub parentid       { shift->_get_set('parentcatid')        }

1;
