package TheSchwartz::Worker::NotifyPingbackServer;
use strict;
use base 'TheSchwartz::Worker';
use LJ::Entry;
use LJ::PingBack;
use LJ::ExtBlock;

sub work {
    my ($class, $job) = @_;
    my $args = $job->arg;
    my $client = $job->handle->client;

    send_ping(uri  => $args->{uri},
              mode => $args->{mode},
              );

    $job->completed;

}

sub send_ping {
    my %args = @_;

    my $source_uri = $args{uri};
    my $mode = $args{mode};

    # return unless $mode =~ m/^[LO]$/; # (L)ivejournal only, (O)pen.

    my $source_entry = LJ::Entry->new_from_url($source_uri);
    return unless $source_entry;
    
    my $antispam_params = &_get_antispam_params();
    if ( $antispam_params->{enable_reader_weight} ) {

        my $weight_data = LJ::PersonalStats::DB->fetch_raw('ratings', {
            func => 'get_reader_weight',
            journal_id => $source_entry->posterid,
        });
        if ($weight_data && $weight_data->{status} eq 'Ok') {
            return if $weight_data->{reader_weight} < $antispam_params->{min_reader_weight};
        }
    }

    my @links = ExtractLinksWithContext->do_parse($source_entry->event_raw);
    # use Data::Dumper;
    # warn "Links: " . Dumper(\@links);
    return unless @links;
    
    foreach my $link (@links){
        my $target_entry = LJ::Entry->new_from_url($link->{uri});

        next unless $target_entry;
        next if $target_entry->original_post;
        next unless LJ::PingBack->should_entry_recieve_pingback($target_entry);
        next unless log_ping($source_entry, $target_entry);

        # on success returns LJ::Comment.
        my $res =
            LJ::PingBack->ping_post(
                    sourceURI => $source_uri,
                    targetURI => $link->{uri},
                    context   => $link->{context},
                    title     => $source_entry->subject_raw,
                    ); # returns LJ::Comment object on success or error string otherwise.
        drop_relation($source_entry, $target_entry) unless ref $res;
    }

    return 1;
}

sub log_ping {
    my ($source_entry, $target_entry) = @_;
    my $target_poster = $target_entry->poster;
    return 1 unless $target_poster; # positive value skips this link

    my $dbh = $target_poster->writer;
    die "Can't get db writer for user " . $target_poster->username
        unless $dbh;

    my $sth = $dbh->prepare("
        INSERT IGNORE INTO pingrel
            (suid, sjid, tuid, tjid)
        VALUES
            (?, ?, ?, ?)
    ");
    $sth->execute(
        $source_entry->posterid, $source_entry->jitemid,
        $target_entry->posterid, $target_entry->jitemid
        ) or return 0;

    return 1;
}
sub drop_relation {
    my ($source_entry, $target_entry) = @_;
    my $target_poster = $target_entry->poster;
    return 1 unless $target_poster; # positive value skips this link

    my $dbh = $target_poster->writer;
    die "Can't get db writer for user " . $target_poster->username
        unless $dbh;

    my $sth = $dbh->prepare("
        DELETE
        FROM pingrel
        WHERE
            suid = ?
            AND sjid = ? 
            AND tuid = ? 
            AND tjid = ?
    ");
    $sth->execute(
        $source_entry->posterid, $source_entry->jitemid,
        $target_entry->posterid, $target_entry->jitemid
        ) or return 0;

    return 1;
}

sub _get_antispam_params {

    my $result = {
        enable_reader_weight => 0,
        min_reader_weight    => 0,
    };

    my $ext_block;
    my $eval_res = eval { $ext_block = LJ::ExtBlock->load_by_id('antispam_params'); 1 };
    if ($eval_res) {
        my $values = $ext_block ? LJ::JSON->from_json($ext_block->blocktext) : { c => {} };
        if ( $values->{c}->{enable_reader_weight} && $values->{c}->{min_reader_weight} ) {
            $result->{enable_reader_weight} = $values->{c}->{enable_reader_weight};
            $result->{min_reader_weight}    = $values->{c}->{min_reader_weight};
        }
    } else {
        warn $@;
    }

    return $result;

}

package ExtractLinksWithContext;
use strict;
use HTML::Parser;
use Encode qw//;
use Data::Dumper;

# if needed this vars easily can be moved to $parser object as its properties.
my $prev_link_end = 0;
my @links = ();
my $res = '';


sub do_parse {
    my $class = shift;
    my $text  = shift;

    $res = '';
    $prev_link_end = 0;
    @links = ();

    # text can be a plain text or html or combined.
    # some links can be a well-formed <A> tags, other just a plain text like http://some.domain/page.html
    # after detecting a link we need to extract a text (context) in which this link is.
    # To fetching link context in the one way we do process text twice:
    #   1) convert links in plain text in an <a> tags
    #   2) extract links and its context.

    # <a href="http://ya.ru">http://ya.ru</a> - well-formed a-tag
    # <div>well-known search is http://google.ru</div> - link in plain text


    # convert links from plain text in <a> tags.
    my $normolized_text = '';
    my $normolize = HTML::Parser->new(
        api_version => 3,
        start_h     => [ sub { 
                            my ($self, $tagname, $text, $attr) = @_;
                            $normolized_text .= $text;
                            $self->{_smplf_in_a} = 1 if $tagname eq 'a';
                        }, "self, tagname,text,attr" ],
        end_h       => [ sub {
                            my ($self, $tagname, $text, $attr) = @_;
                            $normolized_text .= $text;
                            $self->{_smplf_in_a} = 0 if $tagname eq 'a';
                        }, "self,tagname,text,attr" ],
        text_h      => [ sub {
                            my ($self, $text) = @_;
                            unless ($self->{_smplf_in_a}){
                                $text =~ s|(http://[\w\-\_]{1,16}\.$LJ::DOMAIN/\d+\.html(\?\S*(\#\S*)?)?)|<a href="$1">$1</a>|g;
                                $text =~ s|(http://community\.$LJ::DOMAIN/[\w\-\_]{1,16}/\d+\.html(\?\S*(\#\S*)?)?)|<a href="$1">$1</a>|g;
                            }
                            $normolized_text .= $text;
                        },  "self,text" ],
    );
    $normolize->parse( Encode::decode_utf8($text . "\n") );

    # parse
    my $parser = HTML::Parser->new(
        api_version => 3,
        start_h     => [ \&tag_start, "tagname,text,attr" ],
        end_h       => [ \&tag_end,   "tagname,text,attr" ],
        text_h      => [ \&text,  "text" ],
    );
    $parser->parse($normolized_text);
    
    return 
        map { $_->{context} =  Encode::encode_utf8($_->{context}); $_ } 
        @links;
}

sub tag_start {
    my $tag_name = shift;
    my $text     = shift;
    my $attr     = shift;

    if ($tag_name eq 'a') {
        parse_a ($text, $attr)
    } elsif ($tag_name =~ m/(br|p|table|hr|object)/) {
        $res .= ' ' if substr($res, -1, 1) ne ' ';
    }

}
sub tag_end {
    my $tag_name = shift;
    if ($tag_name eq 'a'){
        my $context = substr $res, (length($res) - 100 < $prev_link_end ? $prev_link_end : -100); # last 100 or less unused chars
        
        if ( length($res) > length($context) ){ # context does not start from the text begining.
            $context =~ s/^(\S{1,5}\s*)//;
        }

        $links[-1]->{context} = $context if scalar @links;        
        $prev_link_end = length($res);
    }
    return;
}
sub text {
    my $text = shift;
    my $copy = $text;
    $copy =~ s/\s+/ /g;
    $res .= $copy;
    return;

}
sub parse_a {
    my $text = shift;
    my $attr = shift;
    
    my $uri = URI->new($attr->{href});
    return unless $uri;

    my $context = $text;

    push @links => { uri => $uri->as_string, context => $context };
    return;
}

=comment Debug:
use lib "$ENV{LJHOME}/cgi-bin";
require "ljlib.pl";

my $input = join('', <ARGV>);
print $input;
my @output = ExtractLinksWithContext->do_parse($input);
print "\n>>\n", join("\n", map { "$_->{uri} 'in' $_->{context}" } @output);
print "\n";
=cut

1;
