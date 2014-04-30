
### Bio::Otter::Source

package Bio::Otter::Source;

use strict;
use warnings;

use Carp;

sub name {
    my ($self, @args) = @_;
    ($self->{'name'}) = @args if @args;
    my $name = $self->{'name'};
    return $name;
}

sub description {
    my ($self, @args) = @_;
    ($self->{'description'}) = @args if @args;
    my $description = $self->{'description'};
    return $description;
}

sub file {
    my ($self, @args) = @_;
    ($self->{'file'}) = @args if @args;
    my $file = $self->{'file'};
    return $file;
}

sub csver {
    my ($self, @args) = @_;
    ($self->{'csver'}) = @args if @args;
    my $csver = $self->{'csver'};
    return $csver;
}

sub classification {
    my ($self, $class) = @_;

    if ($class) {
        $self->{'_classification_array'} = [split /\s*>\s*/, $class];
    }

    if (my $c_ref = $self->{'_classification_array'}) {
        return @$c_ref;
    }
    else {
        return 'misc';
    }
}

sub wanted { # it's a flag showing whether the user wants this filter to be loaded
             # ( initialized from ['species'.use_filters] section of otter_config )
    my ($self, $wanted) = @_;

    if (defined($wanted)) {
        $self->{'_wanted'} = $wanted ? 1 : 0;
        unless (defined $self->{'_wanted_default'}) {
            $self->{'_wanted_default'} = $self->{'_wanted'};
        }
    }
    return $self->{'_wanted'};
}

sub wanted_default {
    my ($self, @args) = @_;

    if (@args) {
        confess "wanted_default is a read-only method";
    }
    elsif (! defined $self->{'_wanted_default'}) {
        confess "Error: wanted must be set before wanted_default is called";
    }
    else {
        return $self->{'_wanted_default'};
    }
}

# source methods

sub featuresets {
    confess "featuresets() not implemented in parent ", __PACKAGE__;
}

sub zmap_column {
    my ($self, @args) = @_;
    ($self->{'zmap_column'}) = @args if @args;
    my $zmap_column = $self->{'zmap_column'};
    return $zmap_column;
}

sub zmap_style {
    my ($self, @args) = @_;
    ($self->{'zmap_style'}) = @args if @args;
    my $zmap_style = $self->{'zmap_style'};
    return $zmap_style;
}

sub content_type {
    my ($self, @args) = @_;
    ($self->{'content_type'}) = @args if @args;
    my $content_type = $self->{'content_type'};
    return $content_type;
}

sub internal {
    my ($self, @args) = @_;
    ($self->{'internal'}) = @args if @args;
    my $internal = $self->{'internal'};
    return $internal;
}

# GFF methods

sub gff_source {
    my ($self, @args) = @_;
    ($self->{'gff_source'}) = @args if @args;
    my $gff_source = $self->{'gff_source'};
    return $gff_source || $self->name;
}

# Utility methods

sub script_name {
    confess "script_name() not implemented in parent ", __PACKAGE__;
}

sub url {
    my ($self, $session) = @_;
    return sprintf "pipe:///%s?%s", $self->script_name, $self->_url_query_string($session);
}

sub _url_query_string {
    my ($self, $session) = @_;
    confess "_query_string() not implemented in parent ", __PACKAGE__;
}

sub _param_value {
    my ($self, $param) = @_;
    my ($method, $key) =
        ref $param ? @{$param} : ($param, $param);
    my @argument = ( $key => $self->$method );
    return @argument;
}

1;

__END__

=head1 NAME - Bio::Otter::Source

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk
