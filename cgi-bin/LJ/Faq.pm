#!/usr/bin/perl

package LJ::Faq;

use strict;
use Carp;

# Initially built in a hackathon, so this is only moderately awesome
# -- whitaker 2006/06/23

# FIXME: lazy loading?
#        -- especially good here because then searching non-english 
#           doesn't hit the db for question/answer/summary
# FIXME: singletons?

sub new {
    my $class = shift;
    my $self  = bless {};

    my %opts = @_;

    $self->{faqid}    = delete $opts{faqid};
    $self->{question} = delete $opts{question};
    $self->{summary}  = delete $opts{summary};
    $self->{answer}   = delete $opts{answer};
    $self->{lang}     = delete $opts{lang} || $LJ::DEFAULT_LANG;

    croak("unknown parameters: " . join(", ", keys %opts))
        if %opts;

    return $self;
}

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

    my $f = $dbr->selectrow_hashref
        ("SELECT faqid, question, summary, answer FROM faq WHERE faqid=?",
         undef, $faqid);

    my $faq = $class->new(%$f, lang => $lang);

    if ($lang ne $LJ::DEFAULT_LANG) {
        $faq->lang_update_in_place;
    }

    return $faq;
}

sub load_all {
    my $class = shift;

    my %opts = @_;
    my $lang = delete $opts{lang} || $LJ::DEFAULT_LANG;
    croak("unknown parameters: " . join(", ", keys %opts))
        if %opts;

    my $dbr = LJ::get_db_reader()
        or die "Unable to contact global reader";

    my $sth = $dbr->prepare
        ("SELECT faqid, question, summary, answer FROM faq WHERE faqcat!=''");
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
    return $self->{lang};
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

# called as:
#   - $self->lang_update_in_place;
#   - LJ::Faq->lang_update_in_place(@faqs)
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
    my $l = LJ::Lang::get_lang($lang);
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
    }

    return 1;
}

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
	    $score += 1.5;
	}
	if ($f->{question} =~ /\b\Q$term\E\b/i) {
	    $score += 1.5;
	}

	if ($f->{summary} =~ /\Q$term\E/i) {
	    $score += 1;
	}
	if ($f->{summary} =~ /\b\Q$term\E\b/i) {
	    $score += 1;
	}

	if ($f->{answer} =~ /\Q$term\E/i) {
	    $score += 1;
	}
	if ($f->{answer} =~ /\b\Q$term\E\b/i) {
	    $score += 1;
	}

	next unless $score;

	$scores{$f->{faqid}} = $score;

	push @results, $f;
    }

    return sort { $scores{$b->{faqid}} <=> $scores{$a->{faqid}} } @results;
}

1;
