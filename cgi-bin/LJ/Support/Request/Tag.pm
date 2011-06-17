# LJ::Support::Request::Tag module: backend interface for tags assigned to
# Support requests.
#
# From the database standpoint, a Support tag is an object assigned to a
# specific Support cat which has a defined name; entities of this type are
# stored in the "supporttag" DB table. This object has a many-to-many
# relationship with Support requests; the "supporttagmap" table serves the
# purpose of organizing that relationship.
#
# Names for Support tags are normalized in a specific way:
#
#  * leading and trailing whitespace is removed
#  * all the other whitespace is collapsed
#  * uppercase letters are converted to lowercase; specific code is added
#    to ensure that this works for non-EBCDIC characters (e.g. Cyrillic)
#
# On development servers, when a request tag name is requested, indication
# of what supportcat that tag belongs to is appended to the name itself;
# the normalize function checks if that is the case and specifically strips
# such indication when it normalizes the name.
#
# Related modules:
#
#  * LJ::Support (supportlib.pl)
#
# Related user-facing pages:
#
#  * /support/help.bml
#  * /support/see_request.bml
#  * /support/append_request.bml
#  * /support/manage_tags.bml
#
# Related privileges:
#
#  * supportviewinternal
#    Allows for seeing tags in all categories one can see at all, as well as
#    changing tags in all requests in those categories, provided that no new
#    tags are added in those categories.
#  * supporthelp
#    Allows for seeing tags in all categories one can see at all, as well as
#    changing tags in all requests in those categories. This also allows for
#    adding new tags.
#  * siteadmin:manage-support-tags
#    Allows for removing existing tags in all categories one can see.
#  * siteadmin:manage-support-tags/$cat
#    Allows for removing existing tags in the $cat category.

package LJ::Support::Request::Tag;

use strict;

use Encode qw(encode decode);

# get_requests_tags(): fetches information about which tags are assigned
# to the given requests; returns:
# { $spid1 => [ $sptagid1, $sptagid2 ], $spid2 => [ $sptagid3, $sptagid4 ] }
# you can use tag_id_to_name() later if you need names
# this doesn't check if the tags are assigned to the correct cat
sub get_requests_tags {
    my @spids = @_;

    return {} unless @spids;

    @spids = map { int $_ } @spids;
    my $spids = join ',', @spids;

    my $dbr = LJ::get_db_reader();
    my $rows = $dbr->selectall_arrayref(
        "SELECT spid, sptagid FROM supporttagmap WHERE spid IN ($spids)",
        { Slice => {} }
    );

    my %ret = map { $_ => [] } @spids;

    foreach my $row (@$rows) {
        push @{$ret{$row->{'spid'}}}, $row->{'sptagid'};
    }

    return \%ret;
}

# get_request_tags(): fetches information about which tags are assigned
# to the given request; returns:
# [ $sptagid1, $sptagid2 ]
# you can use tag_id_to_name() later if you need names
# this doesn't check if the tags are assigned to the correct cat
sub get_request_tags {
    my ($spid) = @_;

    my $tags = get_requests_tags($spid);

    return $tags->{$spid};
}

# set_request_tags(): sets tags for a given request
# calling format:
# set_request_tags($spid, $sptagid1, $sptag2, ...)
# this doesn't check if the tags are assigned to the correct cat
sub set_request_tags {
    my ($spid, @tagids) = @_;

    $spid = $spid + 0;

    @tagids = grep { $_ } @tagids;
    my $curtagids = LJ::Support::Request::Tag::get_request_tags($spid);
    my @curtagids = $curtagids ? @$curtagids : ();

    my %tagids = map { $_ => 1 } @tagids;
    my %curtagids = map { $_ => 1 } @curtagids;

    my @tags_add = grep { !$curtagids{$_} } @tagids;
    my @tags_remove = grep { !$tagids{$_} } @curtagids;

    my $dbh = LJ::get_db_writer();

    if (@tags_remove) {
        @tags_remove = map { int $_ } @tags_remove;
        my $tags_remove = join( ',', map { int $_ } @tags_remove );
        $dbh->do(
            qq{
                DELETE FROM supporttagmap
                WHERE spid=? AND sptagid IN ($tags_remove)
            },
            undef, $spid
        );
    }

    if (@tags_add) {
        @tags_add = map { int $_ } @tags_add;
        my @tags_add_exprs = map { "($spid,$_)" } @tags_add;
        my $tags_add_exprs = join ',', @tags_add_exprs;

        $dbh->do(
            qq{
                INSERT INTO supporttagmap (spid, sptagid)
                VALUES $tags_add_exprs
            }
        );
    }

    return { added => \@tags_add, removed => \@tags_remove };
}

# normalize_tag_name(): performs normalization of a given tag name
# see the comment on the beginning of the module for information on what
# "normalization" here means
# it doesn't work in place, so you might need to call it like:
# $name = normalize_tag_name($name);
sub normalize_tag_name {
    my ($name) = @_;

    $name =~ s/\(.*?\)//g if $LJ::IS_DEV_SERVER;

    # cleanup
    $name =~ s/,//g; # tag separator
    $name =~ s/(^\s+|\s+$)//g; # starting or trailing whitespace
    $name =~ s/\s+/ /g; # excessive whitespace

    return undef unless $name;

    # this hack is to get Perl actually perform lc() on a Unicode string
    # you're welcome to fix it if you know a better way ;)
    $name = decode('utf8', $name);
    $name = lc($name);
    $name = encode('utf8', $name);

    # leave only the first 50 characters - it's the DB schema limit
    $name =~ s/^(.{50}).*$/$1/;

    return $name;
}

# tag_name_to_id(): gets an sptagid for a given name and spcatid,
# performing an insert if necessary.
# calling format:
# tag_name_to_id($name, $spcatid [,$nocreate])
# passing optional $nocreate that evaluates to true restricts the procedure
# from performing an insert. you might want to use that if $remote is not
# allowed to add new tags to a category but is allowed to use existing ones.
# this performs tag name normalization to ensure that DB doesn't store
# non-normalized tag names.
sub tag_name_to_id {
    my ($name, $spcatid, $nocreate) = @_;

    $name = normalize_tag_name($name);

    return undef unless $name;

    # in the best case, we can use the reader only
    my $dbr = LJ::get_db_reader();
    my $tag = $dbr->selectrow_hashref(
        'SELECT sptagid FROM supporttag WHERE name=? AND spcatid=?', undef,
        $name, $spcatid
    );
    return $tag->{'sptagid'} if $tag;

    return undef if $nocreate;

    # alright, let's create it if it doesn't exist
    my $dbh = LJ::get_db_writer();
    $dbh->do(
        'INSERT INTO supporttag SET name=?, spcatid=?', undef,
        $name, $spcatid
    );

    return $dbh->{'mysql_insertid'};
}

# tag_id_to_name(): gets a name assigned to a given tag
# takes an sptagid and converts it to a string with the name
# for ease of debugging, on dev servers it:
#  * doesn't use memcache
#  * appends the support cat shortcode to the name
sub tag_id_to_name {
    my ($id) = @_;

    unless ($LJ::IS_DEV_SERVER) {
        my $cached = LJ::MemCache::get("sptag:$id");
        return $cached if $cached;
    }

    my $dbr = LJ::get_db_reader();
    my $tag = $dbr->selectrow_hashref(
        'SELECT name, spcatid FROM supporttag WHERE sptagid=?', undef, $id
    );

    return undef unless $tag;
    LJ::MemCache::set("sptagid:$id", $tag->{'name'}, 86400) unless ($LJ::IS_DEV_SERVER);
    my $name = $tag->{'name'};
    if ($LJ::IS_DEV_SERVER) {
        my $spcats = LJ::Support::load_cats($tag->{'spcatid'});
        $name .= ' ('.$spcats->{$tag->{'spcatid'}}->{'catkey'}.')';
    }

    return $name;
}

# get_cats_tag_names(): gets sorted and unique tag names that exist
# in the given cats.
# calling format:
# get_cats_tag_names($spcatid1, $spcatid2, ...)
# returns an array of names.
sub get_cats_tag_names {
    my (@spcatids) = @_;

    @spcatids = map { $_ + 0 } @spcatids;
    my $spcatids = join(',', @spcatids);
    return () if $spcatids eq '';

    my $dbr = LJ::get_db_reader();
    my $res = $dbr->selectcol_arrayref(
        'SELECT DISTINCT name FROM supporttag '.
        'WHERE spcatid IN ('.$spcatids.') '.
        'ORDER BY name'
    );

    return @$res;
}

# get_cats_tags(): gets tag ids that exist in the given cats
# calling format:
# get_cats_tags($spcatid1, $spcatid2, ...)
# returns an array of sptagids.
sub get_cats_tags {
    my (@spcatids) = @_;

    @spcatids = map { $_ + 0 } @spcatids;
    my $spcatids = join(',', @spcatids);
    my $dbr = LJ::get_db_reader();
    my $res = $dbr->selectcol_arrayref(
        'SELECT sptagid FROM supporttag '.
        'WHERE spcatid IN ('.$spcatids.') '
    );

    return @$res;
}

# drop_tags(): removes all information about the given tag from the database
# optionally, it can restrict tag deletion to the given cats
# calling format:
# drop_tags([$sptagid1, $sptagid2, ...], [$spcatid1, $spcatid2, ...])
sub drop_tags {
    my ($sptagids, $spcatids) = @_;

    my @sptagids = map { $_ + 0 } @$sptagids;

    my $dbh = LJ::get_db_writer();

    my $sptagids_cond;
    if ($spcatids) {
        my @spcatids = map { $_ + 0 } @$spcatids;
        my $spcatids_cond = join(',', @spcatids);

        $sptagids_cond = join(',', @sptagids);
        @sptagids = @{$dbh->selectcol_arrayref(
            "SELECT sptagid FROM supporttag WHERE ".
            "sptagid IN ($sptagids_cond) AND spcatid IN ($spcatids_cond)"
        )};
    }

    $sptagids_cond = join(',', @sptagids);
    $dbh->do("DELETE FROM supporttag WHERE sptagid IN ($sptagids_cond)");
    $dbh->do("DELETE FROM supporttagmap WHERE sptagid IN ($sptagids_cond)");
}

1;