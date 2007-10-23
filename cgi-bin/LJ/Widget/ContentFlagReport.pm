package LJ::Widget::ContentFlagReport;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);
use LJ::ContentFlag;

sub render_body {
    my $class = shift;
    my %opts = @_;
    my $ret;

    my $remote = LJ::get_remote() or die "You must be logged in to flag content";

    if ($opts{flag}) {
        my $url = $opts{flag}->url;

        my $itemtype;
        if ($opts{itemid}) {
            $itemtype = "Entry";
        } else {
            $itemtype = "Journal";
        }

        return qq {
            <p>Thank you for your report. We will process it as soon as possible and take the appropriate action.
                Unfortunately, we can't respond individually to each report we receive.</p>
            <ul>
               <li><a href="$url">Return to $itemtype</a></li>
               <li><a href="$LJ::SITEROOT/site/search.bml">Explore $LJ::SITENAME</a></li>
            </ul>
        }; #' stupid emacs }
    } else {
        $ret .= $class->start_form;
        $ret .= $class->html_hidden($_ => $opts{$_}) foreach qw /journalid itemid/;

        if ($opts{adult_content}) {
            my $ditemid = $opts{itemid};
            my $journalid = $opts{journalid};
            my $journal = LJ::load_userid($journalid) or return "Invalid journalid";

            my $url = $journal->journal_base;
            if ($ditemid) {
                my $entry = LJ::Entry->new($journal, ditemid => $ditemid);
                return "Invalid entry" unless $entry;
                $url = $entry->url;
            }

            my ($itemtype, $itemtype_id);
            if ($ditemid) {
                $itemtype = 'entry';
                $itemtype_id = LJ::ContentFlag::ENTRY;
            } else {
                $itemtype = 'journal';
                $itemtype_id = LJ::ContentFlag::JOURNAL;
            }

            my $journal_link = "<a href='$url'>Return to " . ucfirst $itemtype . "</a>";

            $ret .= $class->html_hidden(catid => LJ::ContentFlag::EXPLICIT_ADULT_CONTENT, type => $itemtype_id);

            return "Invalid arguments" unless $journalid;

            my $flag_btn = $class->html_submit("Flag " . ucfirst $itemtype);

            $ret .= qq {
                <div><b>Flag this $itemtype as containing explicit adult content</b></div>
                    Flagging this content will submit it to us so that we can review it for age-inappropriate material. This flag
                    only pertains to content that is of a <a href="$LJ::HELPURL{adult_content}">graphic and explicit nature</a>.

                    <p>To report anything outside of this category, please use the <a href="$LJ::SITEROOT/abuse/">Abuse report system.</a>
                    Please review the <a href="$LJ::SITEROOT/support/faqbrowse.bml?faqid=105&view=full">Abuse Reporting Guidelines</a>
                    before submitting. If you consistently abuse this reporting system, we reserve the right to take action against your account.</p>

                    $flag_btn $journal_link
                };

        } else {

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
        }

        $ret .= $class->end_form;
    }

    return $ret;
}

sub handle_post {
    my ($class, $post, %opts) = @_;

    my %params = (
        catid => $post->{catid},
        journalid => $post->{journalid},
        itemid => $post->{itemid},
        type => $post->{type},
    );

    my $remote = LJ::get_remote() or die "You must be logged in to flag content";

    die "You must select the type of abuse you want to report\n"
        unless $params{catid};

    my $url = $post->{url};
    my $u;

    if (! $params{journalid} || ! $params{type}) {
        # FIXME: this logs comments/entries in the journal they were posted
        # and not against the person who posted them in the first place.
        if (my $comment = LJ::Comment->new_from_url($url)) {
            $params{type} = LJ::ContentFlag::COMMENT;
            $params{journalid} = $comment->journal->id;
            $params{itemid} = $comment->dtalkid;
        } elsif (my $entry = LJ::Entry->new_from_url($url)) {
            $params{type} = LJ::ContentFlag::ENTRY;
            $params{journalid} = $entry->journal->id;
            $params{itemid} = $entry->ditemid;
        } elsif ($url =~ m!(.+)/profile!
                 && ($u = LJ::User->new_from_url($1))) {
            $params{type} = LJ::ContentFlag::PROFILE;
            $params{journalid} = $u->id;
            $params{itemid} = 0;
        } elsif ($u = LJ::User->new_from_url($url)) {
            $params{type} = LJ::ContentFlag::JOURNAL;
            $params{journalid} = $u->id;
            $params{itemid} = 0;
        } else {
            die "Please provide direct URLs to entries or comments on $LJ::SITENAME. We cannot accept links from other sites.";
        }
    }

    # create flag
    $params{flag} = LJ::ContentFlag->flag(%params, reporter => $remote);

    return %params;
}

1;
