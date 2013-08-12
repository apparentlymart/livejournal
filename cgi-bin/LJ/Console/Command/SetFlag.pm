package LJ::Console::Command::SetFlag;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "set_flag" }

sub desc { "Set a content flag for an account or an entry." }

sub args_desc { [
                 'content' => "The username of the account or the URL of the entry",
                 'state' => "Options are: 'explicit_adult', 'hate_speech', 'illegal_activity', 'child_porn', 'self_harm', 'sexual_content', 'other', or 'none' (which unsets the flag)",
                 'reason' => "Reason why the action is being done",
                 'stock:%num%' => '%num% is stocks ID from "console" group at http://www.livejournal.com/admin/sendmail/stocks.bml which should be sent to the affected user instead of default notification.',
                 ] }

sub usage { '<content> <state> <reason> [<stock>]' }

sub can_execute {
    my $remote = LJ::get_remote();
    return $remote && $remote->can_admin_content_flagging ? 1 : 0;
}

sub execute {
    my ($self, $content, $state, $reason, @args) = @_;

    return $self->error("This command takes 3-4 arguments. Consult the reference.")
        unless $content && $state && $reason && scalar(@args) <= 1;

    my $stock = $args[0];
    # check to see if it's a user or an entry
    my $u = LJ::load_user($content);
    my $entry = LJ::Entry->new_from_url($content);
    my ($type, $content_obj, $for_u);
    if ($u && !$entry) {
        $type = "Journal";
        $content_obj = $u;
        $for_u = $u;
    } elsif (!$u && $entry) {
        $type = "Entry";
        $content_obj = $entry;
        $for_u = $entry->poster;
    } else {
        return $self->error("First argument must be either a username or the URL to an entry.");
    }

    return $self->error("Second argument must be one of: 'explicit_adult', 'hate_speech', 'illegal_activity', 'child_porn', 'self_harm', 'sexual_content', 'other', or 'none'.")
        unless $state =~ /^(?:explicit_adult|hate_speech|illegal_activity|child_porn|self_harm|sexual_content|other|none)$/;

    my $stock_num;
    if ($stock) {
        ($stock_num) = $stock =~ /^stock:(\d+)$/;
        return $self->error("Fourth argument must be format such stock:%num%.") unless $stock_num;
    }

    if ($content_obj->admin_content_flag eq $state) {
        return $self->error("$type is already flagged as: $state");
    } elsif (!$content_obj->admin_content_flag && $state eq "none") {
        return $self->error("$type already doesn't have a content flag set.");
    }

    if ($state eq "none") {
        $content_obj->set_prop("admin_content_flag", undef);
        $self->print("${type}'s content flag has been unset.");
    } else {
        $content_obj->set_prop("admin_content_flag", $state);
        $self->print("$type has been flagged as: $state");
    }

    if ($state =~ /explicit_adult/) {
        my %mail_param = (
            username => $for_u->user,
            url  => $content,
        );

        my $subject = ($type eq "Journal") ? LJ::Lang::ml("console.flag_journal.subject") : LJ::Lang::ml("console.flag_entry.subject");
        my $body = ($type eq "Journal") ? LJ::Lang::ml("console.flag_journal.text", \%mail_param) : LJ::Lang::ml("console.flag_entry.text", \%mail_param);

        if ($stock_num) {
            my $dbh = LJ::get_db_reader();
            my $stock = LJ::Sendmail::Stock::from_id($stock_num, $dbh);
    
            $body = $stock->body;
            $body =~ s/\[\[($_)\]\]/$mail_param{$1}/g for keys %mail_param;
        }

        LJ::send_mail({
            'to'      => $for_u->email_raw,
            'from'    => $LJ::ABUSE_EMAIL,
            'subject' => $subject,
            'body'    => $body,
        }) or $self->info("Email notification could not be sent.");
    }
    

    my $remote = LJ::get_remote();
    if ($type eq "Journal") {
        LJ::statushistory_add($for_u, $remote, "set_flag", "journal flagged as $state: " . $reason);
    } else { # entry
        LJ::statushistory_add($for_u, $remote, "set_flag", "$content flagged as $state: " . $reason);
    }

    return 1;
}

1;
