package LJ::Widget::UpdateJournal;

use strict;
use base qw(LJ::Widget::Template);
use Carp qw(croak);

# they are not widgets, they are perl modules
use LJ::Widget::UpdateJournal::TextBlock; # subject + body, tags and userpic group of elements
use LJ::Widget::UpdateJournal::OptionsBlock; # all entry options (properties)
use LJ::Widget::UpdateJournal::ActionsBlock; # right column with actions

#sub need_res { qw( stc/widgets/examplepostwidget.css ) }

sub template_filename {
    return "$ENV{'LJHOME'}/templates/UpdateJournal/main.tmpl";
}

sub prepare_template_params {
    my $class = shift;
    my $template_obj = shift;
    my $opts = shift;

    # put all needed parameters in common template object
    LJ::Widget::UpdateJournal::TextBlock->prepare_template_params($template_obj, $opts);
    LJ::Widget::UpdateJournal::OptionsBlock->prepare_template_params($template_obj, $opts);
    LJ::Widget::UpdateJournal::ActionsBlock->prepare_template_params($template_obj, $opts);

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
