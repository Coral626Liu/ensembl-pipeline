#
# Written by Eduardo Eyras
#
# Copyright GRL/EBI 2002
#
# You may distribute this module under the same terms as perl itself
#
# POD documentation - main docs before the code

=pod

=head1 NAME

Bio::EnsEMBL::Pipeline::RunnableDB::PseudoGeneFinder;

=head1 SYNOPSIS

my $exonerate2genes = Bio::EnsEMBL::Pipeline::RunnableDB::PseudoGeneFinder->new(
                              -db         => $refdb,
			      -input_id   => \@sequences,
			      -rna_seqs   => \@sequences,
			      -analysis   => $analysis_obj,
			      -database   => $EST_GENOMIC,
			      -options    => $EST_EXONERATE_OPTIONS,
			     );
    

$exonerate2genes->fetch_input();
$exonerate2genes->run();
$exonerate2genes->output();
$exonerate2genes->write_output(); #writes to DB

=head1 DESCRIPTION

This object contains the logic for (processed) pseudogene finding.
It is based on the alignment of cDNAs on the genome.
For every cDNA sequence, it will try to detect the locations
for processed pseudogenes with similarity to the cDNA sequence.
For the alignments we use Exonerate (G. Slater).
Potential processed pseudogene loci are test further for
lack of homology with other genomes. The tests carried out are the following:

* whether the supporting evidence is found spliced elsewhere in the genome - processed pseudogenes 
  represent an unspliced copy of a functional transcript.
  This is the first test performed on the alignments.
 
* lack of introns, i.e. single exon transcripts
  Using the ensembl representation, this means we are looking for
  transcripts with >=0 introns such that all the introns are frameshifts.

* presence of a poly A tail downstream of the disrupted open reading frame
 
* absence of methionine at the start of the predicted translation
  This is tricky to test with cDNAs - we will find an alternative for this

* whether there is sequence similarity in homologous regions in other species - 
  most of the detectable processed pseudogenes have appeared 
  after speciation, hence they are independently integrated in 
  the genome and therefore unlikely to have any sequence similarity in homologous regions.

  For this we will need a compara database with dna-dna alignments (only)

We found that the strongest signals for processed pseudogenes are for
single-exon predictions with frameshifts, which are based on protein
evidence that is spliced elsewhere in the genome and that have no
sequence similarity in the homologous region in other genomes.

=head1 CONTACT

Post general queries to B<ensembl-dev@ebi.ac.uk>

=head1 APPENDIX

The rest of the documentation details each of the object methods.
Internal methods are usually preceded with a _

=cut

package Bio::EnsEMBL::Pipeline::RunnableDB::PseudoGeneFinder;

use strict;
use Bio::EnsEMBL::Pipeline::RunnableDB;
use Bio::EnsEMBL::Pipeline::Runnable::NewExonerate;
use Bio::EnsEMBL::Pipeline::DBSQL::DenormGeneAdaptor;
use Bio::EnsEMBL::DnaDnaAlignFeature;
use Bio::EnsEMBL::Exon;
use Bio::EnsEMBL::Transcript;
use Bio::EnsEMBL::DBSQL::DBAdaptor;
use Bio::EnsEMBL::Gene;
use Bio::EnsEMBL::Pipeline::Tools::TranscriptUtils;
use Bio::EnsEMBL::Pipeline::Config::PseudoGenes::PseudoGenes;
use Bio::EnsEMBL::DBSQL::DBAdaptor;

use vars qw(@ISA);

@ISA = qw (Bio::EnsEMBL::Pipeline::RunnableDB);

sub new {
  my ($class,@args) = @_;
  my $self = $class->SUPER::new(@args);
  
  ############################################################
  # SUPER::new(@args) has put the refdb in $self->db()
  #

  my ($database, $rna_seqs, $query_type, $target_type, $exonerate, $options) =  
      $self->_rearrange([qw(
			    DATABASE 
			    RNA_SEQS
			    QUERY_TYPE
			    TARGET_TYPE
			    EXONERATE
			    OPTIONS
			    )], @args);
  
  # must have a query sequence
  unless( @{$rna_seqs} ){
      $self->throw("ExonerateToGenes needs a query: @{$rna_seqs}");
  }
  $self->rna_seqs(@{$rna_seqs});
  
  # you can pass a sequence object for the target or a database (multiple fasta file);
  if( $database ){
      $self->database( $database );
  }
  else{
      $self->throw("ExonerateToGenes needs a target - database: $database");
  }
  
  # Target type: dna  - DNA sequence
  #              protein - protein sequence
  if ($target_type){
      $self->target_type($target_type);
  }
  else{
    print STDERR "Defaulting target type to dna\n";
    $self->target_type('dna');
  }
  
  # Query type: dna  - DNA sequence
  #             protein - protein sequence
  if ($query_type){
    $self->query_type($query_type);
  }
  else{
    print STDERR "Defaulting query type to dna\n";
    $self->query_type('dna');
  }


  # can choose which exonerate to use
  $self->exonerate($EXONERATE);
  
  # can add extra options as a string
  if ($options){
    $self->options($options);
  }
  return $self;
}

############################################################

sub fetch_input {
  my( $self) = @_;
  
  my @sequences = $self->rna_seqs;
  my $target;
  if ($self->database ){
    $target = $self->database;
  }
  else{
    $self->throw("sorry, it can only run with a database");
  }
  
  my @chr_names = $self->get_chr_names;

  foreach my $chr_name ( @chr_names ){
    my $database = $target."/".$chr_name.".fa";
    
    # check that the file exists:
    if ( -s $database){
      
      #print STDERR "creating runnable for target: $database\n";
      my $runnable = Bio::EnsEMBL::Pipeline::Runnable::NewExonerate
	->new(
	      -database    => $database,
	      -query_seqs  => \@sequences,
	      -exonerate   => $self->exonerate,
	      -options     => $self->options,
	      -target_type => $self->target_type,
	      -query_type  => $self->query_type,
	     );
      $self->runnables($runnable);
    }
    else{
      $self->warn("file $database not found. Skipping");
    }
  }
}

############################################################

sub run{
  my ($self) = @_;
  my @results;
  
  ############################################################
  # align the cDNAs with Exonerate
  $self->throw("Can't run - no funnable objects") unless ($self->runnables);
  foreach my $runnable ($self->runnables){
      
    # run the funnable
    $runnable->run;  
    
    # store the results
    my @results_here = $runnable->output;
    push ( @results, @results_here );
    print STDERR scalar(@results_here)." matches found in ".$runnable->database."\n";
    
  }
  
  ############################################################
  # filter the output to get the candidate pseudogenes
  my @filtered_results = $self->filter_output(@results);
  
  ############################################################
  # make genes/transcripts
  my @genes = $self->make_genes(@filtered_results);
  
  ############################################################
  # print out the results:
  foreach my $gene (@genes){
    foreach my $trans (@{$gene->get_all_Transcripts}){
      Bio::EnsEMBL::Pipeline::Tools::TranscriptUtils->_print_Evidence($trans);
    }
  }
  
 
  ############################################################
  # test for homology
  my @processed_pseudogenes = $self->test_homology( @genes );
 
  ############################################################
  # check that pseudogenes are not overlapping each other
  my @final_genes = $self->check_for_overlap( @processed_pseudogenes );

  ############################################################
  # need to convert coordinates
  my @mapped_genes = $self->convert_coordinates( @final_genes );
  
  ############################################################
  # store the results
  unless ( @mapped_genes ){
    print STDERR "No genes stored - exiting\n";
    exit(0);
  }
  $self->output(@mapped_genes);
}

############################################################
# this method will collect all the alignments for each
# cDNA sequence and will try to get the potential processed
# pseudogenes out of them. The logic is as follows: 
# If there is an alignment for which all the introns are in fact frameshifts
# (or there is no introns) and there is a equal or better spliced alignment
# elsewhere in the genome, we consider that a potential processed pseudogene.

sub filter_output{
  my ($self,@results) = @_;
  
  # results are Bio::EnsEMBL::Transcripts with exons and supp_features  
  my @potential_processed_pseudogenes;

  ############################################################
  # collect the alignments by cDNA identifier
  my %matches;
  foreach my $transcript (@results ){
    my $id = $self->_evidence_id($transcript);
    push ( @{$matches{$id}}, $transcript );
  }
  
  ############################################################
  # sort the alignments by coverage - number of exons - percentage identity
  my %matches_sorted_by_coverage;
  my %selected_matches;
 RNA:
  foreach my $rna_id ( keys( %matches ) ){
    
    @{$matches_sorted_by_coverage{$rna_id}} = 
      sort { my $result = ( $self->_coverage($b) <=> $self->_coverage($a) );
	     if ( $result){
	       return $result;
	     }
	     else{
	       my $result2 = ( scalar(@{$b->get_all_Exons}) <=> scalar(@{$a->get_all_Exons}) );
	       if ( $result2 ){
		 return $result2;
	       }
	       else{
		 return ( $self->_percent_id($b) <=> $self->_percent_id($a) );
	       }
	     }
	   }    @{$matches{$rna_id}} ;
    
    my $count = 0;
    my $is_spliced = 0;
    my $max_score;
    my $perc_id_of_best;
    my $best_has_been_seen = 0;
    
    print STDERR "####################\n";
    print STDERR "Matches for $rna_id:\n";
    
  TRANSCRIPT:
    foreach my $transcript ( @{$matches_sorted_by_coverage{$rna_id}} ){
      $count++;
      unless ($max_score){
	$max_score = $self->_coverage($transcript);
      }
      unless ( $perc_id_of_best ){
	$perc_id_of_best = $self->_percent_id($transcript);
      }
      
      Bio::EnsEMBL::Pipeline::Tools::TranscriptUtils->_print_Transcript($transcript);
      
      my $score   = $self->_coverage($transcript);
      my $perc_id = $self->_percent_id($transcript);
      
      my @exons  = sort { $a->start <=> $b->start } @{$transcript->get_all_Exons};
      my $start  = $exons[0]->start;
      my $end    = $exons[$#exons]->end;
      my $strand = $exons[0]->strand;
      my $seqname= $exons[0]->seqname;
      $seqname   =~ s/\.\d+-\d+$//;
      my $extent = $seqname.".".$start."-".$end;
      
      my $label;
      if ( $count == 1 ){
	$label = 'best_match';
      }
      elsif ( $count > 1 
	      && $is_spliced 
	      && !Bio::EnsEMBL::Pipeline::Tools::TranscriptUtils->is_spliced( $transcript )
	    ){
	$label = 'potential_processed_pseudogene';
      }
      else{
	$label = $count;
      }
      
      ############################################################
      # put flag if the first one is spliced
      if ( $count == 1 && Bio::EnsEMBL::Pipeline::Tools::TranscriptUtils->is_spliced( $transcript ) ){
	$is_spliced = 1;
      }
      
      my $accept;
      ############################################################
      # if we use the option best in genome:
      if ( $BEST_IN_GENOME ){
	if ( ( $score  == $max_score && 
	       $score >= $MIN_COVERAGE && 
	       $perc_id >= $MIN_PERCENT_ID
	     )
	     ||
	     ( $score == $max_score &&
	       $score >= (1 + 5/100)*$MIN_COVERAGE &&
	       $perc_id >= ( 1 - 3/100)*$MIN_PERCENT_ID
	     )
	   ){
	  ############################################################
	  # if we have an unspliced alignment which which has similarity with a
	  # spliced alignment we have a potential processed pseudogene:	  
	  if ( $count > 1 
	       && $is_spliced 
	       && !Bio::EnsEMBL::Pipeline::Tools::TranscriptUtils->is_spliced( $transcript )
	     ){
	    $accept = 'YES';
	    push( @potential_processed_pseudogenes, $transcript);
	  }
	  else{
	    $accept = 'NO';
	  }
	}
	############################################################
	# don't accept if below threshold
	else{
	  $accept = 'NO';
	}
	print STDERR "match:$rna_id coverage:$score perc_id:$perc_id extent:$extent strand:$strand comment:$label accept:$accept\n";
	
	print STDERR "--------------------\n";
	
      }
      ############################################################
      # we might want to keep more than just the best one
      else{
	
	############################################################
	# we keep anything which is 
	# within the 2% of the best score
	# with score >= $MIN_COVERAGE and percent_id >= $MIN_PERCENT_ID
	if ( ( $score >= (0.98*$max_score) && 
	       $score >= $MIN_COVERAGE && 
	       $perc_id >= $MIN_PERCENT_ID )
	     ||
	     ( $score >= (0.98*$max_score) &&
	       $score >= (1 + 5/100)*$MIN_COVERAGE &&
	       $perc_id >= ( 1 - 3/100)*$MIN_PERCENT_ID
	     )
	   ){
	  
	  ############################################################
	  # non-best matches are kept only if they are not unspliced with the
	  # best match being spliced - otherwise they could be processed pseudogenes
	  if ( $count > 1 
	       && $is_spliced 
	       && !Bio::EnsEMBL::Pipeline::Tools::TranscriptUtils->is_spliced( $transcript )
	     ){
	    $accept = 'YES';
	    push( @potential_processed_pseudogenes, $transcript);
	  }
	  else{
	    $accept = 'NO';
	  }
	}
	else{
	  $accept = 'NO';
	}
	print STDERR "match:$rna_id coverage:$score perc_id:$perc_id extent:$extent strand:$strand comment:$label accept:$accept\n";
	
	print STDERR "--------------------\n";
      }
    }
  }
  
  return @potential_processed_pseudogenes;
}

############################################################

sub _evidence_id{
    my ($self,$tran) = @_;
    my @exons = @{$tran->get_all_Exons};
    my @evi = @{$exons[0]->get_all_supporting_features};
    return $evi[0]->hseqname;
}

############################################################

sub _coverage{
    my ($self,$tran) = @_;
    my @exons = @{$tran->get_all_Exons};
    my @evi = @{$exons[0]->get_all_supporting_features};
    return $evi[0]->score;
}

############################################################

sub _percent_id{
    my ($self,$tran) = @_;
    my @exons = @{$tran->get_all_Exons};
    my @evi = @{$exons[0]->get_all_supporting_features};
    return $evi[0]->percent_id;
}

############################################################

sub write_output{
  my ($self,@output) = @_;

  ############################################################
  # here is the only place where we need to create a db adaptor
  # for the database where we want to write the genes
  my $db = new Bio::EnsEMBL::DBSQL::DBAdaptor(
					      -host             => $EST_DBHOST,
					      -user             => $EST_DBUSER,
					      -dbname           => $EST_DBNAME,
					      -pass             => $EST_DBPASS,
					      );

  # Get our gene adaptor, depending on the type of gene tables
  # that we are working with.
  my $gene_adaptor;

  if ($EST_USE_DENORM_GENES) {
    $gene_adaptor = Bio::EnsEMBL::Pipeline::DBSQL::DenormGeneAdaptor->new($db);
  } else {
    $gene_adaptor = $db->get_GeneAdaptor;  
  } 



  unless (@output){
      @output = $self->output;
  }
  foreach my $gene (@output){
      print STDERR "gene is a $gene\n";
      print STDERR "about to store gene ".$gene->type." $gene\n";
      foreach my $tran (@{$gene->get_all_Transcripts}){
	Bio::EnsEMBL::Pipeline::Tools::TranscriptUtils->_print_Transcript($tran);
      }
      
      eval{
	$gene_adaptor->store($gene);
      };

      if ($@){
	  $self->warn("Unable to store gene!!\n$@");
      }
  }
}

############################################################

sub make_genes{
  my ($self,@transcripts) = @_;
  
  my @genes;
  my $slice_adaptor = $self->db->get_SliceAdaptor;
  my $gene;
  my $checked_transcript;
  foreach my $tran ( @transcripts ){
    $gene = Bio::EnsEMBL::Gene->new();
    $gene->analysis($self->analysis);
    $gene->type($self->analysis->logic_name);
    
    ############################################################
    # put a slice on the transcript
    my $slice_id      = $tran->start_Exon->seqname;
    my $chr_name;
    my $chr_start;
    my $chr_end;
    #print STDERR " slice_id = $slice_id\n";
    if ($slice_id =~/$INPUTID_REGEX/){
      $chr_name  = $1;
      $chr_start = $2;
      $chr_end   = $3;
      #print STDERR "chr: $chr_name start: $chr_start end: $chr_end\n";
    }
    else{
      $self->warn("It cannot read a slice id from exon->seqname. Please check.");
    }
    my $slice = $slice_adaptor->fetch_by_chr_start_end($chr_name,$chr_start,$chr_end);
    foreach my $exon (@{$tran->get_all_Exons}){
      $exon->contig($slice);
      foreach my $evi (@{$exon->get_all_supporting_features}){
	$evi->contig($slice);
	$evi->analysis($self->analysis);
      }
    }
    
    $checked_transcript = $self->check_strand( $tran );
    $gene->add_Transcript($checked_transcript);
    push( @genes, $gene);
  }
  return @genes;
}

############################################################

sub convert_coordinates{
  my ($self,@genes) = @_;
  
  my $rawcontig_adaptor = $self->db->get_RawContigAdaptor;
  my $slice_adaptor     = $self->db->get_SliceAdaptor;
  
  my @transformed_genes;
 GENE:
  foreach my $gene (@genes){
  TRANSCRIPT:
    foreach my $transcript ( @{$gene->get_all_Transcripts} ){
      
      # is it a slice or a rawcontig?
      my $rawcontig = $rawcontig_adaptor->fetch_by_name($transcript->start_Exon->seqname);
      if ( $rawcontig ){
	foreach my $exon (@{$transcript->get_all_Exons}){
	  $exon->contig( $rawcontig);
	}
      }
      
      my $contig = $transcript->start_Exon->contig;
      
      if ( $contig && $contig->isa("Bio::EnsEMBL::RawContig") ){
	print STDERR "transcript already in raw contig, no need to transform:\n";
	Bio::EnsEMBL::Pipeline::Tools::TranscriptUtils->_print_Transcript($transcript);
	next TRANSCRIPT;
      }
      my $slice_id      = $transcript->start_Exon->seqname;
      my $chr_name;
      my $chr_start;
      my $chr_end;
      if ($slice_id =~/$EST_INPUTID_REGEX/){
	$chr_name  = $1;
	$chr_start = $2;
	$chr_end   = $3;
      }
      else{
	$self->warn("It looks that you haven't run on slices. Please check.");
	next TRANSCRIPT;
      }
      
      my $slice = $slice_adaptor->fetch_by_chr_start_end($chr_name,$chr_start,$chr_end);
      foreach my $exon (@{$transcript->get_all_Exons}){
	$exon->contig($slice);
	foreach my $evi (@{$exon->get_all_supporting_features}){
	  $evi->contig($slice);
	}
      }
    }
    
    my $transformed_gene;
    eval{
      $transformed_gene = $gene->transform;
    };
    if ( !$transformed_gene || $@ ){
      my @t        = @{$gene->get_all_Transcripts};
      my $id       = $self->_evidence_id( $t[0] );
      my $coverage = $self->_coverage( $t[0] );
      print STDERR "gene $id with coverage $coverage falls on a gap\n";
    }
    else{
      push( @transformed_genes, $transformed_gene);
    }
  }
  return @transformed_genes;
}

############################################################

sub get_chr_names{
  my ($self) = @_;
  my @chr_names;
  
  print STDERR "fetching chromosomes info\n";
  my $chr_adaptor = $self->db->get_ChromosomeAdaptor;
  my @chromosomes = @{$chr_adaptor->fetch_all};
  
  foreach my $chromosome ( @chromosomes ){
    push( @chr_names, $chromosome->chr_name );
  }
  print STDERR "retrieved ".scalar(@chr_names)." chromosome names\n";
  return @chr_names;
}
############################################################

=head2 check_splice_sites

processed pseudogenes are single-exon objects. Using dna-2-dna alignments
remains a questions of what is the correct strand for the alignment.
We try to estimate that.

=cut

sub check_strand{
  my ($self,$transcript) = @_;

  my $verbose = 0;
    
  #print STDERR "checking splice sites in transcript:\n";
  #Bio::EnsEMBL::Pipeline::Tools::TranscriptUtils->_print_Transcript($transcript);
  #Bio::EnsEMBL::Pipeline::Tools::TranscriptUtils->_print_TranscriptEvidence($transcript);
  
  my $strand = $transcript->start_Exon->strand;
  my @exons;
  if ( $strand == 1 ){
    @exons = sort { $a->start <=> $b->start } @{$transcript->get_all_Exons};
  }
  else{
    @exons = sort { $b->start <=> $a->start } @{$transcript->get_all_Exons};
  }
  my $introns  = scalar(@exons) - 1 ; 
  if ( $introns <= 0 ){
    return $transcript;
  }
  
  my $correct  = 0;
  my $wrong    = 0;
  my $other    = 0;
  
  # all exons in the transcripts are in the same seqname coordinate system:
  my $slice = $transcript->start_Exon->contig;
  
  if ($strand == 1 ){
    
  INTRON:
    for (my $i=0; $i<$#exons; $i++ ){
      my $upstream_exon   = $exons[$i];
      my $downstream_exon = $exons[$i+1];
      
      my $upstream_start = ($upstream_exon->end     + 1);
      my $upstream_end   = ($upstream_exon->end     + 2);      
      my $downstream_start = $downstream_exon->start - 2;
      my $downstream_end   = $downstream_exon->start - 1;

      #eval{
#	$upstream_site = 
#	  $slice->subseq( ($upstream_exon->end     + 1), ($upstream_exon->end     + 2 ) );
#	$downstream_site = 
#	  $slice->subseq( ($downstream_exon->start - 2), ($downstream_exon->start - 1 ) );
#      };
            
      #print STDERR "upstream $upstream_site, downstream: $downstream_site\n";
      ## good pairs of upstream-downstream intron sites:
      ## ..###GT...AG###...   ...###AT...AC###...   ...###GC...AG###.
      
      ## bad  pairs of upstream-downstream intron sites (they imply wrong strand)
      ##...###CT...AC###...   ...###GT...AT###...   ...###CT...GC###...
      
      # print STDERR "From database:\n";
#      print STDERR "strand: + upstream (".
#	($upstream_exon->end + 1)."-".($upstream_exon->end + 2 ).") = $upstream_site, downstream ".
#	  ($downstream_exon->start - 2)."-".($downstream_exon->start - 1).") = $downstream_site\n";
      
      ############################################################
      # use chr_subseq from Tim Cutts
      
      my $upstream_site   = 
	$self->get_chr_subseq($slice->chr_name, $upstream_start, $upstream_end, $strand );
      my $downstream_site = 
	$self->get_chr_subseq($slice->chr_name, $downstream_start, $downstream_end, $strand );
      
      unless ( $upstream_site && $downstream_site ){
	print STDERR "problems retrieving sequence for splice sites\n";
	next INTRON;
      }

      print STDERR "Tim's script:\n" if $verbose;
      print STDERR "strand: + upstream (".
      	($upstream_start)."-".($upstream_end).") = $upstream_site, downstream ".
        ($downstream_start)."-".($downstream_end).") = $downstream_site\n" if $verbose;

      if (  ($upstream_site eq 'GT' && $downstream_site eq 'AG') ||
	    ($upstream_site eq 'AT' && $downstream_site eq 'AC') ||
	    ($upstream_site eq 'GC' && $downstream_site eq 'AG') ){
	$correct++;
      }
      elsif (  ($upstream_site eq 'CT' && $downstream_site eq 'AC') ||
	       ($upstream_site eq 'GT' && $downstream_site eq 'AT') ||
	       ($upstream_site eq 'CT' && $downstream_site eq 'GC') ){
	$wrong++;
      }
      else{
	$other++;
      }
	} # end of INTRON
  }
  elsif ( $strand == -1 ){
    
    #  example:
    #                                  ------CT...AC---... 
    #  transcript in reverse strand -> ######GA...TG###... 
    # we calculate AC in the slice and the revcomp to get GT == good site
    
  INTRON:
    for (my $i=0; $i<$#exons; $i++ ){
      my $upstream_exon   = $exons[$i];
      my $downstream_exon = $exons[$i+1];
      my $up_site;
      my $down_site;
      
      my $up_start   = $upstream_exon->start - 2;
      my $up_end     = $upstream_exon->start - 1;
      my $down_start = $downstream_exon->end + 1;
      my $down_end   = $downstream_exon->end + 2;

      #eval{
#	$up_site = 
#	  $slice->subseq( ($upstream_exon->start - 2), ($upstream_exon->start - 1) );
#	$down_site = 
#	  $slice->subseq( ($downstream_exon->end + 1), ($downstream_exon->end + 2 ) );
#      };
       
#      ( $upstream_site   = reverse(  $up_site  ) ) =~ tr/ACGTacgt/TGCAtgca/;
#      ( $downstream_site = reverse( $down_site ) ) =~ tr/ACGTacgt/TGCAtgca/;
      	  
#      print STDERR "From database:\n";
#      print STDERR "strand: + ".
#	"upstream ($up_start-$up_end) = $upstream_site,".
#	  "downstream ($down_start-$down_end) = $downstream_site\n";
      
      ############################################################
      # use chr_subseq from Tim Cutts
      my $upstream_site   = 
	$self->get_chr_subseq($slice->chr_name, $up_start, $up_end, $strand );
      my $downstream_site = 
	$self->get_chr_subseq($slice->chr_name, $down_start, $down_end, $strand );
 
      unless ( $upstream_site && $downstream_site ){
	print STDERR "problems retrieving sequence for splice sites\n";
	next INTRON;
      }
      
      print STDERR "Tim's script:\n" if $verbose;
      print STDERR "strand: + upstream (".
	($up_start)."-".($up_end).") = $upstream_site, downstream ".
	  ($down_start)."-".($down_end).") = $downstream_site\n" if $verbose;

      
      #print STDERR "strand: - upstream $upstream_site, downstream: $downstream_site\n";
      if (  ($upstream_site eq 'GT' && $downstream_site eq 'AG') ||
	    ($upstream_site eq 'AT' && $downstream_site eq 'AC') ||
	    ($upstream_site eq 'GC' && $downstream_site eq 'AG') ){
	$correct++;
      }
      elsif (  ($upstream_site eq 'CT' && $downstream_site eq 'AC') ||
	       ($upstream_site eq 'GT' && $downstream_site eq 'AT') ||
	       ($upstream_site eq 'CT' && $downstream_site eq 'GC') ){
	$wrong++;
      }
      else{
	$other++;
      }
      
    } # end of INTRON
  }
  unless ( $introns == $other + $correct + $wrong ){
    print STDERR "STRANGE: introns:  $introns, correct: $correct, wrong: $wrong, other: $other\n";
  }
  if ( $wrong > $correct ){
    print STDERR "changing strand\n" if $verbose;
    return  $self->change_strand($transcript);
  }
  else{
    return $transcript;
  }
}

############################################################

sub get_chr_subseq{
  my ( $self, $chr_name, $start, $end, $strand ) = @_;

  my $chr_file = $EST_GENOMIC."/".$chr_name.".fa";
  my $command = "chr_subseq $chr_file $start $end |";
 
  #print STDERR "command: $command\n";
  open( SEQ, $command ) || $self->throw("Error running chr_subseq within ExonerateToGenes");
  my $seq = uc <SEQ>;
  chomp $seq;
  close( SEQ );
  
  if ( length($seq) != 2 ){
    print STDERR "WRONG: asking for chr_subseq $chr_file $start $end and got = $seq\n";
  }
  if ( $strand == 1 ){
    return $seq;
  }
  else{
    ( my $revcomp_seq = reverse( $seq ) ) =~ tr/ACGTacgt/TGCAtgca/;
    return $revcomp_seq;
  }
}


############################################################
=head2 change_strand

    this method changes the strand of the exons

=cut

sub change_strand{
    my ($self,$transcript) = @_;
    my $original_strand = $transcript->start_Exon->strand;
    my $new_strand      = (-1)*$original_strand;
    foreach my $exon (@{$transcript->get_all_Exons}){
      $exon->strand($new_strand);
      foreach my $evi ( @{$exon->get_all_supporting_features} ){
	$evi->strand($new_strand);
	$evi->hstrand( $evi->hstrand*(-1) );
      }
    }
    $transcript->sort;
    return $transcript;
}

############################################################


=head2 _get_SubseqFetcher

Prototype fast SubseqFetcher to get splice sites.

=cut

sub _get_SubseqFetcher {
    
  my ($self, $slice) = @_;
  
  if (defined $self->{'_current_chr_name'}  && 
      $slice->chr_name eq $self->{'_current_chr_name'} ){
    return $self->{'_chr_subseqfetcher'};
  } else {
    
    $self->{'_current_chr_name'} = $slice->chr_name;
    my $chr_filename = $EST_GENOMIC . "/" . $slice->chr_name . "\.fa";

    $self->{'_chr_subseqfetcher'} = Bio::EnsEMBL::Pipeline::SubseqFetcher->new($chr_filename);
  }
}



############################################################
#
# get/set methods
#
############################################################

############################################################

# must override RunnableDB::output() which is an eveil thing reading out from the Runnable objects

sub output {
  my ($self, @output) = @_;
  if (@output){
    push( @{$self->{_output} }, @output);
  }
  return @{$self->{_output}};
}

############################################################

sub runnables {
  my ($self, $runnable) = @_;
  if (defined($runnable) ){
    unless( $runnable->isa("Bio::EnsEMBL::Pipeline::RunnableI") ){
      $self->throw("$runnable is not a Bio::EnsEMBL::Pipeline::RunnableI");
    }
    push( @{$self->{_runnable}}, $runnable);
  }
  return @{$self->{_runnable}};
}

############################################################

sub rna_seqs {
  my ($self, @seqs) = @_;
  if( @seqs ) {
    unless ($seqs[0]->isa("Bio::PrimarySeqI") || $seqs[0]->isa("Bio::SeqI")){
      $self->throw("query seq must be a Bio::SeqI or Bio::PrimarySeqI");
    }
    push( @{$self->{_rna_seqs}}, @seqs);
  }
  return @{$self->{_rna_seqs}};
}

############################################################

sub genomic {
  my ($self, $seq) = @_;
  if ($seq){
    unless ($seq->isa("Bio::PrimarySeqI") || $seq->isa("Bio::SeqI")){
      $self->throw("query seq must be a Bio::SeqI or Bio::PrimarySeqI");
    }
    $self->{_genomic} = $seq ;
  }
  return $self->{_genomic};
}

############################################################

sub exonerate {
  my ($self, $location) = @_;
  if ($location) {
    $self->throw("Exonerate not found at $location: $!\n") unless (-e $location);
    $self->{_exonerate} = $location ;
  }
  return $self->{_exonerate};
}

############################################################

sub options {
  my ($self, $options) = @_;
  if ($options) {
    $self->{_options} = $options ;
  }
  return $self->{_options};
}

############################################################

sub database {
  my ($self, $database) = @_;
  if ($database) {
    $self->{_database} = $database;
  }
  return $self->{_database};
}
############################################################

sub query_type {
  my ($self, $mytype) = @_;
  if (defined($mytype) ){
    my $type = lc($mytype);
    unless( $type eq 'dna' || $type eq 'protein' ){
      $self->throw("not the right query type: $type");
    }
    $self->{_query_type} = $type;
  }
  return $self->{_query_type};
}

############################################################

sub target_type {
  my ($self, $mytype) = @_;
  if (defined($mytype) ){
    my $type = lc($mytype);
    unless( $type eq 'dna' || $type eq 'protein' ){
      $self->throw("not the right target type: $type");
    }
    $self->{_target_type} = $type ;
  }
  return $self->{_target_type};
}

############################################################





1;