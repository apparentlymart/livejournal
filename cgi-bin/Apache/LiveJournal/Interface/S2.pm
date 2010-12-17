#!/usr/bin/perl
#

package Apache::LiveJournal::Interface::S2;

use strict;
use MIME::Base64 ();

sub load { 1 }

sub handler {

    my $meth = LJ::Request->method();
    my %GET = LJ::Request->args();
    my $uri = LJ::Request->uri();
    my $id;
    if ($uri =~ m!^/interface/s2/(\d+)$!) {
        $id = $1 + 0;
    } else {
        return LJ::Request::NOT_FOUND;
    }

    my $lay = LJ::S2::load_layer($id);
    return error(404, 'Layer not found', "There is no layer with id $id at this site")
        unless $lay;

    LJ::auth_digest(LJ::Request->r);
    my $u = LJ::get_remote();
    unless ($u) {
        # Tell the client how it can authenticate
        # use digest authorization.

        LJ::Request->send_http_header("text/plain; charset=utf-8");
        LJ::Request->print("Unauthorized\nYou must send your $LJ::SITENAME username and password or a valid session cookie\n");

        return LJ::Request::OK;
    }

    my $dbr = LJ::get_db_reader();

    my $lu = LJ::load_userid($lay->{'userid'});

    return error(500, "Error", "Unable to find layer owner.")
        unless $lu;

    if ($meth eq 'GET') {

        return error(403, "Forbidden", "You are not authorized to retrieve this layer")
            unless $lu->{'user'} eq 'system' || ($u && $u->can_manage($lu));

        my $layerinfo = {};
        LJ::S2::load_layer_info($layerinfo, [ $id ]);
        my $srcview = exists $layerinfo->{$id}->{'source_viewable'} ?
            $layerinfo->{$id}->{'source_viewable'} : 1;

        # Disallow retrieval of protected system layers
        return error(403, "Forbidden", "The requested layer is restricted")
            if $lu->{'user'} eq 'system' && ! $srcview;

        my $s2code = LJ::S2::load_layer_source($id);

        LJ::Request->send_http_header("application/x-danga-s2-layer");
        LJ::Request->print($s2code);

    }
    elsif ($meth eq 'PUT') {

        return error(403, "Forbidden", "You are not authorized to edit this layer")
            unless $u && $u->can_manage($lu);

        return error(403, "Forbidden", "Your account type is not allowed to edit layers")
            unless LJ::get_cap($u, "s2styles");

        # Read in the entity body to get the source
        my $len = LJ::Request->header_in("Content-length")+0;

        return error(400, "Bad Request", "Supply S2 layer code in the request entity body and set Content-length")
            unless $len;

        return error(415, "Bad Media Type", "Request body must be of type application/x-danga-s2-layer")
            unless lc(LJ::Request->header_in("Content-type")) eq 'application/x-danga-s2-layer';

        my $s2code;
        LJ::Request->read($s2code, $len);

        my $error = "";
        LJ::S2::layer_compile($lay, \$error, { 's2ref' => \$s2code });

        if ($error) {
            error(500, "Layer Compile Error", "An error was encountered while compiling the layer.");

            ## Strip any absolute paths
            $error =~ s/LJ::.+//s;
            $error =~ s!, .+?(src/s2|cgi-bin)/!, !g;

            print $error;
            return LJ::Request::OK;
        }
        else {
            LJ::Request->status_line("201 Compiled and Saved");
            LJ::Request->header_out("Location" => "$LJ::SITEROOT/interface/s2/$id");
            LJ::Request->send_http_header("text/plain; charset=utf-8");
            LJ::Request->print("Compiled and Saved\nThe layer was uploaded successfully.\n");
        }
    }
    else {
        #  Return 'method not allowed' so that we can add methods in future
        # and clients will get a sensible error from old servers.
        return error(405, 'Method Not Allowed', 'Only GET and PUT are supported for this resource');
    }
}

sub error {
    my ($code, $string, $long) = @_;

    LJ::Request->status_line("$code $string");
    LJ::Request->send_http_header("text/plain; charset=utf-8");
    LJ::Request->print("$string\n$long\n");

    # Tell Apache OK so it won't try to handle the error
    return LJ::Request::OK;
}

1;
