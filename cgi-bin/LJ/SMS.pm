package LJ::SMS;
use strict;

sub new {
    my ($class, %opts) = @_;
    my $from = delete $opts{'from'};
    my $text = delete $opts{'text'};
    die if %opts;
    my $self = bless {}, $class;

    $self->{from} = $from;
    $self->{text} = $text;

    return $self;
}

sub owner {
    my $self = shift;
    my $dbr = LJ::get_db_reader();
    my $from = $self->{from} or
        return undef;
    my $uid = $dbr->selectrow_array("SELECT userid FROM smsusermap WHERE number=?",
                                    undef, $from);
    return $uid ? LJ::load_userid($uid) : undef;
}

sub as_string {
    my $self = shift;
    return "from=$self->{from}, text=$self->{text}\n";
}

1;
