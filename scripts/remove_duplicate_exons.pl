#!/usr/local/bin/perl

# extract list of clones for any given chromosome based set of coordinates

use strict;
use Getopt::Long;
use Bio::EnsEMBL::DBSQL::DBAdaptor;
use cluster;

# hard wired
my $driver="mysql";

my $port=3352;
my $pass;
my $host='ecs4';
my $user='ensro';
my $dbname='vega_mus_musculus_chr11_20050131';

my $opt_i='duplicate_exons.lis';
my $opt_o='remove_duplicate_exons.sql';

my $opt_t;
my $opt_v;
my $opt_n;

my $help;
my $phelp;

$Getopt::Long::ignorecase=0;

GetOptions(
	   'port:s', \$port,
	   'pass:s', \$pass,
	   'host:s', \$host,
	   'user:s', \$user,
	   'db:s',   \$dbname,

	   'i:s',    \$opt_i,
	   'o:s',    \$opt_o,

	   't',      \$opt_t,
	   'v',      \$opt_v,
	   'n:s',    \$opt_n,

	   'help',   \$phelp,
	   'h',      \$help,
	   );

# help
if($phelp){
    exec('perldoc', $0);
    exit 0;
}
if($help){
    print<<ENDOFTEXT;
remove_duplicate_exons.pl

  -host           host    host of mysql instance ($host)
  -db             dbname  database ($dbname)
  -port           port    port ($port)
  -user           user    user ($user)
  -pass           pass    password 

  -i              file    input file (pair list of duplicate exon_ids)
  -o              file    output sql to remove duplicates

  -t                      wrap output sql as mysql transactions

  -h        help

ENDOFTEXT
    exit 0;
}

my $dbh;
$dbh = new Bio::EnsEMBL::DBSQL::DBConnection(-host => $host,
					     -user => $user,
					     -pass => $pass,
					     -port => $port,
					     -dbname => $dbname,
					     -driver=>'mysql');

# build max version for stable_id in exon_stable_id
my $sql=qq{SELECT stable_id,version
	     FROM exon_stable_id
	   };
my $sth = $dbh->prepare($sql);
$sth->execute();
my $n=0;
my $ne=0;
my %seid;
while (my @row = $sth->fetchrow_array()){
  my($seid,$ver)=@row;
  if($seid{$seid}){
    $seid{$seid}=$ver if $seid{$seid}<$ver;
  }else{
    $seid{$seid}=$ver;
    $ne++;
  }
  $n++;
}
print "read $n entries, $ne exons\n";

my $cl=new cluster();
my $n=0;
open(IN,"$opt_i") || die "cannot open $opt_i";
while(<IN>){
  if(/^(\d+)\s+(\d+)/){
    $cl->link([$1,$2]);
    $n++;
  }
}
close(IN);
my $nc=$cl->cluster_count;
print "$n pairs resolved to $nc clusters\n";
my @cnt;
foreach my $cid ($cl->cluster_ids){
  my @mid=$cl->cluster_members($cid);
  $cnt[scalar(@mid)]++;
}
for(my $i=2;$i<scalar(@cnt);$i++){
  print "$i: $cnt[$i]\n";
}

my $nf=0;
my $nok=0;
my $n=0;
my $nver=0;
my $nmix=0;
my $ndiff=0;
my $nmax=0;
my %exon_synonym;
open(OUT,">$opt_o") || die "cannot open $opt_o";
foreach my $cid ($cl->cluster_ids){
  my @mid=$cl->cluster_members($cid);
  print "processing exons ".join(',',@mid)."(".scalar(@mid).")\n" if $opt_v;
  my $flag_fail;

  my $txt=join(',',@mid);
  my $sql=qq{SELECT t.gene_id,t.transcript_id,esi.stable_id,esi.version,e.* 
	       FROM exon_stable_id esi, transcript t, exon_transcript et, exon e 
	      WHERE t.transcript_id=et.transcript_id 
		AND et.exon_id=e.exon_id 
                AND esi.exon_id=e.exon_id 
                AND e.exon_id in ($txt)
		};
  my $sth = $dbh->prepare($sql);
  $sth->execute();

  my($gid2,$eid2,$cid2,$cst2,$ced2,$st2,$ph2,$eph2,$sr2);
  my %tid;
  while (my @row = $sth->fetchrow_array()){
    my($gid,$tid,$seid,$sev,$eid,$cid,$cst,$ced,$st,$ph,$eph,$sr)=@row;
    if($gid2){
      # check both exons part of same gene
      if($gid!=$gid2){
	print " FATAL: Different gene_ids $gid $gid2\n";
	$flag_fail=1;
	last;
      }
      # check exons really are identical
      if($cid!=$cid2 || $cst!=$cst2 || $ced!=$ced2 || $st!=$st2 || $ph!=$ph2 || $eph!=$eph2 || $sr!=$sr2){
	print " FATAL: Exons not identical\n";
	print "  $eid,$cid,$cst,$ced,$st,$ph,$eph,$sr\n";
	print "  $eid2,$cid2,$cst2,$ced2,$st2,$ph2,$eph2,$sr2\n";
	$flag_fail=1;
	last;
      }
      if($tid{$tid}){
	print " FATAL: Multiple exons saved for transcript $tid\n";
	print "  ".join(',',@{$tid{$tid}})."\n";
	print "  $seid,$sev,$eid\n";
	$flag_fail=1;
	last;
      }else{
	$tid{$tid}=[$seid,$sev,$eid];
      }
    }else{
      ($gid2,$eid2,$cid2,$cst2,$ced2,$st2,$ph2,$eph2,$sr2)=
	  ($gid,$eid,$cid,$cst,$ced,$st,$ph,$eph,$sr);
      $tid{$tid}=[$seid,$sev,$eid];
    }
  }
  if($flag_fail){
    next;
    $nf++;
  }
  
  # work out which one we are going to change
  my %seid2;
  my %seid3;
  my %seid4;
  my $txt;
  foreach my $tid (keys %tid){
    my($seid,$sev,$eid)=@{$tid{$tid}};
    $txt.="$tid($seid.$sev);";
    $seid2{$seid}++;
    $seid3{$seid}=$sev if $seid3{$seid}<$sev;
    $seid4{"$seid.$sev"}=[$tid,$eid];
  }
  my $label;
  if(scalar(keys %seid2)==1){
    my($seid)=(keys %seid2);
    # exons are different versions of same id
    $nver++;
    # max version of this stable_id in DB?
    if($seid3{$seid}==$seid{$seid}){
      $nmax++;
      $label='MAX';
    }else{
      $label='INTERNAL';
    }
  }else{
    if(scalar(keys %seid2)!=scalar(keys %tid)){
      $nmix++;
      $label='mix';
    }else{
      $ndiff++;
      $label='diff';
    }
  }

  # keep lowest stable_id; highest version
  my($rseid)=(sort keys %seid2);
  my $rsev=$seid3{$rseid};
  print "$rseid.$rsev: [$label] $txt\n" if $opt_v;
  my($rtid,$reid)=@{$seid4{"$rseid.$rsev"}};
  
  print OUT "START TRANSACTION;\n" if $opt_t;
  
  # write required SQL
  foreach my $tid (keys %tid){
    my($seid,$sev,$eid)=@{$tid{$tid}};
    # skip match
    next if($rtid==$tid);
    print OUT "update exon_transcript set exon_id=$reid where transcript_id=$tid and exon_id=$eid;\n";
    print OUT "delete from exon where exon_id=$eid;\n";
    print OUT "delete from exon_stable_id where exon_id=$eid;\n";
    my $rsv="$rseid.$rsev";
    my $sv="$seid.$sev";
    # ensure unique entry (perhaps should check here)
    if(!$exon_synonym{"$rsv.$sv"}){
      $exon_synonym{"$rsv.$sv"}=1;
      print OUT "insert into exon_synonym values(\'$rsv\',\'$sv\');\n";
    }
  }
  
  print OUT "COMMIT;\n" if $opt_t;
  
  # successful
  $nok++;
  $n++;
  last if($opt_n && $n>=$opt_n);
}
print "Duplicate removal: $nf failed; $nok ok\n";
print "$nver same stable_id ($nmax); $ndiff different stable_id; $nmix mixture\n";
close(IN);
close(OUT);

exit 0;

__END__

=pod

=head1 patch24.pl

=head1 DESCRIPTION

=head1 EXAMPLES

=head1 FLAGS

=over 4

=item -h

Displays short help

=item -help

Displays this help message

=back

=head1 VERSION HISTORY

=over 4

=item 16-JAN-2003

B<th> released first version

=back

=head1 BUGS

=head1 AUTHOR

B<Tim Hubbard> Email th@sanger.ac.uk

=cut
