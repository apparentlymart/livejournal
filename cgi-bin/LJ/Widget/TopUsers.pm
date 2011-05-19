package LJ::Widget::TopUsers;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);

use LJ::ExtBlock;
use LJ::JSON;

# Keys to get data from ext_block
my %keys = ();

# 0 - get data from LJ::ExtBlock
# 1 - use debug data from %debug_data hash
# 2 - store debug data in LJ::ExtBlock and use it.
my $use_debug_data  = 0;

my %debug_data = (
    'ontd_authors'      => '[{"count":"2","userid":"3"},{"count":"1","userid":"4"}]',
    'ontd_commenters'   => '[{"count":"276","userid":"2"},{"count":"170","userid":"3"},{"count":"139","userid":"4"},{"count":"124","userid":"5"},{"count":"123","userid":"6"},{"count":"120","userid":"6"}]',
);

sub _fetch_data {
    %keys = (
        #'ontd_authors'      => { title => "widget.topusers.top5posters.title",   order => 1, data => [] },
        'ontd_commenters'   => { title => "widget.topusers.top5commenters.title", order => 2, data => [] },
    );

    foreach my $key (keys %keys) {

        my $json_data;
        if ($use_debug_data) {
            LJ::ExtBlock->create_or_replace($key, $debug_data{$key}) if $use_debug_data > 1;
            $json_data = $debug_data{$key};
        } else {
            my $block = LJ::ExtBlock->load_by_id($key);
            $json_data = $block->blocktext() if $block;
        }
        next unless $json_data;

        my $data = LJ::JSON->from_json($json_data);
        next unless ref($data) eq 'ARRAY';
        
        foreach (@$data) {
            my $count = $_->{count};
            my $user  = LJ::load_userid($_->{userid});

            my $userpic = undef;
            $userpic = $user->userpic() if $user;

            warn "Cannot load user with id=$_->{userid}\n" unless $user;
            warn "Cannot load userpic with id=$_->{userid}\n" unless $userpic;

            if ($count && $user && $userpic) {
                push @{$keys{$key}->{'data'}},
                    {
                        count   => $count,
                        userpic => $userpic ? $userpic->url : '',
                        display => $user->ljuser_display,
                        user    => $user->user,
                        url     => $user->journal_base,
                    };
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

    $ret .= "<div class='w-topcommenters w-ontd'>";
    $ret .= "<div class='w-head'>";
    $ret .= "<h2><span class='w-head-in'>Top commenters</span></h2>";
    $ret .= "<i class='w-head-corner'></i>";
    $ret .= "</div>";
    $ret .= "<div class='w-content' id='topcommentersbox'>";

    foreach my $key (@keys) {

        my $index = 1;
        $ret .= "<ol>";

        foreach my $data (@{$keys{$key}->{'data'}}) {

            # Element begin
            $ret .= "<li style='background-image: url($data->{userpic});'>";

            # User info
                        $ret .= "<a href='$data->{url}'>$data->{user} <span>$data->{'count'}</span></a>";

            # Element end
            $ret .= "</li>";

            $index++;
            last if $index > 6;
        }

        # Footer of coumn
        $ret .= "</ol>";
    }

    $ret .= "</div>";
    # Footer of whole widget
    $ret .= "</div>";

    return $ret;
}

1;
