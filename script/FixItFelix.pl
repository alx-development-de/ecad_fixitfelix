#!/usr/bin/perl
use strict;
use warnings FATAL => 'all';

use ALX::EN81346;

use Log::Log4perl;

Log::Log4perl->init("conf/log_test.ini");

#my $interpreter = ALX::EN81346->new();
print(ALX::EN81346::segments("==200=A1.23=100+200-300"));

exit(0);
