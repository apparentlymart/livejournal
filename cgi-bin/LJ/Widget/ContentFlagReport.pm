package LJ::Widget::ContentFlagReport;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);
use LJ::ContentFlag;

sub render_body {
    my $class = shift;
    my %opts = @_;
    my $ret;

    my $remote = LJ::get_remote();

    return "This feature is disabled" if LJ::conf_test($LJ::DISABLED{content_flag});
    return "You are not allowed to flag content" unless $remote && $remote->can_flag_content;

    if ($opts{flag}) {
        my $url = $opts{flag}->url;

        return qq {
            <p>Thank you for your report. We will process it as soon as possible and take the appropriate action.
                Unfortunately, we can't respond individually to each report we receive.</p>
            <ul>
               <li><a href="$url">Return to Journal</a></li>
               <li><a href="$LJ::SITEROOT/site/search.bml">Explore $LJ::SITENAME</a></li>
            </ul>
        }; #' stupid emacs }
    }

    $ret .= $class->start_form;
    $ret .= $class->html_hidden($_ => $opts{$_}) foreach qw /journalid itemid/;

    my $cat_radios;
    my $cats = LJ::ContentFlag->category_names;

    $cat_radios .= $class->html_check(type => 'radio',
                                      name => 'catid',
                                      value => $_,
                                      id    => "cat_$_",
                                      label => $cats->{$_},
                                      selected => $opts{catid} == $_,
                                      ) . "<br />" foreach keys %$cats;

    my $url = $class->html_text(name => "url", maxlength => 100, size => 50, value => $opts{url});

    $ret .= qq {
        <p>To report anything outside of these three categories, please use the <a href="$LJ::SITEROOT/abuse/report.bml">Abuse
            reporting system</a>. Submitting false reports may result in action being taken against your account.</p>
        <p><i>What is the nature of your abuse complaint?</i></p>
        <div>
        $cat_radios
        </div>
        <p><i>Please provide a direct URL to the location where the abuse is taking place:</i></p>
        <div>
        $url
        </div>
    };

    $ret .= "<p>" . $class->html_submit('Submit Report') . "</p>";
    $ret .= $class->end_form;
}

sub handle_post {
    my ($class, $post, %opts) = @_;

    my %params = (
        catid => $post->{catid},
    );

    return "This feature is disabled" if LJ::conf_test($LJ::DISABLED{content_flag});

    my $remote = LJ::get_remote() or die "You must be logged in to flag content";
    return "You are not allowed to flag content" unless $remote->can_flag_content;

    die "You must select the type of abuse you want to report\n"
        unless $params{catid};


    my $url = $post->{url};

    if (my $comment = LJ::Comment->new_from_url($url)) {
        $params{type} = LJ::ContentFlag::COMMENT;
        $params{journalid} = $comment->poster ? $comment->poster->id : $comment->journal->id;
        $params{itemid} = $comment->dtalkid;
    } elsif (my $entry = LJ::Entry->new_from_url($url)) {
        $params{type} = LJ::ContentFlag::ENTRY;
        $params{journalid} = $entry->poster->id;
        $params{itemid} = $entry->ditemid;
    } elsif ($url =~ m!(.+)/profile!
             && my $u = LJ::User->new_from_url($1)) {
        $params{type} = LJ::ContentFlag::PROFILE;
        $params{journalid} = $u->id;
        $params{itemid} = 0;
    } elsif (my $u = LJ::User->new_from_url($url)) {
        $params{type} = LJ::ContentFlag::JOURNAL;
        $params{journalid} = $u->id;
        $params{itemid} = 0;
    } else {
        die "Please provide direct URLs to entries or comments on $LJ::SITENAME. We cannot accept links from other sites.";
    }

    # create flag
    $params{flag} = LJ::ContentFlag->flag(%params, reporter => $remote);

    return %params;
}

1;
