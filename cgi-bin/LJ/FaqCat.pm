package LJ::FaqCat;
use strict;

my $faq_dmid;

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

sub load {
    my ( $class, $id ) = @_;
    my ($faqcat) = $class->load_by_ids($id);
    return $faqcat;
}

sub load_all {
    my ($class) = @_;

    my $dbh = LJ::get_db_reader();
    my $rows = $dbh->selectall_arrayref(
        'SELECT * FROM faqcat ORDER BY catorder', { 'Slice' => {} } );

    return map { $class->new($_) } @$rows;
}

sub catname_display {
    my ( $self, $lang ) = @_;

    if ( $lang eq $LJ::DEFAULT_LANGUAGE ) {
        return $self->faqcatname;
    }

    unless ( defined $faq_dmid ) {
        my $dom = LJ::Lang::get_dom('faq');
        $faq_dmid = $dom->{'dmid'};
    }

    my $varname = 'cat.' . $self->faqcat;
    return LJ::Lang::get_text( $lang, $varname, $faq_dmid );
}

sub page_url {
    my ($self) = @_;

    my $faqcat = $self->faqcat;
    return "$LJ::SITEROOT/support/faq/cat/$faqcat.html";
}

1;
