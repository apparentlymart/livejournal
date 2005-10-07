package LJ::Portal::Box::Birthdays; # <--- Change this
use base 'LJ::Portal::Box';
use strict;

######################## override this stuff ######################

our $_box_class = "Birthdays";
our $_prop_keys = { 'Show' => 1 };
our $_config_props = {
    'Show' => { 'type'    => 'integer',
                'desc'    => 'Maximum number of friends to show',
                'max'     => 50,
                'min'     => 1,
                'maxlength' => 2,
                'default' => 5} };
our $_box_description = 'Show upcoming birthdays of your friends.';
our $_box_name = "Friends' Birthdays";

sub generate_content {
    my $self = shift;
    my $content = '';
    my $userid = $self->{'u'}->{'userid'};

    my @bdays = $self->{'u'}->get_friends_birthdays;

    if (@bdays && scalar @bdays > 0) {

        # sort upcoming birthdays
        my $now = DateTime->now;
        $now = $now->month . '-' . $now->day;

        my $i = 0;
        while(($bdays[0]->[0] . '-' . $bdays[0]->[1]) lt $now && $i++ < $#bdays) {
            push @bdays, shift @bdays;
        }

        # cut the list down
        my $show = $self->get_prop('Show');
        if (@bdays > $show) { @bdays = @bdays[0..$show-1]; }

        $content .= "<table width='100%'>";
        my $add_ord = BML::get_language() =~ /^en/i;
        foreach my $bi (@bdays)
        {
            my $mon = BML::ml( LJ::Lang::month_short_langcode($bi->[0]) );
            my $day = $bi->[1];
            $day .= LJ::Lang::day_ord($bi->[1]) if $add_ord;

            $content .= "<tr><td nowrap='nowrap'><b>" . LJ::ljuser($bi->[2]) . "</b></td>";
            $content .= "<td align='right' nowrap='nowrap'>$mon $day</td>";
            $content .= "<td align='right'><a href=\"$LJ::SITEROOT/shop/view.bml?gift=1&for=$bi->[2]\"><img src=\"$LJ::IMGPREFIX/btn_gift.gif\" alt=\"Buy this user a gift\" align=\"right\" /></a></td></tr>";
        }
        $content .= "</table>";
    } else {
        $content .= "(No upcoming friend's birthdays.)";
    }

    return $content;
}


#######################################


sub box_description { $_box_description; }
sub box_name { $_box_name; };
sub config_props { $_config_props; }
sub prop_keys { $_prop_keys; }
sub box_class { $_box_class; }

# caching options
sub cache_global { 0; } # cache per-user
sub cache_time { 30 * 60; } # check etag every 30 minutes
sub etag {
    my $self = shift;
    my $now = DateTime->now;

    return $self->get_prop('Show') + $now->day;
}

1;
