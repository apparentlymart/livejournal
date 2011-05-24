package LJ::WURFL::Parser;
use strict;

use XML::Parser;
use Storable qw(nstore);

use base 'LJ::WURFL';

sub parse {
    my ($self, $file) = @_;

    my ($id, $ua, $fb) = 3 x '';
    my $is_wireless = 0;

    my @wireless_devices = ();
    my @generic_devices  = ();

    my $_handle_wurfl_start = sub {
        my $expat = shift;
        my $element = shift;

        if ($element eq 'capability') {
            my $at_wireless_attr = 0;
            while (@_) {
                my $attr = shift;
                my $val  = shift;
                if ($attr eq 'name' && $val eq 'is_wireless_device') {
                    $at_wireless_attr = 1;
                }

                if ($attr eq 'value' && $at_wireless_attr) {
                    $is_wireless = $val;
                    $at_wireless_attr = 0;
                }
            }

            return;
        }

        if ($element eq 'device') {

            while (@_) {
                my $attr = shift;
                my $val  = shift;

                if ($attr eq 'id') {
                    $id = $val;
                    next;
                }

                if ($attr eq 'user_agent') {
                    $ua = $val;
                    next;
                }

                if ($attr eq 'fall_back') {
                    $fb = $val;
                    next;
                }

                if ($attr eq 'actual_device_root') {
                    next;
                }

                print "$attr -> $val\n";
            }

        }
    };

    my $_handle_wurfl_end = sub {
        my ($expat, $element) = @_;

        return unless $element eq 'device';

        # Add one element to our data.
        my $device_model = ($fb && $fb ne 'root') ? $fb : $id;
        if ($is_wireless ne 'false') {
            push @wireless_devices, $ua if $ua;
        } else {
            push @generic_devices, $ua if $ua;
        }

        ($id, $ua, $fb) = 3 x '';
        $is_wireless = 0;
    };

    my $parser = new XML::Parser(
        Handlers => {
            Start => $_handle_wurfl_start,
            End   => $_handle_wurfl_end,
        }
    );

    $parser->parsefile($file);

    print "Keys loaded: ",
        (scalar @wireless_devices), " for wireless and ",
        (scalar @generic_devices), " for generic devices.\n";

    my %wireless_devices = map { $_ => $_ } @wireless_devices;
    my %generic_devices = map { $_ => $_ } @generic_devices;

    # OK, now we has a flat list of ua-keys.
    $self->{'wireless_devices'} = \%wireless_devices;
    $self->{'generic_devices'} = \%generic_devices;

    return 1;
}

sub store {
    my ($self, $file) = @_;
    nstore(
        {
            generic_devices     => [ keys %{$self->{'generic_devices'}}  ],
            wireless_devices    => [ keys %{$self->{'wireless_devices'}} ],
        },
    $file);
    return 0;
}

1;
