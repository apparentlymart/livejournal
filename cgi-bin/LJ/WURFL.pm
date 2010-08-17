package LJ::WURFL;

use Storable qw(retrieve);

sub new {
	my $class = shift;
	return bless {}, $class;
}

sub load {
	my ($self, $file) = @_;

	my $retr = eval { retrieve($file) };
    if ($@) {
        warn $@;
        return 0;
    }

	if ($retr->{'wireless_devices'} && $retr->{'generic_devices'}) {
	    my %wireless_devices = map { $_ => $_ } @{$retr->{'wireless_devices'}};
	    my %generic_devices =  map { $_ => $_ } @{$retr->{'generic_devices'}};

	    $self->{'wireless_devices'} = \%wireless_devices;
	    $self->{'generic_devices'} =  \%generic_devices;

        return $self;
    } else {
        return 0;
    }
}

sub is_mobile {
	my $self = shift;
	my $ua = shift;

    while (length $ua) {
        return 0 if $self->{'generic_devices'}->{$ua};
        return 1 if $self->{'wireless_devices'}->{$ua};
        last unless $ua =~ /\//;
        $ua =~ s/^(.+)\/(.*)$/$1/;
    }

	return 0;
}

1;
