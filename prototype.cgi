#!/usr/bin/perl

use warnings;
use strict;

use CGI;
use DBI;
use FindBin;

use vars qw($dbh);

my $q = new CGI;
if ($q->param('person_id')) {
    show_person($q);
} elsif ($q->param('division_id')) {
    show_division($q);
} else {
    show_frontpage($q);
}
db_disconnect();
exit 0;

sub print_html_header {
    my ($q) = @_;
    print($q->header( -type => 'text/html; charset=utf-8' ));
    print '<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN" "http://www.w3.org/TR/html4/loose.dtd">', "\n";
    print "<html>\n";
    print "<head>\n";
    print $q->title('Valgt av folket'), "\n";
    print "</head>\n";
    print "<body>\n";
    print $q->p(
        $q->a({href => $q->url(-path_info=>1)},
                       'Valgt av folket') .
        ' | ' .
        $q->a({href => 'http://www.nuug.no/' },
                       'Foreningen NUUG')
        ), "\n";
    print $q->hr();
}

sub print_html_footer {
    my ($q) = @_;
    print $q->hr();
    print $q->p(
        'Inspirert av ' .
        $q->a({href => 'http://www.publicwhip.org.uk/'},
              'Public Whip') .
        ' og ' .
        $q->a({href => 'http://www.theyworkforyou.com/'},
              'TheyWorkForYou') .
        '.  Basert på ' .
        $q->a({href => 'https://gitorious.org/nuug/folketingparser'},
              'snedig fri programvare') .
        '.'
        ), "\n";
    print "</body>\n";
    print "</html>\n";
}

sub show_division {
    my ($q) = @_;

    my $division_id = $q->param('division_id');

    print_html_header($q);

    print $q->h2('Votering'), "\n";
    my $division =
        select_all('SELECT id, description, when_divided, heading_id, '.
                   '  yes_count, no_count ' .
                   '  FROM division '.
                   '  WHERE id = ? ', $division_id);
    print $q->p('Tema: ' .
                $q->a({href => $q->url(-path_info=>1) .
                           '?division_id=' . $division_id},
                      $division->[0]->{description})), "\n";

    if ($division->[0]->{heading_id}) {
        my $heading_id = $division->[0]->{heading_id};
        my $link = "http://www.stortinget.no/no/Saker-og-publikasjoner/Saker/Sak/?p=$heading_id";
        print $q->p($q->a({href => $link}, 'Saksinfo fra stortinget')), "\n";
    }
    print($q->p(sprintf('Opptelling gav %d for og %d mot.',
                        $division->[0]->{yes_count},
                        $division->[0]->{no_count})), "\n");

    my $votecount =
        select_all('SELECT vote, count(*) AS count FROM vote '.
                   'WHERE division_id = ? GROUP BY vote '.
                   'ORDER BY count DESC', $division_id);
    my %count;
    map { $count{$_->{vote}} = $_->{count}; } @{$votecount};
    printf($q->p(
               sprintf('Databasen inneholder %d for, %d mot og %d fraværende.',
                       $count{'yes'}, $count{'no'}, $count{'absent'})));

    my $votes =
        select_all('SELECT person_id, vote, first_name, last_name, party '.
                   'FROM division, vote, person '.
                   'WHERE division.id = vote.division_id '.
                   '  AND person.id = vote.person_id '.
                   '  AND division_id = ? '.
                   'ORDER BY vote DESC, party, last_name, first_name', $division_id);

    print $q->start_table({border=>1, cellpadding=>2, cellspacing=>0}), "\n";
    print $q->Tr({}, $q->th({}, ['Hvem', 'Parti', 'Stemme'])), "\n";
    map {
        print $q->Tr({}, $q->td({}, [ $q->a({href => $q->url(-path_info=>1) .
                                                 '?person_id=' . $_->{person_id}},
                                            $_->{first_name} . ' ' .
                                            $_->{last_name} ),
                                      $_->{party},
                                      $_->{vote} ])), "\n";
    } @{$votes};
    print $q->end_table(), "\n";
    print_html_footer($q);
}

sub show_person {
    my ($q) = @_;
    my $person_id = $q->param('person_id');

    print_html_header($q);

    my $person = select_all('SELECT first_name, last_name, type, ref '.
                            '  FROM person, person_ref '.
                            '  WHERE person_id = id AND  id = ?', $person_id);
    if ($person) {
        print($q->h1($person->[0]->{first_name} . ' ' .
                     $person->[0]->{last_name}), "\n");
    }

    for my $ref (@$person) {
        my $value = $ref->{ref};
        my ($link, $text);
        my ($link2, $text2);
        if ('stortinget-perid' eq $ref->{type}) {
            $link = "http://www.stortinget.no/no/Representanter-og-komiteer/Representantene/Representantfordeling/Representant/?perid=$value";
            $text = 'Informasjon fra Stortinget';
            $link2 = "http://sok.stortinget.no/?customercode=$value";
            $text2 = 'Innlegg fra Stortingets talerstol'
        } elsif ('nsd-polsys-id' eq $ref->{type}) {
            $link = "http://www.nsd.uib.no/polsys/index.cfm?UttakNr=33&person=$value";
            $text = 'Informasjon fra NSD';
        } elsif ('no.wikipedia.org' eq $ref->{type}) {
            $link = "http://no.wikipedia.org/wiki/$value";
            $text = 'Informasjon fra norsk Wikipedia';
        }
        print( $q->p( $q->a({href => $link}, $text) ), "\n") if ($link);
        print( $q->p( $q->a({href => $link2}, $text2) ), "\n") if ($link2);
    }

    print $q->h2('Voteringer'), "\n";

    my $count = select_all('SELECT COUNT(*) as count FROM vote WHERE person_id = ?',
                           $person_id);
    my $absent = select_all('SELECT COUNT(*) as count FROM vote '.
                            '  WHERE person_id = ? '.
                            '        AND vote = "absent"',
                            $person_id,);
    if ($count->[0]->{count}) {
        print $q->p(sprintf('Fraværende på %d av %d (%.0f%%) av voteringene.',
                            $absent->[0]->{count},$count->[0]->{count},
                            100*$absent->[0]->{count}/$count->[0]->{count}));
    }

    my $votes =
        select_all('SELECT id, description, when_divided, vote '.
                   'FROM division, vote '.
                   'WHERE division.id = vote.division_id '.
                   'AND vote.person_id = ? '.
                   'ORDER BY when_divided desc', $person_id);
    print $q->start_table({border=>1, cellpadding=>2, cellspacing=>0}), "\n";
    print $q->Tr({}, $q->th({}, [ 'Når', 'Stemme', 'Tema' ])), "\n";
    map {
        print $q->Tr({}, $q->td({}, [ $_->{when_divided}, $_->{vote},
                                      $q->a({href => $q->url(-path_info=>1) .
                                                 '?division_id=' . $_->{id}},
                                            $_->{description}) ])), "\n";
    } @{$votes};
    print $q->end_table(), "\n";

    print_html_footer($q);
}

sub show_frontpage {
    my ($q) = @_;
    print_html_header($q);
    print($q->h1('Valgt av folket'), "\n");
    print($q->p('Nettsted som lar deg følge de folkevalgte fra dag til dag.  Dette er en proof-of-concept-løsning som demonstrerer hva som kan vises frem når voterings-data fra Stortinget blir tilgjengelig.'),
          "\n");

    print($q->h2('Siste 10 voteringer'), "\n");

    my $divisions =
        select_all('SELECT id, when_divided, description FROM division '.
                   'ORDER BY when_divided DESC LIMIT 10');
    print($q->ul(
              map { ($q->li($_->{when_divided} . ' ' .
                            $q->a({href => $q->url(-path_info=>1) .
                                       '?division_id=' . $_->{id}},
                                  $_->{description})), "\n"); }
              @{$divisions}
          ), "\n");

    print($q->h2('Representanter'), "\n");

    my $people = select_all('SELECT id, first_name, last_name FROM person '.
                            'WHERE id in (SELECT person_id FROM vote) '.
                            'ORDER BY last_name, first_name');
    print($q->ul(
              map { ($q->li($q->a({href => $q->url(-path_info=>1) .
                                       '?person_id=' . $_->{id}},
                                  $_->{first_name} . ' ' .
                                  $_->{last_name} )), "\n"); } @{$people}
          ), "\n");
    print_html_footer($q);
}

sub db_connect {
    my $dbfile = "$FindBin::Bin/prototype.sqlite";
    my $dbh = DBI->connect("dbi:SQLite:dbname=$dbfile", "", "");
}

sub db_disconnect {
    if ($dbh) {
        $dbh->disconnect or warn $dbh->errstr;
        $dbh = undef;
    }
}

sub select_all {
    my ($query, @bind_values) = @_;
    unless ($dbh) {
        $dbh = db_connect();
    }
    $dbh->selectall_arrayref($query, { Slice => {} }, @bind_values);
}
