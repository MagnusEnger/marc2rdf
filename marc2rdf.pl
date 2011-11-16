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

my $maptags = LoadFile($yaml);

# Set up some Redland stuff
my $storage = new RDF::Redland::Storage("hashes", "test", "new='yes',hash-type='memory'");
die "Failed to create RDF::Redland::Storage\n" unless $storage;
my $model = new RDF::Redland::Model($storage, "");
die "Failed to create RDF::Redland::Model for storage\n" unless $model;
# Possible formats: rdfxml, ntriples, turtle (more?)
my $serializer = new RDF::Redland::Serializer($ARGV[0]);
die "Failed to find serializer\n" if !$serializer;

my $batch = MARC::File::USMARC->in($marc);
my $count = 0;

# Iterate through our MARC records and do stuff
while (my $record = $batch->next()) {

  print "\n";
  
  # Construct the subject URI
  # TODO Pull this from config
  my $s = new RDF::Redland::URINode('http://example.org' . '/collections/' . 'id_' . $record->subfield('999',"c"));

  my @fields = $record->fields();
  foreach my $field (@fields) {
  
    my $tag = $field->tag();
    
    if ($field->is_control_field()) {
      
      # Map control fields
      if ($maptags->{'tag'}->{$tag}) {
        print "$tag\n";
        print $maptags->{'tag'}->{$tag}->{'predicate'}, "\n";
        # Construct the predicate URI
        my $p = new RDF::Redland::URINode($maptags->{'tag'}->{$tag}->{'predicate'});
        print "\tp: ", $p->as_string(), "\n";
        # Construct the object
        my $data = $field->data();
        # Get data based on a regexp
        if ($maptags->{'tag'}->{$tag}->{'object'}->{'regex'}) {
          my $regex = $maptags->{'tag'}->{$tag}->{'object'}->{'regex'};
          # print "regex: $regex\n";
          # $data =~ m/($regex)/i;
          $data = $1;
        }
        # Get data based on a substring
        if ($maptags->{'tag'}->{$tag}->{'object'}->{'substr_offset'} && $maptags->{'tag'}->{$tag}->{'object'}->{'substr_length'}) {
          my $substr_offset = $maptags->{'tag'}->{$tag}->{'object'}->{'substr_offset'};
          my $substr_length = $maptags->{'tag'}->{$tag}->{'object'}->{'substr_length'};
          # print "substr: $substr_offset $substr_length\n";
          $data = substr $data, $substr_offset, $substr_length;
        }
        # Prepend the prefix, if there is one
        if ($data && $maptags->{'tag'}->{$tag}->{'object'}->{'prefix'}) {
          $data = $maptags->{'tag'}->{$tag}->{'object'}->{'prefix'} . $data;
        }
        # Turn the data into a URI if it starts with "http"
        if ($maptags->{'tag'}->{$tag}->{'object'}->{'datatype'} eq "uri") {
          $data = new RDF::Redland::URINode($data);
        }
        my $o = new RDF::Redland::Node($data);
        print "\to: ", $o->as_string(), "\n";
        # Construct the triple
        my $statement = new RDF::Redland::Statement($s, $p, $o);
        $model->add_statement($statement);
        $statement = undef;
      }
    
    } else {
      
      # Map other fields
      # Get the subfields first
      my @subfields = $field->subfields();
      foreach my $subfield (@subfields) {
        my $subfieldindicator = $subfield->[0];
        my $subfieldvalue     = $subfield->[1];
        if ($maptags->{'tag'}->{$tag}->{'subfield'}->{$subfieldindicator}) {
          print "$tag $subfieldindicator $subfieldvalue\n";
          print $maptags->{'tag'}->{$tag}->{'subfield'}->{$subfieldindicator}->{'predicate'}, "\n";
          # Construct the predicate URI
          my $p = new RDF::Redland::URINode($maptags->{'tag'}->{$tag}->{'subfield'}->{$subfieldindicator}->{'predicate'});
          print "\t", $p->as_string(), "\n";
          # Construct the object
          my $o = new RDF::Redland::Node($subfieldvalue);
          print "\t", $o->as_string(), "\n";
          # Construct the triple
          my $statement = new RDF::Redland::Statement($s, $p, $o);
          $model->add_statement($statement);
          $statement = undef;
        }
      }
    
    }
  
  }
  $count++;
  
}

print "$count records done\n\n";

my $base_uri = new RDF::Redland::URINode("http://example.org/");
print $serializer->serialize_model_to_string($base_uri, $model);
