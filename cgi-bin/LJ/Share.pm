=head1 HOW TO USE

 # somewhere near to your need_res calls:
 LJ::Share->request_resources;

=cut

package LJ::Share;

use strict;
use warnings;

# Internal modules
use LJ::JSON;
use LJ::Text;

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

sub request_resources {
    my ( $class, %opts ) = @_;

    return if $LJ::REQ_GLOBAL{'sharing_resources_requested'}++;

    while ( my ( $name, $service ) = each %$services ) {
        $service->{'title'} ||= LJ::Lang::ml("sharing.service.$name");
        $service->{'openInTab'} = 1 if $name eq 'livejournal';
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

    LJ::need_res( 'stc/share.css' );
    LJ::need_res_group('share');
    LJ::include_raw( 'js' => "Site.LJShareParams = $params_out;" );
}

1;
