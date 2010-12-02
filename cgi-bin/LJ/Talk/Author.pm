=head1 NAME

LJ::Talk::Author - a set of classes to handle various commenting choices,
including logged-in users, anonymous commenters, and identities.

=head1 SYNOPSIS

 foreach my $author_class (LJ::Talk::Author->all) {
     warn $author_class;                            # 'LJ::Talk::Author::OpenID'
     warn $author_class->short_code;                # 'OpenID'
     warn $author_class->display_params($opts);     # 'HASH(0xDEADBEEF)'
 }

 my $author_class = LJ::Talk::Author->get_handler('openid');
 die unless $author_class;
 warn $author_class->handle_user_input(...); # 'LJ::User=HASH(0xDEADBEEF)'

=cut

package LJ::Talk::Author;
use strict;

use Carp qw();

my %code_map;

=head1 METHODS

=head2 Base class / final

=head3 all

List all of the supported author choices. Used by LJ::Talk::talkform
and LJ::Talk::Post::init.

=head3 get_handler

Get the handler for the given 'usertype' form field value. See also:
want_user_input. Used by LJ::Talk::Post::init.

=cut

sub all {
    return map { "LJ::Talk::Author::$_" } @LJ::TALK_METHODS_ORDER;
}

sub get_handler {
    my ($class, $usertype) = @_;

    foreach my $author_class($class->all) {
        return $author_class if $author_class->want_user_input($usertype);
    }

    return;
}

=head2 (Purely) virtual

=head3 enabled

Return a boolean value indicating that this author choice is enabled on the
server. Disabled choices are not displayed to the user.

=cut

sub enabled { 1 }

=head3 short_code

Return the "short code" for this author choice. It is used by the
templates/CommentForm/Form.tmpl template to find the corresponding
templates/CommentForm/Author-${short_code}.tmpl template.

=cut

sub short_code {
    my ($class) = @_;
    $class =~ s/^LJ::Talk::Author:://;
    return $class;
}

=head3 display_params($opts)

Return a hashref with the form params for the same template. The $opts
argument is the same argument that gets passed to LJ::Talk::talkform.
Used by LJ::Talk::talkform.

=cut

sub display_params {
    my ($class, $opts) = @_;

    my $remote = LJ::get_remote();

    return {};
}

=head3 want_user_input($usertype)

Return a boolean value indicating that the provided 'usertype' form
field value in the commenting form corresponds to this author class.
Used by get_handler.

=head3 usertype_default($remote)

Return a string with the default 'usertype' field value, provided
that the remote user corresponds to this author class and does not
need any further authorization to comment. Return a value that evaluates
to false otherwise.

=head3 handle_user_input(...)

 my $up = $author_class->handle_user_input(
     $form,
     $remote,
     $need_captch,
     $errret,
     $init,
 );

Handle the user input in the form fields as appropriate with this
commenting choice. The parameters passed are the same parameters that
are passed to LJ::Talk::Post::init, plus an $init hashref that can be
written to to alter the initialization results.

Returns an LJ::User object that is supposed to be the comment author, or
undef in case the comment is supposed to be posted anonymously. In case
of an error, $errret listref is populated with errors, and the return
value should be discarded.

Used by LJ::Talk::Post::init.

=cut

sub want_user_input { 0 }
sub handle_user_input {
    my ($class, $form, $remote, $need_captcha, $errret, $init) = @_;
}

# initialization code here
foreach my $method (@LJ::TALK_METHODS_ORDER) {
    my $package = "LJ::Talk::Author::$method";
    eval "use $package";
    die $@ if $@;
    $code_map{$package->short_code} = $package;
}

1;
