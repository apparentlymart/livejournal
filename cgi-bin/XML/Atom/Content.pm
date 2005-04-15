# $Id$

package XML::Atom::Content;
use strict;

use XML::Atom;
use base qw( XML::Atom::ErrorHandler );
use XML::Atom::Util qw( remove_default_ns );
use MIME::Base64 qw( encode_base64 decode_base64 );

use constant NS => 'http://purl.org/atom/ns#';

sub new {
    my $class = shift;
    my $content = bless {}, $class;
    $content->init(@_) or return $class->error($content->errstr);
    $content;
}

sub init {
    my $content = shift;
    my %param = @_ == 1 ? (Body => $_[0]) : @_;
    my $elem;
    unless ($elem = $param{Elem}) {
        if (LIBXML) {
            my $doc = XML::LibXML::Document->createDocument('1.0', 'utf-8');
            $elem = $doc->createElementNS(NS, 'content');
            $doc->setDocumentElement($elem);
        } else {
            $elem = XML::XPath::Node::Element->new('content');
        }
    }
    $content->{elem} = $elem;
    if ($param{Body}) {
        $content->body($param{Body});
    }
    if ($param{Type}) {
        $content->type($param{Type});
    }
    $content;
}

sub elem { $_[0]->{elem} }

sub type {
    my $content = shift;
    if (@_) {
        $content->elem->setAttribute('type', shift);
    }
    $content->elem->getAttribute('type');
}

sub mode {
    my $content = shift;
    $content->elem->getAttribute('mode');
}

sub body {
    my $content = shift;
    my $elem = $content->elem;
    if (@_) {
        my $data = shift;
        if (LIBXML) {
            $elem->removeChildNodes;
        } else {
            $elem->removeChild($_) for $elem->getChildNodes;
        }
        if (!_is_printable($data)) {
            if (LIBXML) {
               $elem->appendChild(XML::LibXML::Text->new(encode_base64($data, '')));
            } else {
               $elem->appendChild(XML::XPath::Node::Text->new(encode_base64($data, '')));
            }
            $elem->setAttribute('mode', 'base64');
        } else {
            my $copy = '<div xmlns="http://www.w3.org/1999/xhtml">' .
                       $data .
                       '</div>';
            my $node;
            eval {
                if (LIBXML) {
                    my $parser = XML::LibXML->new;
                    my $tree = $parser->parse_string($copy);
                    $node = $tree->getDocumentElement;
                } else {
                    my $xp = XML::XPath->new(xml => $copy);
                    $node = (($xp->find('/')->get_nodelist)[0]->getChildNodes)[0]
                        if $xp;
                }
            };
            if (!$@ && $node) {
                $elem->appendChild($node);
                $elem->setAttribute('mode', 'xml');
            } else {
                if (LIBXML) {
                    $elem->appendChild(XML::LibXML::Text->new($data));
                } else {
                    $elem->appendChild(XML::XPath::Node::Text->new($data));
                }
                $elem->setAttribute('mode', 'escaped');
            }
        }
    } else {
        unless (exists $content->{__body}) {
            my $mode = $elem->getAttribute('mode') || 'xml';
            if ($mode eq 'xml') {
                my @children = grep ref($_) =~ /Element/,
                    LIBXML ? $elem->childNodes : $elem->getChildNodes;
                if (@children) {
                    if (@children == 1 && $children[0]->getLocalName eq 'div') {
                        @children =
                            LIBXML ? $children[0]->childNodes :
                                     $children[0]->getChildNodes
                    }
                    $content->{__body} = '';
                    for my $n (@children) {
                        remove_default_ns($n) if LIBXML;
                        $content->{__body} .= $n->toString(LIBXML ? 1 : 0);
                    }
                } else {
                    $content->{__body} = LIBXML ? $elem->textContent : $elem->string_value;
                }
            } elsif ($mode eq 'base64') {
                $content->{__body} = decode_base64(LIBXML ? $elem->textContent : $elem->string_value);
            } elsif ($mode eq 'escaped') {
                $content->{__body} = LIBXML ? $elem->textContent : $elem->string_value;
            } else {
                $content->{__body} = undef;
            }
            if ($] >= 5.008) {
                require Encode;
                Encode::_utf8_off($content->{__body});
            }
        }
    }
    $content->{__body};
}

sub _is_printable {
    my $data = shift;

    # printable ASCII or UTF-8 bytes
    $data =~ /^(?:[\x09\x0a\x0d\x20-\x7f]|[\xc0-\xdf][\x80-\xbf]|[\xe0-\xef][\x80-\xbf][\x80-\xbf])*$/;
}

sub as_xml {
    my $content = shift;
    if (LIBXML) {
        my $doc = XML::LibXML::Document->new('1.0', 'utf-8');
        $doc->setDocumentElement($content->elem);
        return $doc->toString(1);
    } else {
        return $content->elem->toString;
    }
}

1;
