#!/usr/bin/perl
#

require '/home/lj/cgi-bin/ljlib.pl';
use LWP;
use LWP::UserAgent;

package LJ::Pay;

%account = (
	    2 => { 'name' => '2 months', 'amount' => 5 },
	    6 => { 'name' => '6 months', 'amount' => 15 },
	    12 => { 'name' => '12 months', 'amount' => 25 },
	    );

%ibill = (
	  100 => { 'months' => 12, amount => "25", },
	  101 => { 'months' =>  6, amount => "15", },
	  102 => { 'months' =>  2, amount => "5", },
	  500 => { 'months' => 12, amount => "25", },
	  501 => { 'months' =>  6, amount => "15", },
	  502 => { 'months' =>  2, amount => "5.95", },
	  );

sub register_payment
{
    my $dbh = shift;
    my $o = shift;
    my $sth;
    my $error = $o->{'error'};

    my $user = lc($o->{'user'});
    $user =~ s/\W//g;
    my $userid = LJ::get_userid($dbh, $user);
    
    unless ($userid) {
	$$error = "Invalid user ($user)";
	return 0;
    }

    my $qdatesent = $dbh->quote($o->{'datesent'});
    my $qamount = $dbh->quote($o->{'amount'});
    my $qmonths = $dbh->quote($o->{'months'});
    my $qnotes = $dbh->quote($o->{'notes'});
    my $qmethod = $dbh->quote($o->{'method'});
    my $qwhat = $dbh->quote($o->{'what'});

    ### now, insert a payment
    $sth = $dbh->prepare("INSERT INTO payments (userid, datesent, daterecv, amount, months, used, mailed, notes, method, forwhat) VALUES ($userid, $qdatesent, NOW(), $qamount, $qmonths, 'N', 'N', $qnotes, $qmethod, $qwhat)");
    $sth->execute;

    if ($dbh->err) {
	$$error = "Database error: " . $dbh->errstr;
	return 0;
    }

    my $payid = $sth->{'mysql_insertid'};

    my $whoenter = $o->{'remote'}->{'user'} || "auto";
    my $msgbody = "Entered by $whoenter: payment# $payid for $user\n\n";
    $msgbody .= "AMOUNT: $o->{'amount'}   MONTHS: $o->{'months'}\n";
    $msgbody .= "METHOD: $o->{'method'}   WHAT: $o->{'what'}\n";
    $msgbody .= "DATE: $o->{'datesent'}\n";
    $msgbody .= "NOTES:\n$o->{'notes'}\n";

    &LJ::send_mail({ 'to' => 'accounts@livejournal.com',
		     'from' => 'lj_noreply@livejournal.com',
		     'subject' => "Payment \#$payid -- $user",
		     'body' => $msgbody,
		 });

    return $userid;
}

sub register_paypal_payment
{
    my $dbh = shift;
    my $pp = shift;
    my $o = shift;
    my $error = $o->{'error'};
    
    my %custom;
    foreach my $pair (split(/&/, $pp->{'custom'}))
    {
	my ($key, $value) = split(/=/, $pair);
	foreach (\$key, \$value) {
	    tr/+/ /;
	    s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/eg;
	}
	$custom{$key} = $value;
    }
    
    if ($account{$custom{'months'}}->{'amount'} != $pp->{'payment_gross'}) {
	$$error = "Payment gross not valid for that month value";
	return 0;
    }

    my %mon2num = qw(Jan 1 Feb 2 Mar 3 Apr 4 May 5 Jun 6
		     Jul 7 Aug 8 Sep 9 Oct 10 Nov 11 Dec 12);

    # normal payment for self
    if ($custom{'type'} eq "") {
	my %pay;
	$pay{'user'} = $custom{'user'};
	$pay{'months'} = $custom{'months'};
	$pay{'amount'} = $pp->{'payment_gross'};
	if ($pp->{'payment_date'} =~ /\b(\w\w\w) (\d{1,2}), (\d\d\d\d)\b/) {	
	    my ($year, $month, $day);
	    $year = $3;
	    $month = $mon2num{$1};
	    $day = $2;
	    $pay{'datesent'} = sprintf("%04d-%02d-%02d", $year, $month, $day);
	}
	$pay{'what'} = "account";  # one of (account, rename, gift)
	$pay{'method'} = "paypal";
	$pay{'notes'} = "PayPal Transaction ID: " . $pp->{'txn_id'};

	$pay{'error'} = $error;
	if (register_payment($dbh, \%pay)) { return 1; }
	return 0;
    }

}

sub verify_paypal_transaction
{
    my $hash = shift;
    my $opts = shift;

    my $ua = new LWP::UserAgent;
    $ua->agent("LJ-PayPalAuth/0.1");

    # Create a request
    my $req = new HTTP::Request POST => 'https://www.paypal.com/cgi-bin/webscr?cmd=_notify-validate';
    $req->content_type('application/x-www-form-urlencoded');
    $req->content(join("&", map { &LJ::eurl($_) . "=" . &LJ::eurl($hash->{$_}) } keys %$hash));
    
    # Pass request to the user agent and get a response back
    my $res = $ua->request($req);
    
    # Check the outcome of the response
    if ($res->is_success) {
	if ($res->content eq "VERIFIED") { return 1; }
	${$opts->{'error'}} = "Invalid";
	return 0;
    } 
    ${$opts->{'error'}} = "Connection Problem";
    return 0;
}

1;
