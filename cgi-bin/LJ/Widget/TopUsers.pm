package LJ::Widget::TopUsers;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);

use LJ::ExtBlock;

# Keys to get data from ext_block
my %keys = (
    'ontd_authors'      => { title => "widget.topusers.top5commenters.title",   order => 2 },
    #'ontd_commenters'   => { title => "widget.topusers.top5posters.title",      order => 2 },
);

# 0 - get data from LJ::ExtBlock
# 1 - use debug data from %debug_data hash
# 2 - store debug data in LJ::ExtBlock and use it.
my $use_debug_data  = 0;

my %debug_data = (
    'ontd_authors'      => '[{"count":"2","userid":"3"},{"count":"1","userid":"4"}]',
    'ontd_commenters'   => '[{"count":"276","userid":"2"},{"count":"170","userid":"3"},{"count":"139","userid":"4"},{"count":"124","userid":"5"},{"count":"123","userid":"6"}]',
);

sub _fetch_data {
    foreach my $key (keys %keys) {
        my $data;

        if ($use_debug_data) {
            LJ::ExtBlock->create_or_replace($key, $debug_data{$key}) if $use_debug_data > 1;
            $data = $debug_data{$key};
        } else {
            my $block = LJ::ExtBlock->load_by_id($key);
            $data = $block->blocktext() if $block;
        }

        next unless $data;

        $data =~ s/\[|\]//g;
        while ($data) {
            $data =~ s/\{([^\}]*)\},?//;
            if ($1) {
                my ($count, $user) = 2 x undef;
                foreach my $pair (split(/,/, $1)) {
                $pair =~ s/\{|\}|\"//g;
                    my ($name, $value) = split(/:/, $pair);
                    if ('count' eq $name) {
                        $count = $value;
                    } elsif ('userid' eq $name) {
                        $user = LJ::load_userid($value);
                        warn "Cannot load user with id=$value\n" unless $user;
                    }
                }
                if ($count && $user) {
                    my $userpic = $user->userpic();
                    $userpic = $userpic->url if $userpic;
                    push @{$keys{$key}->{'data'}},
                        {
                            count   => $count,
                            userpic => $userpic,
                            display => $user->ljuser_display(),
                        };
                }
            }
        }
        @{$keys{$key}->{'data'}} = sort { $b->{'count'} <=> $a->{'count'} } @{$keys{$key}->{'data'}};
        $keys{$key}->{'title'} = BML::ml($keys{$key}->{'title'});
    }
}

sub render_body {
    my $class = shift;
    my %opts = @_;

    return '' unless LJ::is_enabled('widget_top_users');

    $class->_fetch_data();

    my $ret = '';

    my @keys = sort { $keys{$a}->{'order'} <=> $keys{$b}->{'order'} } keys %keys;

    # Head of whole widget
    $ret .= "<div class='w-topusers w-ontd'><div class='w-head'><h2><span class='w-head-in'>". $class->ml('widget.topusers.spotlight.title') ."</span></h2>
    <i class='w-head-corner'></i></div><div class='w-content'>";

    foreach my $key (@keys) {
	
		# Header of widget column
        $ret .= "<h3>".$keys{$key}->{'title'}."</h3>";

        my $index = 1;
		$ret .= "<ol>";

        foreach my $data (@{$keys{$key}->{'data'}}) {

            # Element begin
            $ret .= "<li>";

            # User info
            $ret .= $data->{'display'};
			$ret .= "<span class='num'>" . $data->{'count'} . "</span>";

            # Element end
            $ret .= "</li>";

            $index++;
        }

        # Footer of coumn
        $ret .= "</li></ol>";
    }

    # Footer of whole widget
    $ret .= "</div></div>";

    return $ret;
}

1;
