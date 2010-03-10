# AtomAPI support for LJ

package Apache::LiveJournal::Interface::ElsewhereInfo;

use strict;
use lib "$ENV{LJHOME}/cgi-bin";
use LJ::JSON;

# for Class::Autouse (so callers can 'ping' this method to lazy-load this class)
sub load { 1 }

sub should_handle {

    # FIXME: trust specific consumers of this data?
    return $LJ::IS_DEV_SERVER ? 1 : 0;
}

# this routine accepts the apache request handle, performs
# authentication, calls the appropriate method handler, and
# prints the response.
sub handle {
    shift if $_[0] eq __PACKAGE__;
    #my $r = shift;

    my %args = LJ::Request->args;

    # should we handle this request due according to access rules?
    unless (should_handle()) {
        return respond(403, "Forbidden");
    }

    # find what node_u we're dealing with
    my $u;
    if (my $id = $args{id}) {
        $u = LJ::load_userid($id);
        return respond(404, "Invalid id: $id")
            unless $u;
    } elsif (my $node = $args{ident}) {
        $u = LJ::load_user($node);
        return respond(404, "Invalid ident: $node")
            unless $u;
    } else {
        return respond(400, "Must specify 'id' or 'ident'");
    }

    # find what node type we're dealing with
    my $node_type;
    my $node_ident = $u->user;
    if ($u->is_community || $u->is_shared || $u->is_news) {
        $node_type = 'group';
    } elsif ($u->is_person) {
        $node_type = 'person';
    } elsif ($u->is_identity) {
        $node_type = 'openid';
        $node_ident = $u->url; # should be identity type O
    } else {
        return respond(403, "Node is neither person, group, nor openid: " . $u->user . " (" . $u->id . ")");
    }

    # response hash to pass to JSON
    my %resp = (
                node_id    => $u->id,
                node_ident => $node_ident,
                node_type  => $node_type,
                );

    if (my $digest = $u->validated_mbox_sha1sum) {
        $resp{mbox_sha1sum} = $digest;
    }

    if (my $url = $u->url) {
        $resp{claimed_urls} = [ $url, 
                                # FIXME: collect more sites!
                              ];
    }

    # is the caller requesting edges for the requested node?
    my $want_edges = $args{want_edges} ? 1 : 0;

    if ($want_edges) {
        $resp{edges_in}  = [ map { $_ } $u->friendof_uids ];
        $resp{edges_out} = [ map { $_ } $u->friend_uids   ];
    }

    respond(200, LJ::JSON->to_json(\%resp));

    return LJ::Request::OK;
}

sub respond {
    my ($status, $body) = @_;

    my %msgs = (
                200 => 'OK',
                400 => 'Bad Request',
                403 => 'Forbidden',
                404 => 'Not Found',
                500 => 'Server Error',
                );

    LJ::Request->status_line(join(" ", grep { length } $status, $msgs{$status}));
    LJ::Request->content_type('text/html');#'application/json');
    LJ::Request->send_http_header();
    LJ::Request->print($body);

    return LJ::Request::OK;
};

1;
