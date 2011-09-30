package LJ::SiteScheme::Lynx;
use strict;
use warnings;

use base qw( LJ::SiteScheme );

sub code {'lynx'}

sub need_res {
    LJ::need_res(qw( stc/lj_base-app.css stc/lynx/layout.css ));
}

sub template_params {
    my ( $class, $args ) = @_;

    my $remote = LJ::get_remote();

    my ( $parentcrumb_title, $parentcrumb_link ) = ( '', '' );
    if ( LJ::get_active_crumb() ) {
        my @path = LJ::get_crumb_path();
        if ( my $parentcrumb = $path[-2] ) {
            ( $parentcrumb_title, $parentcrumb_link ) = @$parentcrumb;
        }
    }

    my $body_class = 'scheme-lynx ' . LJ::get_body_class_for_service_pages();

    return {
        %{ $class->common_template_params($args) },

        'parentcrumb_title' => $parentcrumb_title,
        'parentcrumb_link'  => $parentcrumb_link,
        'body_class'        => $body_class,
    };
}

1;
