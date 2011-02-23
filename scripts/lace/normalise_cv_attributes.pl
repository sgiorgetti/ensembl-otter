#!/usr/bin/env perl

use warnings;
use strict;

use Carp;
use Readonly;
use JSON;

use Bio::Otter::Lace::Defaults;

Readonly my %sql_tab => (
    atid_from_code => 'SELECT attrib_type_id FROM attrib_type WHERE code = ?',
    gene => {
        title  => 'gene attribute',
        id_tag => 'gene_id',
        insert => 'INSERT into gene_attrib (gene_id, attrib_type_id, value) VALUES (?, ?, ?)',
        update => 'UPDATE gene_attrib SET attrib_type_id = ?, value = ? __WHERE__',
        delete => 'DELETE FROM gene_attrib __WHERE__',
        select => 'SELECT COUNT(*) FROM gene_attrib __WHERE__',
        where  => 'WHERE gene_id = ? AND attrib_type_id = ? AND value = ?',
    },
    transcript => {
        title  => 'transcript attribute',
        id_tag => 'transcript_id',
        insert => 'INSERT into transcript_attrib (transcript_id, attrib_type_id, value) VALUES (?, ?, ?)',
        update => 'UPDATE transcript_attrib SET attrib_type_id = ?, value = ? __WHERE__',
        delete => 'DELETE FROM transcript_attrib __WHERE__',
        select => 'SELECT COUNT(*) FROM transcript_attrib __WHERE__',
        where  => 'WHERE transcript_id = ? AND attrib_type_id = ? AND value = ?',
    },
    );

my $opts = {
    dry_run  => 1,
    debug    => 0,
    total    => 0,
    quiet    => 0,
    verbose  => 0,
    max_slop => 3,
    just_query => 0,
    };

{
    local $0 = 'otterlace'; # for access to test_human

    my $dataset_name = undef;
    my $attrib_pattern = undef;

    my $usage = sub { exec('perldoc', $0) };
    # This do_getopt() call is needed to parse the otter config files
    # even if you aren't giving any arguments on the command line.
    Bio::Otter::Lace::Defaults::do_getopt(
        'h|help!'       => $usage,
        'dataset=s'     => \$dataset_name,
	'attrib=s'      => \$attrib_pattern,
        'dryrun!'       => \$opts->{dry_run},
        'debug!'        => \$opts->{debug},
        'quiet!'        => \$opts->{quiet},
        'total!'        => \$opts->{total},
        'verbose!'      => \$opts->{verbose},
        'unkeep=s'      => \$opts->{unkeep},
        'ignore=s'      => \$opts->{ignore},
        'justquery!'    => \$opts->{just_query},
        'summarise:s'   => \$opts->{summarise},
        'output=s'      => \$opts->{output},
        ) or $usage->();
    $usage->() unless ($dataset_name and $attrib_pattern);

    if (defined $opts->{summarise} and not $opts->{dry_run}) {
        carp("Forcing -dryrun for -summarise mode");
        $opts->{dry_run} = 1;
    }

    if ($opts->{output}) {
        # Redirect stdout
        open STDOUT, '>', $opts->{output} or croak "Can't redirect STDOUT: $!";
    }

    # Client communicates with otter HTTP server
    my $cl = Bio::Otter::Lace::Defaults::make_Client();
    
    # DataSet interacts directly with an otter database
    my $ds = $cl->get_DataSet_by_name($dataset_name);

    # falls over on human_test, in _attach_DNA_DBAdaptor
    # my $otter_dba = $ds->get_cached_DBAdaptor;

    my $otter_dba = $ds->make_Vega_DBAdaptor;

    print_divider(sprintf("Normalise %s using '%s'%s",
                          $dataset_name, $attrib_pattern, 
                          $opts->{dry_run} ? ' [dry run]' : ''
                  ));

    $cl->get_server_otter_config;
    my $vocab_locus = $ds->vocab_locus;
    my $vocab_transcript = $ds->vocab_transcript;

    my $cv_locus = match_vocab($attrib_pattern, $vocab_locus);
    my $cv_transcript = match_vocab($attrib_pattern, $vocab_transcript);

    print_divider('Controlled vocab matches');

    printf("Locus CV:      %s\nTranscript CV: %s\n",
           $cv_locus      || '<no match>',
           $cv_transcript || '<no match>') unless $opts->{quiet};

    unless ($cv_locus or $cv_transcript) {
        print_divider("WARNING: no CV found");
        carp("WARNING: no CV found");
    }

    my $on_both_branches = ($cv_locus and $cv_transcript);
    print_divider("NB: found both locus and transcript CVs") if $on_both_branches;

    print_divider('Find relevant gene items');
    my ($genes,       $g_values) = find_genes($otter_dba, $attrib_pattern);

    print_divider('Find relevant transcript items');
    my ($transcripts, $t_values) = find_transcripts($otter_dba, $attrib_pattern);

    print_divider('Identified variants');

    my %summary;
    $summary{variants}->{locus}      = summarise_variants('Locus',      $g_values, $cv_locus);
    $summary{variants}->{transcript} = summarise_variants('Transcript', $t_values, $cv_transcript);

    my $warnings = identify_warnings($genes, $transcripts);
    if (%{$warnings->{summary}}) {
        $summary{warnings} = $warnings->{summary};
        unless($opts->{quiet}) {
            print_divider('WARNINGS');
            show_warnings($warnings);
        }
    }
    
    summary_exit(\%summary, 0) if $opts->{just_query};

    print_divider('Calculate actions');

    my ($gene_actions, $transcript_actions);

    if ($cv_locus) {

        $gene_actions = plan_update_actions($cv_locus, $genes, $transcripts);

        unless ($on_both_branches) {
            my $gene_matches_for_ts = identify_ts_where_gene_attrib_exists($transcripts, $genes);
            $transcript_actions = plan_ts_to_gene_actions($cv_locus, $transcripts, $gene_actions, $gene_matches_for_ts);
        }

    } 

    if ($cv_transcript) {

        $transcript_actions = plan_update_actions($cv_transcript, $transcripts, $genes);

        unless ($on_both_branches) {
            # We cannot necessarily assign from transcript to gene
            # $gene_actions =       plan_move_actions($cv_transcript, $genes, $transcript_actions);
        }

    }

    print_divider('Implement actions');

    if ($gene_actions) {
        $summary{actions}->{locus} =
            implement_actions($otter_dba, $gene_actions,       'gene',       $opts->{dry_run});
    }
    if ($transcript_actions) {
        $summary{actions}->{transcript} =
            implement_actions($otter_dba, $transcript_actions, 'transcript', $opts->{dry_run});
    }
    
    print_divider('Done');

    summary_exit(\%summary, 0);
}

sub summary_exit {
    my ($summary, $exit_code) = @_;

    if (defined $opts->{summarise}) {

        my $summary_fh;
        if ($opts->{summarise}) {
            open $summary_fh, '>', $opts->{summarise} or croak "Can't open summary file: $!";
        } else {
            $summary_fh = *STDOUT;
        }
        print $summary_fh to_json($summary, { pretty => 1 }), "\n";
        close $summary_fh;
    }
    exit $exit_code;
}

sub print_divider {
    my ($comment) = @_;
    return if $opts->{quiet};
    if ($comment) {
        printf("--- %s %s\n", $comment, '-' x (66 - 5 - length $comment));
    } else {
        printf("%s\n", '-' x 66);
    }
    return;
}

sub match_vocab {
    my ($pattern, $vocab) = @_;

    my $perl_pattern = sql_to_perl_regexp($pattern);
    croak "Don't understand '$pattern'" unless $perl_pattern;

    my @hits = map { /($perl_pattern)/ix } keys %$vocab;
    croak "More than one vocab match for $perl_pattern:", join(',', @hits) if scalar @hits > 1;

    return $hits[0];
}

sub sql_to_perl_regexp {
    my $pattern = shift;

    $pattern =~ s/%/.*/xg;
    $pattern =~ s/_/./xg;

    return "^$pattern\$";
}

sub find_genes {
    my ($otter_dba, $attrib_pattern) = @_;

    my $list_genes = $otter_dba->dbc->prepare(<<'__SQL_END__');
        SELECT
                g.gene_id,
                gsi.stable_id,
                gan.value,
                ga.attrib_type_id,
                at.code,
                ga.value,
                sr.name
        FROM
                gene                 g
           JOIN gene_attrib          ga  USING (gene_id)
           JOIN attrib_type          at  USING (attrib_type_id)
           JOIN gene_stable_id       gsi USING (gene_id)
           JOIN gene_attrib          gan ON     g.gene_id = gan.gene_id 
                                            AND gan.attrib_type_id = (
                                                SELECT attrib_type_id
                                                FROM   attrib_type
                                                WHERE  code = 'name'
                                               )
           JOIN seq_region           sr  USING (seq_region_id)
        WHERE
                g.is_current = 1
            AND ga.value LIKE ?
            AND at.code IN ('remark', 'hidden_remark')
__SQL_END__

    $list_genes->execute($attrib_pattern);

    my %genes;
    my %values;

    my $count = 0;
    my $out_format = "%s\t%s\t%s\t%s\t%s\n";
    printf( $out_format,
	    "Chromosome", "Gene name", "stable id",
	    "Code", "Attribute" ) if $opts->{verbose};
    
    GENE_ATTR: while (my ($gid, $gene_sid, $gene_name, 
                          $attrib_type_id, $attrib_code, $attrib_value,
                          $seq_region_name) = $list_genes->fetchrow()) {

        my $duplicates;
        if (my $prev = $genes{$attrib_code}->{$gid}) {
            carp "Already seen ", $attrib_code, " for gene ", $gene_sid;
            $duplicates = ++$prev->{duplicates};
        }

        $genes{$attrib_code}->{$gid} = {
            gene_id => $gid,
            sid   => $gene_sid,
            atid  => $attrib_type_id,
            code  => $attrib_code,
            value => $attrib_value,
            duplicates => $duplicates, # yuk - shouldn't be throwing away prev
        };

        ++$values{$attrib_code}->{$attrib_value};
        ++$count;

        printf( $out_format,
                $seq_region_name, $gene_name, $gene_sid,
		$attrib_code, $attrib_value,
            ) if $opts->{verbose};

    } # GENE_ATTR

    printf "Total genes: %d\n", $count if $opts->{total};

    return ( \%genes, \%values );
}

sub find_transcripts {
    my ($otter_dba, $attrib_pattern) = @_;

    my $list_transcripts = $otter_dba->dbc->prepare(<<'__SQL_END__');
        SELECT
                g.gene_id,
                gsi.stable_id,
                gan.value,
                t.transcript_id,
                tsi.stable_id,
                tan.value,
                ta.attrib_type_id,
                at.code,
                ta.value,
                sr.name
        FROM
                transcript           t
           JOIN transcript_attrib    ta  USING (transcript_id)
           JOIN attrib_type          at  USING (attrib_type_id)
           JOIN transcript_stable_id tsi USING (transcript_id)
           JOIN gene                 g   USING (gene_id)
           JOIN gene_stable_id       gsi USING (gene_id)
           JOIN gene_attrib          gan ON     g.gene_id = gan.gene_id 
                                            AND gan.attrib_type_id = (
                                                SELECT attrib_type_id
                                                FROM   attrib_type
                                                WHERE  code = 'name'
                                               )
           JOIN transcript_attrib    tan ON     t.transcript_id = tan.transcript_id
                                            AND tan.attrib_type_id = (
                                                SELECT attrib_type_id
                                                FROM   attrib_type
                                                WHERE  code = 'name'
                                               )
           JOIN seq_region           sr  ON g.seq_region_id = sr.seq_region_id
        WHERE
                t.is_current = 1
            AND ta.value LIKE ?
            AND at.code IN ('remark', 'hidden_remark')
__SQL_END__

    $list_transcripts->execute($attrib_pattern);

    my %transcripts;
    my %values;

    my $count = 0;
    my $out_format = "%s\t%s\t%s\t%s\t%s\t%s\t%s\n";
    printf( $out_format,
	    "Chromosome", "Gene name", "stable id",
	    "Transcript name", "stable ID",
	    "Code", "Attribute" ) if $opts->{verbose};
    
    TS_ATTR: while (my ($gid, $gene_sid, $gene_name, 
                        $tid, $transcript_sid, $transcript_name,
                        $attrib_type_id, $attrib_code, $attrib_value,
                        $seq_region_name) = $list_transcripts->fetchrow()) {

        my $duplicates;
        if (my $prev = $transcripts{$attrib_code}->{$tid}) {
            carp "Already seen ", $attrib_code, " for transcript ", $transcript_sid;
            $duplicates = ++$prev->{duplicates};
        }

        $transcripts{$attrib_code}->{$tid} = {
            gene_id => $gid,
            transcript_id => $tid,
            sid   => $transcript_sid,
            atid  => $attrib_type_id,
            code  => $attrib_code,
            value => $attrib_value,
            duplicates => $duplicates, # yuk - shouldn't be throwing away prev
        };

        ++$values{$attrib_code}->{$attrib_value};
        ++$count;

        printf( $out_format,
                $seq_region_name, $gene_name, $gene_sid,
		$transcript_name, $transcript_sid,
		$attrib_code, $attrib_value,
            ) if $opts->{verbose};

    } # TS_ATTR

    printf "Total transcripts: %d\n", $count if $opts->{total};

    return ( \%transcripts, \%values );
}

sub summarise_variants {
    my ($title, $values, $vocab) = @_;
    my %summary;
    foreach my $code (qw(remark hidden_remark)) {
        printf("%s values for %s:\n", $title, $code) unless $opts->{quiet};
        foreach my $value (sort keys %{$values->{$code}}) {
            my $hit = ' ';
            if ($vocab and $vocab eq $value and $code eq 'remark') {
                $hit = '*';
                $summary{hit}->{$code}++;
            } else {
                $summary{miss}->{$code}++;
            }
            printf(" %4d %s '%s'\n", $values->{$code}->{$value}, $hit, $value) unless $opts->{quiet};
        }
    }
    return \%summary;
}

sub identify_warnings {
    my ($genes, $transcripts) = @_;

    my $branches = {
        locus      => $genes,
        transcript => $transcripts,
    };

    my @list;
    my %summary;

    foreach my $branch (sort keys %$branches) {
        foreach my $code (qw(remark hidden_remark)) {
            my $items = $branches->{$branch}->{$code};
            foreach my $id (keys %$items) {
                my $item = $items->{$id};
                if ($item->{duplicates}) {
                    push @list, sprintf("%s: duplicate entries (%d extras) on %s",
                                        $item->{sid}, $item->{duplicates}, $code);
                    ++$summary{duplicates}->{$branch}->{$code};
                }
            }
        }
    }

    return {
        list    => \@list,
        summary => \%summary,
    };
}

sub show_warnings {
    my $warnings = shift;
    foreach my $w (@{$warnings->{list}}) {
        print "$w\n";
    }
    1;
}

sub plan_update_actions {
    my ($correct_value, $items, $wrong_branch_items) = @_;

    my %actions = ( insert => [], update => [], delete => [] );

    # 'remark' items have the correct attribute code already
    #
  REMARK: foreach my $id (keys %{$items->{remark}}) {
      my $item = $items->{remark}->{$id};

      next REMARK if $item->{value} eq $correct_value;

      if (skip_match($item->{value}, $correct_value)) {

          printf("%s: skipping remark '%s'\n", $item->{sid}, $item->{value}) unless $opts->{quiet};
          next REMARK;
      }

      $item->{new_value} = $correct_value;
      $item->{new_code}  = 'remark';

      if (retain_match($item->{value}, $correct_value)) {

          # Leave the long tag and add a new tag
          printf("%s: leaving long remark, adding cv remark\n", $item->{sid}) unless $opts->{quiet};
          push @{$actions{insert}}, $item;
          next REMARK;
      }

      # If we get here, update the tag
      push @{$actions{update}}, $item;

  }

  HIDDEN_REMARK: foreach my $id (keys %{$items->{hidden_remark}}) {
      my $item = $items->{hidden_remark}->{$id};

      if (skip_match($item->{value}, $correct_value)) {

          printf("%s: skipping hidden_remark '%s'\n", $item->{sid}, $item->{value}) unless $opts->{quiet};
          next HIDDEN_REMARK;
      }

      $item->{new_value} = $correct_value;
      $item->{new_code}  = 'remark';

      if ($items->{remark}->{$id}) {

          # There's already a remark, which will be fixed if necessary above

          if (retain_match($item->{value}, $correct_value)) {

              # Leave this long hidden_remark tag
              printf("%s: leaving long hidden_remark, already cv remark\n", $item->{sid}) unless $opts->{quiet};

          } else {

              # Delete the hidden_remark tag
              printf("%s: deleting hidden_remark, already cv remark\n", $item->{sid}) unless $opts->{quiet};
              push @{$actions{delete}}, $item;

          }


      } else {

          if (retain_match($item->{value}, $correct_value)) {

              # Leave the long hidden_remark tag and insert a remark tag
              printf("%s: leaving long hidden_remark, adding cv remark\n", $item->{sid}) unless $opts->{quiet};
              push @{$actions{insert}}, $item;

          } else {

              # Move the hidden_remark tag to remark
              push @{$actions{update}}, $item;

          }
      }
     
  }
    return \%actions;
}

sub plan_ts_to_gene_actions {
    my ($correct_value, $transcripts, $gene_actions, $gene_matches) = @_;

    my %actions = ( delete => [] );

    # It doesn't matter whether hidden or not on wrong branch
    #
    CODE: foreach my $code (qw(remark hidden_remark)) {

        ITEM: foreach my $id (keys %{$transcripts->{$code}}) {

            my $item = $transcripts->{$code}->{$id};

            if (skip_match($item->{value}, $correct_value)) {

                printf("%s: skipping %s '%s' (in ts_to_gene)\n", $item->{sid}, $code, $item->{value})
                    unless $opts->{quiet};
                next ITEM;
            }

            $item->{new_value} = $correct_value;
            $item->{new_code}  = 'remark';

            # Add a tag on the other branch
            unless ($gene_matches->{$item->{gene_id}}) {
                push @{$gene_actions->{insert}}, $item;
                $gene_matches->{$item->{gene_id}}++; # avoid duplicate inserts
            }

            if (retain_match($item->{value}, $correct_value)) {

                # Leave the long tag
                printf("%s: leaving long %s on transcript\n", $item->{sid}, $code) unless $opts->{quiet};

            } else {

                # Delete the tag
                push @{$actions{delete}}, $item;

            }

        } # ITEM

    } # CODE

    return \%actions;
}

# Exceptions to be left alone
#
sub skip_match {
    my ($value, $correct_value) = @_;

    if ($value =~ /
                     \?   # a real question mark
                     \s*  # followed by optional white space
                     $    # at the end of the value
                  /x) {
        return 1;
    }

    if ($opts->{ignore}) {
        my @matches = split(/,/, $opts->{ignore});
        my @regexps = map { sql_to_perl_regexp($_) } @matches;
        if (grep { $value =~ /$_/ } @regexps) {
            return 1;
        }
    }

    return 0;                   # do not skip by default
}

sub retain_match {
    my ($value, $correct_value) = @_;

    # do not retain if no more than max_slop longer than correct value
    return 0 if length($value) <= (length($correct_value) + $opts->{max_slop});

    if ($opts->{unkeep}) {
        my @matches = split(/,/, $opts->{unkeep});
        my @regexps = map { sql_to_perl_regexp($_) } @matches;
        if (grep { $value =~ /$_/ } @regexps) {
            return 0;
        }
    }

    return 1;                   # retain by default
}

sub identify_ts_where_gene_attrib_exists {
    my ($transcripts, $genes) = @_;
    my %gene_matches;

    foreach my $code (qw(remark hidden_remark)) {
        foreach my $id (keys %{$transcripts->{$code}}) {

            my $item = $transcripts->{$code}->{$id};

            my $r_gene = $genes->{remark}->{$item->{gene_id}};
            my $hr_gene = $genes->{hidden_remark}->{$item->{gene_id}};

            if ($r_gene or $hr_gene) {
                my $gsid = $r_gene->{sid} || $hr_gene->{sid};
                printf("%s: already locus remark on %s\n", $item->{sid}, $gsid) unless $opts->{quiet};
                $gene_matches{$item->{gene_id}}++;
            }
        }
    }

    return \%gene_matches;
}

sub implement_actions {
    my ($dba, $actions, $type, $dry_run) = @_;

    my %summary;

    my $inserts = $actions->{insert};
    if ($inserts and @$inserts) {
        do_insert($dba, $inserts, $type, $dry_run);
        $summary{insert} = scalar @$inserts;
    }

    foreach my $a_type (qw(update delete)) {
        my $action_list = $actions->{$a_type};
        if ($action_list and @$action_list) {
            do_composite($dba, $action_list, $type, $a_type, $dry_run);
            $summary{$a_type} = scalar @$action_list;
        }
    }

    return \%summary;
}

sub do_insert {
    my ($dba, $list, $type, $dry_run) = @_;

    tell_db_action($list, $type, 'insert', $dry_run);

    my $sql;
    unless ($dry_run) {
        $sql = $sql_tab{$type}->{insert};
    }

    print "  SQL: $sql\n" if $sql and $opts->{debug};

    my $sth;
    $sth = $dba->dbc->prepare($sql) if $sql;
    my $total_rows = 0;

    foreach my $item (@$list) {
        $item->{new_atid} = get_attrib_type_id($dba, $item->{new_code}) unless $item->{new_atid};

        my @args = ( $item->{$sql_tab{$type}->{id_tag}}, $item->{new_atid}, $item->{new_value} );
        tell_db_item($item, @args);
        my $count = 0;
        $count = $sth->execute(@args) if $sql;
        close_tell_db_item($item, $count);
        $total_rows += $count;
    }

    return;
}

sub do_composite {
    my ($dba, $list, $type, $action, $dry_run) = @_;

    tell_db_action($list, $type, $action, $dry_run);

    my $sql;
    if ($dry_run) {
        $sql = $sql_tab{$type}->{select};
    } else {
        $sql = $sql_tab{$type}->{$action};
    }

    my $where = $sql_tab{$type}->{where};
    $sql =~ s/__WHERE__/$where/;

    print "  SQL: $sql\n" if $opts->{debug};

    my $sth = $dba->dbc->prepare($sql);
    my $total_rows = 0;

    foreach my $item (@$list) {
        $item->{new_atid} = get_attrib_type_id($dba, $item->{new_code}) unless $item->{new_atid};

        my @args = ( $item->{$sql_tab{$type}->{id_tag}}, $item->{atid}, $item->{value} );
        unless ($dry_run) {
            if ($action eq 'update') {
                unshift @args, ($item->{new_atid}, $item->{new_value});
            }
        }
        tell_db_item($item, @args);
        my $count = $sth->execute(@args);
        close_tell_db_item($item, $count);
        $total_rows += $count;
    }

    printf("  Total %d rows\n", $total_rows) unless $opts->{quiet};
    return $total_rows;
}

{
    my %attrib_type_cache = ();
    my $attrib_type_sth;

    sub get_attrib_type_id {
        my ($dba, $code) = @_;

        return $attrib_type_cache{$code} if exists $attrib_type_cache{$code};

        $attrib_type_sth ||= $dba->dbc->prepare(<<'__SQL_END__');
            SELECT attrib_type_id
            FROM   attrib_type
            WHERE  code = ?
__SQL_END__

        $attrib_type_sth->execute($code);
        my ( $atid ) = $attrib_type_sth->fetchrow_array;

        return $attrib_type_cache{$code} = $atid;
    }

}

sub tell_db_action {
    my ($list, $type, $action, $dry_run) = @_;
    return if $opts->{quiet};
    printf("%s: %s %d items %s\n",
           $sql_tab{$type}->{title}, $action, scalar @$list,
           $dry_run ? '[dry run]' : ''
        );
    return;
}

sub tell_db_item {
    my ($item, @args) = @_;
    return unless $opts->{verbose};
    printf("  %s [%s:%s]>[%s:%s] (%s) : ",
           $item->{sid}, 
           $item->{code}, $item->{value},
           $item->{new_code}, $item->{new_value},
           join(', ', map { "'$_'" } @args),
        );
    return;
}

sub close_tell_db_item {
    my ($item, $count) = @_;
    return unless $opts->{verbose};
    printf("did %s row%s\n", $count, $count == 1 ? '' : 's');
    return;
}

__END__

=head1 NAME - normalise_cv_attributes.pl

=head1 SYNOPSIS

normalise_cv_attributes -dataset <DATASET NAME> -attrib <ATTRIB PATTERN> 
                        [-unkeep <VOCAB1>[,<VOCAB2>...]] [-maxslop 3]
                        [-ignore <PATTERN1>[,<PATTERN2>...]]
                        [-[no]dryrun] [-summarise [<FILE>]]
                        [-quiet] [-verbose] [-debug] [-total]
                        [-output <FILNAME>]
=head1 DESCRIPTION

Checks for, and optionally fixes up, transcript and gene attributes which
should come from the relevant controlled vocabulary. The attrib pattern is
matched against the locus and transcript controlled vocabulary to find the
canonical version. 

Attribute values matching '-ignore' patterns are left alone and not
considered further.

Wrong versions which match the pattern are corrected, moved from 
type 'hidden_remark' to 'remark' if necessary, and from transcript to
gene if necessary.

The 'wrong' matches must be no more than maxslop (default 3) characters 
longer than the correct version to be replaced. If longer, the long 'wrong'
match will be retained but a controlled-vocab tag will be added.

If there are long matches which should be replaced rather than
retained-and-augmented, these can be specified via -unkeep. See the example
below, which ensures that 'readonly_transcript' is replaced by 'readonly'.

The attribute value can and normally should contain SQL wildcards.

=head1 EXAMPLE

  normalise_cv_attributes.pl --dataset=mouse --attrib='frag%loc%'
  normalise_cv_attributes.pl --dataset=zebrafish --attrib='read%only%' \
                             --unkeep='readonly_transcript' --nodryrun

=head1 AUTHOR

Michael Gray B<email> mg13@sanger.ac.uk

