package Bio::Vega::Region;

use strict;
use warnings;

use Carp;

use Bio::Otter::Lace::CloneSequence;
use Bio::Otter::Utils::Attribute qw( get_single_attrib_value );

=head1 NAME

Bio::Vega::Region

=head1 DESCRIPTION

Represents a region as processed by Bio::Otter::ServerAction::Region
in write_region() after XML decoding, and get_region() before XML
encoding.

=cut

sub new {
    my ($class, %options) = @_;

    my $self = bless { %options }, $class;
    return $self;
}

sub new_from_otter_db {
    my ($class, %options) = @_;

    my $self = $class->new(%options);

    confess "Cannot fetch data without slice"     unless $self->slice;
    confess "Cannot fetch data without otter_dba" unless $self->otter_dba;

    $self->fetch_CloneSequences;
    $self->fetch_species;
    $self->fetch_SimpleFeatures;
    $self->fetch_Genes;

    return $self;
}

sub otter_dba {
    my ($self, @args) = @_;
    ($self->{'otter_dba'}) = @args if @args;
    my $otter_dba = $self->{'otter_dba'};
    return $otter_dba;
}

sub slice {
    my ($self, @args) = @_;
    ($self->{'slice'}) = @args if @args;
    my $slice = $self->{'slice'};
    return $slice;
}

sub species {
    my ($self, @args) = @_;
    ($self->{'species'}) = @args if @args;
    my $species = $self->{'species'};
    return $species;
}

sub genes {
    my ($self, @args) = @_;
    $self->_gene_list( [ @args ] ) if @args;
    my $genes = $self->_gene_list;
    return @$genes;
}

sub seq_features {
    my ($self, @args) = @_;
    $self->_seq_feature_list( [ @args ] ) if @args;
    my $seq_features = $self->_seq_feature_list;
    return @$seq_features;
}

sub clone_sequences {
    my ($self, @args) = @_;
    $self->_clone_seq_list( [ @args ] ) if @args;
    my $clone_sequences = $self->_clone_seq_list;
    return @$clone_sequences;
}

# FIXME: this should be merged with clone_sequences.
#        provided only to support refactoring of apache/write_region.
#
sub tiles {
    my ($self, @args) = @_;
    $self->_tile_list( [ @args ] ) if @args;
    my $tiles = $self->_tile_list;
    return @$tiles;
}

sub _tile_list {
    my ($self, @args) = @_;
    ($self->{'_tile_list'}) = @args if @args;
    my $_tile_list = $self->{'_tile_list'} ||= [];
    return $_tile_list;
}

sub fetch_CloneSequences {
    my ($self) = @_;

    my $slice_projection = $self->slice->project('contig');
    my $cs_list = $self->_clone_seq_list([]); # empty list
    foreach my $contig_seg (@$slice_projection) {
        my $cs = $self->fetch_CloneSeq($contig_seg);
        push @$cs_list, $cs;
    }

    return @$cs_list;
}

sub fetch_CloneSeq {
    my ($self, $contig_seg) = @_;

    my $contig_slice = $contig_seg->to_Slice();

    my $cs = Bio::Otter::Lace::CloneSequence->new;
    $cs->chromosome(get_single_attrib_value($self->slice, 'chr'));
    $cs->contig_name($contig_slice->seq_region_name);

    my $clone_slice = $contig_slice->project('clone')->[0]->to_Slice;
    $cs->accession(     get_single_attrib_value($clone_slice, 'embl_acc')           );
    $cs->sv(            get_single_attrib_value($clone_slice, 'embl_version')       );

    if (my ($cna) = @{$clone_slice->get_all_Attributes('intl_clone_name')}) {
        $cs->clone_name($cna->value);
    } else {
        $cs->clone_name($cs->accession_dot_sv);
    }

    my $assembly_offset = $self->slice->start - 1;
    $cs->chr_start( $contig_seg->from_start + $assembly_offset  );
    $cs->chr_end(   $contig_seg->from_end   + $assembly_offset  );
    $cs->contig_start(  $contig_slice->start                );
    $cs->contig_end(    $contig_slice->end                  );
    $cs->contig_strand( $contig_slice->strand               );
    $cs->length(        $contig_slice->seq_region_length    );

    if (my $ci = $self->otter_dba->get_ContigInfoAdaptor->fetch_by_contigSlice($contig_slice)) {
        $cs->ContigInfo($ci);
    }

    return $cs;
}

sub fetch_species {
    my ($self) = @_;
    return $self->species($self->otter_dba->species);
}

sub fetch_SimpleFeatures {
    my ($self) = @_;

    my $slice = $self->slice;
    my $features        = $slice->get_all_SimpleFeatures;
    my $slice_length    = $slice->length;

    # Discard features which overlap the ends of the slice
    for (my $i = 0; $i < @$features; ) {
        my $sf = $features->[$i];
        if ($sf->start < 1 or $sf->end > $slice_length) {
            splice(@$features, $i, 1);
        } else {
            $i++;
        }
    }

    $self->_seq_feature_list($features);

    return @$features;
}

sub fetch_Genes {
    my ($self) = @_;

    my $gene_list = $self->slice->get_all_Genes;
    $self->_gene_list($gene_list);

    return @$gene_list;
}

sub _clone_seq_list {
    my ($self, @args) = @_;
    ($self->{'_clone_seq_list'}) = @args if @args;
    my $_clone_seq_list = $self->{'_clone_seq_list'} ||= [];
    return $_clone_seq_list;
}

sub _seq_feature_list {
    my ($self, @args) = @_;
    ($self->{'_seq_feature_list'}) = @args if @args;
    my $_seq_feature_list = $self->{'_seq_feature_list'} ||= [];
    return $_seq_feature_list;
}

sub _gene_list {
    my ($self, @args) = @_;
    ($self->{'_gene_list'}) = @args if @args;
    my $_gene_list = $self->{'_gene_list'} ||= [];
    return $_gene_list;
}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk
