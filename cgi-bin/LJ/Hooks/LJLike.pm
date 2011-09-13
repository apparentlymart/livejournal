package LJ::Hooks::LJLike;
use strict;
use warnings;

LJ::register_hook( 'insert_html_after_body_open' => sub {
    my ($after_body_open_ref) = @_;

    return if $LJ::REQ_GLOBAL{'sitewide_resources_ljlike_google'}++;

    my $language = LJ::Lang::get_remote_lang();

    my $locale = LJ::lang_to_locale($language);
    $locale =~ s/_.*//g;

    $$after_body_open_ref .=  qq{<script type="text/javascript">LiveJournal.injectScript('http://apis.google.com/js/plusone.js',{text:"{lang: '$locale'}"});</script>};
} );

LJ::register_hook( 'insert_html_after_body_open' => sub {
    my ($after_body_open_ref) = @_;

    my $language = LJ::Lang::get_remote_lang();
    my $locale = LJ::lang_to_locale($language);

    $$after_body_open_ref .= qq{<div id="fb-root"></div>
        <script type="text/javascript">
          window.fbAsyncInit = function() {
            FB.init({appId: '214181831945836', xfbml: true});
          };

          LiveJournal.injectScript(document.location.protocol + '//connect.facebook.net/$locale/all.js', null, document.getElementById('fb-root'))
        </script>
    };
} );

LJ::register_hook( 'insert_html_after_body_open' => sub {
    my ($after_body_open_ref) = @_;

    return if $LJ::REQ_GLOBAL{'sitewide_resources_ljlike_twitter'}++;

    $$after_body_open_ref .=  qq{<script type="text/javascript">LiveJournal.injectScript('http://platform.twitter.com/widgets.js');</script>};
} );

LJ::register_hook( 'sitewide_resources' => sub {
    return unless $LJ::VKONTAKTE_CONF;
    return if $LJ::REQ_GLOBAL{'sitewide_resources_ljlike_vkontakte'}++;

    my $api_id = $LJ::VKONTAKTE_CONF->{'client_id'};

    LJ::need_res ( 'js/jquery/jquery.vkloader.js' );
    LJ::include_raw( 'html' => qq[<script type="text/javascript">if (jQuery.VK) { jQuery.VK.init({apiId: $api_id, onlyWidgets: true})} </script> ] );
} );

1;
