# Copyright GRL & EBI 2001
# Author: Val Curwen
# Creation: 02.05.2001

# configuration information for GeneBuild scripts
# give useful keynames to things

# I've left in sample entries for the various options to hopefully make this easier to use

BEGIN {
package main;

# general parameters for database connection

%db_conf = (
#	    'dbhost'      => 'ecs1b',
	    'dbhost'      => '',

#	    'dbname'      => 'simon_dec12',
	    'dbname'      => '',

#	    'dbuser'      => 'ensadmin',
	    'dbuser'      => '',

#	    'dbpass'      => 'ensembl',
	    'dbpass'      => '',	  

# db for writing final genes to - to get round table locks
# this db needs to have clone & contig tables populated
# later we will copy over dna, pruned features etc to hand over
#	    'finaldbhost'    => 'ecs1f',
	    'finaldbhost'    => '',

#	    'finaldbname'    => 'final_genebuild',
	    'finaldbname'    => '',

#           'golden_path' => 'UCSC',
	    'golden_path' => '',
);

# parameters for ensembl-pipeline/scripts/GeneBuild/*.pl

%scripts_conf = ( 
	    # general options
#	    'runner'      => '/work2/vac/ensembl-pipeline/scripts/test_RunnableDB',
	    'runner'      => '',

#	    'tmpdir'      => '/scratch3/ensembl/vac',
	    'tmpdir'      => '',

#	    'queue'       => 'acarilong',
	    'queue'       => '',

	    # prepare_proteome options
#	    'refseq'      => '/work2/vac/TGW/Dec_gp/human_proteome/refseq.fa',
	    'refseq'      => '',

#	    'sptr'        => '/work2/vac/TGW/Dec_gp/human_proteome/sptr_minus_P17013.fa',
	    'sptr'        => '',

#	    'pfasta'      => '/work2/vac/GeneBuild/script-test/human_proteome.fa',
	    'pfasta'      => '',

	    # pmatch from below

	    # pmatch_filter options
            # pfasta from above
#	    'pmatch'      => '/work2/vac/rd-utils/pmatch',
	    'pmatch'      => '',

#           'tblastn'     => 'tblast2n',
	    'tblastn'     => '',

#	    'pm_output'   => '/work2/vac/GeneBuild/script-test/',
	    'pm_output'   => '',

#	    'fpcdir'      => '/work2/vac/data/humangenome/',
	    'fpcdir'      => '',

	    # protein2cdna options
#	    'rf_gnp'      => '/work2/vac/TGW/Dec_gp/human_proteome/refseq.gnp',
	    'rf_gnp'      => '',

#	    'sp_swiss'    => '/work2/vac/TGW/Dec_gp/human_proteome/sptr.swiss',
	    'sp_swiss'    => '',

#	    'efetch'      => '/usr/local/ensembl/bin/efetch.new', 
	    'efetch'      => '', 

#	    'cdna_pairs'  => '/work2/vac/GeneBuild/script-test/cpp.out',
	    'cdna_pairs'  => '',

#	    'cdna_seqs'   => '/work2/vac/GeneBuild/script-test/cdna_seqs.fa',
	    'cdna_seqs'   => '',

	    # options specific to Targetted runnables
#	    'targetted_runnables'   => ['TargettedGeneWise', 'TargettedGeneE2G'],
	    'targetted_runnables'   => [''],

	    # options specific to length based runnables
#	    'length_runnables'      => ['CombinedGeneBuild'],
	    'length_runnables'      => ['CombinedGeneBuild'],

#           'size'        => '5000000',
            'size'        => '5000000',

);

# seqfetch parameters - location of getseqs indices used by the RunnableDBs
%seqfetch_conf = (

#	    location of seq_index for protein sequences; if not set, will use pfetch
#	    'protein_index' => '/data/blastdb/Ensembl/swall.all',
	    'protein_index' => '',

);	    

# TargettedGeneE2G parameters
%targetted_conf = (
#	    location of seq_index for cdna sequences; if not set, will use pfetch
#	    'cdna_index' => '/data/blastdb/Ensembl/cdna_seqs.fa',
	    'cdna_index' => '',

#	    location of seq_index for human_proteome sequences - swissprot plus refseq; 
#	    if not set, will use pfetch
#	    'protein_index' => '/data/blastdb/Ensembl/human_proteome.fa',
	    'protein_index' => '',
);

# FPC_BlastMiniGenewise parameters
%similarity_conf = (
#		    type of (protein) similarity features to be got - sptr, swall, whatever
#		    'type' => 'sptr',
		    'type' => '',

#		    score threshold for selecting features for MiniGenewise
#		    'threshold' => 200,
		    'threshold' => 200,
);

# Riken_BlastMiniGenewise parameters
%riken_conf = (
#	    location of seq_index for riken protein sequences
#	    'riken_index' => '/data/blastdb/Ensembl/riken_prot',
	    'riken_index' => '',
);

# GeneBuild parameters
%genebuild_conf = (
		   'vcontig' => 0, #set to choose vc/rc building
		   'bioperldb' => 0, #set to use/not bioperl-db to fetch seq
		   'bpname'     => '', #bioperl-db database name
		   'bpuser'     => '', #bioperl-db database user
		   'bpbiodb_id' => '', #bioperl-db biodatabase_id
		   'supporting_databases' => '', #dbs for supp evidence
);

# Post gene build integrity checking script parameters
%verify_conf = (
		   'minshortintronlen'  => 7, 
		   'maxshortintronlen'  => 50, 
		   'minlongintronlen'   => 100000, 
		   'minshortexonlen'    => 3, 
		   'maxshortexonlen'    => 10, 
		   'minlongexonlen'     => 50000, 
                   'mintranslationlen'  => 10, 
		   'maxexonstranscript' => 150, 
		   'maxtranscripts'     => 10, 
                   'ignorewarnings'     => 1 
);

}

1;
