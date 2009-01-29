package LJ::FaqCat;
use strict;

sub new {
    my $class = ref $_[0] ? ref shift : shift;
    my $opts  = ref $_[0] ? shift : {@_};
    my $self = {};
    $self->{faqcat}     = $opts->{faqcat};
    $self->{faqcatname} = $opts->{faqcatname};
    $self->{catorder}   = $opts->{catorder};

    bless $self => $class;
    return $self;
}
sub faqcat     { shift->{faqcat}     }
sub faqcatname { shift->{faqcatname} }
sub catorder   { shift->{cartorder}  }


sub load_by_ids {
    my $class = shift;
    my @ids   = @_;
    return () unless scalar @ids;

    # avoid non-uniq ids
    my %uniq = map { $_ => 1 } @ids;
    @ids = keys %uniq;

    my $dbh = LJ::get_db_reader();
    my $sth = $dbh->prepare("
                SELECT *
                FROM faqcat
                WHERE faqcat in (" . join ("," => map {"?"} @ids) . ")
                ");
    $sth->execute(@ids);
    my @res = ();
    while (my $h = $sth->fetchrow_hashref()){
        push @res => new LJ::FaqCat($h);
    }
    return @res;
}



1;

