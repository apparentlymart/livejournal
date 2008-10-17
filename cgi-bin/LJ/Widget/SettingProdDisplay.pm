package LJ::Widget::SettingProdDisplay;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);

sub render_body {
    my $class = shift;

    my $remote = LJ::get_remote();
    return unless $remote;

    my $body;
    foreach my $prod (@LJ::SETTING_PROD) {
        if ($prod->{should_show}->($remote)) {
            $body .= "\n<script language='javascript'>setTimeout(\"displaySettingProd('" .
                    $prod->{setting} . "', '" . $prod->{field} . "')\", 400)</script>\n";
            last;
        }
    }

    return $body;
}

sub need_res {
    qw(js/settingprod.js
       js/ljwidget.js
       js/ljwidget_ippu.js
       js/widget_ippu/settingprod.js
       stc/widgets/settingprod.css
      )
}

1;
