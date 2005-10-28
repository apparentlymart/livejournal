package LJ::Portal::Box::UpdateJournal; # <--- Change this
use base 'LJ::Portal::Box';
use strict;

######################## override this stuff ######################

our $_box_description = 'A handy box for updating your journal.';
our $_box_name = "Quick Update";
our $_box_class = "UpdateJournal";

sub generate_content {
    my $self = shift;

    my $content = '';
    my $pboxid = $self->pboxid;
    my $u = $self->{'u'};

    my $datetime = LJ::entry_form_date_widget();
    my $subjectwidget = LJ::entry_form_subject_widget('UpdateBoxSubject');
    my $entrywidget = LJ::entry_form_entry_widget('UpdateBoxEvent');
    my $postto = LJ::entry_form_postto_widget($u, 'UpdateBoxPostTo');
    my $securitywidget = LJ::entry_form_security_widget($u, 'UpdateBoxSecurity');
    my $tagswidget = LJ::entry_form_tags_widget();

    $postto = $postto ? $postto . '<br/><br/>' : '';

    my $formauth = LJ::form_auth();

    $content .= "<form action='$LJ::SITEROOT/update.bml' method='POST' name='updateform'>";

    # translation stuff:
    my $subjecttitle =  BML::ml('portal.update.subject');
    my $eventtitle = BML::ml('portal.update.entry');
    my $updatetitle = BML::ml('/update.bml.btn.update');
    my $moreoptstitle = BML::ml('portal.update.moreopts');

    $content .= qq {
            $formauth
                <input type="hidden" name="realform" value="1" />
                $subjecttitle<br/>
                $subjectwidget<br/>
                $eventtitle<br/>
                $entrywidget<br/>
                <table width="100%">
                <tr><td valign="bottom" align="left">
                $postto</td><td align="left" valign="top">
                $securitywidget
                </tr> <tr>
                <td valign="bottom" align="top" width="100%" colspan="2">
                $tagswidget</td>
                </tr></table>
                <br/>
                <input type="submit" value="$updatetitle" name="postentry" onclick="return portal_settime();" /> <input type="submit" name="moreoptsbtn" value="$moreoptstitle"/>
                $datetime
                </form>
            };

    return $content;
}


#######################################


sub box_description { $_box_description; }
sub box_name { $_box_name; };
sub box_class { $_box_class; }
#sub config_props { $_config_props; }
#sub prop_keys { $_prop_keys; }

1;
