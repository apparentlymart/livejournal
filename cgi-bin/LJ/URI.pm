# This is a module for handling URIs
use strict;

package LJ::URI;

use LJ::Pay::Wallet;

# Takes an Apache a path to BML filename relative to htdocs
sub bml_handler {
    my ($class, $filename) = @_;

    LJ::Request->handler("perl-script");
    LJ::Request->notes("bml_filename" => "$LJ::HOME/htdocs/$filename");
    LJ::Request->push_handlers(PerlHandler => \&Apache::BML::handler);
    return LJ::Request::OK;
}

# Handle a URI. Returns response if success, undef if not handled
# Takes URI and Apache $r
sub handle {
    my ($class, $uri) = @_;

    return undef unless $uri;

    # handle "RPC" URIs
    if (my ($rpc) = $uri =~ m!^.*/__rpc_(\w+)$!) {
        my $bml_handler_path = $LJ::AJAX_URI_MAP{$rpc};

        return LJ::URI->bml_handler($bml_handler_path) if $bml_handler_path;
    }

    # handle normal URI mappings
    if (my $bml_file = $LJ::URI_MAP{$uri}) {
        return LJ::URI->bml_handler($bml_file);
    }

    # handle URI redirects
    if (my $url = $LJ::URI_REDIRECT{$uri}) {
        return Apache::LiveJournal::redir($url, LJ::Request::HTTP_MOVED_TEMPORARILY);
    }

    my $args = LJ::Request->args;
    my $full_uri = $uri;
    $full_uri .= "?$args" if $args;

    ########
    #
    # Now we handle verticals as subproject of community directory via LJ::Browse
    #
    ########
=head
    # handle vertical URLs
    if (my $v = LJ::Vertical->load_by_url($full_uri)) {
        if ($v->is_canonical_url($full_uri)) {
            my $args_for_redir = $args ? "?$args" : '';
            return Apache::LiveJournal::redir($v->url . $args_for_redir);
        } else {
            return LJ::URI->bml_handler("explore/index.bml");
        }
    }
=cut

    if (my $c = LJ::Vertical->load_by_url($full_uri)) {
        return LJ::URI->bml_handler("browse/index.bml");
    }

    if ($uri =~ m!^/statistics(/.*|$)! or $uri =~ m!^/ratings(/.*|$)! and not $uri eq '/ratings/admin.bml') {
        return LJ::URI->bml_handler("statistics/index.bml");
    }

    return undef;
}

1;
