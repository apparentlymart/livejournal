# Blogger API wrapper for LJ

package Apache::LiveJournal::Interface::Blogger;

sub newPost {
    shift;
    my ($appkey, $journal, $user, $password, $content, $publish) = @_;

    my $err;
    my @ltime = localtime();
    my $req = {
	'usejournal' => $journal ne $user ? $journal : undef,
	'ver' => 1,
	'username' => $user,
	'password' => $password,
	'event' => $content,
	'year' => $ltime[5]+1900,
	'mon' => $ltime[4]+1,
	'day' => $ltime[3],
	'hour' => $ltime[2],
	'min' => $ltime[1],
    };

    use Data::Dumper;
    print STDERR Dumper($req);

    my $res = LJ::Protocol::do_request("postevent", $req, \$err);
    
    if ($err) {
        die SOAP::Fault
            ->faultstring(LJ::Protocol::error_message($err))
            ->faultcode(substr($err, 0, 3));
    }

    return $res->{'itemid'};
}

1;
