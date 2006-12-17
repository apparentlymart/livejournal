package LJ::ExternalSite;
use strict;
use warnings;

# instance method.  given a URL (or partial URL), returns
# true (in the form of a canonical URL for this user) if
# this URL is owned by this site, or returns false otherwise.
sub matches_url {
    my ($self, $url) = @_;
    return 0;
}

# class or instance method.
# 16x16 image to be shown for the LJ user head for this user.
# unless overridden, external users are just (as default), OpenID-looking users
sub icon_url {
    return "$LJ::IMGPREFIX/openid-profile.gif";
}

1;
