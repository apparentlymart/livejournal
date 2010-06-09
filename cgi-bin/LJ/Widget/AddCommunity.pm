package LJ::Widget::AddCommunity;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);

sub need_res { qw( stc/widgets/widget-layout.css stc/widgets/add-community.css ) }

sub render_body {
    my $class = shift;
    my %opts = @_;

    my ($caption, $form_text, $submit_caption) =
        map { BML::ml('widget.addcommunity.' . $_,
            {
                openlink    => qq|<a href="$LJ::SITEROOT/misc/suggest_spotlight.bml">|,  # TODO: This is a url to Spotlight
                closelink   => '</a>',
            })
        } qw(caption form_text submit_button_caption);

    return <<EOT;
    <div class="right-mod">
        <div class="mod-tl">
            <div class="mod-tr">
                <div class="mod-br">
                    <div class="mod-bl">
                        <div class="w-head">
                            <h2><span class="w-head-in">$caption</span></h2><i class="w-head-corner"></i>
                        </div>
                        <div class="w-body">
                            <form action='$LJ::SITEROOT/community/directory.bml' method='post'>
                            <p>$form_text</p>
                            <fieldset>
                                <input type="submit" value="$submit_caption" />
                            <fieldset>
                            </form>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </div>

EOT
}

1;

