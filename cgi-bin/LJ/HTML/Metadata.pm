##############################################################################
#       $Id$
#  $HeadURL$
##############################################################################

package LJ::HTML::Metadata;
use strict;
use warnings;

# also update POD when you change this
our $VERSION = 1.000;

use Carp qw();
use Encode qw();
use HTML::TokeParser;

our @FIELDS;
my ( @metadata_fields, %metadata_fields );

BEGIN {
    @metadata_fields = qw( title description image og_url );
    @metadata_fields{@metadata_fields} = ();
    @FIELDS = ( qw( url html ua ), @metadata_fields );
}

use fields ( @FIELDS, '_html_parsed' );
use base qw( Class::Accessor );
__PACKAGE__->mk_accessors(@FIELDS);

my %EXTRACTED_DATA = (
    'title' => { 'extract_body' => 1,     'fill' => 'title', },
    'h1'    => { 'extract_body' => 1,     'fill' => 'html_title_h1', },
    'h2'    => { 'extract_body' => 1,     'fill' => 'html_title_h2', },
    'h3'    => { 'extract_body' => 1,     'fill' => 'html_title_h3', },
    'p'     => { 'extract_body' => 1,     'fill' => 'html_description', },
    'img'   => { 'extract_attr' => 'src', 'fill' => 'html_image' },
    'link'  => {
        'require_attr' => { 'rel' => 'image_src' },
        'extract_attr' => 'href',
        'fill'         => 'link_image'
    },
    'meta' => [
        {
            'require_attr' => { 'name' => 'title' },
            'extract_attr' => 'content',
            'fill'         => 'meta_title'
        },
        {
            'require_attr' => { 'name' => 'description' },
            'extract_attr' => 'content',
            'fill'         => 'meta_description'
        },
        {
            'require_attr' => { 'property' => 'og:title' },
            'extract_attr' => 'content',
            'fill'         => 'og_title'
        },
        {
            'require_attr' => { 'property' => 'og:description' },
            'extract_attr' => 'content',
            'fill'         => 'og_description'
        },
        {
            'require_attr' => { 'property' => 'og:image' },
            'extract_attr' => 'content',
            'fill'         => 'og_image'
        },
        {
            'require_attr' => { 'property' => 'og:url' },
            'extract_attr' => 'content',
            'fill'         => 'og_url'
        },
    ],
);

sub new {
    my ( $class, %params ) = @_;
    my $self = fields::new($class);

    foreach ( keys %params ) {
        $self->{$_} = $params{$_};
    }

    return $self;
}

sub get {
    my ( $self, $key ) = @_;

    if ( $key eq 'ua' ) {
        my $ua = $self->SUPER::get($key);
        return $ua if defined $ua;

        require LWP::UserAgent;
        $ua = LWP::UserAgent->new;
        $self->ua($ua);
        return $ua;
    }

    if ( $key eq 'html' ) {
        my $html = $self->SUPER::get($key);
        return $html if defined $html;
        return $self->_fetch_html;
    }

    if ( exists $metadata_fields{$key} ) {
        $self->_extract_metadata;
        return Encode::encode_utf8( $self->SUPER::get($key) );
    }

    return $self->SUPER::get($key);
}

sub set {    ## no critic (ProhibitAmbiguousNames)
    my ( $self, $key, $value ) = @_;

    $self->SUPER::set( $key => $value );

    if ( $key eq 'url' ) {
        $self->html(undef);
    }

    if ( $key eq 'html' ) {
        undef $self->{'_html_parsed'};
    }

    return $value;
}

# only get() is supposed to call the following two private methods
sub _fetch_html {
    my ($self) = @_;

    my $ua  = $self->ua;
    my $url = $self->url;

    if ( !$url ) {
        Carp::croak 'HTML::Metadata: no html and no url passed, '
          . 'cannot extract metadata from nowhere';
    }

    my $res = $ua->get($url);

    if ( !$res->is_success ) {
        my $status = $res->status_line;
        Carp::croak "HTML::Metadata: couldn't get content from $url ($status)";
    }

    return $self->html( $res->decoded_content );
}

sub _apply_rule {
    my ( $self, $params ) = @_;

    my $attr            = $params->{'attr'};
    my $extracted_data  = $params->{'extracted_data'};
    my $parser          = $params->{'parser'};
    my $rule            = $params->{'rule'};
    my $tag             = $params->{'tag'};

    if ( exists $rule->{'require_attr'} ) {
        my $required_attrs = $rule->{'require_attr'};
        foreach my $k ( keys %{ $required_attrs } ) {
            if ( ! exists $attr->{$k} ) {
                return;
            }

            if ( $attr->{$k} ne $required_attrs->{$k} ) {
                return;
            }
        }
    }

    if ( $rule->{'extract_body'} ) {
        my $body = $parser->get_text("/$tag");
        $parser->get_tag("/$tag");
        $extracted_data->{ $rule->{'fill'} } ||= $body;
        return;
    }

    if ( $rule->{'extract_attr'} ) {
        if ( my $attrval = $attr->{ $rule->{'extract_attr'} } ) {
            $extracted_data->{ $rule->{'fill'} } ||= $attrval;
        }
        return;
    }

    return;
}

sub _extract_metadata {
    my ($self) = @_;

    return if $self->{'_html_parsed'};

    my $html = $self->html;

    if ( ! Encode::is_utf8($html) ) {
        ## pass #1 - find the document encoding
        my $encoding = "utf-8";
        {
            my $parser = HTML::TokeParser->new( \$html );
            while (my $taginfo = $parser->get_tag('meta')) {
                my $attr = $taginfo->[1];
                my $he = $attr->{'http-equiv'};
                if ($he && lc($he) eq 'content-type') {
                    my $content = $attr->{'content'};
                    if ($content && $content =~ /charset=([\w\-]+)/) {
                        $encoding = $1;
                    }
                    last;
                }
            }
        }

        $html = Encode::decode($encoding, $html);
    }

    my %extracted_data;

    my $parser = HTML::TokeParser->new( \$html );

    my @tags_handled = keys %EXTRACTED_DATA;

    while ( my $taginfo = $parser->get_tag(@tags_handled) ) {
        my ( $tag, $attr, $attrseq, $text ) = @{ $taginfo };

        my $rules = $EXTRACTED_DATA{$tag};
        if ( ref $rules ne 'ARRAY' ) {
            $rules = [ $rules ];
        }

        foreach my $rule (@{ $rules }) {
            $self->_apply_rule( {
                'attr'              => $attr,
                'extracted_data'    => \%extracted_data,
                'parser'            => $parser,
                'rule'              => $rule,
                'tag'               => $tag,
            } );
        }
    }
    
    $self->title( $extracted_data{'og_title'}
          || $extracted_data{'meta_title'}
          || $extracted_data{'title'}
          || $extracted_data{'html_title_h1'}
          || $extracted_data{'html_title_h2'}
          || $extracted_data{'html_title_h3'} );

    $self->description( $extracted_data{'og_description'}
          || $extracted_data{'meta_description'}
          || $extracted_data{'html_description'} );

    $self->image( $extracted_data{'og_image'}
          || $extracted_data{'link_image'}
          || $extracted_data{'html_image'} );
    
    $self->og_url($extracted_data{'og_url'});

    $self->{'_html_parsed'} = 1;

    return;
}

1;

__END__

=head1 NAME

LJ::HTML::Metadata

=head1 DESCRIPTION

Extract metadata (title, description, image) from
arbitrary HTML pages.

=head1 SYNOPSIS

 use LJ::HTML::Metadata;
 
 my $url = 'http://kommersant.ru/doc/1639415';
 
 my $metadata;
 
 # pass an URL; 'ua' param here is optional:
 $metadata = LJ::HTML::Metadata->new( 'url' => $url,
                                      'ua' => LWP::UserAgent->new, );
 
 # alternatively, pass HTML code
 $metadata = LJ::HTML::Metadata->new( 'html' => $html );
 
 print $metadata->title;
 print $metadata->description;
 print $metadata->image;

=head1 CONVENTIONS

The module assumes that it works in an UTF-8 context. It always
returns 'byte strings', as opposed to 'character strings'
(it works with 'character strings' internally, but this is subject to change).

=head1 DATA EXTRACTED

In order of priority, descending. Generally, a site would want to conform
to the OpenGraph spec (http://ogp.me/) which has the most priority, but
failing that, we can try to extract stuff from other data.

For 'title':

 <meta property="og:title" content="$title"/>
 <meta name="title" content="$title"/>
 <h[123]>$title</h[123]>
 <title>$title</title>

(h1 doesn't take precedence over h2/h3 for now.)

For 'description':

 <meta property="og:description" content="$description"/>
 <meta name="description" content="$description"/>
 <p>$description</p>

For 'image':

 <meta property="og:image" content="$image"/>
 <link rel="image_src" href="$image"/>
 <img src="$image">

=head1 VERSION

1.0

