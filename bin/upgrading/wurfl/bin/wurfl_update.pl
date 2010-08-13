#!/usr/bin/perl

=for copyright
(c) 2006 ZAO Sup Fabrik. All rights reserved.
This Software is protected by copyright law and international copyright treaty. 
No actions permitted without permission of the ZAO Sup Fabrik. 

Should you have any questions arise contact us at info@sup.com 

(c) 2006 ЗАО "Суп Фабрик". Все права защищены.
Данное программное обеспечение подлежит защите в соответствии с нормами законодательства об авторских правах, а также международных конвенций по авторскому праву. 
Запрещено осуществлять какие либо действия с данным програмным обеспечением без согласия ЗАО "Суп Фабрик".

При возникновении каких-либо вопросов вы можете связаться с нами info@sup.com
=cut

# $Id: wurfl_update.pl 3196 2009-05-15 08:00:45Z slobin $

use strict;

use File::Spec::Functions 'catfile';
use FindBin;
use XML::Simple 'XMLin';

use Storable 'nstore';

BEGIN {
	$XML::Simple::PREFERRED_PARSER = 'XML::Parser';
}

# unbuffered output
local $/;

my $data_dir = catfile($FindBin::Bin, '..', 'data');

my $xml = XMLin(catfile($data_dir, 'wurfl.xml'), KeyAttr => [ qw(id name) ] , ForceArray => 1);

my $devices = $xml->{devices}[0]->{device};

my %user_agents;

foreach my $device_id (keys %$devices) {

    my $device_ua = $devices->{$device_id}->{user_agent};

    my @parts = split /\//, $device_ua;

    my $ua = '';

    foreach (@parts) {
        $ua .= $ua ? "/$_" : $_;
        $user_agents{$ua} = 1;
    }

    while ($device_id) {
        my $device_capabilities = eval { $devices->{$device_id}{group}{object_download} };
        $device_id = $devices->{$device_id}->{fall_back};
    }
}

delete $user_agents{'Mozilla'};

nstore(\%user_agents, catfile($data_dir, 'devices_useragents.stor'));

