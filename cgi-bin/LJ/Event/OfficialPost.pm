package LJ::Event::OfficialPost;
use strict;
use Class::Autouse qw(LJ::Entry LJ::HTML::Template LJ::TimeUtil);
use Carp qw(croak);
use base 'LJ::Event';

sub new {
    my ($class, $entry) = @_;
    croak "No entry" unless $entry;

    $class->clear_memcache($entry);

    return $class->SUPER::new($entry->journal, $entry->ditemid);
}

sub memkey {
    my ($class, $entry) = @_;
    return join '.', "esn.news.post.html" , $entry->journalid, $entry->ditemid;
}

sub clear_memcache {
    my ($class, $entry) = @_;

    LJ::MemCache::delete( $class->memkey($entry) );
}

sub entry {
    my $self = shift;
    my $ditemid = $self->arg1;
    return LJ::Entry->new($self->event_journal, ditemid => $ditemid);
}

sub content {
    my $self = shift;
    my $entry = $self->entry;
    return $entry->event_html( {cuturl => $entry->url, no_ljcut_collapse => 1} );
}

sub is_common { 1 }

sub zero_journalid_subs_means { 'all' }

sub _construct_prefix {
    my $self = shift;
    return $self->{'prefix'} if $self->{'prefix'};
    my ($classname) = (ref $self) =~ /Event::(.+?)$/;
    return $self->{'prefix'} = 'esn.' . lc($classname);
}

sub as_email_subject {
    my $self = shift;
    my $u = shift;
    my $label = _construct_prefix($self);

    # construct label

    if ($self->entry->subject_text) {
        $label .= '.subject';
    } else {
        $label .= '.nosubject';
    }

    return LJ::Lang::get_text(
        $u->prop("browselang"),
        $label,
        undef,
        {
            siteroot        => $LJ::SITEROOT,
            sitename        => $LJ::SITENAME,
            sitenameshort   => $LJ::SITENAMESHORT,
            subject         => $self->entry->subject_text || '',
            username        => $self->entry->journal->display_username,
        });
}

sub as_email_html {
    my $self = shift;
    my $u = shift;

    unless  ( LJ::is_enabled('news_mail_redisign') ) {
        return sprintf "%s<br />\n<br />\n%s", $self->as_html($u), $self->content;
    } else {
        
        my $entry = $self->entry or return "(Invalid entry)";

        my $memkey = $self->memkey($entry);

        my $from_cache = LJ::MemCache::get($memkey);

        return $from_cache if $from_cache;

        my $template = LJ::HTML::Template->new(
            { use_expr => 1 },
            filename => "$ENV{'LJHOME'}" . '/templates/ESN/OfficialPost/email_html.tmpl',
            die_on_bad_params => 0,
        );

        my $lang = $u->prop("browselang");

        $template->param({
            date    => LJ::TimeUtil->fancy_time_format($entry->logtime_unix, 'day', $u->prop('timezone'), {lang => $lang}),
            content => $self->content,
            subject => $self->entry->subject_text || '',
            url     => $entry->url,
            lang    => $lang,
        });

        my $result = $template->output();
        
        LJ::MemCache::set($memkey, $result);

        return $result;
    }
}

sub as_email_string {
    my $self = shift;
    my $u = shift;

    my $text = $self->content;
    $text =~ s/\n+/ /g;
    $text =~ s/\s*<\s*br\s*\/?>\s*/\n/g;
    $text = LJ::strip_html($text);

    return sprintf "%s

%s", $self->as_string($u), $text;
}

sub as_html {
    my $self = shift;
    my $u = shift;
    my $entry = $self->entry or return "(Invalid entry)";

    return LJ::Lang::get_text(
        $u->prop("browselang"),
        _construct_prefix($self) . '.html',
        undef,
        {
            siteroot        => $LJ::SITEROOT,
            sitename        => $LJ::SITENAME,
            sitenameshort   => $LJ::SITENAMESHORT,
            subject         => $self->entry->subject_text || '',
            username        => $entry->journal->ljuser_display,
            url             => $entry->url,
            rcpt            => $u->ljuser_display,
        });
}

sub tmpl_params {
    my ($self, $u) = @_;
    my $entry = $self->entry or return { body => "(Invalid entry)" };

    my $lang = ($u && $u->prop('browselang')) || $LJ::DEFAULT_LANG;

    return { 
        body => LJ::Lang::get_text(
        $lang,
        _construct_prefix($self) . '.html',
        undef,
        {
            siteroot        => $LJ::SITEROOT,
            sitename        => $LJ::SITENAME,
            sitenameshort   => $LJ::SITENAMESHORT,
            subject         => $self->entry->subject_text || '',
            username        => $entry->journal->ljuser_display,
            url             => $entry->url,
            rcpt            => $u->ljuser_display,
        }),
        subject => LJ::Lang::get_text($lang, 'esn.officialpost.params.subject'),
        content => $entry->event_html( {cuturl => $entry->url} ),
    }
}

sub as_string {
    my $self = shift;
    my $u = shift;
    my $entry = $self->entry or return "(Invalid entry)";

    return LJ::Lang::get_text(
        $u->prop("browselang"),
        _construct_prefix($self) . '.string',
        undef,
        {
            siteroot        => $LJ::SITEROOT,
            sitename        => $LJ::SITENAME,
            sitenameshort   => $LJ::SITENAMESHORT,
            subject         => $entry->subject_text || '',
            username        => $entry->journal->display_username,
            url             => $entry->url,
            rcpt            => $u->display_username,
        });
}

sub as_sms {
    my ($self, $u, $opt) = @_;

    my $lang = ($u && $u->prop('browselang')) || $LJ::DEFAULT_LANG;
    my $entry = $self->entry or return "(Invalid entry)";

    my $tinyurl = 'http://m.livejournal.com/read/user/'
         . $entry->journal->user . '/' . $entry->ditemid . '/';
    my $mparms = $opt->{mobile_url_extra_params};
    $tinyurl .= '?' . join('&', map {$_ . '=' . $mparms->{$_}} keys %$mparms) if $mparms;
    $tinyurl = LJ::Client::BitLy->shorten($tinyurl);
    undef $tinyurl if $tinyurl =~ /^500/;
        
# There is a new [[abbrev]] announcement in [[journal]]. Reply with READ [[journal]] to read it. [[disclaimer]]
    return LJ::Lang::get_text($lang, 'notification.sms.officialpost', undef, {
        abbrev     => $LJ::SITENAMEABBREV,
        journal    => $entry->journal->display_username(1),
        disclaimer => $LJ::SMS_DISCLAIMER,
        mobile_url => $tinyurl,
    });    
}

# esn.officialpost.alert=There is a new [[sitenameabbrev]] announcement in [[username]]. Reply with READ [[username]] to read it. Standard rates apply.
# esn.supofficialpost.alert=There is a new [[sitenameabbrev]] announcement in [[username]]. Reply with READ [[username]] to read it. Standard rates apply.

sub as_alert {
    my $self = shift;
    my $u = shift;
    my $entry = $self->entry or return "(Invalid entry)";

    return LJ::Lang::get_text(
        $u->prop("browselang"),
        _construct_prefix($self) . '.alert',
        undef,
        {
            siteroot        => $LJ::SITEROOT,
            sitename        => $LJ::SITENAME,
            sitenameshort   => $LJ::SITENAMESHORT,
            sitenameabbrev  => $LJ::SITENAMEABBREV,
            subject         => $entry->subject_text || '',
            username        => $entry->journal->ljuser_display(),
            url             => $entry->url,
            openlink        => '<a href="' . $entry->url . '" target="_blank">',
            closelink       => '</a>',
        });
}

sub subscription_as_html {
    my ($class, $subscr) = @_;

    # $LJ::SITENAME makes a new announcement
    return LJ::Lang::ml( 'event.officialpost2',
        { 'sitename' => $LJ::SITENAME } );
}

sub is_tracking { 0 }

sub is_subscription_visible_to { 1 }

sub as_push {
    my $self = shift;
    my $u    = shift;
    my $lang = shift;

    return LJ::Lang::get_text($lang, "esn.push.notification.offcialpost", 1, {
        community => $self->event_journal->user,
    })
}

sub as_push_payload {
    my $self = shift;
    return { 't' => 1,
             'p' => $self->arg1,
           };
}

sub show_promo { 0 }

1;
