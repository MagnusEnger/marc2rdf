#!/usr/bin/perl -w 

# marc2rdf.pl - transform MARC records to RDF, based on a mapping file in YAML

use MARC::File::USMARC;
use MARC::Record;
use MARC::Field;
use RDF::Redland;
use YAML::Syck;
use strict;

# DEBGUG
use Data::Dumper;

# my $yaml = 'mapping-normarc2rdf.yml';
my $yaml = 'mini.yml';
my $marc = 'koha.mrc';

# Load the MARC to RDF mapping
my $maptags = LoadFile($yaml);

# Set up some Redland stuff
my $storage = new RDF::Redland::Storage("hashes", "test", "new='yes',hash-type='memory'");
die "Failed to create RDF::Redland::Storage\n" unless $storage;
my $model = new RDF::Redland::Model($storage, "");
die "Failed to create RDF::Redland::Model for storage\n" unless $model;
# Possible formats for the serializer: rdfxml, ntriples, turtle (more?)
my $serializer = new RDF::Redland::Serializer($ARGV[0]);
die "Failed to find serializer\n" if !$serializer;

# Get the MARC records
my $batch = MARC::File::USMARC->in($marc);
my $count = 0;

# Iterate through our MARC records and convert them
while (my $record = $batch->next()) {

  print "\n";
  
  # Construct the subject URI
  # TODO Pull this from config
  my $s = new RDF::Redland::URINode('http://example.org' . '/collections/' . 'id_' . $record->subfield('999',"c"));
  
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
      
      print $tag , " ", $fieldmap->{'predicate'}, "\n";
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
        print $tag, " ", $subfieldindicator, " ", $fieldmap->{'predicate'}, "\n";
        _create_triple($s, $subfieldvalue, $fieldmap);
      }
      
    }
  
  }
  $count++;
  
}

print "$count records done\n\n";

# Serialize the model into the format we set initially
my $base_uri = new RDF::Redland::URINode("http://example.org/");
print $serializer->serialize_model_to_string($base_uri, $model);

sub _create_triple {

  my $s    = shift;
  my $data = shift;
  my $map  = shift;
  
  # Construct the predicate URI
  my $p = new RDF::Redland::URINode($map->{'predicate'});
  print "\tp: ", $p->as_string(), "\n";

  # Construct the object
  # Get data based on a regexp
  if ($map->{'object'}->{'regex'}) {
    my $regex = $map->{'object'}->{'regex'};
    # print "regex: $regex\n";
    # FIXME $data =~ m/($regex)/i;
    $data = $data;
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
  print "\to: ", $o->as_string(), "\n";
  # Construct the triple
  my $statement = new RDF::Redland::Statement($s, $p, $o);
  $model->add_statement($statement);
  $statement = undef;

}
