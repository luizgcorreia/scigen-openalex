#!/usr/bin/perl

use strict;
use FindBin;
use lib $FindBin::Bin;
use scigen;
use IO::File;
use Getopt::Long;

my $count = 10;
my $outfile = "dataset.csv";

sub usage {
    select(STDERR);
    print <<EOUsage;
    
$0 [options]
  Options:

    --help                    Display this help message
    --count <number>          Number of papers to generate (default: 10)
    --out <file>              Output CSV file (default: dataset.csv)

EOUsage
    exit(1);
}

my %options;
&GetOptions( \%options, "help|?", "count=i", "out=s" ) or &usage;

if( $options{"help"} ) {
    &usage();
}
if( defined $options{"count"} ) {
    $count = $options{"count"};
}
if( defined $options{"out"} ) {
    $outfile = $options{"out"};
}

my $fh = new IO::File ("<scirules.in");
if( !defined $fh ) {
    die("Couldn't open scirules.in");
}

my $sysname_fh = new IO::File ("<system_names.in");
if( !defined $sysname_fh ) {
    die("Couldn't open system_names.in");
}

# Read rules
my $dat = {};
my $RE;
scigen::read_rules ($fh, $dat, \$RE, 0);

my $name_dat = {};
my $name_RE;
scigen::read_rules ($sysname_fh, $name_dat, \$name_RE, 0);

# Escape double quotes for CSV
sub escape_csv {
    my $str = shift;
    my $sysname = shift;
    if (!defined $str) {
        return "";
    }
    
    # Remove latex specific formatting
    $str =~ s/\\section\*?\{([^\}]+)\}/$1/g;
    $str =~ s/\\subsection\{([^\}]+)\}/$1/g;
    $str =~ s/\\em\s+([^\}]+)\}/$1/g;
    $str =~ s/\{\\em\s+([^\}]+)\}/$1/g;
    $str =~ s/\\{/\(/g;
    $str =~ s/\\}/\)/g;
    $str =~ s/\\//g;
    $str =~ s/cite\{[^\}]+\}//g;
    if (defined $sysname) { 
        $str =~ s/\{SYSNAME\}/$sysname/g;
    }
    $str =~ s/\{[^\}]+\}//g;
    $str =~ s/\n/ /g;
    $str =~ s/\s+/ /g;
    $str =~ s/^\s+//;
    $str =~ s/\s+$//;
    
    # Escape quotes
    $str =~ s/"/""/g;
    return '"' . $str . '"';
}

# Open output file
my $csv_fh = new IO::File (">$outfile");
if( !defined $csv_fh ) {
    die("Couldn't open $outfile for writing");
}

# CSV Header
print $csv_fh "source_provider,id,title,abstract_text,authorships,publication_year,cited_by_count,citation_normalized_percentile,doi,oa_status,primary_location,countries,topics,type,language,keywords,has_fulltext\n";

print "Generating $count OpenAlex records to $outfile...\n";

for (my $i = 0; $i < $count; $i++) {
    my $seed = int rand 0xffffffff;
    srand($seed);

    # 1. System Name
    my $sysname = scigen::generate ($name_dat, "SYSTEM_NAME", $name_RE, 0, 0);
    chomp($sysname);
    my @a = ($sysname);
    $dat->{"SYSNAME"} = \@a;

    # 2. Title
    my $title = scigen::generate ($dat, "SCI_TITLE", $RE, 0, 1);
    
    # 3. Abstract
    # We want a longer abstract. The grammar rule SCI_ABSTRACT in scirules.in
    # currently only expands to "SCI_INTRO_A SCI_ABSTRACT_A SCI_INTRO_THESIS".
    # We will construct an extended abstract programmatically so it still reads like an abstract.
    
    my $abs_intro = scigen::generate ($dat, "SCI_INTRO_A", $RE, 0, 1);
    my $abs_thesis = scigen::generate ($dat, "SCI_INTRO_THESIS", $RE, 0, 1);
    
    # Generate 5 additional abstract body sentences
    my $abs_body = "";
    for (my $j = 0; $j < 5; $j++) {
        $abs_body .= scigen::generate ($dat, "SCI_ABSTRACT_A", $RE, 0, 1) . " ";
    }
    
    my $abstract = "$abs_intro $abs_body $abs_thesis";
    
    # 4. Keywords
    my $keywords = scigen::generate ($dat, "SCI_BUZZWORD_ADJ", $RE, 0, 1) . " " . scigen::generate ($dat, "SCI_BUZZWORD_NOUN", $RE, 0, 1) . ", " .
                   scigen::generate ($dat, "SCI_BUZZWORD_ADJ", $RE, 0, 1) . " " . scigen::generate ($dat, "SCI_BUZZWORD_NOUN", $RE, 0, 1) . ", " .
                   scigen::generate ($dat, "SCI_BUZZWORD_ADJ", $RE, 0, 1) . " " . scigen::generate ($dat, "SCI_BUZZWORD_NOUN", $RE, 0, 1);

    # Format for CSV
    my $csv_source_provider = escape_csv("scigen", $sysname);
    my $csv_id = escape_csv("rand_" . $i, $sysname);
    my $csv_title = escape_csv($title, $sysname);
    my $csv_abstract = escape_csv($abstract, $sysname);
    my $csv_authorships = escape_csv("[]", $sysname);
    my $csv_publication_year = escape_csv("", $sysname);
    my $csv_cited_by_count = 0;
    my $csv_citation_norm = 0.0;
    my $csv_doi = escape_csv("", $sysname);
    my $csv_oa_status = escape_csv("", $sysname);
    my $csv_primary_location = escape_csv("", $sysname);
    my $csv_countries = escape_csv("[]", $sysname);
    my $csv_topics = escape_csv("[]", $sysname);
    my $csv_type = escape_csv("synthetic", $sysname);
    my $csv_language = escape_csv("en", $sysname);
    my $csv_keywords = escape_csv($keywords, $sysname);
    my $csv_has_fulltext = escape_csv("False", $sysname);
    
    print $csv_fh "$csv_source_provider,$csv_id,$csv_title,$csv_abstract,$csv_authorships,$csv_publication_year,$csv_cited_by_count,$csv_citation_norm,$csv_doi,$csv_oa_status,$csv_primary_location,$csv_countries,$csv_topics,$csv_type,$csv_language,$csv_keywords,$csv_has_fulltext\n";
    
    if ($i > 0 && $i % 100 == 0) {
        print "  $i records generated...\n";
    }
}

$csv_fh->close();
print "Done.\n";
