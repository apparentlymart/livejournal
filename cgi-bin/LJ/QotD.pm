package LJ::QotD;
use strict;
use Carp qw(croak);

# returns 'current' or 'old' depending on given start and end times
sub get_type {
    my $class = shift;
    my %times = @_;

    return $class->is_current(%times) ? 'current' : 'old';
}

# given a start and end time, returns if now is between those two times
sub is_current {
    my $class = shift;
    my %times = @_;

    return 0 unless $times{start} && $times{end};

    my $now = time();
    return $times{start} <= $now && $times{end} >= $now;
}

sub memcache_key {
    my $class = shift;
    my $type = shift;

    return "qotd:$type";
}

sub cache_get {
    my $class = shift;
    my $type = shift;

    # first, is it in our per-request cache?
    my $questions = $LJ::QotD::REQ_CACHE_QOTD{$type};
    return $questions if $questions;

    my $memkey = $class->memcache_key($type);
    my $memcache_data = LJ::MemCache::get($memkey);
    if ($memcache_data) {
        # fill the request cache since it was empty
        $class->request_cache_set($type, $memcache_data);
    }
    return $memcache_data;
}

sub request_cache_set {
    my $class = shift;
    my $type = shift;
    my $val = shift;

    $LJ::QotD::REQ_CACHE_QOTD{$type} = $val;
}

sub cache_set {
    my $class = shift;
    my $type = shift;
    my $val = shift;

    # first set in request cache
    $class->request_cache_set($type, $val);

    # now set in memcache
    my $memkey = $class->memcache_key($type);
    my $expire = 60*5; # 5 minutes
    return LJ::MemCache::set($memkey, $val, $expire);
}

sub cache_clear {
    my $class = shift;
    my $type = shift;

    # clear request cache
    delete $LJ::QotD::REQ_CACHE_QOTD{$type};

    # clear memcache
    my $memkey = $class->memcache_key($type);
    return LJ::MemCache::delete($memkey);
}

# returns the current active questions
sub load_current_questions {
    my $class = shift;
    my %opts = @_;

    my $questions = $class->cache_get('current');
    return @$questions if $questions;

    my $dbr = LJ::get_db_reader()
        or die "no global database reader for QotD";

    my $now = time();
    my $sth = $dbr->prepare(
         "SELECT * FROM qotd WHERE time_start <= ? AND time_end >= ? AND active='Y'"
    );
    $sth->execute($now, $now);

    my @rows = ();
    while (my $row = $sth->fetchrow_hashref) {
        push @rows, $row;
    }
    $class->cache_set('current', \@rows);

    return @rows;
}

# returns the non-current active questions that
# have an end time more recent than a month ago
sub load_old_questions {
    my $class = shift;
    my %opts = @_;

    my $questions = $class->cache_get('old');
    return @$questions if $questions;

    my $dbr = LJ::get_db_reader()
        or die "no global database reader for QotD";

    my $now = time();
    my $one_month_ago = $now - 86400*30;
    my $sth = $dbr->prepare(
         "SELECT * FROM qotd WHERE time_end >= ? AND time_end < ? AND active='Y'"
    );
    $sth->execute($one_month_ago, $now);

    my @rows = ();
    while (my $row = $sth->fetchrow_hashref) {
        push @rows, $row;
    }
    $class->cache_set('old', \@rows);

    return @rows;
}

sub get_questions {
    my $class = shift;
    my %opts = @_;

    my $skip = defined $opts{skip} ? $opts{skip} : 0;

    my @questions;
    if ($skip == 0) {
        @questions = $class->load_current_questions;
    } else {
        @questions = $class->load_old_questions;
    }

    # sort questions in descending order by start time (newest first)
    @questions = 
        sort { $b->{time_start} <=> $a->{time_start} } 
        grep { ref $_ } @questions;

    # if we're getting the current questions, just return them
    return @questions if $skip == 0;

    # if we're getting old questions, we need to only return the one for this view
    my $index = $skip - 1;

    # only return the array elements that exist
    my @ret = grep { ref $_ } $questions[$index];
    return @ret;
}

sub store_question {
    my $class = shift;
    my %vals = @_;

    my $dbh = LJ::get_db_writer()
        or die "Unable to store question: no global dbh";

    # update existing question
    if ($vals{qid}) {
        $dbh->do("UPDATE qotd SET time_start=?, time_end=?, active=?, text=?, img_url=? WHERE qid=?",
                 undef, (map { $vals{$_} } qw(time_start time_end active text img_url qid)))
            or die "Error updating qotd: " . $dbh->errstr;
    }
    # insert new question
    else {
        $dbh->do("INSERT INTO qotd VALUES (?,?,?,?,?,?)",
                 undef, "null", (map { $vals{$_} } qw(time_start time_end active text img_url)))
            or die "Error adding qotd: " . $dbh->errstr;
    }

    # insert/update question in translation system
    my $qid = $vals{qid} || $dbh->{mysql_insertid};
    my $ml_key = LJ::Widget::QotD->ml_key("$qid.text");
    LJ::Widget->ml_set_text($ml_key => $vals{text});

    # clear cache
    my $type = $class->get_type( start => $vals{time_start}, end => $vals{time_end} );
    $class->cache_clear($type);
    return 1;
}

# returns all questions that started during the given month
sub get_all_questions_for_month {
    my $class = shift;
    my ($year, $month) = @_;

    my $dbh = LJ::get_db_writer()
        or die "Error: no global dbh";

    my $time_start = DateTime->new( year => $year, month => $month );
    my $time_end = $time_start->clone;
    $time_end = $time_end->add( months => 1 );

    my $sth = $dbh->prepare("SELECT * FROM qotd WHERE time_start >= ? AND time_start <= ?");
    $sth->execute($time_start->epoch, $time_end->epoch)
        or die "Error getting this month's questions: " . $dbh->errstr;

    my @rows = ();
    while (my $row = $sth->fetchrow_hashref) {
        push @rows, $row;
    }

    # sort questions in descending order by start time (newest first)
    @rows =
        sort { $b->{time_start} <=> $a->{time_start} }
        grep { ref $_ } @rows;

    return @rows;
}

# given an id for a question, returns the info for it
sub get_single_question {
    my $class = shift;
    my $qid = shift;

    my $dbh = LJ::get_db_writer()
        or die "Error: no global dbh";

   my $sth = $dbh->prepare("SELECT * FROM qotd WHERE qid = ?");
    $sth->execute($qid)
        or die "Error getting single question: " . $dbh->errstr;

    return $sth->fetchrow_hashref;
}

# change the active status of the given question
sub change_active_status {
    my $class = shift;
    my $qid = shift;

    my %opts = @_;
    my $to = delete $opts{to};
    croak "invalid 'to' field" unless $to =~ /^(active|inactive)$/; 

    my $question = $class->get_single_question($qid)
        or die "Invalid question: $qid";

    my $dbh = LJ::get_db_writer()
        or die "Error: no global dbh";

    my $active_val = $to eq 'active' ? 'Y' : 'N';
    my $rv = $dbh->do("UPDATE qotd SET active = ? WHERE qid = ?", undef, $active_val, $qid)
        or die "Error updating active status of question: " . $dbh->errstr;

    my $type = $class->get_type( start => $question->{time_start}, end => $question->{time_end} );
    $class->cache_clear($type);

    return $rv;
}

1;
