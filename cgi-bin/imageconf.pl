#!/usr/bin/perl
#

use strict;
package LJ::Img;
use vars qw(%img);

$img{'btn_up'} = { 'src' => '/btn_up.gif',
		   'width' => 22,
		   'height' => 20,
		   'alt' => 'Up',
	       };

$img{'btn_down'} = { 'src' => '/btn_dn.gif',
		     'width' => 22,
		     'height' => 20,
		     'alt' => 'Up',
		 };

$img{'btn_del'} = { 'src' => '/btn_del.gif',
		    'width' => 22,
		    'height' => 20,
		    'alt' => 'Delete',
		};


1;

