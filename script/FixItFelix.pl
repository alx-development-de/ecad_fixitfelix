#!/usr/bin/perl
use strict;
use warnings FATAL => 'all';

use ALX::EN81346;

use XML::Parser;
use XML::Encoding;
use XML::Entities;
use XML::LibXML;

use Getopt::Long;
use File::Spec;

use Pod::Usage;
use Log::Log4perl;

use Data::Dumper;
our $VERSION = '1.0';

## Parse options
my $opt_help = 0;
my $opt_man = 0;
my $opt_source_file = undef;
my $opt_target_file = undef;

GetOptions (
				"help|?" => \$opt_help,
				"man" => \$opt_man,
				"output:s" => \$opt_target_file,
			) or die("Error in command line arguments\n");

pod2usage(-verbose => 1)  if ($opt_help);
pod2usage(-verbose => 2)  if ($opt_man);

# Check for too many filenames and reading command line
pod2usage(
    -verbose => 2,
    -message => "Error in command line arguments:\nToo many files given. Perhaps you forgot parentheses.\n"
) if (scalar(@ARGV) > 1);

# TODO: Make the logger configuration variable
Log::Log4perl->init("conf/log.ini");
my $logger = Log::Log4perl->get_logger();

# The source file to be parsed is given as command line argument beside
# the option semantic. This is done, to enable drag and drop behaviour
# for files without optional parameters.
$opt_source_file = File::Spec->rel2abs(shift());
$logger->info("Looking for source file [$opt_source_file]");
$logger->logdie("Source file not a valid file, or not readable") unless (-f $opt_source_file);

# ----------------------------------------------------------

# Opening the source file and parsing the xml content
#my $xml_parser = XML::Parser->new(Style => 'Debug');
#$xml_parser->parsefile($opt_source_file, ProtocolEncoding => 'ISO-8859-1');
#print Dumper $xml_parser;

# first instantiate the parser
my $parser = XML::LibXML->new();
$parser->set_options({
	#encoding => 'ISO-8859-1',
	#no_cdata => 1,
	recover         => 1,
	expand_entities => 0,

});
#my $dom = $parser->parse_html_file($opt_source_file);
my $dom = $parser->parse_file($opt_source_file);

# Reading the source file
#open(XML, '<', $opt_source_file) or die "Couldn't Open file [$opt_source_file]";
#my @lines = <XML>;
#close(XML);

#my $dom = XML::LibXML->load_xml(location => $opt_source_file);

#open my $fh, '<', $opt_source_file;
#binmode $fh; # drop all PerlIO layers possibly created by a use open pragma
#my $dom = XML::LibXML->load_xml(IO => $fh);

print Dumper $dom;

# ----------------------------------------------------------

exit(0);

=head1 Fix-It-Felix

	Control application for downloading, history management and cleaning
	the 7up output structure from a 7up server system

=head2 SYNOPSIS

	FixItFelix [options]

Options:

	-help		brief help message
	-man		full documentation
	-input=<file>	The input file which should be fixed

=head2 OPTIONS

=over 8

=item B<-help>

	Print a brief help message and exits.

=item B<-man>

	Prints the manual page and exits.

=item B<-input>

	With this option it is possible to define the input file, which
	is used as source to be parsed and fixed

=item B<-output>

	An optional file name and path for the resulting archive
	file. If not specified the archive will be stored with the
	name of the documentation folder right beside the it.

=back

=head1 DESCRIPTION

	This program is connecting to the 7up server specified in the 7up.ini
	configuration and reading the archive structure and history.

	You may store the structure as YAML encoded file for further processings
	to the local filesystem, or directly pull actual archives from the server.

	Beside it is possible to clean up the server and remove old version of archives.

=cut
