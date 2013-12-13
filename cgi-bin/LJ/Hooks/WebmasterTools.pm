package LJ::LJcom;

use strict;

LJ::register_hook('head_content', sub {
    my ($headref) = @_;

    LJ::need_res({ 'separate_list' => 1 }, qw{
        js/ads/axz.min.js
    });

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
