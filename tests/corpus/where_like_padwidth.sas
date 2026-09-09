/* BUG-likepadwidth: WHERE LIKE/CONTAINS must treat both operands under ONE
   trailing-blank policy (was: value trimmed, pattern verbatim → a trailing-
   blank pattern could never match).
   Declared width is NOT reachable at the functions boundary, so the landed
   behavior is symmetric trim (ponytail, EPIC-charfixedwidth umbrella):
     r1  like 'grape     ' → MATCH   (SAS: MATCH — agrees)
     r2  like 'gr_pe'      → MATCH   (SAS: NOMATCH — pinned divergence; `_`
                                     would have to match a padding blank,
                                     needs the declared $10 width)
     r3  like 'gr_pe%'     → MATCH   (SAS: MATCH — agrees)
     r4  contains 't '     → MATCH   (SAS: MATCH — agrees)
     r5  like 'x%'         → NOMATCH (SAS: NOMATCH — agrees)              */
data a;
  length s $10 t $10;
  s='grape'; t='cat';
run;
data r1; set a; where s like 'grape     '; run;
proc print data=r1 noobs; run;
data r2; set a; where s like 'gr_pe'; run;
proc print data=r2 noobs; run;
data r3; set a; where s like 'gr_pe%'; run;
proc print data=r3 noobs; run;
data r4; set a; where t contains 't '; run;
proc print data=r4 noobs; run;
data r5; set a; where s like 'x%'; run;
proc print data=r5 noobs; run;
