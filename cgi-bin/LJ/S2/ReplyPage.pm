#!/usr/bin/perl
#

use strict;
package LJ::S2;

sub ReplyPage
{
    my ($u, $remote, $opts) = @_;

    my $p = Page($u, $opts);
    $p->{'_type'} = "ReplyPage";
    $p->{'view'} = "reply";

    my ($entry, $s2entry) = EntryPage_entry($u, $remote, $opts);
    return if $opts->{'handler_return'};

    if ($u->{'opt_blockrobots'}) {
        $p->{'head_content'} .= "<meta name=\"robots\" content=\"noindex,nofollow\" />\n";
    }

    $p->{'entry'} = $s2entry;

    $p->{'form'} = {
        '_type' => "ReplyForm",
        '_remote' => $remote,
        '_u' => $u,
    };

    return $p;
}

package S2::Builtin::LJ;

sub ReplyForm__print
{
    my ($ctx, $form) = @_;
    $S2::pout->("<form>Reply here: (incomplete)<br /><textarea rows='10' cols='40'></textarea></form>");
}

1;
