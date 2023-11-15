#!/usr/bin/perl
use strict;
use warnings FATAL => 'all';

use XML::Parser;
use XML::Parser::Expat;
use XML::Twig;

use File::Spec;
use File::Basename;

use JSON;

use ECAD::EN81346;

use Log::Log4perl qw(:easy);
use Log::Log4perl::Level;
use Log::Log4perl::Logger;

use Getopt::Long;
use Config::General;
use Pod::Usage;

use Data::Dumper; # TODO: Remove debug stuff

our $VERSION = "0.0.2";

# Reading the default configuration from the __DATA__ section
# of this script
my $default_config = do {
    local $/;
    <main::DATA>
};
# Loading the file based configuration
my $conf = Config::General->new(
    -ConfigFile            => basename($0, qw(.pl .exe .bin)) . '.cfg',
    -ConfigPath            => [ "./", "./etc", "/etc" ],
    -AutoTrue              => 1,
    -MergeDuplicateBlocks  => 1,
    -MergeDuplicateOptions => 1,
	-InterPolateEnv		   => 1,
    -DefaultConfig         => $default_config,
);
my %options = $conf->getall;

# Processing the command line options
GetOptions(
    'help|?'             => \($options{'run'}{'help'}),
    'man'                => \($options{'run'}{'man'}),
    'loglevel=s'         => \($options{'log'}{'rootLogger'}),
    'compact_terminals'  => \($options{'compact'}{'terminals'} = 0),  # Removing end brackets, inside continuous terminal strips
    'compact_identifier' => \($options{'compact'}{'identifier'} = 0), # Compacting the identifier according the EN81346 rules
) or die "Invalid options passed to $0\n";

# Show the help message if '--help' or '--?' if provided as command line parameter
pod2usage(-verbose => 1) if ($options{'run'}{'help'});
pod2usage(-verbose => 2) if ($options{'run'}{'man'});

=head1 NAME

FixItFelix - Correcting terminal strip definitions exported by an E-CAD system.

=head1 DESCRIPTION

This program fixes the EN81346 handling in ECAD-XML data sets which
are primarily used to handle terminal strips in worker assistance systems
from PHOENIX Contact.

While exporting terminal strips from an E-CAD system like ePlan for example
the terminal reference identifier is falsely changed to the identifier of
the mounting rail. If the location of the terminal differs to that of the
rail it is not used correctly.

The program fixes the reference identifier and is able to do some more stuff
with the data like compacting the identifier on labels according the EN81346.

=head1 SYNOPSIS

C<FixItFelix> F<[options]>

Options:
    --help                  Shows a brief help message
    --man                   Prints the full documentation
    --loglevel=<VALUE>      Defines the level for messages

=head1 OPTIONS

=over 4

=item B<--help>

Prints a brief help message containing the synopsis and a few more
information about usage and exists.

=item B<--man>

Prints the complete manual page and exits.

=item B<--loglevel>=I<[VALUE]>

To adjust the level for the logging messages the desired level may be defined
with this option. Valid values are:

=over 4

=item I<FATAL>

One or more key business functionalities are not working and the whole system does not fulfill
the business functionalities.

=item I<ERROR>

One or more functionalities are not working, preventing some functionalities from working correctly.

=item I<WARN>

Unexpected behavior happened inside the application, but it is continuing its work and the key
business features are operating as expected.

=item I<INFO>

An event happened, the event is purely informative and can be ignored during normal operations.

=item I<DEBUG>

A log level used for events considered to be useful during software debugging when more granular
information is needed.

=item I<TRACE>

A log level describing events showing step by step execution of your code that can be ignored
during the standard operation, but may be useful during extended debugging sessions.

=back

=item B<--compact_terminals>

Often end brackets are added by default while exporting the data in the ECAD XML
format after each terminal strip (identified by the BMK).

Activating this option these end brackets are removed if there is no space between the
bracket an the next terminal strip. This is very useful to build a compact mounting rail
containing several terminal strips.

=item B<--compact_identifier>

If active, the device identifier is compacted according the EN81346 rules compared to the mounting
rail on which the device has been placed. Every aspect is compared separately and if identical removed
from the label description.

=back

=cut

# Internally used state flags for process control
my %global_state_flags = (
    'space_active' => undef,
    'last_bracket' => undef,
);

# The configuration data hash is not primarily used to store a real configuration, it
# contains format specific adaptions necessary to interpret the ECAD-XML the correct
# way
my %configuration_data = ("parameters" => {
    "p8.locationId" => {
        "alx.location.prefix" => {
            "1100;" => "=",
            "1200;" => "+",
            "1400;" => "++",
            "1300;" => "=="
        }
    }
});

# Initializing the logging mechanism
my %log4perl_options = %{$options{'log'}};
my $log4perl_conf = join("\n", map { "log4perl.$_ = $log4perl_options{$_}" } keys %log4perl_options);

# SECURITY NOTE: Arbitrary perl code can be embedded in the config file. In the rare case where the people
# who have access to your config file are different from the people who write your code and shouldn't have
# execute rights, you might want to call $Log::Log4perl::Config->allow_code(0); before you call init().
# This will prevent Log::Log4perl from executing any Perl code in the config file (including code for
# custom conversion specifiers
Log::Log4perl::Config->allow_code(0);

# Changing the Signalhandler temporarily
{
    local $SIG{__WARN__} = sub {
        # Here we setup the standard logging mechanism at info level
		Log::Log4perl->easy_init(Log::Log4perl::Level::to_priority('INFO'));
		WARN "Error in logging configuration, falling back to standard mode";
    };
    # Try loading the configuration. If failed, the default logging with easy_init is loaded while
	# the warning message is catched
	Log::Log4perl::init( \$log4perl_conf );
}
my $logger = Log::Log4perl->get_logger();

# For debug reasons printing the configuration sources which have been parsed
$logger->info("Configuration file(s) parsed: [".join('], [', $conf->files())."]");

# The source file must be passed as command line parameter
my $opt_source_file = File::Spec->rel2abs(join(' ', @ARGV));
# Testing if a valid filename has been provided by the command line option
$logger->logdie("The provided parameter [$opt_source_file] seems not to be a valid file")
    unless (-f $opt_source_file);
# Generating the target file name
my $opt_target_file = undef;
{
    my ($name, $path, $suffix) = fileparse($opt_source_file, ('.xml'));
    $opt_target_file = File::Spec->catfile($path, "${name}_fixed${suffix}");
}

# Parsing the XML source
$logger->info("Parsing source file [$opt_source_file]");
my $twig = XML::Twig->new(pretty_print => 'nice');
$twig->parsefile($opt_source_file);

# Getting the root element, which is the <pbf>
my XML::Twig::Elt $root = $twig->root;

# Looking up the references and building a reference table
my %xml_references;
{
    $logger->debug("Loading reference structure");
    my @references = $root->descendants('ref');
    $logger->debug(scalar(@references) . " Reference entries found");

    # For a fast iteration over all objects, we keep them in an array
    my @all_objects = $root->descendants('o');

    # First we build a reverse ordered structure to be able to find the
    # matching item fast
    {
        my %forward_references;
        foreach my $reference (@references) {
            my $object_id = $reference->att('oid');
            my $reference_id = $reference->att('id');
            $forward_references{$reference_id} = $object_id;
            $logger->debug("[$reference_id]->[$object_id] Reference entry found");
        }

        # Let's load all the objects and build the resulting reference tree
        my %reverse_references = reverse %forward_references;
        foreach my $object (@all_objects) {
            my $object_id = $object->att('id');
            my $reference_id = $reverse_references{$object_id};
            if (defined($reference_id)) {
                my $target_type = $object->att('type');
                $logger->debug("Reference [$reference_id]->TARGET:[$object_id]-[$target_type] updated");
                $xml_references{$reference_id}{'target'} = \$object;
            }
        }

        # Now inspecting the objects to identify the source objects
        $logger->debug("Inspecting the reference source structure");
        foreach my $object (@all_objects) {
            if (my %references = &get_references($object)) {
                my $object_id = $object->att('id');
                foreach my $reference_id (keys(%references)) {
                    my $source_type = $object->att('type');
                    $logger->debug("Reference [$reference_id]->SOURCE:[$object_id]-[$source_type] updated");
                    $xml_references{$reference_id}{'source'} = \$object;
                }
            }
        }
    }
    $logger->debug(scalar(keys(%xml_references)) . " Reference entries added to matching table");

    # Now iterating over all references and cleaning the EN81346 information
    foreach my $reference_id (keys(%xml_references)) {
        my $target_object = ${$xml_references{$reference_id}{'target'}};
        my $target_type = $target_object->att('type');

        # TODO: Handling empty 'clipprj.description' fields
        if ($target_type eq 'clipprj.accessory') {
            my %target_parameter = &get_parameters($target_object);
            my $target_en81346_id = (split /;/, $target_parameter{'clipprj.description'})[3];

            $logger->debug("Inspecting reference [$reference_id] with ECAD reference [$target_en81346_id]");

            # We need to iterate over the siblings of the source until we find a valid description
            # and the type is terminal. Sometimes there is no clipprj.targets specification in the
            # whole terminal block. In this case nothing will be changed
            my $source_object = ${$xml_references{$reference_id}{'source'}};
            my $source_en81346_id;
            my $lookup_object = $source_object;
            my $lookup_type = "clipprj.terminal";
            while (($lookup_type eq "clipprj.terminal") & !$source_en81346_id) {
                my %source_parameter = &get_parameters($lookup_object);
                $source_en81346_id = $source_parameter{'clipprj.targets'};

                # Setting the lookup_object to the next sibling for the next loop
                $lookup_object = $lookup_object->next_sibling('o');
                $lookup_type = $lookup_object->att('type');
            }

            # Compacting the source id
            # In several cases no source could be found. In this case this part is ignored
            if (defined $source_en81346_id) {
                # Splitting the input string at either colon or semicolon and then filtering
                # only valid reference ids. In the regular expression for the filter, the minus
                # has been explicitly put to the end of the match to avoid a positive match, if
                # the terminal name contains any plus signs.
                # TODO: The regular expression should be handled by the EN81346 lib instead of this code
                my @ids = grep(/[+=]+[0-9a-zA-Z._]+-+[0-9a-zA-Z._]+/, split(/[:;]/, $source_en81346_id));
                my %unique_ids;
                foreach (@ids) {$unique_ids{$_}++;}
                my $unique_id_count = scalar(keys(%unique_ids));
                if ($unique_id_count == 1) {
                    $source_en81346_id = (keys(%unique_ids))[0];
                    if ($source_en81346_id ne $target_en81346_id) {
                        $logger->info(sprintf("Reference [%3d] source [%s] => target [%s]",
                            $reference_id,
                            $source_en81346_id,
                            $target_en81346_id
                        ));
                        my @target_string_elements = split /;/, $target_parameter{'clipprj.description'};
                        $target_string_elements[3] = $source_en81346_id;
                        # TODO: Writing the result into the target parameters
                        &add_parameter($target_object, 'clipprj.description', join(';', @target_string_elements));
                    }
                    else {
                        $logger->info(sprintf("Reference [%3d] source and target are the same",
                            $reference_id
                        ));
                    }
                }
                else {
                    $logger->warn(sprintf("Reference [%3d] ID is not unique! [%s] Different IDs detected",
                        $reference_id,
                        $unique_id_count
                    ));
                }
            }
        }
    }
}

# There should only be one project inside an export file per definition,
# but in this implementation we're open for multi-project structures.
$logger->info("Inspection project structure");
my @projects = $root->children('o');
foreach my XML::Twig::Elt $project (@projects) {
    if ($project->att('type') eq 'clipprj.project') {
        # Checking type attribute to avoid failures
        $logger->info("Project [" . $project->att('id') . "] " . $project->att('name') . " found");

        # Iterating the projects substructure objects
        &parse_substructure($project);
    }
}

# Exporting the result to the target file
$logger->debug("Writing fixed ECAD XML to [$opt_target_file]");
$twig->print_to_file($opt_target_file);
$logger->info("ECAD XML processing finished");
exit(0);

#----------------------------------------------------------------------------

sub get_parameters($;) {
    # The parent object
    my XML::Twig::Elt $parent = shift();
    my %parameters;

    # Parsing the parameters
    my $parameter_list = $parent->first_child('pl');
    if (defined $parameter_list) {
        my @parameter_array = $parameter_list->children('p');
        $logger->debug("[" . scalar(@parameter_array) . "] Parameter entries found");
        foreach my $parameter (@parameter_array) {
            my $name = $parameter->att('name');
            my $value = $parameter->text_only;
            $logger->debug("Parameter [$name]->[$value] identified");
            $parameters{$name} = $value;
        }

        # Looking if there are some properties which should be automatically build
        # by some rules
        foreach my $source_parameter (keys(%{$configuration_data{'parameters'}})) {
            # Skip this, if there is no fitting parameter available to build the rule
            next unless defined($parameters{$source_parameter});
            $logger->debug("Automatic parameter generation for [$source_parameter] identified");
            foreach my $target_parameter (keys(%{$configuration_data{'parameters'}{$source_parameter}})) {
                if (my $value = $configuration_data{'parameters'}{$source_parameter}{$target_parameter}{$parameters{$source_parameter}}) {

                    # Generating a new XML parameter element and adding this to the ECAD XML file
                    &add_parameter($parent, $target_parameter, $value);
                    $parameters{$target_parameter} = $value;
                }
            }
        }
    }
    return %parameters;
}

sub get_references($;) {
    # The parent object
    my XML::Twig::Elt $parent = shift();
    my %references;

    # Parsing the references
    my $reference_list = $parent->first_child('rl');
    if (defined $reference_list) {
        $logger->debug("Reference list found");
        my @reference_array = $reference_list->children('r');
        $logger->debug("[" . scalar(@reference_array) . "] Reference entries found");
        foreach my $reference (@reference_array) {
            my $name = $reference->att('name');
            my $reference_id = $reference->att('rid');
            $logger->debug("Reference [$reference_id]->[$name] identified");
            $references{$reference_id} = $name;
        }
    }
    return %references;
}

sub add_parameter($$$;) {
    my XML::Twig::Elt $parent = shift();
    my ($key, $value) = @_;
    my $parent_id = $parent->att('id');

    if (my $parameter_list = $parent->first_child('pl')) {
        my @parameter_array = $parameter_list->children('p');

        # Removing the parameter if existing to avoid duplicates
        foreach my $parameter (@parameter_array) {
            # Looking if the parameter is already existing
            if ($parameter->att('name') eq $key) {
                $parameter->cut();
                $logger->debug("Parameter [$key] removed");
            }
        }

        # Generating a new XML parameter element and adding this to the ECAD XML file
        my $elt = XML::Twig::Elt->new('p' => { 'name' => $key }, $value);
        $elt->paste(last_child => $parameter_list);
        $logger->info("Parameter [$key]->[$value] to object [$parent_id] added");
    }
}

sub parse_substructure($;$) {
    # The parent object
    my XML::Twig::Elt $parent = shift();
    # The parents location id for the structure element
    my $parent_location_id = shift();

    # Iterating the projects substructure objects
    if (my @object_list = $parent->children('ol')) {
        my @objects = $object_list[0]->children('o');
        foreach my $object (@objects) {
            my $type = $object->att('type');
            $logger->debug("Object of type [$type] identified");

            # Parsing the available parameters
            my %parameters = get_parameters($object);
            # Parsing possible object references
            my %references = get_references($object);

            # This ist the active location id
            my $active_location_id = $parent_location_id;

            # Analyzing the location id and fixing it in the XML export
            if ($type eq 'clipprj.location') {
                my $name = $object->att('name');
                $logger->debug("Location [$name] identified");

                # Building the EN81346 conform identifier and adding this to the
                # parameters list
                if (defined $parameters{'alx.location.prefix'}) {
                    # Building the location id and adding the result to the
                    # parameter list
                    my $location_id = $parameters{'alx.location.prefix'} . $name;

                    if (ECAD::EN81346::is_valid($location_id)) {
                        $logger->debug("Location id [$location_id] identified");

                        # The location must be concatenated with the already available
                        # TODO: Must be fixed, cause the last element duplicates while concatenation
                        $active_location_id .= $location_id;

                        &add_parameter($object, 'alx.location.id', $active_location_id);
                        $logger->debug("Location id has been set to [$active_location_id]");
                    }
                }
            }

            # Shorten the location ID based on the clipprj.description
            if ($options{'compact'}{'identifier'} == 1 && defined($parameters{'clipprj.description'})) {
                # Backing up the original parameters
                &add_parameter($object, 'alx.description.original', $parameters{'clipprj.description'});
                &add_parameter($object, 'alx.EN81346.base', $active_location_id);
                # The minus 1 parameter is used to preserve trailing empty elements
                if (my @targets = split(/;/, $parameters{'clipprj.description'}, -1)) {
                    $logger->debug("Compacting reference IDs based on [$active_location_id]");
                    for my $i (0 .. $#targets) {
                        # Skipping, if target is not defined or not a valid identifier
                        next unless (defined($targets[$i]) && ECAD::EN81346::is_valid($targets[$i]));
                        $logger->debug("Compacting reference id [" . $targets[$i] . "] to [$active_location_id]");

                        # Compacting the string on given base
                        my $compacted_string = ECAD::EN81346::base($active_location_id, $targets[$i]);
                        $logger->debug("Compacting reference results to [$compacted_string]");
                        $targets[$i] = $compacted_string;
                    }
                    # Writing the change parameter to the parameters list
                    &add_parameter($object, 'clipprj.description', join(';', @targets));
                }
            }

            # Removing internal brackets if compacting is specified
            if ($options{'compact'}{'terminals'} == 1) {

                if ($type =~ m/^clipprj\.mountingSpacing(Left|Right)?$/gi) {
                    $logger->debug("Mounting space [$type] detected");
                    $global_state_flags{'space_active'} = 1;

                    # Insert the last detected end bracket if a spacing is detected
                    # and a formerly removed bracket is stored.
                    if (defined $global_state_flags{'last_bracket'}) {
                        $global_state_flags{'last_bracket'}->paste(before => $object);
                        $global_state_flags{'last_bracket'} = undef;
                        $logger->debug("Last detected end bracket inserted");
                    }
                }

                if ($type eq 'clipprj.endBracket') {
                    # If a bracket is detected and before a spacing has been detected, the bracket
                    # is cut og the list. It is stored temporarily, cause if it is the last one of
                    # the terminal strip, it must be re-inserted.
                    if ($global_state_flags{'space_active'} == 0) {
                        $logger->debug("End bracket should be removed");
                        $global_state_flags{'last_bracket'} = $object->cut();
                    }
                    else {
                        $logger->debug("End bracket should be left in place");
                    }
                    $global_state_flags{'space_active'} = 0; # If an end bracket has been found the space region is terminated
                }
            }

            # Recursive parsing the substructure
            &parse_substructure($object, $active_location_id);
        }
    }
}

=pod

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2022 Alexander Thiel

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

=cut

__DATA__

<log>
    rootLogger	= INFO, Screen
	
 	appender.Screen         = Log::Log4perl::Appender::Screen
	appender.Screen.stderr  = 0
	appender.Screen.layout	= Log::Log4perl::Layout::PatternLayout
	appender.Screen.layout.ConversionPattern = %d %5p %c - %m%n
</log>

<compact>
    terminals = false
    identifier = true
</compact>
