/* QA tick155: extends BUG-printobsnum (cf0f179) past the shipped fixture —
   PROC PRINT's Obs column = physical source obs number under BY-group printing
   (on a SORTed dataset the numbers are the new sorted positions), a BY-group
   WHERE sub-select (non-contiguous Obs per group), and a second dataset (Obs
   resets to that dataset's own 1..n). NOOBS still suppresses the column. */
data class;
  input name $ sex $ age;
  datalines;
Alfred M 14
Alice F 13
Barbara F 13
Carol F 14
Henry M 14
James M 12
;
run;
proc sort data=class out=csort; by sex; run;
/* BY-group over sorted data: Obs = sorted physical positions 1..6 */
proc print data=csort; by sex; run;
/* BY-group + WHERE: only age>=14 survive → non-contiguous source Obs per group */
proc print data=csort; by sex; where age >= 14; run;
/* second, smaller dataset: Obs resets to its own 1..n (not carried over) */
data two; input v; datalines;
100
200
;
run;
proc print data=two; run;
