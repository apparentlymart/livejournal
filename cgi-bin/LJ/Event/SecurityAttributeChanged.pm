package LJ::Event::SecurityAttributeChanged;

use strict;

use Carp qw(croak);
use LJ::TimeUtil;

use base 'LJ::Event';

sub new {
    my ($class, $u, $opts) = @_;
    croak 'Not an LJ::User' unless LJ::isu($u);

    my $_get_logtime = sub {
        my $u       = shift;
        my $action  = shift;
        my $opts    = shift;

        my $ip      = $opts->{ip};

        die "Missing credentials" unless $ip && $action;

        # $action == 1 -- deleted
        my $extra = (1 == $action) ? 'new=D&old=V' : 'new=V&old=D';

        # TODO: change this to use LJ::User::Userlog
        my $dbr = LJ::get_cluster_reader($u);
        my $sth = $dbr->prepare(
            "SELECT logtime, ip".
            " FROM userlog".
            " WHERE userid=? AND extra=?".
            " ORDER BY logtime DESC LIMIT 2");
        $sth->execute($u->{userid},$extra);
        my ($logtime, $logip) = $sth->fetchrow_array;

        # Check for errors
        die "This event (uid=$u->{userid}, extra=$extra) was not found in logs" unless $logtime;

        my ($logtime2, $logip2) = $sth->fetchrow_array;
        die "Second record about this event was found in log"
            if $logtime2 && $logtime2 == $logtime && ($logip2 ne $logip);

        die "The event (uid=$u->{userid}, extra=$extra, logtime=$logtime) was found in log,".
            " but with wrong ip address ($logip, but not $ip)"
                if $ip ne $logip;

        return $logtime;
    };

    my $_get_rename_id = sub {
        my $u       = shift;
        my $action  = shift;
        my $opts    = shift;

        my $ip              = $opts->{ip};
        my $old_username    = $opts->{old_username};
        my $userid          = $u->{userid};

        # TODO: check is $u a user object?
        die "Missing credentials" unless $ip && $action && $old_username;

        my $infohistory = LJ::User::InfoHistory->get( $u, 'username' );
        my ($latest_record) =
            reverse
            sort { $a->timechange_unix <=> $b->timechange_unix }
            @$infohistory;

        die "This event (uid=$userid, what=username) was not found in logs"
            unless $latest_record;

        my $timechange = $latest_record->timechange_unix;
        my $oldvalue   = $latest_record->oldvalue;

        die "Event (uid=$userid, what=username) was not found in logs".
            " has wrong old username: $oldvalue instead of $old_username"
                if $oldvalue ne $old_username;

        return $timechange;
    };

    my %actions = (
        'account_deleted'   => [ 1, $_get_logtime ],
        'account_activated' => [ 2, $_get_logtime ],
        'account_renamed'   => [ 3, $_get_rename_id ],
    );

    die 'Wrong action parameter' unless exists($actions{$opts->{action}});

    my $action = $actions{$opts->{action}}[0];
    return
        $class->SUPER::new($u,$action,$actions{$opts->{action}}[1]->($u,$action,$opts));
}

sub is_common { 1 } # As seen in LJ/Event.pm, event fired without subscription

# Override this with a false value make subscriptions to this event not show up in normal UI
sub is_visible { 0 }

# Whether Inbox is always subscribed to
sub always_checked { 0 }

sub is_significant { 1 }

# override parent class subscriptions method to always return
# a subscription object for the user
sub subscriptions {
    my ($self, %args) = @_;
    my $cid   = delete $args{'cluster'};  # optional
    my $limit = delete $args{'limit'};    # optional
    croak("Unknown options: " . join(', ', keys %args)) if %args;
    croak("Can't call in web context") if LJ::is_web_context();

    my @subs;
    my $u = $self->u;

    if ($cid == $u->clusterid) {
        my $row = { userid  => $self->u->{userid},
                    ntypeid => LJ::NotificationMethod::Email->ntypeid, # Email
                  };

        push @subs, LJ::Subscription->new_from_row($row);
        $limit--;
    }

    push @subs, eval { $self->SUPER::subscriptions(cluster => $cid,
                                                   limit   => $limit) };

    return @subs;
}

sub _arg1_to_mlkey {
    my $action = shift;
    my @ml_actions = (
        'account_deleted',
        'account_activated',
        'account_renamed',
    );

    return 'esn.security_attribute_changed.' . $ml_actions[$action-1] . '.';
}

sub as_alert {
    my ($self, $u) = @_;
    my $lang    = $u->prop('browselang');
    return LJ::Lang::get_text($lang, _arg1_to_mlkey($self->arg1) . 'alert',
        undef,
        {
            'user' => $u->ljuser_display()
        });
}

sub as_email_subject {
    my ($self, $u) = @_;
    my $lang    = $u->prop('browselang');
    return LJ::Lang::get_text($lang, _arg1_to_mlkey($self->arg1) . 'email_subject',
        undef,
        {
            'user' => $u->{user}
        });
}

sub _as_email {
    my ($self, $u, $is_html) = @_;

    my $lang    = $u->prop('browselang');
    my $action  = $self->arg1;
    my $logtime = $self->arg2;

    my $_get_params_from_logtime = sub {
        my ($u, $logtime) = @_;

        # TODO: change this to use LJ::User::Userlog
        my $userid = $u->{userid};
        my $dbr = LJ::get_cluster_reader($u);
        my ($datetime, $remoteid, $ip, $uniq) = $dbr->selectrow_array(
            "SELECT FROM_UNIXTIME(logtime), remoteid, ip, uniq".
            " FROM userlog".
            " WHERE userid=$userid AND logtime=$logtime LIMIT 1");
        return undef unless $remoteid;
        return (
            datetime    => $datetime,
            remoteid    => $remoteid,
            ip          => $ip,
            uniq        => $uniq,
            userid      => $userid,
        );
    };

    my $_get_params_from_rename_id = sub {
        my ($u, $timechange_stamp) = @_;
        my $userid = $u->{userid};

        my $infohistory = LJ::User::InfoHistory->get( $u, 'username' );
        my ($infohistory_record) =
            grep { $_->timechange_unix == $timechange_stamp }
            @$infohistory;

        unless ($infohistory_record) {
            croak "This event (uid=$userid, what=username) was not found in logs";
            return undef;
        }

        my $old_name = $infohistory_record->oldvalue;
        my $other    = $infohistory_record->other;

        # Convert $timechange from GMT to local for user
        my $offset = 0;
        LJ::get_timezone($u, \$offset);
        my $timechange = LJ::TimeUtil->mysql_time($timechange_stamp + 60*60*$offset, 0);

        $other =~ /ip=(.+)/;
        my ($ip) = ($1);

        return (
            oldname     => $old_name,
            ip          => $ip,
            datetime    => $timechange,
        );
    };

    my @actions = (
        $_get_params_from_logtime,
        $_get_params_from_logtime,
        $_get_params_from_rename_id,
    );

    my %logparams = $actions[$action-1]($u, $logtime);

    if (%logparams && $logparams{datetime}) {
        ($logparams{date}, $logparams{time}) = split(/ /, $logparams{datetime});
    }

    my $vars = {
            'user'      => $u->{user},
            'username'  => $u->{name},
            'sitename'  => $LJ::SITENAME,
            'siteroot'  => $LJ::SITEROOT,
            %logparams,
    };

    return LJ::Lang::get_text($lang, _arg1_to_mlkey($action) . 'email_text', undef, $vars);
}

sub as_email_string {
    my ($self, $u) = @_;
    return '' unless $u;
    return _as_email($self, $u, 0);
}

sub as_email_html {
    my ($self, $u) = @_;
    return '' unless $u;
    return _as_email($self, $u, 1);
}

1;
