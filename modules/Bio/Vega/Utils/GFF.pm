### Bio::Vega::Utils::GFF

package Bio::Vega::Utils::GFF;

use strict;
use warnings;

use Carp;

use Bio::Vega::Utils::GFF::Format;

sub gff_header {
    my ($gff_version, $dna) = @_;

    # build up a date string in the format specified by the GFF spec

    my ($sec, $min, $hr, $mday, $mon, $year) = localtime;
    $year += 1900;    # correct the year
    $mon++;           # correct the month
    my $date = sprintf "%4d-%02d-%02d", $year, $mon, $mday;

    my $hdr =
        "##gff-version $gff_version\n"
      . "##source-version EnsEMBL2GFF 1.0\n"
      . "##date $date\n"
      ;

    $hdr .= "##DNA\n##$dna\n##end-DNA\n" if $dna;

    return $hdr;
}

my $version_format_hash = {

    2 => {
        'attribute_format' => '%s %s',
        'attribute_escape' => 0,
    },

    3 => {
        'attribute_format' => '%s=%s',
        'attribute_escape' => 1,
    },

};

sub gff_format {
    my ($gff_version) = @_;
    my $format_hash = $version_format_hash->{$gff_version};
    defined $format_hash or croak sprintf "unsupported GFF version: '%s'", $gff_version;
    my $format = Bio::Vega::Utils::GFF::Format->new($format_hash);
    return $format;
}

1;

__END__

=head1 NAME - Bio::Vega::Utils::GFF

=head1 SYNOPSIS

Utilities for creating GFF.

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

