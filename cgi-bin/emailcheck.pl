#!/usr/bin/perl
#

use Socket;
use Sys::Hostname;
use FileHandle;

# Return the list of mail exchangers for the given domain.  Uses nslookup.
sub get_mail_exchangers
{
    my @mx = ();

    my $NS;
    open(NS, "nslookup -query=mx $_[0] |");
    while (<NS>)
    {
        push @mx, $1 if (/mail exchanger = (([\w-]+\.)*$_[0])/);
    }
    close NS;
    
    return @mx;
}

sub email_check_log
{
    my ($message) = @_;
    if (0 && $message)
    {
        open(LOG, ">>email_check.log");
        print LOG "$message\n";
        close(LOG);
    }
}

sub reject_email
{
    my ($email, $reason, $message, $errors) = @_;

    if ($email) { &email_check_log("$email: $reason"); }
    push @{$errors}, $message;
}


# Check an email address.
sub check_email 
{
    my ($email, $errors) = @_;

    # Trim off whitespace and force to lowercase.
    $email =~ s/^\s+//;
    $email =~ s/\s+$//;
    $email = lc $email;

    # Empty email addresses are not good.
    unless ($email)
    {
        reject_email($email, "empty",
                     "Your email address cannot be blank.",
                     $errors);
        return;
    }

    # Check that the address is of the form username@some.domain.
    my ($username, $domain);
    if ($email =~ /^([^@]+)@([^@]+)/)
    {
        $username = $1;
        $domain = $2;
    }
    else
    {
        reject_email($email, "bad form",
                     "You did not give a valid email address.  An email address looks like username\@some.domain",
                     $errors);
        return;
    }

    # Check the username for invalid characters.
    unless ($username =~ /^[^\s\",;\(\)\[\]\{\}\<\>]+$/)
    {
        reject_email($email, "bad username",
                     "You have invalid characters in your email address username.",
                     $errors);
        return;
    }

    # Check the domain name.
    unless ($domain =~ /^[\w-]+(\.[\w-]+)*\.(ad|ae|af|ag|ai|al|am|an|ao|aq|ar|as|at|au|aw|az|ba|bb|bd|be|bf|bg|bh|bi|bj|bm|bn|bo|br|bs|bt|bv|bw|by|bz|ca|cc|cf|cg|ch|ci|ck|cl|cm|cn|co|cr|cs|cu|cv|cx|cy|cz|de|dj|dk|dm|do|dz|ec|ee|eg|eh|er|es|et|fi|fj|fk|fm|fo|fr|fx|ga|gb|gd|ge|gf|gh|gi|gl|gm|gn|gp|gq|gr|gs|gt|gu|gw|gy|hk|hm|hn|hr|ht|hu|id|ie|il|im|in|io|iq|ir|is|it|jm|jo|jp|ke|kg|kh|ki|km|kn|kp|kr|kw|ky|kz|la|lb|lc|li|lk|lr|ls|lt|lu|lv|ly|ma|mc|md|mg|mh|mk|ml|mm|mn|mo|mp|mq|mr|ms|mt|mu|mv|mw|mx|my|mz|na|nc|ne|nf|ng|ni|nl|no|np|nr|nt|nu|nz|om|pa|pe|pf|pg|ph|pk|pl|pm|pn|pr|pt|pw|py|qa|re|ro|ru|rw|sa|sb|sc|sd|se|sg|sh|si|sj|sk|sl|sm|sn|so|sr|st|su|sv|sy|sz|tc|td|tf|tg|th|tj|tk|tm|tn|to|tp|tr|tt|tv|tw|tz|ua|ug|uk|um|us|uy|uz|va|vc|ve|vg|vi|vn|vu|wf|ws|ye|yt|yu|za|zm|zr|zw|com|edu|gov|int|mil|net|org|arpa|nato|aero|biz|coop|info|museum|name|pro)$/)
    {
        reject_email($email, "bad domain",
                     "Your email address domain is invalid.",
                     $errors);
        return;
    }

    # Catch misspellings of hotmail.com
    if ($domain =~ /^(otmail|hotmial|hotmil|hotamail|hotmaul|hoatmail|hatmail)\.(cm|co|com|cmo|om)$/)
    {
        reject_email($email, "bad hotmail spelling",
                     "You gave $email as your email address.  Are you sure you didn't mean hotmail.com?",
                     $errors);
        return;
    }

    # Catch misspellings of aol.com
    elsif ($domain =~ /^(ol|aoll)\.(cm|co|com|cmo|om)$/)
    {
        reject_email($email, "bad aol spelling",
                     "You gave $email as your email address.  Are you sure you didn't mean aol.com?",
                     $errors);
        return;
    }

    # Catch web addresses (two or more w's followed by a dot)
    elsif ($username =~ /^www*\./)
    {
        reject_email($email, "web address",
                     "You gave $email as your email address, but it looks more like a web address to me.",
                     $errors);
        return;
    }


    # AOL email addresses need to be verified.
    if (0 && $domain =~ /^aol\.com$/)
    {
        my @mx = get_mail_exchangers('aol.com');
        my $host = gethostbyname($mx[rand($#mx + 1)]);
        unless ($host) { email_check_log("Could not find hosts for AOL."); }
        return unless $host;

        my $proto = getprotobyname('tcp');
        my $serv = getservbyname('smtp', 'tcp');
        my $sin = sockaddr_in($serv, $host);

        my $SOCKET;
        return unless socket(SOCKET, PF_INET, SOCK_STREAM, $proto);
        return unless connect(SOCKET, $sin);
        return unless (<SOCKET> =~ /^220/);
        autoflush SOCKET 1;

        # Get a fully qualified hostname for ourself, and introduce ourself.
        my $self = hostname();
        unless ($self =~ /\./)
        {
            my @hostrec = gethostbyname($self);
            $self = $hostrec[0];
        }
        print SOCKET "HELO $self\r\n";
        for (;;)
        {
            return unless defined($_ = <SOCKET>);
            last if /^250/;
            return unless (/^220/);
        }

        # Pretend to send an email to the person and watch the reaction.
        print SOCKET "MAIL FROM:<bradfi2\@bradfitz.com>\r\n";
        return unless <SOCKET> =~ /^250/;
        print SOCKET "RCPT TO:<$email>\r\n";
        $_ = <SOCKET>;
        if (/^5\d\d\s*([^\r\n]+)/)
        {
            reject_email($email, "bad AOL: $1",
                         "Your email address could not be verified. Your ISP's mail server said: <B>$1</B>",
                         $errors);
            return;
        }
        return unless /^250/;

        print SOCKET "QUIT\r\n";
        close SOCKET;
        return;
    }
  
}


1;

