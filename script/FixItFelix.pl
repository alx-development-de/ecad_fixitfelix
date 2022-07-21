#!/usr/bin/perl
use strict;
use warnings FATAL => 'all';

use ALX::EN81346;

use Log::Log4perl;

Log::Log4perl->init("conf/log.ini");
my $logger = Log::Log4perl->get_logger();

my $input_string = "==200=A1.23=100==ABC+200-300";
$logger->info("Segmenting string value: [$input_string]");
my $identifier = ALX::EN81346::segments($input_string);
my $id_string = ALX::EN81346::to_string($identifier);
$logger->info("Resulting string value: [$id_string]");

exit(0);
