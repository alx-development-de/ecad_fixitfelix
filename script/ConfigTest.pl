#!/usr/bin/perl
use strict;
use warnings FATAL => 'all';

use File::Spec;
use File::Basename;

use Log::Log4perl;
use Log::Log4perl::Level;
use Log::Log4perl::Logger;

use Getopt::Long;
use Config::General qw(ParseConfig SaveConfig SaveConfigString);

use Data::Dumper; # TODO: Remove debug stuff

# Reading the default configuration from the __DATA__ section
# of this script
my $default_config = do { local $/; <main::DATA> };
# Loading the file based configuration
my %options = ParseConfig(
    -ConfigFile => basename($0, qw(.pl .exe .bin)).'.cfg',
    -ConfigPath => ["./", "./etc", "/etc"],
    -AutoTrue   => 1,
    -MergeDuplicateBlocks => 1,
    -MergeDuplicateOptions => 1,
    -DefaultConfig => $default_config,
);

# Processing the command line options
GetOptions(
    'loglevel=s' => \($options{'log'}{'level'}),
    'wiring=s'      => \($options{'files'}{'wiring'} = './data/wiring-export.txt'), # Exported wiring list
    'devices=s'     => \($options{'files'}{'devices'} = './data/devices-export.txt'), # Exported device list
    'output=s'      => \($options{'files'}{'output'} = './data/result_output.txt'), # If defined, the output is redirected into this file
) or die "Invalid options passed to $0\n";

# Initializing the logging mechanism
Log::Log4perl->easy_init(Log::Log4perl::Level::to_priority(uc($options{'log'}{'level'})));
my $logger = Log::Log4perl->get_logger();

# Postprocessing command line parameters
$options{'files'}{'wiring'} = File::Spec->rel2abs($options{'files'}{'wiring'});
$options{'files'}{'devices'} = File::Spec->rel2abs($options{'files'}{'devices'});
$options{'files'}{'output'} = File::Spec->rel2abs($options{'files'}{'output'}) if defined $options{'files'}{'output'};

$logger->debug("Wiring input file [$options{'files'}{'wiring'}]");
$logger->debug("Device input file [$options{'files'}{'devices'}]");
$logger->debug("Output file [$options{'files'}{'output'}]");

print Dumper \%options;

__DATA__
<log>
    level=INFO
</log>

<files>
    wiring = "./data/wiring.txt"
    devices = "./data/devices.txt"
</files>
