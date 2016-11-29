#!/usr/bin/perl -w

use FindBin qw($Bin);
use lib "$Bin/..";
use Parsing_Routines;
use Bad_SNPS_and_CNVS;
use Cwd 'realpath';
use Cwd;
use Getopt::Long;
use strict;

my $time = localtime;
print "Script started on $time.\n";

#Changes to the directory of the script executing;
chdir $Bin;

my $parsing = TCGA_Lib::Parsing_Routines->new;
my $Bad_SNP_CNV = TCGA_Lib::Bad_SNPS_and_CNVS->new;
my $TCGA_Pipeline_Dir = realpath("../../");
my $Analysispath = realpath("../../Analysis");

GetOptions(
    'disease|d=s' => \my $disease_abbr,#e.g. OV
    'copynumber|c=s' => \my $copynumber,#directory where copy number data was downloaded
    'affy_dir|a=s' => \my $affy_dir,#either default or user specified directory from script 1.0
    'help|h' => \my $help
) or die "Incorrect options!\n",$parsing->usage("2.0");

if($help)
{
    $parsing->usage("2.0");
}

if(!defined $disease_abbr)
{
    print "disease type was not entered!\n";
    $parsing->usage("2.0");
}
if(!defined $copynumber)
{
    print STDERR "Enter the directory where your copy number variation data was downloaded.\n";
    $parsing->usage("2.0");
}

my $RNA_Path = "$Analysispath/$disease_abbr/RNA_Seq_Analysis";

if (!(-d $RNA_Path))
{
    print "$RNA_Path does not exist. Either it was deleted, moved or the scripts required for it have not been run.\n";
    exit;
}

$affy_dir = "affy6" unless defined $affy_dir;
if(!(-d $RNA_Path/$affy_dir))
{
    print "Enter in the the directory that was specified in script 1.0 or run script 1.0 if it hasn't been run yet.\n";
    $parsing->usage("1.1"); 
}

my $SNP6_Raw_Files_Dir = "$Analysispath/$disease_abbr/SNP6/$copynumber";

my $database_path = "$TCGA_Pipeline_Dir/Database";

chdir "$RNA_Path";

print "Running zcat on GenomeWideSNP_6.cn.na35.annot.csv.zip\n";
open(F,"zcat $database_path/GenomeWideSNP_6.cn.na35.annot.csv.zip|") or die("Can't open zip for input: $!\n");
open(O,">annot_csv") or die("Can't open file for output");
while(my $r = <F>)
{
  print O $r;      
}
close(F);
close(O);

print "Running pull_bed\n";
#pull_bed(annot_csv file create from GenomeWideSNP_6.cn.na35.annot.csv.zip in the Database directory,path to cnv.hg19.bed)
$Bad_SNP_CNV->pull_bed("$RNA_Path/annot_csv","$RNA_Path/$affy_dir/cnv.hg19.bed");

`ls "$SNP6_Raw_Files_Dir" > cnv_file_names.txt`;

#pull normal CNV samples
print "Now running pull_normal\n";
#pull_normal(file containing a list of cnv files,output file)
$Bad_SNP_CNV->pull_normal("cnv_file_names.txt","normal_cnv.txt");

#move barcode from the cds_sorted directory into a file called have_cd
print "Now running mv_bcode for cds_sorted_dir\n";
`ls $RNA_Path/cds_sorted > cds_sorted_dir`;
#mv_bcode(file containing list of bed files from the cds_sorted directory,output file)
$Bad_SNP_CNV->mv_bcode("cds_sorted_dir","have_cd");

print "Now running hv_cd\n";
$parsing->vlookup("normal_cnv.txt",3,"have_cd",2,1,"y","have_hv_cd");
#hv_cd(output file from vlookup,output file)
$Bad_SNP_CNV->hv_cd("have_hv_cd","hv_cd_out");
print("Now running dump_non_01_10_11\n");
#dump_non_01_10_11(output file from hv_cd,output file)
$Bad_SNP_CNV->dump_non_01_10_11("hv_cd_out","look.have_cd");

print "All jobs have finished for $disease_abbr.\n";

$time = localtime;
print "Script finished on $time.\n";

exit;