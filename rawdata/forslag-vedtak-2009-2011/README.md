forslag-ikke-verifiserte-2010-2011:
-----------------------------------

* 71 dager med voteringer: 2010-10-05..2011-06-17
* Totalt 2253 forslagstekster
* 76 av elementene mangler forslagstekst - «Teksten er foreløpig ikke tilgjengelig»
* Felter er `MoteKartNr`, `DagsordenSaksNr`, `Voteringstidspunkt`, `Forslagsbetegnelse` («Komiteens tilrådning» osv.), `Forslagstekst`. Dette bør kunne kobles til våre eksisterende 2010-2011 data.
* To datoer har forslagstekster, men mangler avstemningsdata (2010-10-28 16:13:03.980, 2011-04-04 21:48:19.123)
* Eksempel:

```xml
<IkkeKvalSikreteForslag>
    <MoteKartNr>37</MoteKartNr>
    <DagsordenSaksNr>2</DagsordenSaksNr>
    <VoteringsTidspunkt>2010-12-15T17:31:56.733</VoteringsTidspunkt>
    <Forslagsbetegnelse>Komiteens tilr&#xE5;ding bokstav A. rammeomr&#xE5;de 9, romertall VII. </Forslagsbetegnelse>
    <ForslagTekst>&lt;p&gt;&lt;b&gt;Garantifullmakt&lt;/b&gt;&lt;/p&gt;&lt;br/&gt;&lt;p&gt;Stortinget samtykker i at N&#xE6;rings- og handelsdepartementet
i 2011 kan gi Innovasjon Norge fullmakt til &#xE5; gi tilsagn om nye
garantier for inntil 40 mill. kroner for l&#xE5;n til realinvesteringer og
driftskapital, men slik at total ramme for nytt og gammelt ansvar
ikke overstiger 225 mill. kroner.&lt;/p&gt;</ForslagTekst>
</IkkeKvalSikreteForslag>
```

forslag-ikke-verifiserte-2009-2010:
-----------------------------------

* 54 dager med voteringer: 2009-10-07 .. 2010-06-18
* Totalt 2697 forslagstekster
* Voteringstidspunkt mangler, felter er `MoteDato`, `KartNr`, `SaksNr`, `ForslNr`, `Forslagsbetegnelse`, `PaaVegneAv`
* Eksempel:

```xml
<IkkeKvalSikreteForslag>
    <MoteDato>20091007</MoteDato>
    <KartNr>2</KartNr>
    <SaksNr>2</SaksNr>
    <ForslNr>1</ForslNr>
    <Forslagsbetegnelse>Komiteens tilr&#xE5;ding </Forslagsbetegnelse>
    <PaaVegneAv/>
    <ForslagTekst>   Fullmaktene for representantene og vararepresentantene for &#xD8;stfold fylke, Akershus fylke, Oslo, Hedmark fylke, Oppland fylke, Buskerud fylke, Vestfold fylke, Telemark fylke, Aust-Agder fylke, Vest-Agder fylke, Rogaland fylke, Hordaland fylke, Sogn og Fjordane fylke, M&#xF8;re og Romsdal fylke, S&#xF8;r-Tr&#xF8;ndelag fylke, Nord-Tr&#xF8;ndelag fylke, Nordland fylke, Troms fylke og Finnmark fylke godkjennes. &#xD;
&#xD;
</ForslagTekst>
</IkkeKvalSikreteForslag>
```

lose-forslag-2009-2010.xml:
---------------------------

* Usikker på hva dette er, bør sjekkes opp mot forslag-ikke-verifiserte-2009-2011.
* 73 forslag
* Eksempel:

```xml
<Forslag>
    <MoteDato>20091012</MoteDato>
    <KartNr>4</KartNr>
    <SaksNr>1</SaksNr>
    <Forslagsbetegnelse>Forslag fra Siv Jensen p&#xE5; vegne av Fremskrittspartiet</Forslagsbetegnelse>
    <PaaVegneAv>Fremskrittspartiet:</PaaVegneAv>
    <ForslagTekst>Stortinget ber Regjeringen legge frem en energimelding for Stortinget innen 1. juni 2010.</ForslagTekst>
  </Forslag>
```

vedtak-2009-2010:
-----------------

* Annet format enn filen over, feltene er: `KartNr`, `SaksNr`, `Forslagsbetegnelse` («Komiteens tilrådning» osv.), `VedtaksTeskt`.
* Ingen voteringsdatoer.
* 426 objekter totalt.
* Det lave tallet og at det heter `Vedtakstekst` og ikke `Forslagstekst` får meg til å tenke at dette datasettet kun inneholder avstemninger som ble vedtatt.
* Eksempel:

```xml
<Vedtak>
    <KartNr>100</KartNr>
    <SaksNr>2</SaksNr>
    <Forslagsbetegnelse>Komiteens tilr&#xE5;ding </Forslagsbetegnelse>
    <PaaVegneAv/>
    <Vedtakstekst>&lt;FONT SIZE=2&gt;&#xD;
&lt;div class=Section1&gt;&#xD;
&lt;p class=brodtekstminnr style='text-indent:0cm'&gt;&lt;span style='mso-font-width:&#xD;
100%'&gt;Dokument 8:127 S (2009&#x96;2010) &#x96; representantforslag fra&#xD;
stortingsrepresentantene Line Henriette &lt;span class=SpellE&gt;Hjemdal&lt;/span&gt; og&#xD;
Laila &lt;span class=SpellE&gt;D&#xE5;v&#xF8;y&lt;/span&gt; om tilbaketrekking av utslippstillatelsen&#xD;
til gasskraftverket p&#xE5; Mongstad &#x96; bifalles ikke. &lt;o:p&gt;&lt;/o:p&gt;&lt;/span&gt;&lt;BR&gt;&#xD;
&lt;p class=MsoNormal&gt;&lt;o:p&gt;&amp;nbsp;&lt;/o:p&gt;&lt;BR&gt;&#xD;
&lt;/div&gt;&#xD;
&lt;/FONT&gt;&#xD;
  </Vedtakstekst>
</Vedtak>
```



