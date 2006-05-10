package Bio::Otter::Transform::SequenceSets;

use strict;
use warnings;
use Bio::Otter::Transform;
use Bio::Otter::Lace::SequenceSet;

our @ISA = qw(Bio::Otter::Transform);

# ones were interested in 
my $SUB_ELE = { map { $_ => 1 } qw(description vega_set_id priority)};
# super elements to the actual sequence set
my $SUP_ELE = { map { $_ => 1 } qw(otter sequencesets) };
my $value;

# this should be in xsl and use xslt to transform and create the objects
sub start_handler{
    my $self = shift;
    my $xml  = shift;
    my $ele  = lc shift;
    my $attr = {@_};
    $value='';
    $self->_check_version(@_) if $ele eq 'otter';
    if($ele eq 'sequenceset'){
        my $ss = Bio::Otter::Lace::SequenceSet->new();
        $ss->name($attr->{'name'});
        $ss->is_hidden($attr->{'hide'});
        $ss->dataset_name($self->get_property('dataset_name'));
        $self->add_object($ss);
    }elsif($SUB_ELE->{$ele}){
       # print "* Interesting $ele\n";
    }else{
       # print "Uninteresting $ele\n";
    }
}

sub end_handler{ 
    my $self = shift;
    my $xml  = shift;
    $value =~ s/^\s*//;
    $value =~ s/\s*$//;
    my $context = shift;
    if($SUB_ELE->{$context}){
        my $context_method = $context;
        my $ss = $self->objects;
        my $current = $ss->[$#$ss];
        if($current->can($context_method)){
            $current->$context_method($value);
        }else{
            print STDERR "$current can't $context_method\n";
        }
    }
}

sub char_handler{
  my $self = shift;
  my $xml  = shift;
  my $data = shift;
  if ($data ne ""){
    $value .= $data;
  }
}

1;
__END__

=head1 NAME - SequenceSets.pm


=head1 DESCRIPTION

XML Parsing for sequence sets. Parses xml file and converts to SequenceSet Objects

=head1 AUTHOR

Refactored by Sindhu K. Pillai B<email> sp1@sanger.ac.uk
