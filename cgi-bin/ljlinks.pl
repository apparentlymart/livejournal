#!/usr/bin/perl

#
# Functions for lists of links created by users for display in their journals
#

use strict;

package LJ::Links;

# linkobj structure:
#
# $linkobj = [
#    { 'title'     => 'link title',
#      'url'       => 'http://www.somesite.com',
#      'children'  => [ ... ],
#    },
#    { ... },
#    { ... },
# ];

sub load_linkobj
{
    my ($u, $use_master) = @_;
    return unless LJ::isu($u);

    # check memcache for linkobj
    my $memkey = [$u->{'userid'}, "linkobj:$u->{'userid'}"];
    my $linkobj = LJ::MemCache::get($memkey);
    return $linkobj if defined $linkobj;

    # didn't find anything in memcache
    $linkobj = [];

    {
        # not in memcache, need to build one from db
        my $db = $use_master ? LJ::get_cluster_def_reader($u) : LJ::get_cluster_reader($u);

        local $" = ",";
        my $sth = $db->prepare("SELECT ordernum, parentnum, title, url " .
                               "FROM links WHERE journalid=?");
        $sth->execute($u->{'userid'});
        push @$linkobj, $_ while $_ = $sth->fetchrow_hashref;
    }

    # sort in perl-space
    @$linkobj = sort { $a->{'ordernum'} <=> $b->{'ordernum'} } @$linkobj;

    # fix up the data structure
    foreach (@$linkobj) {

        # TODO: build child relationships
        #       and store in $_->{'children'}

        # ordernum/parentnum are only exposed via the 
        # array structure, delete them here
        delete $_->{'ordernum'};
        delete $_->{'parentnum'};
    }

    # set linkobj in memcache
    LJ::MemCache::set($memkey, $linkobj);

    return $linkobj;
}

sub save_linkobj
{
    my ($u, $linkobj) = @_;
    return undef unless LJ::isu($u) && ref $linkobj eq 'ARRAY' && $u->writer;

    # delete old links, we'll rebuild them shortly
    $u->do("DELETE FROM links WHERE journalid=?", undef, $u->{'userid'});

    # only save allowed number of links
    my $numlinks = @$linkobj;
    my $caplinks = LJ::get_cap($u, "userlinks");
    $numlinks = $caplinks if $numlinks > $caplinks;

    # build insert query
    my (@bind, @vals);
    foreach my $ct (1..$numlinks) {
        my $it = $linkobj->[$ct-1];

        # journalid, ordernum, parentnum, url, title
        push @bind, "(?,?,?,?,?)";
        push @vals, ($u->{'userid'}, $ct, 0, $it->{'url'}, $it->{'title'});
    }

    # invalidate memcache
    my $memkey = [$u->{'userid'}, "linkobj:$u->{'userid'}"];
    LJ::MemCache::delete($memkey);

    # insert into database
    {
        local $" = ",";
        return $u->do("INSERT INTO links (journalid, ordernum, parentnum, url, title) " .
                      "VALUES @bind", undef, @vals);
    }
}

sub make_linkobj_from_form
{
    my ($u, $post) = @_;
    return unless LJ::isu($u) && ref $post eq 'HASH';

    my $linkobj = [];

    # remove leading and trailing spaces
    my $stripspaces = sub {
        my $str = shift;
        $str =~ s/^\s*//;
        $str =~ s/\s*$//;
        return $str;
    };

    # find number of links allowed
    my $numlinks = $post->{'numlinks'};
    my $caplinks = LJ::get_cap($u, "userlinks");
    $numlinks = $caplinks if $numlinks > $caplinks;

    foreach my $num (sort { $post->{"link_${a}_ordernum"} <=>
                            $post->{"link_${b}_ordernum"} } (1..$numlinks)) {

        # title is required
        my $title = $post->{"link_${num}_title"};
        $title = $stripspaces->($title);
        next unless $title;

        my $url = $post->{"link_${num}_url"};
        $url = $stripspaces->($url);

        # smartly add http:// to url unless they are just inserting a blank line
        if ($url && $title ne '-') {
            $url = LJ::CleanHTML::canonical_url($url);
        }

        # build link object element
        $post->{"link_${num}_url"} = $url;
        push @$linkobj, { 'title' => $title, 'url' => $url };

        # TODO: build child relationships
        #       push @{$linkobj->[$parentnum-1]->{'children'}}, $myself
    }

    return $linkobj;
}

# this form is in the lib so we can put it in /customize/ directly later
sub make_modify_form
{
    my ($u, $linkobj, $post) = @_;
    return unless LJ::isu($u) && ref $linkobj eq 'ARRAY' && ref $post eq 'HASH';

    # TODO: parentnum column is not implemented yet
    #   -- it should link to the ordernum of the parent link
    #      so we can support nesting/categories of links

    my $LINK_MIN   = 5;   # how many do they start with ?
    my $LINK_MORE  = 5;   # how many do they get when they click "more"
    my $ORDER_STEP = 10;  # step order numbers by 

    # how many link inputs to show?
    my $showlinks = $post->{'numlinks'} || @$linkobj;
    my $caplinks = LJ::get_cap($u, "userlinks");
    $showlinks += $LINK_MORE if $post->{'action:morelinks'};
    $showlinks = $LINK_MIN if $showlinks < $LINK_MIN;
    $showlinks = $caplinks if $showlinks > $caplinks;

    my $ret = "<table border='0' cellspacing='3' cellpadding='0'>";
    $ret .= "<tr><th>Order</th><th>Title/URL</th><td>&nbsp;</td></tr>";

    foreach my $ct (1..$showlinks) {
        my $it = $linkobj->[$ct-1] || {};

        $ret .= "<tr><td>";
        $ret .= LJ::html_text({ 'name'  => "link_${ct}_ordernum",
                                'size' => 2,
                                'value' => $ct * $ORDER_STEP });
        $ret .= "</td><td>";
        
        $ret .= LJ::html_text({ 'name'  => "link_${ct}_title",
                                'size'  => 50, 'maxlength' => 255,
                                'value' => $it->{'title'} });
        $ret .= "</td><td>&nbsp;</td></tr>";
        
        $ret .= "<tr><td>&nbsp;</td><td>";
        $ret .= LJ::html_text({ 'name'  => "link_${ct}_url",
                                'size'  => 50, 'maxlength' => 255,
                                'value' => $it->{'url'} || "http://"});
        
        # more button at the end of the last line, but only if
        # they are allowed more than the minimum
        $ret .= "<td>&nbsp;";
        if ($ct >= $showlinks && $caplinks > $LINK_MIN) {
            $ret .= LJ::html_submit('action:morelinks', "More &rarr;",
                                    { 'disabled' => $ct >= $caplinks,
                                      'noescape' => 1 });
        }
        if ($ct >= $caplinks) {
            $ret .= LJ::CProd->inline($u, inline => 'Links');
        }
        $ret .= "</td></tr>";

        # blank line unless this is the last line
        $ret .= "<tr><td colspan='3'>&nbsp;</td></tr>"
            unless $ct >= $showlinks;
    }
    
    # submit button
    $ret .= "<tr><td colspan='2' align='center'>";
    $ret .= LJ::html_hidden('numlinks' => $showlinks);
    $ret .= LJ::html_submit('action:savelinks', "Save Changes");
    $ret .= "</td><td>&nbsp;</td></tr>";
    
    $ret .= "</table>";
    
    return $ret;
}

1;
