package LJ::LJcom;

use strict;

LJ::register_hook('head_content', sub {
    my ($headref) = @_;

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

LJ::register_hook('head_content', sub {
    my ($headref) = @_; 
    return if $LJ::DISABLED{siteconfidence_rum_script};

    my $prefix = $LJ::IS_SSL ? $LJ::SSLJSPREFIX : $LJ::STATPREFIX."/js";
    $$headref .= qq{<script src="$prefix/ads/axz.min.js"></script>};
});


1;
