package LJ::Widget::IPPU::SettingProd;

use strict;
use base qw(LJ::Widget::IPPU);
use Carp qw(croak);
use Class::Autouse qw(
                      LJ::JSUtil
                      LJ::Setting
                      );

sub authas { 0 }

sub render_body {
    my ($class, %opts) = @_;

    my $key = $opts{setting};
    my ($config) = grep { $_->{setting} eq $key } @LJ::SETTING_PROD;
    my $setting_class = "LJ::Setting::$key";
    my $no_wrap = $config->{no_wrap};
    my $remote = LJ::get_remote();
   
   
    my $setting_class_html  = $setting_class->as_html($remote, undef, { helper => 0, faq => 1, display_null => 0} );
    my $hidden_setting_key  = $class->html_hidden({ name => 'setting_key', value => $key });
    my $start_form          = $class->start_form( id => 'settingprod_form' );
    my $end_form            = $class->end_form;

    my $body;
    
    if ($no_wrap) {
        $body = $start_form . $setting_class_html . $hidden_setting_key . $end_form;
    } else {
        my $intro           = $class->ml('settings.settingprod.intro',{ sitename => $LJ::SITENAMESHORT });
        my $outro           = $class->ml('settings.settingprod.outro', { aopts => "href='$LJ::SITEROOT/manage/settings/'" } ); 
        my $remind_later    = $class->ml('settings.settingprod.remindlater');
        my $submit          = $class->html_submit( $class->ml('settings.settingprod.update') );
        
        $body = "<div class='settingprod'><p>$intro</p>" .
                $start_form .
                "<div class='warningbar'>" . $setting_class_html .
                "<p>$submit &nbsp;" .
                '<a href="#" onclick="settingProd.cancel();return false">' . $remind_later . "</a>" .
                "</p>" . $hidden_setting_key .
                "</div>" . $end_form .
                "<p><span class='helper'>" . $outro . "</span></p>";
    }
    
    my $ret;
    LJ::run_hooks('campaign_tracking', \$ret,
                  { cname => 'Popup Setting Display' } );
    $body .= $ret;

    $body .= "</div>\n";

    return $body;
}

sub handle_post {
    my ($class, $post, %opts) = @_;

    my $setting = $post->{setting};
    my $setting_class = "LJ::Setting::$setting";

    my $remote = LJ::get_remote();
    my $sv = eval { $setting_class->save($remote, $post) };
    my $save_errors;
    if (my $err = $@) {
        $save_errors = $err->field('map') if ref $err;
        die join(" <br />", map { $save_errors->{$_} } sort keys %$save_errors);
    }

    my $xtra;
    my $postvars = join(",", $setting_class->settings($post));
    LJ::run_hooks('campaign_tracking', \$xtra,
                    { cname     => 'Popup Setting Submitted',
                      trackvars => "$postvars", } );

    return (success => 1, extra => "$xtra", result => $sv    );
}

1;
