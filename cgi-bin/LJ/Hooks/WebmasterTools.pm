package LJ::LJcom;

use strict;

LJ::register_hook('head_content', sub {
    my ($headref) = @_;

    $LJ::HEAD_CONTENT_SHOWN++;

    if (LJ::get_remote() && $LJ::SERVER_NAME eq "bil1-ws49") {
        $$headref .= <<RUM_SCRIPT_HP;
<script> 
var _prum = [['id', '531ed87eabe53dce7b069f59'], 
             ['mark', 'firstbyte', (new Date()).getTime()]]; 
(function() { 
    var s = document.getElementsByTagName('script')[0] 
      , p = document.createElement('script'); 
    p.async = 'async'; 
    p.src = '//rum-static.pingdom.net/prum.min.js'; 
    s.parentNode.insertBefore(p, s); 
})(); 
</script> 
RUM_SCRIPT_HP
    }

    if (
        !($LJ::HEAD_CONTENT_SHOWN % 10) &&
        LJ::get_remote()
        && ( $LJ::IS_LJCOM_BETA || $LJ::SERVER_NAME =~ m{^bil1-ws50} )
    ) {
        $$headref .= <<RUM_SCRIPT;
<script>
var _prum = [['id', '52f0e3dbabe53dcf1b000000'],
             ['mark', 'firstbyte', (new Date()).getTime()]];
(function() {
    var s = document.getElementsByTagName('script')[0]
      , p = document.createElement('script');
    p.async = 'async';
    p.src = '//rum-static.pingdom.net/prum.min.js';
    s.parentNode.insertBefore(p, s);
})();
</script>
RUM_SCRIPT
    }

    my $journal = LJ::get_active_journal();
    return unless $journal;

    $journal->preload_props(qw/webmastertools_google webmastertools_yandex webmastertools_mailru/);

    if (my $content = $journal->prop('webmastertools_google')) {
        $$headref .= qq{
            <meta name="google-site-verification" content="$content" /> 
        };
    }

    if (my $content = $journal->prop('webmastertools_yandex')) {
        $$headref .= qq{
            <meta name="yandex-verification" content="$content" /> 
        };
    }

    if (my $content = $journal->prop('webmastertools_mailru')) {
        $$headref .= qq{
            <meta name="wmail-verification" content="$content" /> 
        };
    }
});

1;
