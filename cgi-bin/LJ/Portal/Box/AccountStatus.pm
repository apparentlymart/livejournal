package LJ::Portal::Box::AccountStatus; # <--- Change this
use base 'LJ::Portal::Box';
use strict;

######################## override this stuff ######################

our $_box_class = "AccountStatus";
our $_box_description = "View your account status";
our $_box_name = "Account Status";

sub generate_content {
    my $self = shift;
    my $content = '';
    my $pboxid = $self->pboxid;
    my $u = $self->{'u'};

    # gotta run the widget through the BML decoder because when it's returning
    # HTML it's gotta be HTML that javascript can understand, not BML. Jerks.

    my $status_widget_bml = LJ::Pay::status_widget($u, { nodetail_link => 0 } );
    $content .= Apache::BML::bml_decode($Apache::BML::cur_req, \$status_widget_bml, \$content);

    return $content;
}


#######################################


sub box_description { $_box_description; }
sub box_name { $_box_name; };
sub box_class { $_box_class; }

1;
