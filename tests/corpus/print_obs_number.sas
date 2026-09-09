/* BUG-printobsnum: PROC PRINT's Obs column shows each row's physical SOURCE
   observation number (1-based position in the input dataset), not its index
   among the printed rows. WHERE → non-contiguous Obs; FIRSTOBS= shifts the
   start; OBS= caps the range. NOOBS still suppresses the column. */
data class;
  input name $ sex $ age;
  datalines;
Alfred M 14
Alice F 13
Barbara F 13
Carol F 14
Henry M 14
;
run;
/* WHERE subset: rows 2,3,4 survive → SAS Obs 2,3,4 */
proc print data=class;
  where sex='F';
run;
/* FIRSTOBS=3: SAS Obs starts at 3 */
proc print data=class(firstobs=3);
run;
/* FIRSTOBS=2 OBS=4: obs is the LAST obs number → SAS Obs 2,3,4 */
proc print data=class(firstobs=2 obs=4);
run;
/* WHERE + FIRSTOBS= (Language Reference: Concepts p.229): FIRSTOBS counts WITHIN the WHERE subset —
   subset is Alice,Barbara,Carol, firstobs=3 → 3rd of the subset → Obs 4 */
proc print data=class(firstobs=3);
  where sex='F';
run;
/* NOOBS control: no Obs column even under a subset */
proc print data=class noobs;
  where sex='F';
run;
