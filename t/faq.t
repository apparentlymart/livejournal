# -*-perl-*-

use strict;
use Test::More qw(no_plan eq_hash);
use lib "$ENV{LJHOME}/cgi-bin";

require 'ljlib.pl';
require 'ljlang.pl';

use LJ::Faq;
use LJ::Test qw(memcache_stress);

sub run_tests {
    # constructor tests
    {   
        my %skel = 
            ( faqid    => 123,
              question => 'some question',
              summary  => 'summary info',
              answer   => 'this is the answer',
              );

        foreach my $lang (qw(en es)) {

            my $f;

            $f = eval { LJ::Faq->new(%skel, lang => $lang, foo => 'bar') };
            like($@, qr/unknown parameters/, "$lang: superfluous parameter");

            # FIXME: more failure cases
            
            $f = eval { LJ::Faq->new(%skel, lang => $lang) };

            # check members
            {
                my $dirty = 0;
                foreach my $el (keys %skel) {
                    next if $f->{$el} eq $skel{$el};
                    $dirty = 1;
                }
                ok(! $dirty, "$lang: members set correctly");
            }

            # check accessors
            {
                my @text = qw(question summary answer);

                my $dirty = 0;
                foreach my $meth (keys %skel) {
                    my $el = $meth;
                    $meth .= "_raw" if grep { $_ eq $meth } @text;
                    next if $f->{$el} eq $f->$meth;

                    $dirty = 1;
                }
                ok (! $dirty, "$lang: accessors return correctly");

                # FIXME: test for _html accessors
            }

            # check loaders
            {
                my @faqs = LJ::Faq->load_all;

                my $dirty = 0;
                foreach (@faqs) {
                    my $faq = LJ::Faq->load($_->{faqid});
                    next if eq_hash($_, $faq);

                    $dirty++;
                }
                ok(! $dirty, "single and multi loaders okay");
            }
        }

        # check multi-lang support
        {
            my $faqid = (LJ::Faq->load_all)[0]->{faqid};
            
            my $default = LJ::Faq->load($faqid);
            my $es      = LJ::Faq->load($faqid, lang => 'es');
            ok($default && $es->summary_raw ne $default->summary_raw, 
               "multiple languages with different results")
        }
    }

    # FIXME: more robust tests

}

memcache_stress {
    run_tests();
};

1;
