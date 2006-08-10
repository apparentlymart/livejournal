#!/usr/bin/perl
#

package LJ::Embed;

use strict;
use HTML::TokeParser ();

sub contains_new_embed
{
    my $postref = shift;
    return ($$postref =~ /<object\b|<embed\b/i);
}

sub _parse_attrs {
    my $input = shift;
    
    return map { ( m/\s*(\S+)="([^"]*)"/ ) } split /\s+/, $input;
}

sub parse
{
    &LJ::nodb;
    my ($postref, $error, $iteminfo) = @_;

    $$postref =~ s!
        <object[^>]*>\s*
        (?:<param[^>]*>\s*
            (?:</param>)?
        )?
        <embed([^>]*?)/?>
            (?:</embed>)?
        </object>
    !
    my %attrs = _parse_attrs( $1 );
    qq{<lj-template name="video">$attrs{src}</lj-template>};
    !gxe;
    
    $$postref =~ s!
        <embed([^>]*)>\s*
        </embed>
    !
    my %attrs = _parse_attrs( $1 );
    qq{<lj-template name="video">$attrs{src}</lj-template>};
    !gxe;
}

1;
