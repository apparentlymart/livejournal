package LJ::Widget::UpdateJournal::ActionsBlock;
# it is not a wdget, it is perl module
# right column with actions

use strict;
use Carp qw(croak);

sub prepare_template_params {
    my $class = shift;
    my $template_obj = shift;
    my $opts = shift;

    $template_obj->param(step => 1);

    return;
}

1;
