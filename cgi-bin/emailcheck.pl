#!/usr/bin/perl
#
# Function to reject bogus email addresses
#

sub check_email 
{
    my ($email, $errors) = @_;

    # Trim off whitespace and force to lowercase.
    $email =~ s/^\s+//;
    $email =~ s/\s+$//;
    $email = lc $email;

    my $reject = sub {
        my $errcode = shift;
        my $errmsg = shift;
        # TODO: add $opts to end of check_email and make option 
        #       to either return error codes, or let caller supply
        #       a subref to resolve error codes into native language
        #       error messages (probably via BML::ML hash, or something)
        push @$errors, $errmsg; 
        return;
    };

    # Empty email addresses are not good.
    unless ($email) {
        return $reject->("empty",
                         "Your email address cannot be blank.");
    }

    # Check that the address is of the form username@some.domain.
    my ($username, $domain);
    if ($email =~ /^([^@]+)@([^@]+)/) {
        $username = $1;
        $domain = $2;
    } else {
        return $reject->("bad_form",
                         "You did not give a valid email address.  An email address looks like username\@some.domain");
    }

    # Check the username for invalid characters.
    unless ($username =~ /^[^\s\",;\(\)\[\]\{\}\<\>]+$/) {
        return $reject->("bad_username",
                         "You have invalid characters in your email address username.");
    }

    # Check the domain name.
    unless ($domain =~ /^[\w-]+(\.[\w-]+)*\.(ad|ae|af|ag|ai|al|am|an|ao|aq|ar|as|at|au|aw|az|ba|bb|bd|be|bf|bg|bh|bi|bj|bm|bn|bo|br|bs|bt|bv|bw|by|bz|ca|cc|cf|cg|ch|ci|ck|cl|cm|cn|co|cr|cs|cu|cv|cx|cy|cz|de|dj|dk|dm|do|dz|ec|ee|eg|eh|er|es|et|fi|fj|fk|fm|fo|fr|fx|ga|gb|gd|ge|gf|gh|gi|gl|gm|gn|gp|gq|gr|gs|gt|gu|gw|gy|hk|hm|hn|hr|ht|hu|id|ie|il|im|in|io|iq|ir|is|it|jm|jo|jp|ke|kg|kh|ki|km|kn|kp|kr|kw|ky|kz|la|lb|lc|li|lk|lr|ls|lt|lu|lv|ly|ma|mc|md|mg|mh|mk|ml|mm|mn|mo|mp|mq|mr|ms|mt|mu|mv|mw|mx|my|mz|na|nc|ne|nf|ng|ni|nl|no|np|nr|nt|nu|nz|om|pa|pe|pf|pg|ph|pk|pl|pm|pn|pr|pt|pw|py|qa|re|ro|ru|rw|sa|sb|sc|sd|se|sg|sh|si|sj|sk|sl|sm|sn|so|sr|st|su|sv|sy|sz|tc|td|tf|tg|th|tj|tk|tm|tn|to|tp|tr|tt|tv|tw|tz|ua|ug|uk|um|us|uy|uz|va|vc|ve|vg|vi|vn|vu|wf|ws|ye|yt|yu|za|zm|zr|zw|com|edu|gov|int|mil|net|org|arpa|nato|aero|biz|coop|info|museum|name|pro)$/)
    {
        return $reject->("bad_domain",
                         "Your email address domain is invalid.");
    }

    # Catch misspellings of hotmail.com
    if ($domain =~ /^(otmail|hotmial|hotmil|hotamail|hotmaul|hoatmail|hatmail|htomail)\.(cm|co|com|cmo|om)$/ or
        $domain =~ /^hotmail\.(cm|co|om|cmo)$/)
    {
        return $reject->("bad_hotmail_spelling",
                         "You gave $email as your email address.  Are you sure you didn't mean hotmail.com?");
    }

    # Catch misspellings of aol.com
    elsif ($domain =~ /^(ol|aoll)\.(cm|co|com|cmo|om)$/ or
           $domain =~ /^aol\.(cm|co|om|cmo)$/)
    {
        return $reject->("bad_aol_spelling",
                         "You gave $email as your email address.  Are you sure you didn't mean aol.com?");
    }

    # Catch web addresses (two or more w's followed by a dot)
    elsif ($username =~ /^www*\./)
    {
        return $reject->("web_address",
                         "You gave $email as your email address, but it looks more like a web address to me.");
    }
}

1;

