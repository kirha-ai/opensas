/* GAP-procprint F1: a PROC PRINT `id` variable REPLACES the Obs column as the
   leftmost row identifier — no Obs column, the id var(s) render leftmost, then
   the var list. Byte-exact: char id is left-justified, numeric var right. */
data d;
  input subj $ score;
  datalines;
A 90
B 85
C 78
;
run;
proc print data=d; id subj; var score; run;
