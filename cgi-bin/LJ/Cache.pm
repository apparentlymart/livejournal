#!/usr/bin/perl
#
# LJ::Cache class
# See perldoc documentation at the end of this file.
#
# -------------------------------------------------------------------------
#
# This package is released under the LGPL (GNU Library General Public License)
#
# A copy of the license has been included with the software as LGPL.txt.  
# If not, the license is available at:
#      http://www.gnu.org/copyleft/library.txt
#
# -------------------------------------------------------------------------
#

package LJ::Cache;

use strict;
use vars qw($VERSION);
$VERSION = '1.0';

sub new {
    my ($class, $args) = @_;
    my $self = {};
    bless $self, ref $class || $class;
    
    $self->init($args);
    return $self;
}

sub walk_items {
    my ($self, $code) = @_;
    my $iter = $self->{'head'};
    while ($iter) {
        my $it = $self->{'items'}->{$iter};
        $code->($iter, $it->[3], $it->[4]);
        $iter = $it->[2];
    }
}

sub init {
    my ($self, $args) = @_;

    $self->{'head'} = 0;
    $self->{'tail'} = 0;
    $self->{'items'} = {}; # key -> [ prev_key, value, next_key, bytes, instime ]
    $self->{'size'} = 0;
    $self->{'bytes'} = 0;
    $self->{'maxsize'} = $args->{'maxsize'}+0;
    $self->{'maxbytes'} = $args->{'maxbytes'}+0;
}

sub get_item_count {
    my $self = shift;
    $self->{'size'};
}

sub get_byte_count {
    my $self = shift;
    $self->{'bytes'};
}

sub get_max_age {
    my $self = shift;
    return undef unless $self->{'tail'};
    return $self->{'items'}->{$self->{'tail'}}->[4];
}

sub validate_list
{
    my ($self, $source) = @_;
    print "Validate list: $self->{'size'} (max: $self->{'maxsize'})\n";
    
    my $count = 1;
    if ($self->{'size'} && ! defined $self->{'head'}) {
	die "$source: no head pointer\n";
    }
    if ($self->{'size'} && ! defined $self->{'tail'}) {
	die "$source: no tail pointer\n";
    }
    if ($self->{'size'}) {
	print "  head: $self->{'head'}\n";
	print "  tail: $self->{'tail'}\n";
    }

    my $iter = $self->{'head'};
    my $last = undef;
    while ($count <= $self->{'size'}) {
	if (! defined $iter) {
	    die "$source: undefined iterator\n";
	}
	my $item = $self->{'items'}->{$iter};
	unless (defined $item) {
	    die "$source: item '$iter' isn't in items\n";
	}
	my $prevtext = $item->[0] || "--";
	my $nexttext = $item->[2] || "--";
	print "  #$count ($iter): [$prevtext, $item->[1], $nexttext]\n";
	if ($count == 1 && defined($item->[0])) {
	    die "$source: Head element shouldn't have previous pointer!\n";
	}
	if ($count == $self->{'size'} && defined($item->[2])) {
	    die "$source: Last element shouldn't have next pointer!\n";
	}
	if (defined $last && ! defined $item->[0]) {
	    die "$source: defined \$last but not defined previous pointer.\n";
	}
	if (! defined $last && defined $item->[0]) {
	    die "$source: not defined \$last but previous pointer defined.\n";
	}
	if (defined $item->[0] && defined $last && $item->[0] ne $last)
	{
	    die "$source: Previous pointer is wrong.\n";
	}

	$last = $iter;
	$iter = defined $item->[2] ? $item->[2] : undef;
	$count++;
    }
}

sub drop_tail
{
    my $self = shift;

    ## who's going to die?
    my $to_die = $self->{'tail'};

    ## set the tail to the item before the one dying.
    $self->{'tail'} = $self->{'items'}->{$to_die}->[0];

    ## adjust the forward pointer on the tail to be undef
    if (defined $self->{'tail'}) {
	undef $self->{'items'}->{$self->{'tail'}}->[2];
    }

    ## kill the item
    my $bytes = $self->{'items'}->{$to_die}->[3];
    delete $self->{'items'}->{$to_die};

    ## shrink the overall size
    $self->{'size'}--;
    $self->{'bytes'} -= $bytes;
}

sub print_list {
    my ($self) = @_;
    print "Size: $self->{'size'} (max: $self->{'maxsize'})\n";

    my $count = 1;
    my $iter = $self->{'head'};
    while (defined $iter) { #$count <= $self->{'size'}) {
	my $item = $self->{'items'}->{$iter};
	print "$count: $iter = $item->[1]\n";
	$iter = $item->[2];
 	$count++;
    }
}

sub get {
    my ($self, $key) = @_;

    if (exists $self->{'items'}->{$key}) 
    {
	my $item = $self->{'items'}->{$key};

	# promote this to the head
	unless ($self->{'head'} eq $key)
	{
	    if ($self->{'tail'} eq $key) {
		$self->{'tail'} = $item->[0];
	    }
	    # remove this element from the linked list.
	    my $next = $item->[2];
	    my $prev = $item->[0];
	    if (defined $next) { $self->{'items'}->{$next}->[0] = $prev; }
	    if (defined $prev) { $self->{'items'}->{$prev}->[2] = $next; }
	    
	    # make current head point backwards to this item
	    $self->{'items'}->{$self->{'head'}}->[0] = $key;
	    
	    # make this item point forwards to current head, and backwards nowhere
	    $item->[2] = $self->{'head'};
	    undef $item->[0];
	    
	    # make this the new head
	    $self->{'head'} = $key;
	}
	
	return $item->[1];
    }
    return undef;
}

# bytes is optional
sub set {
    my ($self, $key, $value, $bytes) = @_;
    
    $self->drop_tail() while ($self->{'maxsize'} && 
                              $self->{'size'} >= $self->{'maxsize'} &&
                              ! exists $self->{'items'}->{$key}) ||
                              ($self->{'maxbytes'} && $self->{'size'} &&
                               $self->{'bytes'} + $bytes >= $self->{'maxbytes'} &&
                               ! exists $self->{'items'}->{$key});
    
    
    if (exists $self->{'items'}->{$key}) {
	# update the value
	my $item = $self->{'items'}->{$key};
	$item->[1] = $value;
        my $bytedelta = $bytes - $item->[3];
        $self->{'bytes'} += $bytedelta;
        $item->[3] = $bytes;
    }
    else {
	# stick it at the end, for now
	$self->{'items'}->{$key} = [undef, $value, undef, $bytes, time() ];
	if ($self->{'size'}) {
	    $self->{'items'}->{$self->{'tail'}}->[2] = $key;
	    $self->{'items'}->{$key}->[0] = $self->{'tail'};
	} else {
	    $self->{'head'} = $key;
	}
	$self->{'tail'} = $key;
	$self->{'size'}++;
	$self->{'bytes'} += $bytes;
    }

    # this will promote it to the top:
    $self->get($key);
}

1;
__END__

=head1 NAME

LJ::Cache - LRU Cache

=head1 SYNOPSIS

  use LJ::Cache;
  my $cache = new LJ::Cache { 'maxsize' => 20 };
  my $value = $cache->get($key);
  unless (defined $value) {
      $val = "load some value";
      $cache->set($key, $value);
  }

=head1 DESCRIPTION

This class implements an LRU dictionary cache.  The two operations on it
are get() and set(), both of which promote the key being referenced to
the "top" of the cache, so it will stay alive longest.

When the cache is full and and a new item needs to be added, the oldest
one is thrown away.

You should be able to regenerate the data at any time, if get() 
returns undef.

This class is useful for caching information from a slower data source
while also keeping a bound on memory usage.

=head1 AUTHOR

Brad Fitzpatrick, bradfitz@bradfitz.com

=cut
