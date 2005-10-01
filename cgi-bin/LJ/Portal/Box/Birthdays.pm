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
        # find next upcoming birthday element
        my $now = DateTime->now;
        my $timedist = -1;
        my $bdaysi = -1;
        my $closesti = -1;
        foreach my $bi (@bdays) {
            $bdaysi++;
            if ($bi->[0] == $now->month && $bi->[1] == $now->day) {
                $closesti = $bdaysi;
                last;
            }

            my $bdate = DateTime->new(
                                      month => $bi->[0],
                                      day   => $bi->[1],
                                      year  => $now->year,
                                      );
            if ($bdate) {
                my $timeoffset = $bdate->subtract_datetime_absolute($now);
                if (DateTime->compare( $bdate, $now ) >= 0) {
                    if ($timedist < 0 || $timeoffset->seconds <= $timedist) {
                        $timedist = $timeoffset->seconds;
                        $closesti = $bdaysi;
                    }
                }
            }
        }

        if ($closesti >= 0) {
            # rotate bdays
            for (my $i = 0; $i < $closesti; $i++) {
                push @bdays, shift @bdays;
            }
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
            $content .= "<td><a href=\"$LJ::SITEROOT/shop/view.bml?gift=1&for=$bi->[2]\"><img src=\"$LJ::IMGPREFIX/btn_gift.gif\" /></a></td></tr>";
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

1;
