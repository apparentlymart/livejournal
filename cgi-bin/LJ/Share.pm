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

sub request_resources {
    my ( $class, %opts ) = @_;

    return if $LJ::REQ_GLOBAL{'sharing_resources_requested'}++;

    my $services = {
        'livejournal' => {
            'bindLink' => $LJ::SITEROOT . '/update.bml?repost_type=c&repost={url}',
            'openInTab'=> 1,
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
            'bindLink' => 'http://www.tumblr.com/share/link?url={url}&name={title}&description={text}'
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
    };

    LJ::run_hooks( 'alter_sharing_params', $params );

    LJ::need_res_group('share');
    LJ::need_var({ LJShareParams => $params });
}

1;
