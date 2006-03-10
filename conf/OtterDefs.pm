#!/usr/local/bin/perl -w

###############################################################################
#   
#   Name:           OtterDefs.pm
#   
#   Description:    Config for Otter server.
#
###############################################################################

package OtterDefs;

use strict;
use vars qw(
    @ISA     @EXPORT     @EXPORT_OK     %EXPORT_TAGS     $VERSION

   $OTTER_PREFIX
   $OTTER_SPECIES
   $OTTER_SERVER_ROOT
   $OTTER_SERVER_PORT
   $OTTER_ALTROOT
   $OTTER_SCRIPTDIR
   $OTTER_GET_SCRIPTS
   $OTTER_POST_SCRIPTS
   $OTTER_SERVER
   $OTTER_PORT
   $OTTER_MAX_CLIENTS
   $OTTER_SCRIPT_TIMEOUT
   $OTTER_DBNAME 
   $OTTER_USER
   $OTTER_HOST
   $OTTER_PORT
   $OTTER_PASS
   $OTTER_TYPE
   $OTTER_DNA_DBNAME 
   $OTTER_DNA_USER
   $OTTER_DNA_HOST
   $OTTER_DNA_PORT
   $OTTER_DNA_PASS
   $OTTER_DEFAULT_SPECIES
   $OTTER_SPECIES_FILE

   $OTTER_GLOBAL_ACCESS_USER
);

use Sys::Hostname;
use Exporter();

@ISA=qw(Exporter);

my ($MAIN_DIR, $OTTER_RELEASE);

$OTTER_SERVER_PORT      = 33999;
$OTTER_RELEASE          = 41;

$MAIN_DIR               = '/nfs/team71/analysis/lg4/work';
# $MAIN_DIR               = "/humsql/ottersrv_rel${OTTER_RELEASE}_port${OTTER_SERVER_PORT}";
# $MAIN_DIR               = "/mysql/otter-live-master/otter/ottersrv_rel${OTTER_RELEASE}_port${OTTER_SERVER_PORT}";

$OTTER_SERVER_ROOT 	    = $MAIN_DIR.'/ensembl-otter';
$OTTER_ALTROOT    	    = $MAIN_DIR.'/ensembl-otter/otter_alt';
$OTTER_SCRIPTDIR        = $OTTER_SERVER_ROOT . '/scripts/server';
$OTTER_SERVER		    = Sys::Hostname::hostname();  # Local machine name
$OTTER_MAX_CLIENTS          = 5;
$OTTER_SCRIPT_TIMEOUT       = 60;
$OTTER_SPECIES_FILE         = $OTTER_SERVER_ROOT . "/conf/species.dat";
$OTTER_SPECIES              = read_species($OTTER_SPECIES_FILE);
$OTTER_DEFAULT_SPECIES      = 'human';
$OTTER_PREFIX               = 'OTT';
$OTTER_GET_SCRIPTS          = {'/perl/get_region'     => 'get_region',
                               '/perl/get_sequence'   => 'get_sequence',
                               '/perl/get_datasets'   => 'get_datasets',
                               '/perl/get_loci_names' => 'get_loci_names',
                               '/perl/lock_region'    => 'lock_region',
                               '/perl/get_align_features'         => 'get_align_features',
                               '/perl/get_simple_features'        => 'get_simple_features',
                               '/perl/get_repeat_features'        => 'get_repeat_features',
                               '/perl/get_prediction_transcripts' => 'get_prediction_transcripts',
                               '/perl/get_pipeline_genes'         => 'get_pipeline_genes',
                               '/perl/get_analyses_status'    => 'get_analyses_status',

                              };
$OTTER_POST_SCRIPTS         = {'/perl/write_region'   => 'write_region',
                               '/perl/unlock_region'  => 'unlock_region',
                              };
$OTTER_GLOBAL_ACCESS_USER   = 'GLOBAL_READONLY'; 

################################################################################################
#
# Nothing below here should need to be edited
#
################################################################################################

unless ($OTTER_SPECIES->{$OTTER_DEFAULT_SPECIES}) {
    die "no information for default species '$OTTER_DEFAULT_SPECIES'";
}

$OTTER_DBNAME        = $OTTER_SPECIES->{$OTTER_DEFAULT_SPECIES}{DBNAME};
$OTTER_USER          = $OTTER_SPECIES->{$OTTER_DEFAULT_SPECIES}{USER} || $OTTER_SPECIES->{defaults}{USER};
$OTTER_HOST          = $OTTER_SPECIES->{$OTTER_DEFAULT_SPECIES}{HOST} || $OTTER_SPECIES->{defaults}{HOST};
$OTTER_PORT          = $OTTER_SPECIES->{$OTTER_DEFAULT_SPECIES}{PORT} || $OTTER_SPECIES->{defaults}{PORT};
$OTTER_PASS          = $OTTER_SPECIES->{$OTTER_DEFAULT_SPECIES}{PASS} || $OTTER_SPECIES->{defaults}{PASS};
$OTTER_TYPE          = $OTTER_SPECIES->{$OTTER_DEFAULT_SPECIES}{TYPE} || $OTTER_SPECIES->{defaults}{TYPE};

$OTTER_DNA_DBNAME    = $OTTER_SPECIES->{$OTTER_DEFAULT_SPECIES}{DNA_DBNAME};

$OTTER_DNA_HOST       = $OTTER_SPECIES->{$OTTER_DEFAULT_SPECIES}{DNA_HOST} || $OTTER_SPECIES->{defaults}{DNA_HOST};
$OTTER_DNA_USER       = $OTTER_SPECIES->{$OTTER_DEFAULT_SPECIES}{DNA_USER} || $OTTER_SPECIES->{defaults}{DNA_USER};
$OTTER_DNA_PORT       = $OTTER_SPECIES->{$OTTER_DEFAULT_SPECIES}{DNA_PORT} || $OTTER_SPECIES->{defaults}{DNA_PORT};
$OTTER_DNA_PASS       = $OTTER_SPECIES->{$OTTER_DEFAULT_SPECIES}{DNA_PASS} || $OTTER_SPECIES->{defaults}{DNA_PASS};

@EXPORT = qw
  (
   $OTTER_SERVER_ROOT
   $OTTER_SERVER_PORT
   $OTTER_ALTROOT
   $OTTER_SCRIPTDIR
   $OTTER_GET_SCRIPTS
   $OTTER_POST_SCRIPTS
   $OTTER_SERVER
   $OTTER_PORT
   $OTTER_MAX_CLIENTS
   $OTTER_SCRIPT_TIMEOUT
   $OTTER_SPECIES
   $OTTER_DEFAULT_SPECIES
   $OTTER_PREFIX
   
   $OTTER_DBNAME 
   $OTTER_USER
   $OTTER_HOST
   $OTTER_PORT
   $OTTER_PASS
   $OTTER_TYPE

   $OTTER_DNA_DBNAME 
   $OTTER_DNA_USER
   $OTTER_DNA_HOST
   $OTTER_DNA_PORT
   $OTTER_DNA_PASS

   $OTTER_GLOBAL_ACCESS_USER
);

sub read_species {
  my ($file) = @_;

  open(IN,"<$file") || die "Can't read species file [$file]\n";

  my $cursect = undef;
  my %defhash;
  my $curhash;
  
  my %info;
  
  while (<IN>) {
    next if /^\#/;
    next unless /\w+/;
    chomp;

    if (/\[(.*)\]/) {
      if (!defined($cursect) && $1 ne "defaults") {
        die "ERROR: First section in species.dat should be defaults\n";
      } elsif ($1 eq "defaults") {
	    #print STDERR "Got default section\n";
        $curhash = \%defhash;
      } else {
        $curhash = {};
        foreach my $key (keys %defhash) {
          $key =~ tr/a-z/A-Z/;
          $curhash->{$key} = $defhash{$key};
        }
      }
      $cursect = $1;
      $info{$cursect} = $curhash;

    } elsif (/(\S+)\s+(\S+)/) {
      #print "Reading entry $1 $2\n";
      $curhash->{$1} = $2;
    }
  }
  return (\%info);
}

	
1;
