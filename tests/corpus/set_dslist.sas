/* ISS-setdslist (GH#21): SET multi-dataset LIST forms — numbered range and
   name-prefix wildcard, both valid SAS 9.4 (Language Reference: Concepts SET "list forms").
   Range covers multi-digit, non-1 start/end (real DM programs use `SET DM100-DM136`). */
data d1; x=1; run;
data d2; x=2; run;
data d3; x=3; run;

/* numbered range: d1-d3 reads all three (x = 1,2,3) */
data allr; set d1-d3; run;
proc print data=allr noobs; run;

/* prefix wildcard: d: reads every d-prefixed member (d1,d2,d3) */
data allp; set d:; run;
proc print data=allp noobs; run;

/* multi-digit, non-1 numbered range */
data dm100; y=100; run;
data dm101; y=101; run;
data dm102; y=102; run;
data allm; set dm100-dm102; run;
proc print data=allm noobs; run;
