#!/usr/bin/perl
#############################################################################
#####                  [ CLIENT PERSISTENCE FUNCTIONS ]                 #####
#############################################################################
#
# Brad Fitzpatrick, bradfitz@bradfitz.com
#

package BMLClient;

&reset;

sub reset
{
    $SAVE_DIR = $main::BMLEnv{'ClientDir'};
    $USE_SESSION = $main::BMLEnv{'UseBmlSession'};
    $LOADED = 0;
    $DIRTY = 0;                 # does it need to be saved?
    %data = ();
    %COOKIE = ();
    $USERID = "";

    $ENV{'HTTP_COOKIE'} .= "";  # quiet warning
    foreach (split(/;\s+/, $ENV{'HTTP_COOKIE'}))
    {
	if ($_ =~ /(.*)=(.*)/)
	{
	    $COOKIE{$1} = $2;
	}
    }
}

sub get_var
{
    my ($var) = @_;
    &load;
    return $data{$var};	
}

sub set_var
{
    my ($var, $val) = @_;
    &load;
    return if ($data{$var} eq $val);  # efficiency, eh? kinda peaceful.
    
    $data{$var} = $val;
    $DIRTY = 1;  # uh-oh.. needs to be saved now	
}

sub load
{
    return if $LOADED || not $USE_SESSION;
    my $user = &user_id;
    my ($var, $val);
    
    open (CL, "$SAVE_DIR/$user.dat");
    my @attributes = <CL>;
    close CL;
    
    chop @attributes;
    %data = @attributes;
    
    $LOADED = 1;
}

sub save
{
    return unless $DIRTY && $USE_SESSION;
    my $user = &user_id;
    
    open (CL, ">$SAVE_DIR/$user.dat") || print "Can't save open<BR>\n";
    for (%data)
    {
	print CL "$_\n";		
    }
    close CL;
    $DIRTY = 0;
}

sub user_id
{
    return $USERID if $USERID;
    
    if ($COOKIE{'BMLSESSION'} && $COOKIE{'BMLSESSION'} !~ /[^\w]/)
    {
	$USERID = $COOKIE{'BMLSESSION'};
	
	return $USERID;
    }
    
    $USERID = "";
    srand;
    for (0..25)
    {
	$USERID .= chr(97+int(rand(26)));
    }
    &set_cookie('BMLSESSION', $USERID, time()+60*60*24*90, ($main::BMLEnv{'ClientTopPath'} || "/"));	
}

# $expires = 0  to expire when browser closes
# $expires = undef to delete cookie
sub set_cookie
{
    my ($name, $value, $expires, $path, $domain) = @_;
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime($expires);
    $year+=1900;

    my @day = qw{Sunday Monday Tuesday Wednesday Thursday Friday Saturday};
    my @month = qw{Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec};
    
    printf "Set-Cookie: %s=%s", BMLUtil::eurl($name), BMLUtil::eurl($value);

    # this logic is confusing potentially
    unless (defined $expires && $expires==0) {
	printf "; expires=$day[$wday], %02d-$month[$mon]-%04d %02d:%02d:%02d GMT", 
		$mday, $year, $hour, $min, $sec;
    }

    print "; path=$path" if $path;
    print "; domain=$domain" if $domain;
    print "\n";
}

package main;
1;
