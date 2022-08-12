#!/usr/bin/perl
use strict;
use warnings FATAL => 'all';

use XML::Parser;
use XML::Encoding;
use XML::Entities;
use XML::LibXML;
use XML::Twig;

use JSON;

use ALX::EN81346;

use Log::Log4perl;
use Log::Log4perl::Level;
use Log::Log4perl::Logger;

use Data::Dumper;

Log::Log4perl->init("conf/log.ini");
my $logger = Log::Log4perl->get_logger();

# TODO: Should be passed as command line parameter
my $opt_source_file = 'untracked/ecad-export.xml';
my $opt_target_file = 'untracked/ecad-export.fixed.xml';
my $opt_configuration_file = 'conf/alx-ecad.conf';
my $opt_compact_terminals = 1; # Removing end brackets, inside continuous terminal strips

# Internally used state flags for process control
my %global_state_flags = (
                'space_active' => undef,
                'last_bracket' => undef,
            );

# Reading the configuration data from a JSON structured file.
# TODO: Proof, if using AppConfig module is more useful for this
open(FH, '<'.$opt_configuration_file) or die "Configuration [$opt_configuration_file] not readable or not existing!\n";
my $data = join('', <FH>); close(FH); # Reading the complete file into a string
my %configuration_data = %{decode_json( $data )};

# Parsing the XML source
$logger->info("Parsing source file [$opt_source_file]");
my $twig=XML::Twig->new( pretty_print => 'nice' );
$twig->parsefile($opt_source_file);

my XML::Twig::Elt $root = $twig->root; # Getting the root element, which is the <pbf>
# There should only be one project inside an export file per definition,
# but in this implementation we're open for multi-project structures.
$logger->info("Inspection project structure");
my @projects= $root->children('o');
foreach my XML::Twig::Elt $project (@projects) {
    if($project->att('type') eq 'clipprj.project') { # Checking type attribute to avoid failures
        $logger->info("Project [".$project->att('id')."] ".$project->att('name')." found");

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
    my $parameter_list = $parent->first_child_matches('pl');
    if(defined $parameter_list) {
        my @parameters = $parameter_list->children('p');
        $logger->debug("[".scalar(@parameters)."] Parameter entries found");
        foreach my $parameter (@parameters) {
            my $name = $parameter->att('name');
            my $value = $parameter->text_only;
            $logger->debug("Parameter [$name]->[$value] identified");
            $parameters{$name} = $value;
        }

        # Looking if there are some properties which should be automatically build
        # by some rules
        foreach my $source_parameter (keys( %{$configuration_data{'parameters'}} )) {
            $logger->debug("Automatic parameter generation for [$source_parameter] identified");
            foreach my $target_parameter (keys( %{$configuration_data{'parameters'}{$source_parameter}} )) {
                if( my $value = $configuration_data{'parameters'}{$source_parameter}{$target_parameter}{$parameters{$source_parameter}} ) {

                    # Generating a new XML parameter element and adding this to the ECAD XML file
                    &add_parameter($parent, $target_parameter, $value);
                    $parameters{$target_parameter} = $value;
                }
            }
        }
    }
    return %parameters;
}

sub add_parameter($$$;) {
    my XML::Twig::Elt $parent = shift();
    my($key, $value) = @_;

    # TODO: Should prove, if the given parent is a valid object (<o>) element
    my $parameter_list = $parent->first_child_matches('pl');

    # Generating a new XML parameter element and adding this to the ECAD XML file
    my $elt= XML::Twig::Elt->new( 'p' => { 'name' => $key }, $value);
    $elt->paste( last_child => $parameter_list);
    $logger->debug("Parameter [$key]->[$value] added");
}

sub parse_substructure($;) {
    # The parent object
    my XML::Twig::Elt $parent = shift();

    # Iterating the projects substructure objects
    if (my @object_list = $parent->children('ol')) {
        my @objects =$object_list[0]->children('o');
        foreach my $object (@objects) {
            my $type = $object->att('type');
            $logger->debug("Object of type [$type] identified");

            # Analyzing the location id and fixing it in the XML export
            if($type eq 'clipprj.location') {
                my $name = $object->att('name');
                $logger->debug("Location [$name] identified");

                # Parsing the available parameters
                my %parameters = get_parameters($object);

                # Building the EN81346 conform identifier and adding this to the
                # parameters list
                if(defined $parameters{'alx.location.prefix'}) {
                    # Building the location id and adding the result to the
                    # parameter list
                    my $location_id = $parameters{'alx.location.prefix'}.$name;
                    if( ALX::EN81346::is_valid($location_id) ) {
                        $logger->debug("Location id [$location_id] identified");
                        &add_parameter($object, 'alx.location.id', $location_id);
                    }
                }
            }

            # Removing internal brackets if compacting is specified
            if( $opt_compact_terminals == 1 ) {

                if($type =~ m/^clipprj\.mountingSpacing(Left|Right)?$/gi) {
                    $logger->debug("Mounting space [$type] detected");
                    $global_state_flags{'space_active'} = 1;

                    # Insert the last detected end bracket if a spacing is detected
                    # and a formerly removed bracket is stored.
                    if( defined $global_state_flags{'last_bracket'} ) {
                        $global_state_flags{'last_bracket'}->paste( before => $object );
                        $global_state_flags{'last_bracket'} = undef;
                        $logger->debug("Last detected end bracket inserted");
                    }
                }

                if($type eq 'clipprj.endBracket') {
                    # If a bracket is detected and before a spacing has been detected, the bracket
                    # is cut og the list. It is stored temporarily, cause if it is the last one of
                    # the terminal strip, it must be re-inserted.
                    if( $global_state_flags{'space_active'} == 0 ) {
                        $logger->debug("End bracket should be removed");
                        $global_state_flags{'last_bracket'} = $object->cut();
                    } else {
                        $logger->debug("End bracket should be left in place");
                    }
                    $global_state_flags{'space_active'} = 0; # If an end bracket has been found the space region is terminated
                }
            }

            # Recursive parsing the substructure
            &parse_substructure($object);
        }
    }
}

# my $input_string = "==200=A1.23=100==ABC+200-300";
# $logger->info("Segmenting string value: [$input_string]");
# my $identifier = ALX::EN81346::segments($input_string);
# my $id_string = ALX::EN81346::to_string($identifier);
# $logger->info("Resulting string value: [$id_string]");
