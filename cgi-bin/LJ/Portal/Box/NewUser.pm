package LJ::Portal::Box::NewUser; # <--- Change this
use base 'LJ::Portal::Box';
use strict;

######################## override this stuff ######################

our $_box_class = "NewUser";
our $_box_description = "New Users - Start Here";
our $_box_name = "New Users - Start Here";

sub generate_content {
    my $self = shift;
    my $content = '';
    my $pboxid = $self->pboxid;
    my $u = $self->{'u'};

    $content .= qq {
        <div class="NewUserBlurb">
            Get the most out of your journal  by putting your personal stamp on it.
            Some touches that will get your journal going:
        </div>
        <table style="width: 100%; border: 0px;">
            <tr>
                <td style="width: 50%;">
                    1) <a href="$LJ::SITEROOT/update.bml">Write</a> a journal entry<br />
                    2) <a href="$LJ::SITEROOT/editpics.bml">Upload</a> userpics<br />
                    3) <a href="$LJ::SITEROOT/editinfo.bml">Fill out</a> your <a href="$LJ::SITEROOT/userinfo.bml?user=$u->{user}">userinfo</a> page<br />
                </td>
                <td style="width: 50%;">
                     4) <a href="$LJ::SITEROOT/customize">Customize</a> the look of your journal<br />
                     5) <a href="$LJ::SITEROOT/interests.bml">Find</a> friends and communities<br />
                     6) <a href="$LJ::SITEROOT/users/$u->{user}/friends">Read</a> your Friends page<br />
                </td>
                <span class="NewUserMoreLink"><a href="$LJ::SITEROOT/manage">more</a></span>
            </tr>
        </table>
    };

    return $content;
}

# add by default if new user (account created after portal goes live date)
sub default_added {
    my $u = shift;

    return 1;
}

#######################################

sub box_description { $_box_description; }
sub box_name { $_box_name; };
sub box_class { $_box_class; }

1;
