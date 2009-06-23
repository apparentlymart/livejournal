package LJ::Widget::IPPU::AddAlias;

use strict;
use base qw(LJ::Widget::IPPU);
use Carp qw(croak);
use Class::Autouse qw(
                      LJ::JSUtil
                      );

use JSON;

sub need_res {
    return qw( js/widgets/aliases.js stc/widgets/aliases.css );
}

sub authas { 1 }

sub render_body {
    my ($class, %opts) = @_;

    my $body;
    my $remote = LJ::get_remote;

    $body .= $class->start_form(
                id => 'addalias_form',
             );
    $body .= "<table border='1' width='100%'>";
    my $for_user = LJ::load_user($opts{foruser});
    $body .= "<tr><td>Set alias for ".$for_user->ljuser_display." (read FAQ for details):</td></tr>";
    $body .= "<tr>";

    $body .= "<div>" .
             $class->html_text(
                name  => 'alias',
                id    => 'Widget[IPPU_AddAlias]_alias',
                size  => 30,
                value => undef,
                raw   => "autocomplete='off'",
             ) . "";

    $body .= "</div>";

    $body .= "<span class='helper'>(" . BML::ml('widget.vgiftadd.display.publicly') . ")</span></div>";

    $body .= $class->html_hidden(
                foruser => $opts{foruser},
             );
    $body .= "<p>" .
             $class->html_submit(BML::ml('widget.vgiftadd.addtocart')) .
             "</p>";
    $body .= $class->end_form;

    $body .= "</td></tr></table>\n";

    return $body;
}

sub handle_post {
    my ($class, $post, %opts) = @_;

    my $remote = LJ::get_remote();

    my $aliases = $remote->prop('aliases');
    $aliases = jsonToObj($aliases);
    my $user_for_alias = LJ::load_user($post->{foruser});

    die BML::ml('.error.cantfinduser', {'user' => $post->{foruser}})
        unless $user_for_alias;

    $aliases->{$post->{foruser}} = $post->{alias};
    $aliases = objToJson($aliases);

    $remote->set_prop('aliases', $aliases);
    
    return (success => 1);
}

1;
