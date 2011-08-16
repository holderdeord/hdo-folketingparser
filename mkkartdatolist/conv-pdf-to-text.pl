#!/usr/bin/perl
use warnings;
use strict;
use Getopt::Long;

# Convert PDFs to text files with corresponding names.
# Assumes PDF extension on target files (will disregard others).
# Uses the utility "pstotext".
# Accepts a target directory to convert all PDFs with <filename>.pdf
# to <filename>.txt. Existing .txt files with the same name
# will be overwritten!

our $VERSION = '0.1';

main();

sub main {
    
    my %opt;
    
    unless (GetOptions (
                        'dir=s'      => \$opt{dir},
                        )
           ) { die "Error parsing options: $!\n"; }
    
    die "No target directory with PDFs specified with --dir\n" unless $opt{dir};
    die "Specified target directory does not exist\n" unless -d $opt{dir};
    
    my $dir = $opt{dir};
    
    process_dir($dir);
    
}

sub process_dir {
    
    my ($dir) = @_;
    
    # Add a trailing slash to the dir name if there isn't one
    $dir =~ s#/?$#/#;
    
    opendir my $dh, $dir or die "Unable to opendir '$dir': $!";
    
    my $start_time = localtime;
    print "Start time: $start_time\n";
    print "Processing: '$dir'\n";
    
    my ($counter, $success_counter, $fail_counter) = (0, 0, 0);
    
    while ( defined (my $de = readdir $dh) ) {
        
        next if $de =~ /^\.\.?$/;
        next unless $de =~ /\.pdf$/;
        
        $counter++;
        
        print "Processing PDF no. $counter\n" unless $counter % 50;
        
        my $full_file_path = $dir . $de;
        
        my ($target_text_file_name) = $de =~ /^(.+)\.pdf$/;
        $target_text_file_name .= '.txt';
        
        if (system("pstotext -output $dir$target_text_file_name $full_file_path") ) {
            
            print "Failed to convert '$de'\n";
            $fail_counter++;
            
        }
        
        else {
            
            print "Successfully created '$target_text_file_name'\n";
            $success_counter++;
            
        }
        
    }
    
    print "Processed $counter PDFs\nSuccessfully converted: $success_counter\nFailed to convert: $fail_counter\n";
    print "Start time: $start_time\n";
    print "End time: ", scalar localtime, "\n";
    
}

