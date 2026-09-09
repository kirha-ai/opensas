/* FEAT-infileobslinesize: INFILE OBS=n caps the records read (the last record
   number, absolute 1-based); LINESIZE=n (alias LS=n) truncates each record to
   n columns, so INPUT never sees past column n. */
data capped;
  infile datalines obs=2;
  input x;
datalines;
10
20
30
;
run;
proc print data=capped noobs; run;

data trunc;
  infile datalines ls=3;
  input s $;
datalines;
abcdef
xy
;
run;
proc print data=trunc noobs; run;
