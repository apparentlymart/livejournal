package LJ::Portal::Box::Frank; # <--- Change this
use base 'LJ::Portal::Box';
use strict;

######################## override this stuff ######################

our $frankpics = {'hover' => 'Baa', 'irish' => 'Irish', 'lights' => 'Lights',
                  'newyear' => 'New Years', 'normal' => 'Normal',
                  'pee' => 'Baad Frank', 'val' => 'Valentine', 'xmas' => 'Xmas'};

our $_box_class = "Frank";
our $_box_description = 'Frank The Livejournal Mascot';
our $_box_name = "Frank";
our $_prop_keys = { 'Image' => 0, };
our $_config_props = { 'Image' => { 'type'      => 'dropdown',
                                    'desc'      => 'Image',
                                    'items'     => $frankpics,
                                    'default'   => 'normal',},
                   };


sub initialize {
    my $self = shift;
}

sub generate_content {
    my $self = shift;
    my $content = '';
    my $goatimg = $self->get_prop('Image');

    $content = qq {
        <div class="PortalFrank">
            <img src="$LJ::SITEROOT/img/goat-$goatimg.gif">
        </div>
    };

    return $content;
}


#######################################


sub box_description { $_box_description; }
sub box_name { $_box_name; };
sub box_class { $_box_class; }
sub config_props { $_config_props; }
sub prop_keys { $_prop_keys; }

1;
