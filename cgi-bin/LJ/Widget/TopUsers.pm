package LJ::Widget::TopUsers;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);

use LJ::ExtBlock;

# Keys to get data from ext_block
my %keys = (
    'ontd_authors'      => { title => "widget.topusers.top5commenters.title",   order => 2 },
    'ontd_commenters'   => { title => "widget.topusers.top5posters.title",      order => 2 },
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
    $ret .= "<table><tr>";

    foreach my $key (@keys) {

        # Start a column
        $ret .= "<td>";

        # Header of widget column
        $ret .= "<ul class=\"top-users-widget\"><dt>".$keys{$key}->{'title'}."</dt><dd>";

        # Header of table columns
        $ret .= '<li>' .
                    BML::ml('widget.topusers.head.nr') .
                    ' | ' .
                    BML::ml('widget.topusers.head.users') .
                '</li>';

        my $index = 1;

        foreach my $data (@{$keys{$key}->{'data'}}) {

            # Element begin
            $ret .= "<li>";

            # 1. Nr
            $ret .= "$index | ";

            # 2. Userpic or paceholder
            if ($data->{'userpic'}) {
                $ret .= "<img src='" . $data->{'userpic'} . "' />";
            } else {
                $ret .= "--- No user pic ---";
            }

            # 3. User info
            $ret .= " | ";
            $ret .= $data->{'display'};

            # Element end
            $ret .= "</li>";

            $index++;
        }

        # Footer of coumn
        $ret .= "</dd></ul>";
        $ret .= "</td>";
    }

    # Footer of whole widget
    $ret .= "</tr></table>";

    return $ret;
}

1;
