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
    
    qq{<lj-template name="video"} . 
    ( $attrs{width} ? qq{ width="$attrs{width}"} : '' ) .
    ( $attrs{height} ? qq{ height="$attrs{height}"} : '' ) .
    qq{>$attrs{src}</ljtemplate>};
    !gxe;
}

# This doesn't work right, fix and replace the regex later.
sub toke_parse
{
    &LJ::nodb;
    my ($postref, $error, $iteminfo) = @_;

    my $newdata = '';

    my $obj_open = 0;
    my $param_open = 0;
    my $embed_open = 0;

    my $width;
    my $height;
    my $src;

    my $p = HTML::TokeParser->new($postref);

    # if we're being called from mailgated, then we're not in web context and therefore
    # do not have any BML::ml functionality.  detect this now and report errors in a 
    # plaintext, non-translated form to be bounced via email.
    my $have_bml = eval { BML::ml() } || ! $@;

    my $err = sub {
        # more than one element, either make a call to BML::ml
        # or build up a semi-useful error string from it
        if (@_ > 1) {
            if ($have_bml) {
                $$error = BML::ml(@_);
                return 0;
            }

            $$error = shift() . ": ";
            while (my ($k, $v) = each %{$_[0]}) {
                $$error .= "$k=$v,";
            }
            chop $$error;
            return 0;
        }

        # single element, either look up in %BML::ML or return verbatim
        $$error = $have_bml ? $BML::ML{$_[0]} : $_[0];
        return 0;
    };

    while (my $token = $p->get_token)    
    {
        my $type = $token->[0];
        my $append;
        
        if ($type eq "S")     # start tag
        {
            my $tag = $token->[1];
            my $opts = $token->[2];
    
            ######## Begin object tag
            
            if ($tag eq "object") {
                die( "object tag opened twice" )
                    if $obj_open;

                $obj_open = 1;
                
                $width = $opts->{'width'};
                $height = $opts->{'height'};
            }

            ######## Begin param tag
            
            elsif ($tag eq "param") 
            {
                die( "Already inside param tag" )
                    if $param_open;
            
                die( "param without object" )
                    unless $obj_open;

                $param_open = 1;

                if (defined( $opts->{name} ) and $opts->{name} eq 'movie') {
                    $src = $opts->{value};
                }
            }

            ######## Begin embed tag

            elsif ($tag eq "embed")
            {
                die( "Nested embed tag" )
                    if $embed_open;

                die( "Not inside object" )
                    unless $obj_open;
                
                $embed_open = 1;

                if (defined( $opts->{src} )) {
                    $src = $opts->{src};
                }

                if (defined( $opts->{width} )) {
                    $width = $opts->{width};
                }

                if (defined( $opts->{height} )) {
                    $height = $opts->{height};
                }
            }   

            #### not a special tag.
            # If we're inside an object, eat it. If not, spit it back out

            else 
            {
                next if $obj_open;
                $append .= "<$tag";
                foreach (keys %$opts) {
                    $append .= " $_=\"$opts->{$_}\"";
                }
                $append .= ">";
            }
        }
        elsif ($type eq "E") 
        {
            my $tag = $token->[1];

            ##### end object

            if ($tag eq "object") {
                die( "Closing object tag without opening one" )
                    unless $obj_open;

                $obj_open = 0;

                if ($src) {
                    $append .= "<lj-template type=stuff";
                }
            } 

            ##### end param

            elsif ($tag eq "param") {
                die( "Closing param tag without opening" )
                    unless $param_open;

                $param_open = 0;
                
            }

            ##### end embed

            elsif ($tag eq "embed") {
                die( "Can't close unopened embed tag" )
                    unless $embed_open;

                $embed_open = 0;
            }
            
            ###### not a special tag.
            
            else
            {
                $append .= "</$tag>";
            }
        }
        elsif ($type eq "T" || $type eq "D") 
        {
            $append = $token->[1];
        } 
        elsif ($type eq "C") {
            # ignore comments
        }
        elsif ($type eq "PI") {
            $newdata .= "<?$token->[1]>";
        }
        else {
            $newdata .= "<!-- OTHER: " . $type . "-->\n";
        }

        if (length( $append )) {
            $newdata .= $append;
        }
    } 

    $$postref = $newdata;
    return 1;
}

1;
