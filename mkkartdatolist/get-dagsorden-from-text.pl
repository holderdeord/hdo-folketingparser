#!/usr/bin/perl
use warnings;
use strict;
use File::Slurp;
use Data::Dumper;
use Encode;

my $start_time = localtime;
print "Start time: $start_time\n";

##################
################## Hard-coded, baby.
my $output_file = 'kartnr.txt';

# Extremely lazy, but polite:
die "Output file '$output_file' exists.\nWon't overwrite. Please rename or move it.\n" if -e $output_file;

open my $out_fh, '>', $output_file or die "Unable to open '$output_file': $!\n";

die "Supply path to text files to extract dagsorden from.\n" unless @ARGV == 1;

my $path = $ARGV[0];

die "Error: Path does not exist: $path\n" unless -d $path;

# Add a trailing slash if there isn't one.
$path =~ s#/?$#/#;

opendir my $dh, $path or die "Unable to open dirhandle for '$path'\n";

my $regex = qr/
    D\s*a\s*g\s*s\s*o\s*r\s*d\s*e\s*n
    .{0,150}?
    \( \s*
        (?:nr\.?)? \s* (\d+)
    \s* \)
/xsi;

my %data;
my $counter = 0;

while (defined (my $de = readdir $dh)) {
    
    next if $de =~ /^\.\.?$/;
    next if $de !~ /\.txt/i;
    
    print "Processing text file no. ", ++$counter, " ($de)\n";
    
    print(scalar localtime, "\n") unless $counter % 100;
    
    # Slurp file
    my $text = read_file $path . $de;
    
    # Extract the "dagsorden" number.
    my $dagsorden = $text =~ $regex ? $1 : 'Unknown';
    
    $data{$de} = $dagsorden;
    
}

print "\n\n##################################################\n\n";

foreach my $file (sort keys %data) {
    
    print $out_fh "File/date: $file | Kart: $data{$file}\n";
    
}

print "Done! Output file: $output_file\n";
print "Start time: $start_time\n";
print "End time: ", scalar localtime, "\n";