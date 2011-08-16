#!/usr/bin/perl
use warnings;
use strict;

# Hard-coded values. You need to change these to make sense...
# "I'll fix it later"...
my $kartnr_file = 'kartnr-alle.txt';
my $output_file = 'sesjon-ting-kart-dato-datosortertXYZ.txt';

open my $fh, '<', $kartnr_file or die "Unable to open '$kartnr_file': $!\n";

my %data;

while (my $line = <$fh>) {
    
    chomp $line;
    
    my ($ting, $date, $kart);
    
    if ($line =~ m{File/date:\s+(\w)(\d+)\.txt\s+\|\s*Kart:\s*(\d+)}i) {
        
        ($ting, $date, $kart) = ($1, $2, $3);
        
        my ($year, $month, $day) = parse_date($date);
        my $session = get_date_session($year, $month, $day);
        my $nice_date = join '-', $year, $month, $day;
        
        $data{$nice_date}->{sesjon} = $session;
        $data{$nice_date}->{kart} = $kart;
        $data{$nice_date}->{ting} = lc $ting;
        
    }
    
    else {
        
        print "Error with line $.: $line\n";
        
    }
    
    
}

open my $out_fh, '>', $output_file or die "Could not open '$output_file': $!\n";

foreach my $date ( sort keys %data ) {
    # sort { $data{$a}->{ting} cmp $data{$b}->{ting} }
    print $out_fh q("), $data{$date}->{sesjon}, q(","), $data{$date}->{ting}, q(","), $data{$date}->{kart}, q(","), $date, q("), "\n";
    
}

close $out_fh;

print "Done! Output file: $output_file\n";

exit 0;

sub get_date_session {
    
    my ($year, $month, $day) = @_;
    
    my %session_map = (
    
    # Some redundant data... had ideas
    
#    135 => { '1989-1993' },
#    136 => '1989-1993',
#    137 => '1989-1993',

#    138 => '1993-1997',
#    139 => '1993-1997',
#    140 => '1993-1997',
#    141 => '1993-1997',
    
    1997 => { session => 142, end_year => 1998, period => '1997-2001' },
    1998 => { session => 143, end_year => 1999, period => '1997-2001' },
    1999 => { session => 144, end_year => 2000, period => '1997-2001' },
    2000 => { session => 145, end_year => 2001, period => '1997-2001' },

    2001 => { session => 146, end_year => 2002, period => '2001-2005' },
    2002 => { session => 147, end_year => 2003, period => '2001-2005' },
    2003 => { session => 148, end_year => 2004, period => '2001-2005' },
    2004 => { session => 149, end_year => 2005, period => '2001-2005' },

    2005 => { session => 150, end_year => 2006, period => '2005-2009' },
    2006 => { session => 151, end_year => 2007, period => '2005-2009' },
    2007 => { session => 152, end_year => 2008, period => '2005-2009' },
    2008 => { session => 153, end_year => 2009, period => '2005-2009' },

    2009 => { session => 154, end_year => 2010, period => '2009-2013' },
    2010 => { session => 155, end_year => 2011, period => '2009-2013' },

#    156 => '2009-2013',
#    157 => '2009-2013',
    
    );
    
    if ($month >= 1 and $month <= 6) {
        
        return exists $session_map{$year-1}->{session} ? $session_map{$year-1}->{session} : 'Not found'
        
    }
    
    elsif ($month >= 10 and $month <= 12) {
        
        return exists $session_map{$year}->{session} ? $session_map{$year}->{session} : 'Not found'
        
    }
    
    else {
        
        return "Month out of range: $month"
        
    }
    
}

sub parse_date {
    
    my $date = shift;
    
    my $year = substr $date, 0, 2;
    
    # Change this after 2071, guys!
    $year = $year > 70 ? '19' . (sprintf '%02d', $year) : '20' . (sprintf '%02d', $year);
    
    my $month = substr $date, 2, 2;
    my $day = substr $date, 4, 2;
    
    return ($year, $month, $day);
    
}

