package LJ::Widget::Template;
# base class for widget of any type (post / ajax / simple(render) ), using template engine

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);

# main 'templated' method to override in subclass
sub prepare_template_params {
    my $class = shift;
    my $template_obj = shift;
    my $opts = shift;

    return;
}

# path to template file,
# subclass may skip overriding this method
sub template_filename { 
    my $class = shift;

    my $lc_class = lc $class->subclass;
    $lc_class =~ s|::|/|g;
    return "$ENV{'LJHOME'}/templates/Widgets/${lc_class}.tmpl";
}

# fully ready 'render_body' method, subclass have no need to override this method
sub render_body {
    my $class = shift;
    my %opts = @_;

    my $filename = $class->template_filename(%opts);
    my $template = LJ::HTML::Template->new(
        { use_expr => 1 }, # force HTML::Template::Pro with Expr support
        filename => $filename,
        die_on_bad_params => 0,
        strict => 0,
    ) or die "Can't open template '$filename': $!";

    # template object already contains 'lj_siteroot' and several same parameters, look LJ/HTML/Template.pm
    # also it contains 'ml', 'ljuser', ... functions

    $template->param(
        is_remote_sup => LJ::SUP->is_remote_sup ? 1 : 0,
        errors => $class->error_list,
        form_auth => LJ::form_auth(),
    );

    $class->prepare_template_params($template, \%opts);
    return if LJ::Request->redirected;

    return $template->output;
}

1;
