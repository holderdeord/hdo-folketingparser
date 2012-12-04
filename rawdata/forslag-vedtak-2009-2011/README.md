forslag-ikke-verifiserte-2010-2011:
-----------------------------------

* 71 dager med voteringer - 2010-10-05..2011-06-17
* Totalt 2253 forslagstekster
* 76 av elementene mangler forslagstekst - «Teksten er foreløpig ikke tilgjengelig»
* Felter er `MoteKartNr`, `DagsordenSaksNr`, `Voteringstidspunkt`, `Forslagsbetegnelse` («Komiteens tilrådning» osv.), `Forslagstekst`. Dette bør kunne kobles til våre eksisterende 2010-2011 data.
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
