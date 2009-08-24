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

    my $authtoken = LJ::Auth->ajax_auth_token(LJ::get_remote(), "/_widget");

	$body .= "<div class='user_alias_act'>";
    $body .= "<div class='user-alias-label'><label for='Widget[IPPU_AddAlias]_alias'>". BML::ml('widget.alias.setalias') ." ".$for_user->ljuser_display."</label> (". BML::ml('widget.alias.faq', {aopts => "href='$LJ::SITEROOT/support/faqbrowse.bml?faqid=295'"}) ."):</div>";

    $body .= $class->html_text(
                name  => 'alias',
                id    => 'Widget[IPPU_AddAlias]_alias',
				class => 'alias-value',
                size  => 60,
				maxlength => 200,
                value => $opts{alias},
                raw   => "autocomplete='off'",
             ) . "";

    $body .= $class->html_hidden(
                foruser => $opts{foruser},
             );

    $body .= "<p>" . $class->html_submit("aliaschange", BML::ml('widget.alias.aliaschange')) . " " . $class->html_submit("aliasdelete", BML::ml('widget.alias.aliasdelete')) ;

    $body .= "<span class='helper'>" . BML::ml('widget.addalias.display.helper', {aopts => "href='$LJ::SITEROOT/manage/notes.bml'"}) . "</span>";
    $body .= "</div>";
    $body .= $class->end_form;
	$body .= "</p>";

    $body .= "<script>Aliases.authToken = \"$authtoken\";</script>";

    return $body;
}

sub handle_post {
    my ($class, $post, %opts) = @_;

    my $remote = LJ::get_remote();

    die "Must be logged in" unless $remote; # hope it is impossibly...

    my $aliases = $remote->prop('aliases');
    $aliases = jsonToObj($aliases);
    my $user_for_alias = LJ::load_user($post->{foruser});

    die BML::ml('.error.cantfinduser', {'user' => $post->{foruser}})
        unless $user_for_alias;

    die "Cannot set alias to yourself" if $remote->{user} eq $user_for_alias->{user}; # again, hope it is impossible

    my $is_edit = 0;
    $is_edit = 1 if $aliases->{$post->{foruser}} ne '';
    my $prepared_alias = substr($post->{alias}, 0, 400);
    $prepared_alias = '' if $post->{'deletealias'} ne '';
    $aliases->{$user_for_alias->{userid}} = $prepared_alias if $prepared_alias;
    delete $aliases->{$user_for_alias->{userid}} unless $prepared_alias;

    my $ready_aliases = objToJson($aliases);
    if (length $ready_aliases < 65536) {
        $remote->set_prop( aliases => $ready_aliases );
    
        return (
            success     => 1, 
            username    => $user_for_alias->user,
            journalname => $user_for_alias->display_name,
            alias       => LJ::dhtml($post->{alias}),
            message     => $is_edit ? BML::ml('widget.addalias.edit_alias') : BML::ml('widget.addalias.add_alias'),
        );

    } else {
        return (
            success     => 0, 
            username    => $user_for_alias->user,
            journalname => $user_for_alias->display_name,
            alias       => LJ::dhtml($post->{alias}),
            message     => BML::ml('widget.addalias.too.long')
        );
    }
}

1;
