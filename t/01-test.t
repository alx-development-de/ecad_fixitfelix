#!/usr/bin/perl
use strict;
use warnings;
use Test::More;

use ALX::EN81346;

my $interpreter = ALX::EN81346->new("=100+200-300");

ok(defined $interpreter);

done_testing();

