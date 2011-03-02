package LJ::Share;
use strict;
use warnings;

use LJ::JSON;
use LJ::Text;

sub request_resources {
    return if $LJ::REQ_GLOBAL{'sharing_resources_requested'}++;

    LJ::need_res( qw( js/share.js stc/share.css ) );

    my $services = {
        'livejournal' => {
			'title' => 'LiveJournal',
            'bindLink' => $LJ::SITEROOT . '/update.bml?repost={url}'
		},
		'facebook' => {
			'title' => 'Facebook',
            'bindLink' => 'http://www.facebook.com/sharer.php?u={url}'
		},
		'twitter' => {
			'title' => 'Twitter',
            'bindLink' => 'http://twitter.com/share?url={url}&text={title}'
		},
		'vkontakte' => {
			'title' => 'Vkontakte',
            'bindLink' => 'http://vkontakte.ru/share.php?url={url}'
		},
		'moimir' => {
			'title' => 'Moi Mir',
            'bindLink' => 'http://connect.mail.ru/share?url={url}'
		},
		'stumbleupon' => {
			'title' => 'Stumbleupon',
            'bindLink' => 'http://www.stumbleupon.com/submit?url={url}'
		},
		'digg' => {
			'title' => 'Digg',
            'bindLink' => 'http://digg.com/submit?url={url}'
		},
		'email' => {
			'title' => 'E-mail',
            'bindLink' => 'http://api.addthis.com/oexchange/0.8/forward/email/offer?username=internal&url={url}'
		},
		'tumblr' => {
			'title' => 'Tumblr',
            'bindLink' => 'http://www.tumblr.com/share?v=3&u={url}'
		},
		'odnoklassniki' => {
			'title' => 'Odnoklassniki',
            'bindLink' => 'http://www.odnoklassniki.ru/dk?st.cmd=addShare&st.s=1&st._surl={url}'
		}
    };

    my $params = {
        'services' => $services,
        'links' => [ sort keys %$services ],
        'ml' => {
            'title' => LJ::Lang::ml('sharing.popup.title'),
            'close' => LJ::Lang::ml('sharing.popup.close'),
        },
    };

    LJ::run_hooks( 'alter_sharing_params', $params );

    my $params_out = LJ::JSON->to_json($params);

    LJ::include_raw( 'js' => "LJShare.init($params_out)" );
}

sub render_js {
    my ( $class, $opts ) = @_;

    if ( my $entry = delete $opts->{'entry'} ) {
        $opts->{'title'}        = LJ::Text->drop_html($entry->subject_raw);
        $opts->{'description'}  = LJ::Text->drop_html($entry->event_raw);
        $opts->{'url'}          = $entry->url;
    }

    my $opts_out = LJ::JSON->to_json($opts);

    return
        qq{<script type="text/javascript">LJShare.link($opts_out);</script>};
}

1;
