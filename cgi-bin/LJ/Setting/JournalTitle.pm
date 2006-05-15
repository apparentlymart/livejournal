package LJ::Setting::JournalTitle;
use base 'LJ::Setting::TextSetting';
use strict;
use warnings;

sub tags { qw(journal title) }

sub prop_name { "journaltitle" }
sub text_size { 40 }
sub question { "Journal Title &nbsp;" }

1;

