package LJ::Widget::AddCommunity;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);

sub need_res { qw( stc/widgets/addcommunity.css ) }

sub render_body {
    my $class = shift;
    my %opts = @_;

    my ($caption, $form_text, $submit_caption) =
        map { BML::ml('widget.addcommunity.' . $_,
            {
                openlink    => '<a href="#">',  # TODO: This is a url to Spotlight
                closelink   => '</a>',
            })
        } qw(caption form_text submit_button_caption);

    return <<EOT;
<h2>$caption</h2>
<form action='$LJ::SITEROOT/search/' method='post'>
$form_text
<input type="submit" value="$submit_caption">
</form>
EOT
}

1;

