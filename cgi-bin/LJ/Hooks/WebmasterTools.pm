package LJ::LJcom;

use strict;

LJ::register_hook('head_content', sub {
    my ($headref) = @_;

    my $journal = LJ::get_active_journal();
    return unless $journal;

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
});

1;
