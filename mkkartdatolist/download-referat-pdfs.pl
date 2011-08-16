#!/usr/bin/perl
use warnings;
use strict;
use LWP::Simple;
use Getopt::Long;
use File::Basename;

# Ultimate Odelsting and Storting PDF Downloader
# By: Joakim Borger Svendsen
# Initially written: 2011-08-14

our $VERSION = '0.2';

# Hardcoded base URL (use trailing slash!)
my $pdf_referat_url_base = 'http://www.stortinget.no/Global/pdf/Referater/';

# Options hash
my %opt;

# Get arguments/parameters/options
unless (GetOptions (
    'ting=s'      => \$opt{ting},
    'destdir=s'   => \$opt{destdir},
    'delay=i'     => \$opt{delay},
    'startyear=i' => \$opt{startyear},
    'endyear=i'   => \$opt{endyear},
    'help'        => \$opt{help},
    )
) {
    
    die "Error: Unable to parse options: $!\n";
    
}

print_help() if $opt{help};

unless ($opt{ting} and $opt{destdir}
        and $opt{startyear}) {
    
    print_help();
    
}

sub print_help {
        
    my $script_name = basename $0;
    
    print <<EOF;
Usage: $script_name --ting <odelsting|storting>
   --destdir <destination download directory>
   --delay : Optional. Delay between each web server hit in
     full seconds. Default "1".
   
   --startyear <first year to collect data from>
   --endyear : Optional. Last year to collect data from. Must be start
   year or higher. If omitted, start year is used (one year only).
   
   --help : Prints this help text and exits.

A Stortings year is from October 1st of the start year to June in
start year + 1.

If you specify only --startyear 2000, data will be retrieved from Oct 1st,
2000 to June 30th, 2001. If you use --startyear 1998 and --endyear 2010,
data will be collected from October 1st, 1998 to June 30th 2011.

Written by Joakim Svendsen - "joakimbs", using Google's mail services

Version $VERSION

EOF
    
    exit 0;
    
}

# Populate variables from arguments or use defaults.
my ($ting, $dest_dir, $start_year) =(@opt{qw(ting destdir startyear)});

# End year in year range. If omitted, use start year.
my $end_year = $opt{endyear} ? $opt{endyear} : $opt{startyear};

# Seconds to sleep between hit attempts. Default 1 second.
my $delay = $opt{delay} ? $opt{delay} : 1;

## Verify/check parameters/arguments

# Verify "ting" and populate $first_file_name_letter. A tiny bit of "fuzzy logic"!
my $first_file_name_letter;

if ($ting =~ /^odel/i) {
    $ting = 'Odelstinget';
    $first_file_name_letter = 'o';
}
elsif ($ting =~ /^stor/i) {
    $ting = 'Stortinget';
    $first_file_name_letter = 's';
}
else {
    die "Unknow 'ting' specified. Cannot continue.\nValid: storting, odelsting\n";
}

my $url_base = $pdf_referat_url_base . $ting . '/';
print "Using URL base: '$url_base'\n";

# Add a trailing slash to destination directory if there isn't one
$dest_dir =~ s#/?$#/#;

# Die if the destination directory does not exist
die "Error: Destination directory does not exist\n" unless -d $dest_dir;

# Verify that the end year is higher than the start year
die "Error: End year is not higher than start year\n" if $end_year < $start_year;

my @years = $start_year..$end_year;

my $start_time = localtime;
print "Start time: $start_time\n";
print "Delay between web server hits: $delay second(s)\n";

# Month info hash
my %month_days = (
    
    january   => { num_days => 31, order => 1 },
    february  => { num_days => 29, order => 2 },
    march     => { num_days => 31, order => 3 },
    april     => { num_days => 30, order => 4 },
    may       => { num_days => 31, order => 5 },
    june      => { num_days => 30, order => 6 },
    july      => { num_days => 31, order => 7 },
    august    => { num_days => 31, order => 8 },
    september => { num_days => 30, order => 9 },
    october   => { num_days => 31, order => 10 },
    november  => { num_days => 30, order => 11 },
    december  => { num_days => 31, order => 12 },
    
);


foreach my $year (@years) {
    
    print "### Processing: $year-", $year + 1, "\n";
    
    my $next_year = $year + 1;
    
    # Go through oct-dec for $year. Stortingsperioder er fra oktober
    # til juni neste år.
    foreach my $month ( qw(october november december) ) {
        
        foreach my $day ( 1..$month_days{$month}->{num_days} ) {
            
            my $year_last_two_digits = substr $year, 2, 2;
            
            my $url = $url_base . "$year-$next_year/" . $first_file_name_letter .
              $year_last_two_digits .
              (sprintf '%02d', $month_days{$month}->{order}) . 
              (sprintf '%02d', $day) . '.pdf';
            
            #print $url, "\n";
            fetch_pdf($url);
            
        }
        
    }
    
    # Go through jan-june for $next_year. Stortingsperioder er fra oktober
    # til juni neste år. Dette er da "neste år".
    foreach my $month ( qw(january february march april may june) ) {
        
        foreach my $day ( 1..$month_days{$month}->{num_days} ) {
            
            my $year_last_two_digits = substr $next_year, 2, 2;
            
            my $url = $url_base . "$year-$next_year/" . $first_file_name_letter .
              $year_last_two_digits .
              (sprintf '%02d', $month_days{$month}->{order}) . 
              (sprintf '%02d', $day) . '.pdf';
            
            #print $url, "\n";
            fetch_pdf($url);
            
        }
        
    }
    
}

sub fetch_pdf {
    
    my $url = shift;
    
    # Should probably pass this in. This is a little filthy.
    my ($file_name) = $url =~ m{/([^/]+)$};
    
    $file_name = $dest_dir . $file_name;
    
    if ( my $pdf = LWP::Simple::get($url) ) {
        
        if (open my $out_fh, '>', $file_name) {
            
            if (print $out_fh $pdf) {
                
                print "Success: '$url'\n";
                
            }
            
            else {
                
                print "Downloaded, but failed to save/print: '$url'\n";
                
            }
            
            close $out_fh;
            
        }
        
        else {
            
            print "Failed to open file handle for: '$file_name'\n";
            
        }
        
    }
    
    else {
        
        print "Failed or not found: '$url'\n";
        
    }
    
    sleep $delay;
    
}

print "Start time: $start_time\n";
print 'End time: ', scalar localtime, "\n";
print "\nDone!\n";

