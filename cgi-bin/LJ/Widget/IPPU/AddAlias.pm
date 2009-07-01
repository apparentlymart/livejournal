package LJ::Widget::IPPU::AddAlias;

use strict;
use base qw(LJ::Widget::IPPU);
use Carp qw(croak);
use Class::Autouse qw(
                      LJ::JSUtil
                      );

use JSON;

sub need_res {
    return qw( js/widgets/aliases.js );
}

sub authas { 1 }

sub render_body {
    my ($class, %opts) = @_;

    my $body;
    my $remote = LJ::get_remote;

    $body .= $class->start_form(
                id => 'addalias_form',
             );
    my $for_user = LJ::load_user($opts{foruser});

	$body .= "<div class='user_alias_act'>";
    $body .= "<label for='Widget[IPPU_AddAlias]_alias'>". BML::ml('widget.alias.setalias') ." ".$for_user->ljuser_display." (". BML::ml('widget.alias.faq') ."):</label>";

    $body .= $class->html_text(
                name  => 'alias',
                id    => 'Widget[IPPU_AddAlias]_alias',
                size  => 30,
                value => undef,
                raw   => "autocomplete='off'",
             ) . "";


    $body .= "<span class='helper'>(" . BML::ml('widget.vgiftadd.display.publicly') . ")</span>";

    $body .= $class->html_hidden(
                foruser => $opts{foruser},
             );
    $body .= "<p>" .
             $class->html_submit(BML::ml('widget.alias.aliaschange')) .
             "</div>";
    $body .= $class->end_form;
	$body .= "</p>";


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
