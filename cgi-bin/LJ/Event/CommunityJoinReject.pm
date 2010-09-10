package LJ::Event::CommunityJoinReject;
use strict;
use Carp qw(croak);
use base 'LJ::Event';

sub new {
    my ($class, $u, $cu, $mu, $maintu, $reason) = @_;
    foreach ($u, $cu) {
        croak 'Not an LJ::User' unless LJ::isu($_);
    }
    return $class->SUPER::new($u, $cu->{userid}, $mu->{userid}, $maintu->{userid}, $reason);
}

sub is_common { 1 } # As seen in LJ/Event.pm, event fired without subscription

# Override this with a false value make subscriptions to this event not show up in normal UI
sub is_visible { 0 }

# Whether Inbox is always subscribed to
sub always_checked { 1 }

my @_ml_strings_en = (
    'esn.comm_join_reject.email_subject',  # 'Your Request to Join [[community]] community',
    'esn.comm_join_reject.alert',          # 'Your request to join [[community]] community has been declined.',
    'esn.comm_join_reject.email_text',      # 'Dear [[user]],
                                            #
                                            #Your request to join the "[[community]]" community has been declined.
                                            #
                                            #Replies to this email are not sent to the community's maintainer(s). If you would 
                                            #like to discuss the reasons for your request's rejection, you will need to contact 
                                            #a maintainer directly.
                                            #
                                            #Regards,
                                            #[[sitename]] Team
                                            #
                                            #',
);

sub subscriptions {
    my ($self, %args) = @_;
    my $cid   = delete $args{'cluster'};
    my $limit = delete $args{'limit'};
    confess("Unknown options: " . join(', ', keys %args)) if %args;
    confess("Can't call in web context") if LJ::is_web_context();

    # allsubs
    my @subs;

    my $limit_remain = $limit;

    # SQL to match only on active subs
    my $and_enabled = "AND flags & " .
        LJ::Subscription->INACTIVE . " = 0";

    # TODO: gearman parallelize:
    foreach my $cid ($cid ? ($cid) : @LJ::CLUSTERS) {
        # we got enough subs
        last if $limit && $limit_remain <= 0;

        ## hack: use inactive server of user cluster to find subscriptions
        ## LJ::DBUtil wouldn't load in web-context
        ## inactive DB may be unavailable due to backup, or on dev servers
        ## TODO: check that LJ::get_cluster_master($cid) in other parts of code
        ## will return handle to 'active' db, not cached 'inactive' db handle
        my $udbh = '';
        if (not $LJ::DISABLED{'try_to_load_subscriptions_from_slave'}){
            $udbh = eval { 
                        require 'LJ/DBUtil.pm';
                        LJ::DBUtil->get_inactive_db($cid); # connect to slave 
                    };
        }
        $udbh ||= LJ::get_cluster_master($cid); # default (master) connect

        die "Can't connect to db" unless $udbh;

        # first we find exact matches (or all matches)
        my $journal_match = "AND journalid=?";

        my $limit_sql = ($limit && $limit_remain) ? "LIMIT $limit_remain" : '';
        my $sql = "SELECT userid, subid, is_dirty, journalid, etypeid, " .
            "arg1, arg2, ntypeid, createtime, expiretime, flags  " .
            "FROM subs WHERE userid=? AND etypeid=? $journal_match $and_enabled $limit_sql";

        my $sth = $udbh->prepare($sql);
        $sth->execute($self->{args}[0], __PACKAGE__->etypeid, $self->u->id);
        if ($sth->err) {
            warn "SQL: [$sql]\n";
            die $sth->errstr;
        }

        while (my $row = $sth->fetchrow_hashref) {
            my $sub = LJ::Subscription->new_from_row($row);
            next unless $sub->owner->clusterid == $cid;

            push @subs, $sub;
        }

        $limit_remain = $limit - @subs;
    }

    return @subs;
}

sub is_subscription_ntype_disabled_for {
    my ($self, $ntypeid, $u) = @_;

    return 1 if $self->SUPER::is_subscription_ntype_disabled_for($ntypeid, $u);

    return 0 if $ntypeid == LJ::NotificationMethod::ntypeid ('LJ::NotificationMethod::Email');

    return 1;
}

sub subscription_as_html {
    my ($class, $subscr, $field_num) = @_;

    my $journal = $subscr->journal;

    return LJ::Lang::ml('event.community.join_reject', { community => $journal->ljuser_display } );
}

sub as_email_subject {
    my ($self, $u) = @_;

    my $mt  = LJ::load_userid($self->{'args'}[0]);
    my $cu = $self->community->is_community ? $self->community : LJ::load_userid($self->{'userid'});
    if ($cu->is_community && $mt->can_manage ($cu)) {
        my $rej_user = LJ::load_userid($self->{'args'}[2]);
        my $lang    = $mt->prop('browselang');
        return LJ::Lang::get_text($lang, 'esn.comm_join_reject.maint.email_subject', undef, { 'username' => $rej_user->{user}, 'community' => $cu->{user} });
    } else {
        my $lang    = $u->prop('browselang');
        return LJ::Lang::get_text($lang, 'esn.comm_join_reject.email_subject', undef, { 'community' => $cu->{user} });
    }
}

sub _as_email {
    my ($self, $u, $cu, $is_html) = @_;

    my $mt  = LJ::load_userid($self->{'args'}[0]);
    my $remover = LJ::load_userid($self->{'args'}[1]);
    my $rej_u = LJ::load_userid($self->{'args'}[2]);
    $cu = LJ::load_userid($self->{'userid'}) unless $cu->is_community;
    my $reason = $self->{'args'}[3];

    if ($mt && $mt->can_manage ($cu)) {
        my $lang    = $mt->prop('browselang');
        return LJ::Lang::get_text($lang, 'esn.comm_join_reject.maint.email_text', undef, {
                user        => $mt->{'name'},
                username    => $rej_u ? $rej_u->{'name'} : '',
                community   => $cu->{'user'},
                maintainer  => $remover->{'user'},
                reason      => $reason,
                sitename    => $LJ::SITENAME,
                siteroot    => $LJ::SITEROOT,
        });
    } else {
        # Precache text lines
        my $lang    = $u->prop('browselang');
        #LJ::Lang::get_text_multi($lang, undef, \@_ml_strings_en);

        my $vars = {
                'user'      => $u->{name},
                'username'  => $u->{name},
                'community' => $cu->{user},
                'sitename'  => $LJ::SITENAME,
                'siteroot'  => $LJ::SITEROOT,
        };

        return LJ::Lang::get_text($lang, 'esn.comm_join_reject.email_text', undef, $vars);
    }
}

sub as_email_string {
    my ($self, $u) = @_;
    my $cu = $self->community;
    return '' unless $u && $cu;
    return _as_email($self, $u, $cu, 0);
}

sub as_email_html {
    my ($self, $u) = @_;
    my $cu = $self->community;
    return '' unless $u && $cu;
    return _as_email($self, $u, $cu, 1);
}

sub as_alert {
    my $self = shift;
    my $u = shift;
    my $cu = $self->community;
    return '' unless $u && $cu;
    return LJ::Lang::get_text($u->prop('browselang'),
        'esn.comm_join_reject.alert', undef, { 'community' => $cu->ljuser_display(), });
}

sub community {
    my $self = shift;
    return LJ::load_userid($self->arg1);
}

sub available_for_user  { 1 }
sub is_subscription_visible_to  { 1 }
sub is_tracking { 1 }

1;
