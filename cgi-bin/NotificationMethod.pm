package LJ::NotificationMethod;

use strict;
use vars qw/ $AUTOLOAD /;
use Carp qw/ croak /;

# this mofo is basically just an interface
# Mischa's contribution:  "straight up"
sub new    { croak "can't instantiate base LJ::NotificationMethod" }
sub notify { croak "can't call notification on LJ::NotificationMethod base class" }

sub can_digest { 0 }

sub new_from_subscription { 
    croak "can't instantiate base LJ::NotificationMethod from subscription"
}

# returns the class name, given an ntypid
sub class {
    my ($class, $ntypeid) = @_;
    my $dbh = LJ::get_db_writer()
        or die "unable to contact db master";

    return $dbh->selectrow_array("SELECT class FROM notifytypelist WHERE ntypeid=?",
                                 undef, $ntypeid);
}

sub ntypeid {
    my ($class_self) = @_;
    my $class = ref $class_self ? ref $class_self : $class_self;

    # TODO: cache this
    my $dbh = LJ::get_db_writer()
        or die "unable to contact db master";

    my $get = sub {
        my $rv = $dbh->selectrow_array
            ("SELECT ntypeid FROM notifytypelist WHERE class=?",
             undef, $class);
    };

    my $etypeid = $get->();
    return $etypeid if $etypeid;

    $dbh->do("INSERT IGNORE INTO notifytypelist SET class=?", undef, $class);
    return $get->() or die "Failed to allocate class number";
}

1;
