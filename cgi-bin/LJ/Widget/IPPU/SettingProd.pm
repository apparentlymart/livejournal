package LJ::Widget::IPPU::SettingProd;

use strict;
use base qw(LJ::Widget::IPPU);
use Carp qw(croak);
use Class::Autouse qw(
                      LJ::JSUtil
                      LJ::Setting
                      );

sub need_res {
#    return qw( js/widgets/settingprod.js stc/widgets/settingprod.css );
}

sub authas { 0 }

sub render_body {
    my ($class, %opts) = @_;

    my $key = $opts{setting};
    my $body;
    my $remote = LJ::get_remote;

    $body .= "<div class='settingprod'>";
    $body .= "<p>" . $class->ml('settings.settingprod.intro',
             { sitename => $LJ::SITENAMESHORT }) . "</p>";

    $body .= $class->start_form(
                id => 'settingprod_form',
             );

    my $setting_class = "LJ::Setting::$key";
    $body .= $setting_class->as_html($remote);

    $body .= "<p style='text-align: center'>" .
             $class->html_submit('Update your Settings') .
             "</p>";
    $body .= $class->html_hidden({ name => 'setting_key', value => $key });

    $body .= $class->end_form;

    $body .= "<p><span class='helper'>" .
             $class->ml('settings.settingprod.outro',
                 { aopts => "href='$LJ::SITEROOT/manage/profile/'" } ) .
             "</span></p>";

    $body .= "</div>\n";

    return $body;
}

sub handle_post {
    my ($class, $post, %opts) = @_;

    my $setting = $post->{setting};
    my $setting_class = "LJ::Setting::$setting";

    my $remote = LJ::get_remote;
    my $sv = eval { $setting_class->save($remote, $post) };
    my $save_errors;
    if (my $err = $@) {
        $save_errors = $err->field('map') if ref $err;
        die join(" <br />", map { $save_errors->{$_} } sort keys %$save_errors);
    }

    return (success => 1);
}

1;
