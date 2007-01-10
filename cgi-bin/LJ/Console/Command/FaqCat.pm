package LJ::Console::Command::FaqCat;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "faqcat" }

sub desc { "Tool for managing FAQ categories." }

sub args_desc { [
                 'command' => "One of: list, delete, add, move.  'list' shows all the defined FAQ categories, including their catkey, name, and sortorder.  Also, it shows all the distinct catkeys that are in use by FAQ. 'add' creates or modifies a FAQ category. 'delete' removes a FAQ category (but not the questions that are in it). 'move' moves a FAQ category up or down in the list.",
                 'commandargs' => "'add' takes 3 arguments: a catkey, a catname, and a sort order field. 'delete' takes one argument: the catkey value. 'move' takes two arguments: the catkey and either the word 'up' or 'down'."
                 ] }

sub usage { '<command> <commandargs>' }

sub can_execute { 1 }

sub execute {
    my ($self, @args) = @_;
    my $command = @args[0];
    my $dbh = LJ::get_db_writer();

    return $self->error("Invalid command. Consult the reference.")
        unless $command eq /(?:list|move|add|delete)/;

    if ($command eq "list") {
        my %catdefined;
        $self->info(sprintf("%-20s %-45s %s", "catkey", "catname", "order" ));
        $self->info("-" x 76);

        my $sth = $dbh->prepare("SELECT faqcat, faqcatname, catorder FROM faqcat ORDER BY catorder");
        $sth->execute;
        while (my ($faqcat, $faqcatname, $catorder) = $sth->fetchrow_array) {
            $catdefined{$faqcat} = 1;
            $self->info(sprintf("%-20s %-45s %5d", $faqcat, $faqcatname, $catorder));
        }
        $sth->finish;

        $self->info("");
        $self->info("catkeys currently in use:");
        $self->info("-" x 25);

        $sth = $dbh->prepare("SELECT faqcat, COUNT(*) FROM faq GROUP BY 1");
        $sth->execute;
        while (my ($faqcat, $count) = $sth->fetchrow_array) {
            my $msg = sprintf("%-15s by %5d", $faqcat, $count);
            if ($catdefined{$faqcat}) {
                $self->info($msg);
            } else {
                $self->error($msg);
            }
        }
        $sth->finish;

        return 1;
    }

    my $remote = LJ::get_remote();
    # anything from this point on requires a priv
    return $self->error("You are not authorized to use this command.")
        unless LJ::check_priv($remote, "faqcat");

    if ($command eq "delete") {
        return $self->error("The 'delete' command takes exactly one argument. Consult the reference.")
            unless scalar(@args) == 2;

        my $catkey = @args[1];

        my $ct = $dbh->do("DELETE FROM faqcat WHERE faqcat = ? ", undef, $catkey);

        if ($ct > 0) {
            return $self->success("Category deleted");
        } else {
            return $self->error("Unknown category: @args[1]");
        }
    }

    if ($command eq "add") {
        return $self->error("The 'add' command takes exactly three arguments. Consult the reference.")
            unless scalar(@args) == 4;

        my $catkey = @args[1];
        my $catname = @args[2];
        my $catorder = @args[3];

        my $faqd = LJ::Lang::get_dom("faq");
        my $rlang = LJ::Lang::get_root_lang($faqd);
        undef $faqd unless $rlang;

        if ($faqd) {
            LJ::Lang::set_text($dbh, $faqd->{'dmid'}, $rlang->{'lncode'},
                               "cat.$args->[2]", $args->[3], { 'changeseverity' => 1 });
          }

        $dbh->do("REPLACE INTO faqcat (faqcat, faqcatname, catorder) VALUES (?, ?, ?)",
                 undef, $catkey, $catname, $catorder);

        return $self->success("Category added/changed");
    }

    if ($command eq "move") {
        return $self->error("The 'move' command takes exactly two arguments. Consult the reference.")
            unless scalar(@args) == 2;

        my $catkey = @args[1];
        my $dir = @args[2];

        return $self->error("Direction argument must be 'up' or 'down'.")
            unless $dir eq "up" || $dir eq "down";

        my %pre;       # catkey -> key before
        my %post;      # catkey -> key after
        my %catorder;  # catkey -> order
        my $sth = $dbh->prepare("SELECT faqcat, catorder FROM faqcat ORDER BY catorder");
        $sth->execute;
        my $last;
        while (my ($key, $order) = $sth->fetchrow_array) {
            push @cats, $key;
            $catorder{$key} = $order;
            $post{$last} = $key;
            $pre{$key} = $last;
            $last = $key;
        }

        my %new;    # catkey -> new order
        if ($dir eq "up" && $pre{$catkey}) {
            $new{$catkey} = $catorder{$pre{$catkey}};
            $new{$pre{$catkey}} = $catorder{$catkey};
        }
        if ($dir eq "down" && $post{$catkey}) {
            $new{$catkey} = $catorder{$post{$catkey}};
            $new{$post{$catkey}} = $catorder{$catkey};
        }
        if (%new) {
            foreach my $n (keys %new) {
                my $qk = $dbh->quote($n);
                my $co = $new{$n}+0;
                $dbh->do("UPDATE faqcat SET catorder=$co WHERE faqcat=$qk");
            }
            return $self->info("Category order changed.");
        }

        return $self->error("Category can't move $dir anymore.");
    }

    return 1;
}

1;
