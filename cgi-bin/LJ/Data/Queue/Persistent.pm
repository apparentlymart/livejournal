package LJ::Data::Queue::Persistent;

use strict;
use warnings;

use base qw/Data::Queue::Persistent/;

## solution of the problem: table_exists fails when it should succeed
## http://rt.cpan.org/Public/Bug/Display.html?id=36337

sub table_exists {
    my $self = CORE::shift();
    # get table info, see if our table exists
    my @tables = $self->dbh->tables(undef, undef, $self->{table_name}, "TABLE");
    my $table = $self->{table_name};

    $table = $self->dbh->quote_identifier($self->{table_name})
        if $self->dbh->get_info(29); # quote if the db driver uses table name quoting

    return grep { $_ eq $table || $_ =~ /\.$table$/ } @tables;
}

1;
