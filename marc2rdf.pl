#!/usr/bin/perl -w 

# marc2rdf.pl - transform MARC records to RDF, based on a mapping file in YAML

use MARC::File::USMARC;
use MARC::Record;
use MARC::Field;
use RDF::Redland;
use YAML::Syck;
use feature "switch";
use strict;

# DEBGUG
use Data::Dumper;

# my $yaml = 'mapping-normarc2rdf.yml';
my $yaml = 'mini.yml';
my $conf = 'config.yml';
my $marc = 'koha.mrc';

# Load the MARC to RDF mapping
my $maptags = LoadFile($yaml);
my $config  = LoadFile($conf);

# Set up some Redland stuff
my $storage = new RDF::Redland::Storage("hashes", "test", "new='yes',hash-type='memory'");
die "Failed to create RDF::Redland::Storage\n" unless $storage;
my $model = new RDF::Redland::Model($storage, "");
die "Failed to create RDF::Redland::Model for storage\n" unless $model;
# Possible formats for the serializer: rdfxml, ntriples, turtle (more?)
my $serializer = new RDF::Redland::Serializer($ARGV[0]);
die "Failed to find serializer\n" if !$serializer;
# Create nodes for the rdf:type predicate
my $p_type = new RDF::Redland::URINode('http://www.w3.org/1999/02/22-rdf-syntax-ns#type');
my $o_type = new RDF::Redland::URINode($config->{'uri'}->{'resource_type'});

# Get the MARC records
my $batch = MARC::File::USMARC->in($marc);
my $count = 0;

# Iterate through our MARC records and convert them
while (my $record = $batch->next()) {

  # DEBUG print "\n";
  
  # Construct the subject URI
  my $s = new RDF::Redland::URINode(
    $config->{'uri'}->{'base'} . 
    $config->{'uri'}->{'resource_path'} . 
    $config->{'uri'}->{'resource_prefix'} . 
    $record->subfield('999',"c")
  );
  
  # Set the rdf:type
  my $statement = new RDF::Redland::Statement($s, $p_type, $o_type);
  $model->add_statement($statement);
  
  # Iterate through all the fields in the record
  my @fields = $record->fields();
  foreach my $field (@fields) {
  
    my $tag = $field->tag();
    if (!$maptags->{'tag'}->{$tag}){
      # Skip this field if there is no mapping for it
      next;
    }
    my $fieldmap = $maptags->{'tag'}->{$tag};

    if ($field->is_control_field()) {
      
      # DEBUG print $tag , " ", $fieldmap->{'predicate'}, "\n";
      _create_triple($s, $field->data(), $fieldmap);
      
    } else {

      my @subfields = $field->subfields();
      # Iterate through the subfields
      foreach my $subfield (@subfields) {
        my $subfieldindicator = $subfield->[0];
        my $subfieldvalue     = $subfield->[1];
        if (!$fieldmap->{'subfield'}->{$subfieldindicator}) {
          # Skip this subfield if there is no mapping for it
          next;
        }
        my $fieldmap = $fieldmap->{'subfield'}->{$subfieldindicator};
        # DEBUG print $tag, " ", $subfieldindicator, " ", $fieldmap->{'predicate'}, "\n";
        _create_triple($s, $subfieldvalue, $fieldmap);
      }
      
    }
  
  }
  $count++;
  
}

# DEBUG print "$count records done\n\n";

# Serialize the model into the format we set initially
my $base_uri = new RDF::Redland::URINode("http://example.org/");
print $serializer->serialize_model_to_string($base_uri, $model);

sub _create_triple {

  my $s    = shift;
  my $data = shift;
  my $map  = shift;
  
  # Construct the predicate URI
  my $p = new RDF::Redland::URINode($map->{'predicate'});
  # DEBUG print "\tp: ", $p->as_string(), "\n";

  # Construct the object
  # Massage data
  if ($map->{'object'}->{'massage'}) {
    given($map->{'object'}->{'massage'}) {
      when ("isbn") { $data = _isbn($data); }
      when ("issn") { $data = _issn($data); }
      when ("remove_trailing_punctuation") { $data =~ s/[\.:,;\/\s]\s*$//; }
    }
  }
  # Get data based on a substring
  if ($map->{'object'}->{'substr_offset'} && $map->{'object'}->{'substr_length'}) {
    my $substr_offset = $map->{'object'}->{'substr_offset'};
    my $substr_length = $map->{'object'}->{'substr_length'};
    # print "substr: $substr_offset $substr_length\n";
    $data = substr $data, $substr_offset, $substr_length;
  }
  # Prepend the prefix, if there is one
  if ($map->{'object'}->{'prefix'}) {
    $data = $map->{'object'}->{'prefix'} . $data;
  }
  # Turn the data into a URI if the datatype is uri
  if ($map->{'object'}->{'datatype'} eq "uri") {
    $data = new RDF::Redland::URINode($data);
  }
  my $o = new RDF::Redland::Node($data);
  # DEBUG print "\to: ", $o->as_string(), "\n";
  # Construct the triple
  my $statement = new RDF::Redland::Statement($s, $p, $o);
  $model->add_statement($statement);
  $statement = undef;

}

sub _isbn {

  use Business::ISBN;
  my $i = shift;
  # Create an ISBN object, this removes any cruft in the data
  my $isbn = Business::ISBN->new( $i );
  if ($isbn) {
    if (!$isbn->is_valid()) { return undef; }
    # Make sure it's isbn13
    my $isbn13 = $isbn->as_isbn13();
    return $isbn13->isbn();
  } else {
    return undef;
  }

}

sub _issn {

  use Business::ISSN;
  my $i = shift;
  # Create an ISSN object, this removes any cruft in the data
  my $issn = Business::ISSN->new( $i );
  if ($issn) {
    if (!$issn->is_valid()) { return undef; }
    return $issn->as_string;
  } else {
    return undef;
  }

}
