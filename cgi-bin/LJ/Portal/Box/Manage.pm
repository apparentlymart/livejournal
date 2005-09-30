package LJ::Portal::Box::Manage; # <--- Change this
use base 'LJ::Portal::Box';
use strict;

######################## override this stuff ######################

our $_box_class = "Manage";
our $_box_description = "Manage your account";
our $_box_name = "Account Management";

sub generate_content {
    my $self = shift;
    my $content = '';
    my $pboxid = $self->pboxid;
    my $u = $self->{'u'};

    $content .= qq {
        <table style="width: 100%;">
            <tr>
            <td style="width: 50%;">
            <a href="$LJ::SITEROOT/friends/edit.bml">Edit Friends</a><br />
            <a href="$LJ::SITEROOT/editinfo.bml?authas=$u->{user}">Edit Personal Information</a><br />
            <a href="$LJ::SITEROOT/editpics.bml">Upload and Manage Your Userpics</a><br />

            </td>
            <td style="width: 50%;">
            <a href="$LJ::SITEROOT/community/manage.bml">Manage Communities</a><br />

            <a href="$LJ::SITEROOT/modify.bml">Set Your Mood Theme</a><br />
            <a href="$LJ::SITEROOT/changepassword.bml">Change Account Password</a><br />
                </td>
            </tr>
        </table>
    };

    return $content;
}


#######################################


sub box_description { $_box_description; }
sub box_name { $_box_name; };
sub box_class { $_box_class; }

1;
