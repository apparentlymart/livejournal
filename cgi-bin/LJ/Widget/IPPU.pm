package LJ::Widget::IPPU;
use strict;

# base class for in page popup widgets

use base 'LJ::Widget';

# load all subclasses
LJ::ModuleLoader->autouse_subclasses("LJ::Widget::IPPU");

sub ajax { 1 }

1;
