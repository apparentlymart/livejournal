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
    my ( $class, %opts ) = @_;

    return if $LJ::REQ_GLOBAL{'sharing_resources_requested'}++;

    LJ::need_res( 'stc/share.css' );

    my $services = {
        'livejournal' => {
            'bindLink' => $LJ::SITEROOT . '/update.bml?repost_type=c&repost={url}'
        },
        'facebook' => {
            'bindLink' => 'http://www.facebook.com/sharer.php?u={url}'
        },
        'twitter' => {
            'bindLink' => 'http://twitter.com/share?url={url}&text={title}&hashtags={hashtags}'
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

    my $include_type = $opts{'include_type'} || 'init';
    if ( $include_type eq 'init' ) {
        LJ::need_res( 'js/share.js' );
        LJ::include_raw( 'js' => "LJShare.init($params_out)" );
    } elsif ( $include_type eq 'define' ) {
        LJ::need_res( 'js/jquery/jquery.lj.share.js' );
        LJ::include_raw( 'js' => "Site.LJShareParams = $params_out;" );
    }
}

sub render_js {
    my ( $class, $opts ) = @_;

    my $cache_key;
    if ( my $entry = delete $opts->{'entry'} ) {
        $opts->{'title'}        = LJ::ejs( $entry->subject_drop_html );
        $opts->{'url'}          = $entry->url;

        if ($opts->{'title'}) {
            $opts->{'title'}       = Encode::decode_utf8($opts->{'title'});
            $opts->{'title'}       =~ s/\r|\n|\x85|\x{2028}|\x{2029}//gsm;
            $opts->{'title'}       = Encode::encode_utf8($opts->{'title'});
        }

        $opts->{'hashtags'} = LJ::eurl(join ',' , grep {s/^#//} $entry->tags) || ""; 

        if ( $opts->{'hashtags'} ) { 
            $opts->{'hashtags'}       = Encode::decode_utf8($opts->{'hashtags'});
            $opts->{'hashtags'}       =~ s/\r|\n|\x85|\x{2028}|\x{2029}//gsm;
            $opts->{'hashtags'}       = Encode::encode_utf8($opts->{'hashtags'});
        }

    }

    my $opts_out = LJ::JSON->to_json($opts);
    my $result_text = 
        qq{<script type="text/javascript">LJShare.link($opts_out);</script>};

    return $result_text;
}

1;
