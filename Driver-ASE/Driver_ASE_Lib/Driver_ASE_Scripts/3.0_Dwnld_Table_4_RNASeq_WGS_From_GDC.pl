#!/usr/bin/perl -w

use strict;
use FindBin qw($Bin);
use lib "$Bin/..";
use Parsing_Routines;
use Dwnld_WGS_RNA;
use File::Copy;
use Getopt::Long;
use autodie;
use Cwd 'realpath';
use File::Basename;

my $time = localtime;
print "Script started on $time.\n";

#Changes to the directory of the script executing;
chdir $Bin;

my $parsing = Driver_ASE_Lib::Parsing_Routines->new;
my $dwnld = Driver_ASE_Lib::Dwnld_WGS_RNA->new;

GetOptions(
    'disease|d=s' => \my $disease_abbr,#e.g. OV or OV,PRAD
    'exp_strat|e=s' => \my $Exp_Strategy,#e.g. WGS RNA-Seq
    'command|c=s' => \my $dwnld_cmd,#curl or aria2c (if aria or aria2 is entered, it changes them to aria2c as that is the command)
    'help|h' => \my $help
) or die "Incorrect options!\n",$parsing->usage("3.0_table");

#If -h was specified on the command line then the usage of the program will be printed.
if($help)
{
    $parsing->usage("3.0_table");
}

#If the disease abbr or file type was not specified then an error will be printed and the usage of the program will be shown.
if(!defined $disease_abbr || !defined $Exp_Strategy)
{
    print "disease type and/or experimental strategy was not entered!\n";
    $parsing->usage("3.0_table");
}

if ($Exp_Strategy ne "RNA-Seq" and $Exp_Strategy ne "WGS")
{
    print STDERR "The file type entered must be RNA-Seq or WGS as these are what this pipeline deals with\n";
    exit;
}

#Defaults to curl if no download command was specified
if (!defined $dwnld_cmd)
{
    $dwnld_cmd = "curl";
    print "No download command specified, defaulting to $dwnld_cmd\n";
}
elsif ($dwnld_cmd eq "curl" or $dwnld_cmd eq "aria2c")
{
    print "Using $dwnld_cmd as the download command.\n";
}
elsif($dwnld_cmd eq "aria" or $dwnld_cmd eq "aria2")
{
    print "Using $dwnld_cmd for the download command.\n";
    $dwnld_cmd = "aria2c";
}
elsif($dwnld_cmd eq "curl")
{
    print "$dwnld_cmd entered, changing it to ";
    $dwnld_cmd = "aria2c";
    print "$dwnld_cmd.\n";
}
else
{
    print "The download command must be either curl or aria2c.\n";
    exit;
}

my $Driver_ASE_Dir = realpath("../../");
#Directory where all analysis data will be going in.
mkdir "$Driver_ASE_Dir/Analysis" unless(-d "$Driver_ASE_Dir/Analysis");
my $Analysispath = realpath("../../Analysis");
my $Table_Dir = "tables";
my $tables = "$disease_abbr\_tables";

my @disease;
if($disease_abbr =~ /,/)
{
    @disease = split(",",$disease_abbr);
}
else
{
   @disease = $disease_abbr; 
}

chdir "$Analysispath";

#defaults to a directory if no output directory was specified in the command line.
my $Input_Dir;
if($Exp_Strategy eq "RNA-Seq")
{   
   `mkdir -p "$Table_Dir/rna"` unless(-d "$Table_Dir/rna");
   $Input_Dir = "$Table_Dir";
   $Table_Dir .= "/rna";
}
elsif($Exp_Strategy eq "WGS")
{
   `mkdir -p "$Table_Dir/wgs"` unless(-d "$Table_Dir/wgs");
   $Input_Dir = "$Table_Dir";
   $Table_Dir .= "/wgs";
}
else
{
    print STDERR "File type must be either RNA-Seq or WGS.\n";
    exit;
}

$Table_Dir = realpath("$Table_Dir");

foreach my $disease_abbr(@disease)
{
    #Makes the directory where all of the results will be processed and stored.
    `mkdir "$Analysispath/$disease_abbr"` unless(-d "$Analysispath/$disease_abbr");
 
    chdir "$Table_Dir";
    
    #Checks if a table file does not exist in the tables directory of the cancer type.
    if(!(-f "$Analysispath/$disease_abbr/$tables/final_downloadtable_$disease_abbr\_$Exp_Strategy.txt"))
    {
        #parses the gdc website manifest of the specified cancer type and prints to a results file.
        #gdc_parser(cancer type(e.g. OV),type(RNA-Seq or WGS))
        $dwnld->gdc_parser($disease_abbr,$Exp_Strategy);
        
        #Gets the metadata data of the file and places the UUID in a Payload.txt file.
        #metadata_collect(.result.txt file from gdc_parser,output file)
        $dwnld->metadata_collect("$disease_abbr.result.txt","Payload.txt");
        
        #Gets metadata files for each UUID and prints to a metadata file.
        `curl --request POST --header "Content-Type: application/json" --data \@Payload.txt 'https://gdc-api.nci.nih.gov/legacy/files' > $disease_abbr\_metadata.txt`;
        
        #Uses the metadata file to get data(i.e. UUID, TCGA ID) an prints the data for the UUIDs to a datatable file.
        #parse_patient_id(_metadata.txt file created from curl,output file)
        $dwnld->parse_patient_id("$disease_abbr\_metadata.txt","$disease_abbr.datatable.txt");
        
        #metadata_ids(.result.txt,output file)
        $dwnld->metadata_ids("$disease_abbr.result.txt","Payload.txt");
        
        `curl --request POST --header \'Content-Type: application/json\' --data \@Payload.txt 'https://gdc-api.nci.nih.gov/legacy/files' > $disease_abbr\_metadata.txt`;
        
        open(my $meta,"$disease_abbr\_metadata.txt") or die "Can\'t open file for input: $!";
        open my $ME,">$disease_abbr.edit.metadata.txt" or die "Can\'t open file for output: $!";
        chomp(my @metaedit = <$meta>);
        close($meta);
        for(my $i = 0;$i < scalar(@metaedit);$i++)
        {
            $metaedit[$i]=~s/\r//g;
        }
        @metaedit = grep{!/\t\s+\t/}@metaedit;
        print $ME "$_\n" for @metaedit;
        close($ME);
        
        #pulls the UUIDs from the edit metadata file
        #pull_column(.edit.metadata.txt,column(s) to pull,output file)
        $parsing->pull_column("$disease_abbr.edit.metadata.txt","2","temp.UUID");
        
        #Strips the headers in the file.
        #strip_head(file to strip headers,output file)
        $parsing->strip_head("temp.UUID","$disease_abbr.UUID.txt");
        `rm temp.UUID`;
        
        #parse_meta_id(.edit.metadata.txt,output file from strip_head,output file)
        $dwnld->parse_meta_id("$disease_abbr.edit.metadata.txt","$disease_abbr.UUID.txt","meta_ids.txt");
        
        #ref_parse(output file from parse_meta_id,directory building table,output file)
        $dwnld->ref_parse("meta_ids.txt","$Table_Dir","reference.txt",$dwnld_cmd);
        
        #index_ids(.result.txt,output file)
        $dwnld->index_ids("$disease_abbr.result.txt","Payload.txt");
        
        `curl --request POST --header \'Content-Type: application/json\' --data \@Payload.txt 'https://gdc-api.nci.nih.gov/legacy/files' > index_file_ids.txt`;
        
        #vlookup(lookupFile,queryCol,sourceFile,lookupCol,returnCol(s),append(y/n),outputFile)
        #e.g. vlookup(lookupfile,3,sourcefile,4,"1,2,4,6","y",outputFile)
        #Will search each column 3 entry of lookupfile within colum 4 of sourceFile and will append columns 1,2,4,6 of sourceFile to the end of each row in lookupfile.
        #N.B. only works on tab-delimited files
        $parsing->vlookup("$disease_abbr.datatable.txt","1","reference.txt","1","2","y","temp");
        $parsing->vlookup("temp","1","index_file_ids.txt","2","3","y","final_downloadtable_$disease_abbr.txt");
        
        `mkdir "$Analysispath/$disease_abbr/$tables"` unless(-d "$Analysispath/$disease_abbr/$tables");
        
        if($Exp_Strategy eq 'WGS')
        {
            `sort -k2,2 -k3,3 -k6,6 final_downloadtable_$disease_abbr.txt > final_downloadtable_$disease_abbr\_sorted.txt`;
            #No header in the output, thus no need to strip head!
            #pull_matched_tn_GDC(sorted bamlist,output file)
            $dwnld->pull_matched_tn_GDC("final_downloadtable_$disease_abbr\_sorted.txt","final_downloadtable_$disease_abbr\_$Exp_Strategy.txt");
            $parsing->vlookup("final_downloadtable_$disease_abbr\_$Exp_Strategy.txt",1,"$disease_abbr.result.txt",1,4,"y","final_downloadtable_$disease_abbr\_$Exp_Strategy\_size.txt");
            open(SIZE,"final_downloadtable_$disease_abbr\_$Exp_Strategy\_size.txt") or die "can't open file final_downloadtable_$disease_abbr\_$Exp_Strategy\_size.txt: $!\n";
            open(SO,">final_downloadtable_$disease_abbr\_$Exp_Strategy\_convert.txt") or die "Can't open file: $!\n";
            #convert the size of the WGS bams to gigabytes.
            while (my $r = <SIZE>)
            {
                chomp($r);
                my @con = split("\t",$r);
                my $vert = pop @con;
                $vert = $vert/1000/1000/1000;
                $vert = eval sprintf('%.2f',$vert);
                push(@con,$vert);
                my $size_wgs = join("\t",@con);
                print SO $size_wgs,"\n";
            }
            close(SIZE);
            close(SO);
            
            #filter table and remove bams aligning to NCBI36 or HG18;
            `cat final_downloadtable_$disease_abbr\_$Exp_Strategy\_convert.txt|grep NCBI36 -v | grep -v HG18|grep -v HG18_Broad_variant > WGS_tmp.txt;mv WGS_tmp.txt final_downloadtable_$disease_abbr\_$Exp_Strategy.txt`;
           copy("final_downloadtable_$disease_abbr\_$Exp_Strategy.txt","$Analysispath/$disease_abbr/$tables");
        }
        elsif($Exp_Strategy eq "RNA-Seq")
        {
           `cat final_downloadtable_$disease_abbr.txt |grep NCBI36 -v|grep -v HG18 |grep -v HG18_Broad_variant|grep -v HG19_Broad_variant |grep -v GRCh37-lite |grep -v NaN > final_downloadtable_$disease_abbr\_sort.txt`;
           `sort -k2,2 final_downloadtable_$disease_abbr\_sort.txt > final_downloadtable_$disease_abbr\_$Exp_Strategy.txt`;     
            copy("final_downloadtable_$disease_abbr\_$Exp_Strategy.txt","$Analysispath/$disease_abbr/$tables");
        }
    }
    else
    {
       print "It seems that there is a table in the dir already: final_downloadtable_$disease_abbr\_$Exp_Strategy.txt\n";
    }
}

`rm -rf "$Analysispath/$Input_Dir"`;

print "All jobs have finished for $disease_abbr.\n";
  
$time = localtime;
print "Script finished on $time.\n";

exit;
