package LJ::Portal::Box::UpdateJournal; # <--- Change this
use base 'LJ::Portal::Box';
use strict;

######################## override this stuff ######################

our $_box_description = 'A handy box for updating your journal.';
our $_box_name = "Quick Update";
our $_box_class = "UpdateJournal";

sub generate_content {
    my $self = shift;

    my $moreopts = 0;
    if ($moreopts) {
        return $self->print_big_form;
    } else {
        return $self->print_small_form;
    }
}

sub print_big_form {
    my $self = shift;
    my $content = '';
    my $pboxid = $self->pboxid;
    my $u = $self->{'u'};

    LJ::need_res('js/entry.js');

    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
    $year+=1900;
    $mon=sprintf("%02d", $mon+1);
    $mday=sprintf("%02d", $mday);
    $min=sprintf("%02d", $min);

    $content = "<form method='post' action='$LJ::SITEROOT/update.bml' id='updateForm' name='updateForm'>";

    my $entry = {
            'mode' => "update",
            'auth_as_remote' => 1,
            'datetime' => "$year-$mon-$mday $hour:$min",
            'remote' => $u,
            'clientversion' => "WebUpdate/2.0.0",
            'richtext' => 0,
            'richtext_on' => 0,
        };

    $content .= LJ::entry_form($entry);

    $content .= '</form>';

    return $content;
}

sub print_small_form {
    my $self = shift;
    my $content = '';
    my $pboxid = $self->pboxid;
    my $u = $self->{'u'};

    my $datetime = LJ::entry_form_date_widget;
    my $subjectwidget = LJ::entry_form_subject_widget('UpdateBoxSubject');
    my $entrywidget = LJ::entry_form_entry_widget('UpdateBoxEvent');
    my $postto = LJ::entry_form_postto_widget($u);

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
                $postto
                <input type="submit" value="$updatetitle" name="postentry" /> <input type="submit" name="moreoptsbtn" value="$moreoptstitle"/>
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
