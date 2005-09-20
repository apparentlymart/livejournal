#!/usr/bin/perl

package LJ::Portal;

use strict;

use lib "$ENV{LJHOME}/cgi-bin";
use LJ::Portal::Config;
use LJ::Portal::Box;

sub new {
    my LJ::Portal $self = shift;

    bless $self, "LJ::Portal";
    return $self;
}

sub get_close_button {
    return qq{<img src="$LJ::IMGPREFIX/portal/PortalConfigCloseButton.gif" width=19 height=19 title="Close" alt="Close" valign="middle" />};
}

# get a little faq link and help icon
sub get_faq_link {
    my LJ::Portal $self = shift;
    my $faqid = shift;

    return "<a href=\"$LJ::SITEROOT/support/faqbrowse.bml?faqid=$faqid\">" .
        "<img src=\"$LJ::IMGPREFIX/help.gif\" /></a>";
}

# clients don't actually like XML
sub return_xml {
    my LJ::Portal $self = shift;
    my $response = shift;
    BML::set_content_type('text/plain');
    return BML::http_response(200, $response);
}

sub create_button {
    my LJ::Portal $self = shift;
    my ($text, $action) = @_;
    $text = LJ::ehtml($text);
    return qq{
        <div class="PortalButton" onmousedown="this.className='PortalButton PortalButtonMouseDown';" onclick="$action" onmouseup="this.className='PortalButton';">$text</div>
        };
}

sub get_portal_box_display_script {
    my LJ::Portal $self = shift;
    my ($id, $class_name, $inner_html, $parent) = @_;

    # escape everything
    $class_name = LJ::ejs($class_name);
    $inner_html = LJ::ejs($inner_html);
    $id = LJ::ejs($id);
    $parent = LJ::ejs($parent);

    return qq{
        var boxelement = xCreateElement("div");
        var parentelement = xGetElementById("$parent");
        if (boxelement && parentelement) {
            boxelement.id = "$id";
            boxelement.className = "$class_name PortalBox";
            boxelement.innerHTML = '$inner_html';
            xAppendChild(parentelement, boxelement);
            fadeIn(boxelement, 200);
        }
    };
}

sub get_portal_box_update_script {
    my LJ::Portal $self = shift;
    my ($config, $box) = @_;

    my $pboxid = $box->pboxid();
    my $newcontents = LJ::ejs($config->generate_box_insides($pboxid));
    return
        qq{
            var box = xGetElementById('pbox$pboxid');
            if (box) {
                box.innerHTML = "$newcontents";
            }
        };
}

sub get_portal_box_titlebar_update_script {
    my LJ::Portal $self = shift;
    my ($config, $box) = @_;

    my $pboxid = $box->pboxid();
    my $newcontents = LJ::ejs($config->generate_box_titlebar($box));
    return
        qq{
            var bar = xGetElementById('pboxtitlebar$pboxid');
            if (bar) {
                bar.innerHTML = "$newcontents";
            }
        };
}

sub get_portal_config_box_update_script {
    my LJ::Portal $self = shift;
    my $box = shift;
    return unless $box;

    my $pboxid = $box->pboxid;
    my $newcontents = LJ::ejs($box->generate_box_config_dialog);
    return qq{
            var confbox = xGetElementById('PortalFensterContentconfig$pboxid');
            if (confbox) {
                confbox.innerHTML = "$newcontents";
            }
        };
}

sub create_fenster {
    my LJ::Portal $self = shift;
    my ($id, $class_name, $inner_html, $parent, $title) = @_;

    # escape everything
    $title = LJ::ehtml($title);
    $class_name = LJ::ejs($class_name);
    $inner_html = LJ::ejs($inner_html);
    $id = LJ::ejs($id);
    $parent = LJ::ejs($parent);

    my $resize_image = qq{<img src="$LJ::IMGPREFIX/portal/PortalBoxResizeIcon.gif" title="Resize" alt="Resize" />};

    my $titlebar_html = LJ::ejs(qq{
        <div class="PortalPatternedTitleBar" id="portalbar$id">
            <div id="portalbarmax$id" class="PortalFensterBarMaxButton"></div>

            <span class="PortalTitleBarText">$title</span>

            </div>
        });
    my $boxbottom_html = LJ::ejs(qq{ <div id="portalbarres$id" class="PortalFensterResButton NormalCursor">$resize_image</div> });
    return qq{
        var boxelement    = xCreateElement("div");
        var parentelement = xGetElementById("$parent");
        if (boxelement && parentelement) {
            xAppendChild(document.body, boxelement);
            boxelement.id = "$id";
            boxelement.style.position='absolute';
            boxelement.className = "$class_name PortalFenster";
            boxelement.innerHTML = '$titlebar_html <div class=\"PortalFensterContent NormalCursor\" id=\"PortalFensterContent$id\">$inner_html</div> $boxbottom_html';
            fadeIn(boxelement);
            boxelement.style.zIndex=4;
        }
    };
}


### XML HTTP Request Fun Stuff

sub addbox {
    my LJ::Portal $self = shift;
    my ($portalconfig, $boxtype, $boxcol) = @_;

    my $returncode = '';

    if ($boxtype =~ /^\w+$/ && $boxcol =~ /^\w$/) {
        my $newbox = $portalconfig->add_box("$boxtype", $boxcol);
        if ($newbox) {
            my $innerHTML = $portalconfig->generate_box_insides($newbox->pboxid());
            my $boxclass = $newbox->box_class;
            my $pboxid = $newbox->pboxid;
            my $boxjs = LJ::Portal->get_portal_box_display_script("pbox$pboxid", "PortalBox $boxclass", $innerHTML, "PortalCol$boxcol");
            $returncode .= $boxjs;

            # update the arrows on the last box in the column
            my $prevbox = $portalconfig->prev_box($newbox);
            if ($prevbox) {
                $returncode .= LJ::Portal->get_portal_box_titlebar_update_script($portalconfig, $prevbox);
            }

            $returncode = 'alert("Could not add box.");' if ! $returncode;
        } else {
            $returncode = 'alert("Could not create a box of that type.");';
        }
    } else {
        $returncode = 'alert("Invalid box creation parameters.");';
    }
    return $returncode;
}

sub configbox {
    my LJ::Portal $self = shift;
    my ($pboxid, $portalconfig) = @_;

    my $box = $portalconfig->get_box_by_id($pboxid);
    my $configboxhtml;
    my $returncode;

    if ($box) {
        $configboxhtml = $box->generate_box_config_dialog;

        my $insertConfigBox =
            LJ::Portal->create_fenster(
                                       "config$pboxid", 'PortalBoxConfig',
                                       $configboxhtml, "pbox$pboxid",
                                       "Configure " . $box->box_name,
                                       );

        my $configboxjs = $insertConfigBox . qq{
            var pbox = xGetElementById("pbox$pboxid");
            var configbox = xGetElementById("config" + $pboxid);
            if (pbox && configbox) {
                xTop(configbox, xPageY(pbox));
                centerBoxX(configbox);
            }
        };
        $returncode = $configboxjs;
    } else {
        $returncode = 'alert("Could not load box properties.");';
    }

    return ($returncode, $configboxhtml);
}

sub movebox {
    my LJ::Portal $self = shift;
    my ($pboxid, $portalconfig, $boxcol,
        $boxcolpos, $moveUp, $moveDown) = @_;

    my $returncode;
    my $oldSwapBox = undef;

    if (($boxcolpos || $moveUp || $moveDown || $boxcol =~ /^\w$/) && $pboxid) {
        my $box = $portalconfig->get_box_by_id($pboxid);
        if ($box) {
            my $inserted = 0;
            my $oldPrevBox = $portalconfig->prev_box($box);
            my $oldNextBox = $portalconfig->next_box($box);

            if ($moveUp) {
                $oldSwapBox = $portalconfig->move_box_up($box);
            } elsif ($moveDown) {
                $oldSwapBox = $portalconfig->move_box_down($box);
            } else {
                if ($boxcolpos) {
                    # insert this box instead of append
                    my $insertbeforebox = $portalconfig->find_box_by_col_order($boxcol, $boxcolpos+1);
                    if ($insertbeforebox && $boxcol ne $box->col) {
                        my $newsortorder = $insertbeforebox->sortorder;
                        $portalconfig->insert_box(
                                                  $box, $boxcol,
                                                  $newsortorder
                                                  );
                        $inserted = 1;
                        $oldSwapBox = $insertbeforebox;
                    } else {
                        # nothing to insert before, append
                        $oldSwapBox = $portalconfig->move_box($box, $boxcol);
                    }
                } else {
                    $oldSwapBox = $portalconfig->move_box($box, $boxcol);
                }
            }

            $returncode = LJ::Portal->get_portal_box_titlebar_update_script($portalconfig, $box);

            if ($oldPrevBox) {
                $returncode .= LJ::Portal->get_portal_box_titlebar_update_script($portalconfig, $oldPrevBox);
            }
            if ($oldNextBox) {
                $returncode .= LJ::Portal->get_portal_box_titlebar_update_script($portalconfig, $oldNextBox);
            }

            # if this box is going where a box already exists do a swap
            if ($oldSwapBox) {
                if ($inserted) {
                    my $nextid = $oldSwapBox->pboxid;
                    $returncode .= qq {
                        var nextbox = xGetElementById("pbox$nextid");
                        var toinsert = xGetElementById("pbox$pboxid");
                        if (toinsert) {
                            var par = xParent(toinsert, true);
                            if (nextbox)
                                par.insertBefore(toinsert, nextbox);
                            else
                                par.appendChild(toinsert);
                        }
                    };
                }
            }

            # update the arrows on all adjacent boxes
            my $prevbox = $portalconfig->prev_box($box);
            my $nextbox = $portalconfig->next_box($box);
            $returncode .= LJ::Portal->get_portal_box_titlebar_update_script($portalconfig, $prevbox) if ($prevbox && $prevbox != $oldPrevBox && $prevbox != $oldNextBox);
            $returncode .= LJ::Portal->get_portal_box_titlebar_update_script($portalconfig, $nextbox) if ($nextbox && $nextbox != $oldPrevBox && $nextbox != $oldNextBox);
        } else {
            $returncode = 'alert("Box not found.");';
        }
    } else {
        $returncode = 'alert("Invalid move parameters.");';
    }

    return $returncode;
}

sub getmenu {
    my LJ::Portal $self = shift;
    my ($portalconfig, $menu) = @_;

    my $returncode;

    if ($menu) {
        if ($menu eq 'addbox') {
            my @classes = $portalconfig->get_box_classes;
            my $closebutton = $self->get_close_button;

            my $addboxtitle = BML::ml('/portal/index.bml.addbox');

            $returncode .= qq{
                <div class="PortalPatternedTitleBar">
                    <a onclick="hidePortalMenu('addbox'); return false;" href="#">
                    $closebutton
                    </a>
                    <span class="PortalTitleBarText">$addboxtitle</span>
                </div>
                    <div class="DropDownMenuContent">
                    <table style="width:100%;">
                };

            foreach my $boxclass (sort @classes) {
                my $fullboxclass = "LJ::Portal::Box::$boxclass";
                # if there can only be one of these boxes at a time and there
                # already is one, don't show it
                if ($portalconfig->get_box_unique($boxclass)) {
                    next if $portalconfig->find_box_by_class($boxclass);
                }

                my $boxname = $fullboxclass->box_name;
                my $boxdesc = $fullboxclass->box_description;
                my $boxcol  = $portalconfig->get_box_default_col($boxclass);
                my $addlink = qq{href="$LJ::SITEROOT/portal/index.bml?addbox=1&boxtype=$boxclass&boxcol=$boxcol" onclick="if(addPortalBox('$boxclass', '$boxcol')) return true; hidePortalMenu('addbox'); return false;"};
                $returncode .= qq{
                    <tr>
                        <td>
                        <a $addlink>
                        $boxname
                        </a>
                        <div class="BoxDescription">$boxdesc</div>
                        </td>
                        <td>
                        <a $addlink>ADD</a>
                        </td>
                        </tr>
                        <br/>};
            }
            $returncode .= '</table></div>';
        }
    } else {
        $returncode = 'alert("Menu not specified.");';
    }

    return $returncode;
}

sub saveconfig {
    my LJ::Portal $self = shift;
    my ($portalconfig, $pboxid, $realform, $postvars) = @_;

    my $box = $portalconfig->get_box_by_id($pboxid);
    my $returncode;

    if ($box) {
        my $configprops = $box->config_props;
        foreach my $propkey (keys %$configprops) {
            if ($propkey) {
                # slightly different format for non-XML submitted data
                my $postkey = $realform ? "$propkey$pboxid" : $propkey;
                my $propval = LJ::ehtml($postvars->{$postkey});

                my $type = $configprops->{$propkey}->{'type'};
                next if $type eq 'hidden';

                # check to see if value is valid:
                my $invalid = 0;

                if ($type eq 'integer') {
                    $invalid = 1 if ($propval != int($propval));
                    $propval = int($propval);
                    my $min = $configprops->{$propkey}->{'min'};
                    my $max = $configprops->{$propkey}->{'max'};
                    $invalid = 1 if ($min && $propval < $min);
                    $invalid = 1 if ($max && $propval > $max);
                } else {
                    $propval = LJ::ehtml($propval);
                }

                if (!$invalid) {
                    $box->set_prop($propkey, $propval);
                } else {
                    return 'alert("Invalid input");';
                }
            }
        }
        $returncode .= LJ::Portal->get_portal_box_update_script($portalconfig, $box);
        $returncode .= "hideConfigPortalBox($pboxid);";
    } else {
        $returncode = 'alert("Box not found.");';
    }

    return $returncode;
}

sub delbox {
    my LJ::Portal $self = shift;
    my ($portalconfig, $pboxid) = @_;

    my $returncode;

    if ($pboxid) {
        my $box = $portalconfig->get_box_by_id($pboxid);
        if ($box) {
            $portalconfig->remove_box($pboxid);

            # update the arrows on nearby boxes
            my $prevbox = $portalconfig->prev_box($box);
            my $nextbox = $portalconfig->next_box($box);
            $returncode .= LJ::Portal->get_portal_box_titlebar_update_script($portalconfig, $prevbox) if ($prevbox);
            $returncode .= LJ::Portal->get_portal_box_titlebar_update_script($portalconfig, $nextbox) if ($nextbox);

            $returncode .= qq {
                var boxid = "pbox$pboxid";
                var delbox = xGetElementById(boxid);
                if (delbox) animateClose(delbox);
            };
        } else {
            $returncode = 'alert("Box not found.");';
        }
    } else {
        $returncode = 'alert("Box not specified.");';
    }

    return $returncode;
}

sub resetbox {
    my LJ::Portal $self = shift;
    my ($pboxid, $portalconfig) = @_;

    my $returncode;

    if ($pboxid) {
        my $box = $portalconfig->get_box_by_id($pboxid);

        if ($box) {
            $box->set_default_props;

            $returncode .= LJ::Portal->get_portal_box_update_script($portalconfig, $box);
            $returncode .= LJ::Portal->get_portal_config_box_update_script($box);
            $returncode .= "hideConfigPortalBox($pboxid);\n";
        } else {
            $returncode = 'alert("Box not found.");';
        }
    } else {
        $returncode = 'alert("Box not specified.");';
    }

    return $returncode;
}

1;
