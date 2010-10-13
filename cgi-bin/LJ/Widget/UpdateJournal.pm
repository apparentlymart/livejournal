package LJ::Widget::UpdateJournal;

use strict;
use base qw(LJ::Widget::Template);
use Carp qw(croak);

#sub need_res { qw( stc/widgets/examplepostwidget.css ) }

sub template_filename {
    return "$ENV{'LJHOME'}/templates/UpdateJournal/main.tmpl";
}

sub prepare_template_params {
    my $class = shift;
    my $template_obj = shift;
    my $opts = shift;

    $template_obj->param(step => 1);

    return;
}

sub handle_post {
    my $class = shift;
    my $post = shift;
    my %opts = @_;

    if ($post->{text}) {
        warn "You entered: $post->{text}\n";
    }

    return;
}

sub js {
    q [
        initWidget: function () {
            var self = this;

        },
    ];
}

1;
