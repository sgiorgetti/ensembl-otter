package ZMap::ConnectUtils;

use strict;
use warnings;
use Exporter;
use X11::XRemote;
use XML::Simple;

our @ISA    = qw(Exporter);
our @EXPORT_OK = qw(parse_request
                    parse_response
                    xml_escape
                    make_xml
                    obj_make_xml
                    newXMLObj
                    setObjNameValue
                    fork_exec
                    );
our %EXPORT_TAGS = ('caching' => [@EXPORT_OK],
                    'all'     => [@EXPORT_OK]
                    );

=pod

=head1 NAME

ZMap::ConnectUtils

=head1 DESCRIPTION

 functions which might get written over and over again.

=head1 PARSING FUNCTIONS

=cut

sub parse_request{
    my ($xml)  = shift;
    my $parser = XML::Simple->new();
    my $hash   = $parser->XMLin(
        $xml,
        KeyAttr => {feature => 'name'},
        ForceArray => [ 'feature', 'subfeature' ],
        );
    return $hash;
}

=head2 parse_response(string)

parse a response into (status, hash of xml)

=cut

sub parse_response{
    my $response = shift;
    my $delimit  = X11::XRemote::delimiter();

    my ($status, $xml) = split(/$delimit/, $response, 2);
    my $parser = XML::Simple->new();
    my $hash   = $parser->XMLin($xml);
    
    return wantarray ? ($status, $hash) : $hash;
}
sub make_xml{
    my ($hash) = @_;
    my $parser = XML::Simple->new(rootname => q{},
                                  keeproot => 1,
                                  );
    my $xml = $parser->XMLout($hash);
    return $xml;
}

sub obj_make_xml{
    my ($obj, $action) = @_;
    return unless $obj && $action;
    my $formatStr = '<zmap><request action="%s">%s</request></zmap>';
    return sprintf($formatStr, $action, xmlString($obj));
}
sub xml_escape{
    my $data    = shift;
    my $parser  = XML::Simple->new(NumericEscape => 1);
    my $escaped = $parser->escape_value($data);
    return $escaped;
}


sub fork_exec {
    my ($command) = @_;
    
    if (my $pid = fork) {
        return $pid;
    }
    elsif (defined $pid) {
    
        exec @$command;
        warn "exec(@$command) failed : $!";
        CORE::exit();   # Still triggers DESTROY
    }
    else {
        die "fork failed: $!";
    }

    return; # not reached
}


#########################
{
    my $encodedXSD = {
        feature => {
            name   => undef,
            style  => undef,
            start  => undef,
            end    => undef,
            strand => undef,
            suid   => undef,
            edit_name  => undef,
            edit_style => undef,
            edit_start => undef,
            edit_end   => undef,
        },
        segment => {
            sequence => undef,
            start    => undef,
            end      => undef,
        },
        client => {
            xwid          => undef,
            request_atom  => undef,
            response_atom => undef,
        },
        location => {
            start => undef,
            end   => undef,
        },
        featureset => {
            suid     => undef,
            features => [],
        },
        error => {
            message => undef,
        },
        meta => {
            display     => undef,
            windowid    => undef,
            application => undef,
            version     => undef,
        },
        response => {},
        zoom_in => {},
        zoom_out => {},
    };
    my @TYPES = keys( %$encodedXSD );

    sub newXMLObj{
        my ($type) = @_;
        $type = lc $type;
        if(grep { /^$type$/ } @TYPES){
            my $obj = [];
            $obj->[0] = $type;
            $obj->[1] = { %{$encodedXSD->{$type}} };
            return $obj;
        }else{
            return;
        }
    }

    sub setObjNameValue{
        my ($obj, $name, $value) = @_;
        return unless $obj && $name && defined($value) && ref($obj) eq 'ARRAY';
        my $type = $obj->[0];
        if((grep { /$type/ } @TYPES) && exists($encodedXSD->{$type}->{$name})){
            if(ref($encodedXSD->{$type}->{$name}) eq 'ARRAY'){
                push(@{$obj->[1]->{$name}}, $value);
            }else{
                $obj->[1]->{$name} = $value;
            }
        }else{
            warn "Unknown type '$type' or name '$name'\n";
        }
        return;
    }

}
sub xmlString{
    my ($obj, $formatStr, @parts, $utype, $uobj) = @_; # ONLY $obj is used.
    return "" unless $obj && ref($obj) eq 'ARRAY';
    $formatStr = "";
    @parts     = ();
    $utype     = $obj->[0];
    $uobj      = $obj->[1];
    if($utype eq 'client'){
        $formatStr = '<client xwid="%s" request_atom="%s" response_atom="%s" />';
        @parts     = map { $uobj->{$_} || '' } qw(xwid request_atom response_atom);
    }elsif($utype eq 'feature'){
        @parts     = map { $uobj->{$_} || '' } qw(suid name style start end strand);
        if($uobj->{'edit_name'} 
           || $uobj->{'edit_start'} 
           || $uobj->{'edit_end'}
           || $uobj->{'edit_style'}){
            $formatStr = '<feature suid="%s" name="%s" style="%s" start="%s" 
                                   end="%s" strand="%s" >
                            <edit name="%s" style="%s" start="%s" end="%s"/>
                          </feature>';
            push(@parts, map{ $uobj->{$_} || '' } qw(edit_name edit_style edit_start edit_end));
        }else{
            $formatStr = '<feature suid="%s" name="%s" style="%s" start="%s" 
                                    end="%s" strand="%s"/>';
        }
    }elsif($utype eq 'featureset'){
        $formatStr = '<featureset suid="%s">%s</featureset>';
        @parts     = map { $uobj->{$_} || '' } qw(suid __empty);
        foreach my $f(@{$uobj->{'features'}}){
            $parts[1] .= xmlString($f);
        }
    }elsif($utype eq 'location'){
        $formatStr = '<location start="%s" end="%s" />';
        @parts     = map { $uobj->{$_} || '' } qw(start end); 
    }elsif($utype eq 'segment'){
        $formatStr = '<segment sequence="%s" start="%s" end="%s" />';
        @parts     = map { $uobj->{$_} || '' } qw(sequence start end);
    }else{
        warn "Unknown object type '$utype'\n";
    }
    return sprintf($formatStr, @parts);
}


1;
__END__

