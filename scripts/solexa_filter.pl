use strict;
use warnings;

use Data::Dumper;

use Bio::EnsEMBL::DBSQL::DBAdaptor;
use Bio::EnsEMBL::SimpleFeature;

my $dba = Bio::EnsEMBL::DBSQL::DBAdaptor->new(
    -host   => 'genebuild4.internal.sanger.ac.uk',
    -port   => 3306,
    -user   => 'ensro',
    -dbname => 'sw4_danio_solexa_genome_align_53',
);

my $result_dba = Bio::EnsEMBL::DBSQL::DBAdaptor->new(
    -host   => 'otterpipe2',
    -port   => 3323,
    -user   => 'ottadmin',
    -pass   => 'wibble',
    -dbname => 'gr5_zebrafish_solexa',
);

my $aa = $result_dba->get_AnalysisAdaptor;

my $analysis = $aa->fetch_by_logic_name('solexa_non_redundant');

my $afa = $result_dba->get_DnaAlignFeatureAdaptor;

my $sa = $dba->get_SliceAdaptor;

my $slice = $sa->fetch_by_region('chromosome',1,537730,587318,-1);

my @afs;

for my $ana (qw(37bp_14dpf_ga 37bp_1dpf_ga 37bp_28dpf_ga 37bp_2dpf_ga 37bp_3dpf_ga 37bp_5dpf_ga)) {
    push @afs, @{ $slice->get_all_DnaAlignFeatures($ana) };
}

#die "num afs: ".scalar(@$afs)."\n";

my %seen;

my @to_keep;

for my $af (@afs) {
    my @fs = $af->ungapped_features;
    #next unless @fs > 1;
    my $str = '';
    
    for my $f (@fs) {
        $str .= int($f->start / 20).'-'.int($f->end / 20).',';
    }
    
    if ($seen{$str}) {
        $seen{$str}->score($seen{$str}->score + 1);
    }
    else {
        $af->analysis($analysis);
        $af->score(1);
        push @to_keep, $af;
        $seen{$str} = $af;
    }
}

print "Reduced ".scalar(@afs)." to ".scalar(@to_keep)."\n";

map { $afa->store($_) } @to_keep;
