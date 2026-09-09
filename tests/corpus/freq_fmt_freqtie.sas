/* BUG-freqfmtorderfreqtie: PROC FREQ ORDER=FREQ breaks frequency TIES among
   VALUE.-format levels by the raw internal value, NOT the formatted label text
   (sibling of BUG-freqfmtorder, which fixed the ORDER=INTERNAL default). Format
   lf 1='Zzz' 2='Aaa' 3='Mmm' with all three levels at EQUAL frequency: SAS
   emits Zzz/Aaa/Mmm (raw 1/2/3 tie-break), never the label-text Aaa/Mmm/Zzz.
   The second table shows a DIFFERENT-frequency case — ORDER=FREQ still sorts by
   descending frequency there (raw tie-break only applies WITHIN equal freq). */
data d;
  input x @@;
  datalines;
1 2 3 1 2 3
;
run;
proc format; value lf 1='Zzz' 2='Aaa' 3='Mmm'; run;
proc freq data=d order=freq;
  format x lf.;
  tables x;
run;
data e;
  input x @@;
  datalines;
2 2 2 1 1 3
;
run;
proc freq data=e order=freq;
  format x lf.;
  tables x;
run;
