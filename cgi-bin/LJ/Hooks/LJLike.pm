package LJ::Hooks::LJLike;
use strict;
use warnings;

LJ::register_hook( 'insert_html_after_body_open' => sub {
    my ($after_body_open_ref) = @_;

    return if $LJ::REQ_GLOBAL{'sitewide_resources_ljlike_google'}++;

    my $language = LJ::Lang::get_remote_lang();

    my $locale = LJ::lang_to_locale($language);
    $locale =~ s/_.*//g;

    $$after_body_open_ref .=  qq{<script type="text/javascript" src="http://apis.google.com/js/plusone.js">{lang: '$locale'}</script>};
} );

LJ::register_hook( 'insert_html_after_body_open' => sub {
    my ($after_body_open_ref) = @_;

    my $language = LJ::Lang::get_remote_lang();
    my $locale = LJ::lang_to_locale($language);

    $$after_body_open_ref .= qq{<div id="fb-root"></div><script src="http://connect.facebook.net/$locale/all.js#appId=214181831945836&amp;xfbml=1"></script>};
} );

LJ::register_hook( 'sitewide_resources' => sub {
    return unless $LJ::VKONTAKTE_CONF;
    return if $LJ::REQ_GLOBAL{'sitewide_resources_ljlike_vkontakte'}++;

    my $api_id = $LJ::VKONTAKTE_CONF->{'client_id'};

    LJ::include_raw( 'html' => qq{<script type="text/javascript" src="http://userapi.com/js/api/openapi.js?31"></script>}
                             . qq{<script type="text/javascript">VK.init({apiId: $api_id, onlyWidgets: true});</script>} );
} );

1;
