=head1 HOW TO USE

 # somewhere near to your need_res calls:
 LJ::Share->request_resources;
 
 # when printing HTML
 print '<a href="#">Share</a>'
     . LJ::Share->render_js({ 'entry' => $entry });

=cut

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
            'bindLink' => $LJ::SITEROOT . '/update.bml?repost={url}'
        },
        'facebook' => {
            'bindLink' => 'http://www.facebook.com/sharer.php?u={url}'
        },
        'twitter' => {
            'bindLink' => 'http://twitter.com/share?url={url}&text={title}'
        },
        'vkontakte' => {
            'bindLink' => 'http://vkontakte.ru/share.php?url={url}'
        },
        'moimir' => {
            'bindLink' => 'http://connect.mail.ru/share?url={url}'
        },
        'stumbleupon' => {
            'bindLink' => 'http://www.stumbleupon.com/submit?url={url}'
        },
        'digg' => {
            'bindLink' => 'http://digg.com/submit?url={url}'
        },
        'email' => {
            'bindLink' => 'http://api.addthis.com/oexchange/0.8/forward/email/offer?username=internal&url={url}&title={title}'
        },
        'tumblr' => {
            'bindLink' => 'http://www.tumblr.com/share?v=3&u={url}'
        },
        'odnoklassniki' => {
            'bindLink' => 'http://www.odnoklassniki.ru/dk?st.cmd=addShare&st.s=1&st._surl={url}'
        }
    };

    while ( my ( $name, $service ) = each %$services ) {
        $service->{'title'} ||= LJ::Lang::ml("sharing.service.$name");
    }

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
        $opts->{'title'}        = LJ::ejs( LJ::Text->drop_html($entry->subject_raw) );
        $opts->{'description'}  = LJ::ejs( LJ::Text->drop_html($entry->event_raw) );
        $opts->{'url'}          = $entry->url;

        $opts->{'title'}       = Encode::decode_utf8($opts->{'title'});
        $opts->{'description'} = Encode::decode_utf8($opts->{description});

        $opts->{'title'}       =~ s/\r|\n|\x85|\x{2028}|\x{2029}//gsm;
        $opts->{'description'} =~ s/\r|\n|\x85|\x{2028}|\x{2029}//gsm;

        $opts->{'title'}       = Encode::encode_utf8($opts->{'title'});
        $opts->{'description'} = Encode::encode_utf8($opts->{description});
    }

    my $opts_out = LJ::JSON->to_json($opts);

    return
        qq{<script type="text/javascript">LJShare.link($opts_out);</script>};
}

1;
