#
# This module knows about all LJ configuration variables, their types,
# and validator functions, so missing, incorrect, deprecated, or
# outdated configuration can be brought to the admin's attention.
#

package LJ::ConfCheck;

use strict;
no strict 'refs';

my %singleton;  # key -> 1

my %conf;

require LJ::ConfCheck::General;
eval { require LJ::ConfCheck::Local; };
die "eval error: $@" if $@ && $@ !~ /^Can\'t locate/;

# these variables are LJ-application singletons, and not configuration:

sub add_singletons {
    foreach (@_) {
        $singleton{$_} = 1;
    }
}

sub add_conf {
    my $key = shift;
    my %opts = @_;
    $conf{$key} = \%opts;
}

sub get_keys {
    my %seen;   # $FOO -> 1

    my $package = "main::LJ::";
    use vars qw(*stab *thingy);
    *stab = *{"main::"};

    while ($package =~ /(\w+?::)/g) {
        *stab = ${stab}{$1};
    }

    while (my ($key,$val) = each(%stab)) {
        return if $DB::signal;
        next if $key =~ /[a-z]/ || $key =~ /::$/;

        my @new;
        local *thingy = $val;
        if (defined $thingy) {
            push @new, "\$$key";
        }
        if (defined @thingy) {
            push @new, "\@$key";
        }
        if (defined %thingy) {
            push @new, "\%$key";
        }
        foreach my $sym (@new) {
            next if $singleton{$sym};
            $seen{$sym} = 1;
        }
    }


    return sort keys %seen;
}

sub config_errors {
    my %ok;
    my @errors;

    # iter through all config, check if okay

    my @keys = get_keys();
    foreach my $k (@keys) {
        if (!$conf{$k}) {
            push @errors, "Unknown config option: $k";
        }
    }
    return @errors;
}

1;
