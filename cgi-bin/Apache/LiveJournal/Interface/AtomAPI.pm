# AtomAPI support for LJ

package Apache::LiveJournal::Interface::AtomAPI;

use strict;
use Apache::Constants qw(:common);
use lib "$ENV{'LJHOME'}/cgi-bin";
require 'parsefeed.pl';

sub respond {
    my ($r, $status, $body, $content_type) = @_;
    $content_type ||= "text/html";
    $r->status_line($status);
    $r->content_type($content_type);
    $r->send_http_header();
    $r->print($body);
    return OK;
};

sub handle_post {
    my ($r, $remote, $u, $opts) = @_;

    # read the content
    my $buff;
    $r->read($buff, $r->header_in("Content-length"));

    # try parsing it
    my ($feed, $error, $items) = LJ::ParseFeed::parse_feed($buff, 'atom');
    return respond($r, "400 Bad Request", "<h1>Bad Request</h1><p>Could not parse the entry due to following error returned by the XML Atom parser: <b>$error</b></p>")
        if $error;

    my $newitem = $items->[0];

    # remove the SvUTF8 flag. See same code in synsuck.pl for
    # an explanation
    foreach my $attr (qw(subject text link)) {
        $newitem->{$attr} = pack('C*', unpack('C*', $newitem->{$attr}));
    }

    # on post, the entry must NOT include an id

    if ($newitem->{'id'}) {
        return respond($r, "400 Bad Request", "<h1>Bad Request</h1><p>Must not include an <b>&lt;id&gt;</b> field in a new entry.</p>");
    }

    # build a post event request.
    my $req = {
        'usejournal' => ($remote->{'userid'} != $u->{'userid'}) ?
            $u->{'user'}:undef,
        'ver' => 1,
        'username' => $u->{'user'},
        'lineendings' => 'unix',
        'subject' => $newitem->{'subject'},
        'event' => $newitem->{'text'},
        'props' => {},
        'security' => 'public'
    };

    # build eventtime 
    if ($newitem->{'time'} && 
        $newitem->{'time'} =~ m!^(\d\d\d\d)-(\d\d)-(\d\d) (\d\d):(\d\d)!) {
        $req->{'year'} = $1;
        $req->{'mon'}  = $2;
        $req->{'day'}  = $3;
        $req->{'hour'} = $4;
        $req->{'min'}  = $5;
    };
        
    my $err;
    my $res = LJ::Protocol::do_request("postevent", 
                                       $req, \$err, {'nopassword'=>1});
    
    if ($err) {
        my $errstr = LJ::Protocol::error_message($err);
        return respond($r, "500 Server Error", "<h1>Server Error</h1><p>Unable to post new entry. Protocol error: <b>$errstr</b>.</p>");
    }

    my $new_link = "$LJ::SITEROOT/interface/atomapi/$u->{'user'}/edit/$res->{'itemid'}";
    $r->header_out("Location", $new_link);
    return respond($r, "303 See Other", "<h1>Success</h1><p>The entry was successfully posted and is available for editing at $new_link .</p1>");
}

sub handle_edit {
    my ($r, $remote, $u, $opts) = @_;

    my $method = $opts->{'method'};

    # first, try to load the item and fail if it's not there
    my $jitemid = $opts->{'param'};
    my $req = {
        'usejournal' => ($remote->{'userid'} != $u->{'userid'}) ?
            $u->{'user'} : undef,
         'ver' => 1,
         'username' => $u->{'user'},
         'selecttype' => 'one',
         'itemid' => $jitemid,
    };

    my $err;
    my $olditem = LJ::Protocol::do_request("getevents", 
                                           $req, \$err, {'nopassword'=>1});
    
    if ($err) {
        my $errstr = LJ::Protocol::error_message($err);
        return respond($r, "404 Not Found", "<h1>Not Found</h1><p>Unable to retrieve the item requested for editing. Protocol error: <b>$errstr</b>.</p>");
    }
    $olditem = $olditem->{'events'}->[0];

    if ($method eq "GET") {
        # return an AtomEntry for this item
        # use the interface between make_feed and create_view_atom in
        # ljfeed.pl

        # get the log2 row (need logtime for createtime)
        my $row = LJ::get_log2_row($u, $jitemid) ||
            return respond($r, "404 Not Found", "<h1>Not Found</h1><p>Could not load the original entry.</p>");

        # we need to put into $item: itemid, ditemid, subject, event, 
        # createtime, eventtime, modtime
        
        my $ctime = LJ::mysqldate_to_time($row->{'logtime'}, 1);

        my $item = {
            'itemid'     => $olditem->{'itemid'},
            'ditemid'    => $olditem->{'itemid'}*256 + $olditem->{'anum'},
            'eventtime'  => LJ::alldatepart_s2($row->{'eventtime'}),
            'createtime' => $ctime,
            'modtime'    => $olditem->{'props'}->{'revtime'} || $ctime,
            'subject'    => LJ::exml($olditem->{'subject'}),
            'event'      => LJ::exml($olditem->{'event'}),
        };

        my $ret = LJ::Feed::create_view_atom({
            'u'=>$u  }, $u, 
                                             {'noheader'=>1,
                                              'saycharset'=>"utf-8",
                                              'noheader'=>1,
                                              'apilinks'=>1,
                                          }, [$item]);

        return respond($r, "200 OK", $ret, "text/xml; charset='utf-8'");
    }

    if ($method eq "PUT") {
        # read the content
        my $buff;
        $r->read($buff, $r->header_in("Content-length"));

        # try parsing it
        my ($feed, $error, $items) = LJ::ParseFeed::parse_feed($buff, 'atom');
        return respond($r, "400 Bad Request", "<h1>Bad Request</h1><p>Could not parse the entry due to following error returned by the XML Atom parser: <b>$error</b></p>")
            if $error;

        my $newitem = $items->[0];

        # remove the SvUTF8 flag. See same code in synsuck.pl for
        # an explanation
        foreach my $attr (qw(subject text link)) {
            $newitem->{$attr} = pack('C*', unpack('C*', $newitem->{$attr}));
        }

        # the AtomEntry must include <id> which must match the one we sent
        # on GET
        unless ($newitem->{'id'} =~ m!atom1:$u->{'user'}:(\d+)$! &&
                $1 == $olditem->{'itemid'}*256 + $olditem->{'anum'}) {
            return respond($r, "400 Bad Request", "<h1>Bad Request</h1><p>Incorrect <b>&lt;id&gt;</b> field in this request.</p>");
        }

        # build an edit event request. Preserve fields that aren't being
        # changed by this item (perhaps the AtomEntry isn't carrying the
        # complete information).
        
        $req = {
            'usejournal' => ($remote->{'userid'} != $u->{'userid'}) ?
                $u->{'user'}:undef,
            'ver' => 1,
            'username' => $u->{'user'},
            'itemid' => $jitemid,
            'lineendings' => 'unix',
            'subject' => $newitem->{'subject'} || $olditem->{'subject'},
            'event' => $newitem->{'text'} || $olditem->{'event'},
            'props' => $olditem->{'props'},
            'security' => $olditem->{'security'},
            'allowmask' => $olditem->{'allowmask'},
        };

        # update eventtime if the request has it. Otherwise it'll be
        # preserved by ljprotocol.pl
        if ($newitem->{'time'} && 
            $newitem->{'time'} =~ m!^(\d\d\d\d)-(\d\d)-(\d\d) (\d\d):(\d\d)!) {
            $req->{'year'} = $1;
            $req->{'mon'}  = $2;
            $req->{'day'}  = $3;
            $req->{'hour'} = $4;
            $req->{'min'}  = $5;
        };
        
        $err = undef;
        my $res = LJ::Protocol::do_request("editevent", 
                                           $req, \$err, {'nopassword'=>1});
    
        if ($err) {
            my $errstr = LJ::Protocol::error_message($err);
            return respond($r, "500 Server Error", "<h1>Server Error</h1><p>Unable to update entry. Protocol error: <b>$errstr</b>.</p>");
        }

        return respond($r, "200 OK", "<h1>Success</h1><p>The entry was successfully updated.</p>");
    }

    if ($method eq "DELETE") {
        
        # build an edit event request to delete the entry.
        
        $req = {
            'usejournal' => ($remote->{'userid'} != $u->{'userid'}) ?
                $u->{'user'}:undef,
            'ver' => 1,
            'username' => $u->{'user'},
            'itemid' => $jitemid,
            'lineendings' => 'unix',
            'event' => '',
        };

        $err = undef;
        my $res = LJ::Protocol::do_request("editevent", 
                                           $req, \$err, {'nopassword'=>1});
    
        if ($err) {
            my $errstr = LJ::Protocol::error_message($err);
            return respond($r, "500 Server Error", "<h1>Server Error</h1><p>Unable to delete entry. Protocol error: <b>$errstr</b>.</p>");
        }

        return respond($r, "200 OK", "<h1>Success</h1><p>Entry successfully deleted.</p>");
    }
    
}

sub handle_feed {
    my ($r, $remote, $u, $opts) = @_;

    # simulate a call to the S1 data view creator, with appropriate
    # options
    
    my %op = ('pathextra' => "/atom",
              'saycharset'=> "utf-8",
              'apilinks'  => 1,
              );
    my $ret = LJ::Feed::make_feed($r, $u, $remote, \%op);

    unless (defined $ret) {
        if ($op{'redir'}) {
            # this happens if the account was renamed or a syn account.
            # the redir URL is wrong because ljfeed.pl is too 
            # dataview-specific. Since this is an admin interface, we can
            # just fail.
            return respond ($r, "404 Not Found", "<h1>Not Found</h1><p>The account <b>$u->{'user'} </b> is of a wrong type and does not allow AtomAPI administration.</h1>");
        }
        if ($op{'handler_return'}) {
            # this could be a conditional GET shortcut, honor it
            $r->status($op{'handler_return'});
            return OK;
        }
        # should never get here
        return respond ($r, "404 Not Found", "<h1>Not Found</h1><p>Unknown error.</p>");
    }

    # everything's fine, return the XML body with the correct content type
    return respond($r, "200 OK", $ret, $op{'contenttype'});

}

# this routine accepts the apache request handle, performs
# authentication, calls the appropriate method handler, and
# prints the response.

sub handle {
    my $r = shift;
    my $uri = $r->uri;


    # break the uri down: /interface/atomapi/<username>/<verb>[/<number>]
    my ($user, $action, $param);

    if ($uri =~ m!^/interface/atomapi/([^/]+)/(\w+)/?(.+)?$!) {
        ($user, $action, $param) = ($1, $2, $3);
    } else {
        return respond($r, "400 Bad Request", "<h1>Bad Request</h1><p>The URI for this AtomAPI request is given in an incorrect format.</p>");
    }

    $user = LJ::canonical_username($user);
    my $u = LJ::load_user($user);
    
    return respond($r, "404 Unknown User", "<h1>Unknown User</h1><p>There is no user <b>$user</b> at $LJ::SITENAME.</p>")
        unless $u;

    my $method = $r->method;

    $action eq 'feed' or $action eq 'edit' or $action eq 'post' or
        return respond($r, "400 Bad Request", "<h1>Bad Request</h1><p>Unknown URI scheme: /interface/atomapi/$user/<b>$action</b> .</p>");

    unless (($action eq 'feed' and $method eq 'GET') or
            ($action eq 'post' and $method eq 'POST') or
            ($action eq 'edit' and 
             {'GET'=>1,'PUT'=>1,'DELETE'=>1}->{$method})) {
        return respond($r, "400 Bad Request", "<h1>Bad Request</h1><p>URI scheme /interface/atomapi/$user/<b>$action</b> is incompatible with request method <b>$method</b>.</p>");
    }

    if (($action ne 'edit' && $param) or
        ($action eq 'edit' && $param !~ m!^\d+$!)) {
        return respond($r, "400 Bad Request", "<h1>Bad Request</h1><p>Either the URI lacks a required parameter, or its format is improper.</p>");
    }

    # let's authenticate
    my $res = LJ::auth_digest($r);
    unless ($res) {
        $r->content_type("text/html");
        $r->send_http_header();
        $r->print("<h1>401 Authentication Failed</h1><p>Digest authentication failed for this AtomAPI request.</p>");
        return OK;
    }

    # we've authenticated successfully and remote is set. But can remote
    # manage the requested account?

    my $remote = LJ::get_remote();
    unless (LJ::can_manage($remote, $u)) {
        return respond($r, "403 Forbidden", "<h1>Access Forbidden</h1><p>User <b>$remote->{'user'}</b> has no administrative access to account <b>$user</b>.</p>");
    }

    # handle the requested action
    my $opts = {'action'=>$action,
                'method'=>$method,
                'param'=>$param};

    {'feed'=>\&handle_feed, 'post'=>\&handle_post,
     'edit'=>\&handle_edit}->{$action}->
         ($r, $remote, $u, $opts);

    return OK;
}

1;
