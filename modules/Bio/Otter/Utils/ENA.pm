
### Bio::Otter::Utils::ENA

package Bio::Otter::Utils::ENA;

use strict;
use warnings;

use LWP::UserAgent;
use Readonly;
use URI::Escape qw(uri_escape);
use XML::Simple;

Readonly my $ENA_VIEW_URL   => 'http://www.ebi.ac.uk/ena/data/view/';
Readonly my $ENA_XML_SUFFIX => '&display=xml';

sub new {
    my ($class, @args) = @_;
    my $self = bless {}, $class;

    my $ua = LWP::UserAgent->new(
        timeout           => 10,
        env_proxy         => 1,
        protocols_allowed => [ 'http' ],
        );

    $self->_user_agent($ua);

    return $self;
}

sub get_sample_accessions {
    my ($self, @accessions) = @_;

    my $acc_list = join(',', map { uri_escape($_) } @accessions);
    my $uri = $ENA_VIEW_URL . $acc_list . $ENA_XML_SUFFIX;
    my $response = $self->_user_agent->get($uri);
    die "No response to ENA request" unless $response;
    unless ($response->is_success) {
        warn $response->status_line;
        return;
    }

    my $xml = $response->decoded_content;
    my $ref = XMLin($xml);

    my %results;
    my $samples = $ref->{SAMPLE};
    if ($samples) {
        foreach my $sample (@$samples) {
            my $sample_acc = $sample->{accession};
            $results{$sample_acc} = {
                alias    => $sample->{alias},
                taxon_id => $sample->{SAMPLE_NAME}->{TAXON_ID},
                title    => $sample->{TITLE},
            };
        }
    }

    return \%results;
}

sub _user_agent {
    my ($self, @args) = @_;
    ($self->{_user_agent}) = @args if @args;
    return $self->{_user_agent};
}

1;

__END__

=head1 NAME - Bio::Otter::Utils::ENA

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

