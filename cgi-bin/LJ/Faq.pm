#!/usr/bin/perl

package LJ::Faq;

use strict;
use Carp;

# Initially built in a hackathon, so this is only moderately awesome
# -- whitaker 2006/06/23

# FIXME: singletons?

# <LJFUNC>
# name: LJ::Faq::new
# class: general
# des: Creates a LJ::Faq object from supplied information.
# args: opts
# des-opts: Hash of initial field values for the new Faq. Allowed keys are:
#           faqid, question, summary, answer, faqcat, lastmoduserid, sortorder,
#           lastmodtime, unixmodtime, and lang. Default for lang is
#           $LJ::DEFAULT_LANG, all others undef.
# returns: The new LJ::Faq object.
# </LJFUNC>
sub new {
    my $class = shift;
    my $self  = bless {}, $class;

    my %opts = @_;

    $self->{$_} = delete $opts{$_}
        foreach qw(faqid question summary answer faqcat lastmoduserid sortorder lastmodtime unixmodtime);
    $self->{lang}     = delete $opts{lang} || $LJ::DEFAULT_LANG;

    croak("unknown parameters: " . join(", ", keys %opts))
        if %opts;

    return $self;
}

# <LJFUNC>
# name: LJ::Faq::load
# class: general
# des: Creates a LJ::Faq object and populates it from the database.
# args: faqid, opts?
# des-faqid: The integer id of the FAQ to load.
# des-opts: Hash of option key => value. Currently only allows lang => language
#           to load the FAQs in, xx or xx_YY. Defaults to $LJ::DEFAULT_LANG.
# returns: The newly populated LJ::Faq object.
# </LJFUNC>
sub load {
    my $class = shift;
    my $faqid = int(shift);
    croak ("invalid faqid: $faqid")
        unless $faqid > 0;

    my %opts = @_;
    my $lang = delete $opts{lang} || $LJ::DEFAULT_LANG;
    croak("unknown parameters: " . join(", ", keys %opts))
        if %opts;

    my $dbr = LJ::get_db_reader()
        or die "Unable to contact global reader";

    my $faq;
    if ($lang eq $LJ::DEFAULT_LANG) {
        my $f = $dbr->selectrow_hashref
            ("SELECT faqid, question, summary, answer, faqcat, lastmoduserid, ".
             "DATE_FORMAT(lastmodtime, '%M %D, %Y') AS lastmodtime, ".
             "UNIX_TIMESTAMP(lastmodtime) AS unixmodtime, sortorder ".
             "FROM faq WHERE faqid=?",
             undef, $faqid);
        $faq = $class->new(%$f, lang => $lang);

    } else { # Don't load fields that lang_update_in_place will overwrite.
        my $f = $dbr->selectrow_hashref
            ("SELECT faqid, faqcat, ".
             "UNIX_TIMESTAMP(lastmodtime) AS unixmodtime, sortorder ".
             "FROM faq WHERE faqid=?",
             undef, $faqid);
        $faq = $class->new(%$f, lang => $lang);
        $faq->lang_update_in_place;
    }

    return $faq;
}

# <LJFUNC>
# name: LJ::Faq::load_all
# class: general
# des: Creates LJ::Faq objects from all FAQs in the database.
# args: opts?
# des-opts: Hash of option key => value. Currently only allows lang => language
#           to load the FAQs in, xx or xx_YY. Defaults to $LJ::DEFAULT_LANG.
# returns: Array of populated LJ::Faq objects, one per FAQ in the database.
# </LJFUNC>
sub load_all {
    my $class = shift;

    my %opts = @_;
    my $lang = delete $opts{lang} || $LJ::DEFAULT_LANG;
    croak("unknown parameters: " . join(", ", keys %opts))
        if %opts;

    my $dbr = LJ::get_db_reader()
        or die "Unable to contact global reader";

    my $sth;
    if ($lang eq $LJ::DEFAULT_LANG) {
        $sth = $dbr->prepare
            ("SELECT faqid, question, summary, answer, faqcat, lastmoduserid, ".
             "DATE_FORMAT(lastmodtime, '%M %D, %Y') AS lastmodtime, ".
             "UNIX_TIMESTAMP(lastmodtime) AS unixmodtime, sortorder ".
             "FROM faq WHERE faqcat!=''");

    } else { # Don't load fields that lang_update_in_place will overwrite.
        $sth = $dbr->prepare
            ("SELECT faqid, faqcat, ".
             "UNIX_TIMESTAMP(lastmodtime) AS unixmodtime, sortorder ".
             "FROM faq WHERE faqcat!=''");
    }

    $sth->execute;

    my @faqs;
    while (my $f = $sth->fetchrow_hashref) {
        push @faqs, $class->new(%$f);
    }

    if ($lang ne $LJ::DEFAULT_LANG) {
        $class->lang_update_in_place($lang => @faqs);
    }

    return @faqs;
}

sub faqid {
    my $self = shift;
    return $self->{faqid};
}
*id = \&faqid;

sub lang {
    my $self = shift;
    return LJ::Lang::get_lang($self->{lang}) ? $self->{lang} : $LJ::DEFAULT_LANG;
}

sub question_raw {
    my $self = shift;
    return $self->{question};
}

sub question_html {
    my $self = shift;
    return LJ::ehtml($self->{question});
}

sub summary_raw {
    my $self = shift;
    return $self->{summary};
}

sub summary_html {
    my $self = shift;
    return LJ::ehtml($self->{summary});
}

sub answer_raw {
    my $self = shift;
    return $self->{answer};
}

sub answer_html {
    my $self = shift;
    return LJ::ehtml($self->{answer});
}

sub faqcat {
    my $self = shift;
    return $self->{faqcat};
}

sub lastmoduserid {
    my $self = shift;
    return $self->{lastmoduserid};
}

sub lastmodtime {
    my $self = shift;
    return $self->{lastmodtime};
}

sub unixmodtime {
    my $self = shift;
    return $self->{unixmodtime};
}

sub sortorder {
    my $self = shift;
    return $self->{sortorder};
}

# <LJFUNC>
# name: LJ::Faq::lang_update_in_place
# class: general
# des: Fill in question, summary and answer from database for one or more FAQs.
# info: May be called either as a class method or an object method, ie:
#       - $self->lang_update_in_place;
#       - LJ::Faq->lang_update_in_place($lang, @faqs);
# args: lang?, faqs?
# des-lang: Language to fetch strings for (as a class method).
# des-faqs: Array of LJ::Faq objects to fetch strings for (as a class method).
# returns: True value if successful.
# </LJFUNC>
sub lang_update_in_place {
    my $class = shift;

    my ($lang, @faqs);
    if (ref $class) {
        $lang = $class->{lang};
        @faqs = ($class);
        croak ("superfluous parameters") if @_;
    } else {
        $lang = shift;
        @faqs = @_;
        croak ("invalid parameters") if grep { ref $_ ne 'LJ::Faq' } @faqs;
    }

    my $faqd = LJ::Lang::get_dom("faq");
    my $l = LJ::Lang::get_lang($lang) || LJ::Lang::get_lang($LJ::DEFAULT_LANG);
    croak ("missing domain") unless $faqd;
    croak ("invalid language: $lang") unless $l;

    my @load;
    foreach (@faqs) {
        push @load, "$_->{faqid}.1question";
        push @load, "$_->{faqid}.3summary";
        push @load, "$_->{faqid}.2answer";
    }

    my $res = LJ::Lang::get_text_multi($l->{'lncode'}, $faqd->{'dmid'}, \@load);
    foreach (@faqs) {
        my $id = $_->{faqid};
        $_->{question} = $res->{"$id.1question"} if $res->{"$id.1question"};
        $_->{summary}  = $res->{"$id.3summary"}  if $res->{"$id.3summary"};
        $_->{answer}   = $res->{"$id.2answer"}   if $res->{"$id.2answer"};

        $_->{summary}  = $LJ::_T_FAQ_SUMMARY_OVERRIDE if $LJ::_T_FAQ_SUMMARY_OVERRIDE;

        # FIXME?: the join can probably be avoid, eg by using something like
        # LJ::Lang::get_chgtime_unix for time of last change and a single-table
        # "SELECT userid FROM ml_text WHERE t.lnid=? AND t.dmid=? AND t.itid=?
        # ORDER BY t.txtid DESC LIMIT 1" for userid.
        my $itid = LJ::Lang::get_itemid($faqd->{'dmid'}, "$id.2answer");
        if ($itid) {
            my $sql = "SELECT DATE_FORMAT(l.chgtime, '%Y-%m-%d'), t.userid " .
                "FROM ml_latest AS l, ml_text AS t WHERE l.dmid = t.dmid AND l.lnid = t.lnid AND l.itid = t.itid " .
                "AND l.lnid=? AND l.dmid=? AND l.itid=? ORDER BY t.txtid DESC LIMIT 1";

            my $dbr = LJ::get_db_reader()
                or die "Unable to contact global reader";
            my $sth = $dbr->prepare($sql);
            $sth->execute($l->{'lnid'}, $faqd->{'dmid'}, $itid);
            @{$_}{'lastmodtime', 'lastmoduserid'} = $sth->fetchrow_array;
        }
    }

    return 1;
}

# <LJFUNC>
# name: LJ::Faq::load_matching
# class: general
# des: Finds all FAQs containing a search term and ranks them by relevance.
# args: term, opts?
# des-term: The string to search for (case-insensitive).
# des-opts: Hash of option key => value. Currently only allows lang => language
#           to search the FAQs in, xx or xx_YY. Defaults to $LJ::DEFAULT_LANG.
# returns: A list of LJ::Faq objects matching the search term, sorted by
#          decreasing relevance.
# </LJFUNC>
sub load_matching {
    my $class = shift;
    my $term = shift;
    croak ("search term requires") unless length($term . "");

    my %opts = @_;
    my $lang = delete $opts{lang} || $LJ::DEFAULT_LANG;
    croak("unknown parameters: " . join(", ", keys %opts))
        if %opts;

    my @faqs = $class->load_all(lang => $lang);
    die "unable to load faqs" unless @faqs;

    my %scores  = (); # faqid => score
    my @results = (); # array of faq objects

    foreach my $f (@faqs) {
	my $score = 0;

        # don't search things in the FURTHER READING section
        # (a livejournal.com convention)
	$f->{answer} =~ s/FURTHER READING.+//s;

	if ($f->{question} =~ /\Q$term\E/i) {
	    $score += 3;
	}
	if ($f->{question} =~ /\b\Q$term\E\b/i) {
	    $score += 5;
	}

	if ($f->{summary} =~ /\Q$term\E/i) {
	    $score += 2;
	}
	if ($f->{summary} =~ /\b\Q$term\E\b/i) {
	    $score += 4;
	}

	if ($f->{answer} =~ /\Q$term\E/i) {
	    $score += 1;
	}
	if ($f->{answer} =~ /\b\Q$term\E\b/i) {
	    $score += 3;
	}

	next unless $score;

	$scores{$f->{faqid}} = $score;

	push @results, $f;
    }

    return sort { $scores{$b->{faqid}} <=> $scores{$a->{faqid}} } @results;
}

1;
