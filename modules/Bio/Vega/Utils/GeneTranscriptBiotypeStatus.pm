
### Bio::Vega::Utils::GeneTranscriptBiotypeStatus

package Bio::Vega::Utils::GeneTranscriptBiotypeStatus;

use strict;
use base 'Exporter';
our @EXPORT_OK = qw{ method2biotype_status biotype_status2method };

my @method_biotype_status = qw{

    Coding                          protein_coding          -
        Known_CDS                   protein_coding          KNOWN
        Novel_CDS                   protein_coding          NOVEL
        Putative_CDS                protein_coding          PUTATIVE
        Nonsense_mediated_decay     =                       -
                                    
    Transcript                      processed_transcript    -
        Non_coding                  =                       -
        Ambiguous_ORF               =                       -
        Retained_intron             =                       -
        Antisense                   =                       -
        Disrupted_domain            =                       -
        IG_segment                  =                       -
        Putative                    =                       -
                                    
    Pseudogene                      =                       -
        Processed_pseudogene        =                       -
        Unprocessed_pseudogene      =                       -
        Expressed_pseudogene        =                       -
                                    
    Transposon                      =                       -
                                    
    Artifact                        =                       -

    TEC                             =                       -

    Predicted                       processed_transcript    PREDICTED

};

if (@method_biotype_status % 3) {
    die "Method, Biotype, Status list is not a multiple of 3";
}

my (%method_to_biotype_status, %biotype_status_to_method);
for (my $i = 0; $i < @method_biotype_status; $i += 3) {
    my ($method, $biotype, $status) = @method_biotype_status[$i, $i+1, $i+2];

    # biotype defaults to lower case of status
    $biotype = lc $method if $biotype eq '=';
    $status = 'UNKNOWN'   if $status  eq '-';

    $biotype_status_to_method{"$biotype.$status"}   = $method;
    $biotype_status_to_method{$biotype}           ||= $method;

    $method_to_biotype_status{$method} = [$biotype, $status];
}

sub method2biotype_status {
    my ($method) = @_;
    
    my ($biotype, $status);
    if (my $bs = $method_to_biotype_status{$method}) {
        return @$bs;
    } else {
        return (lc $method, 'UNKNOWN')
    }
}

sub biotype_status2method {
    my $biotype = lc shift;
    my $status  = uc shift;
    
    #warn "TESTING FOR: '$biotype.$status'";
    return $biotype_status_to_method{"$biotype.$status"}
        || $biotype_status_to_method{$biotype}
        || ucfirst lc $biotype;
}

1;

__END__

=head1 NAME - Bio::Vega::Utils::GeneTranscriptBiotypeStatus

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

