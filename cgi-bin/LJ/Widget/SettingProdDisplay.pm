package LJ::Widget::SettingProdDisplay;

use strict;
use base qw(LJ::Widget);

use Carp qw(croak);

sub render_body {
    my $class = shift;

    my $remote = LJ::get_remote();
    return unless $remote;
    return unless LJ::is_web_context();
    my $codepath = eval { LJ::Request->notes('codepath'); };
    
    my $body;
    my $title = LJ::ejs( $class->ml('setting.prod.display.title') );
    foreach my $prod (@LJ::SETTING_PROD) {
        if ($codepath =~ $prod->{codepaths} && $prod->{should_show}->($remote)) {
            $body .= "\n<script language='javascript'>setTimeout(\"displaySettingProd('" .
                    $prod->{setting} . "', '" . $prod->{field} . "', '" . $title . "', " .  $prod->{window_opts} . " )\", 400)</script>\n";
            last;
        }
    }

    return $body;
}

sub need_res {
  qw(
    stc/widgets/settingprod.css
    js/settingprod.js
  )
}

1;
