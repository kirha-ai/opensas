/* BUG-infilemissover: INFILE record-boundary options. SAS 9.4: MISSOVER/TRUNCOVER
   "control what happens when an INPUT statement reaches the end of the current
   record" — a short record sets the remaining variables to missing instead of
   pulling values from the NEXT line (the default FLOWOVER, which silently misaligns
   all following data). For list input TRUNCOVER behaves like MISSOVER. (no PHI) */
data mo;
  infile datalines missover;
  input a b c;
datalines;
1 2 3
4 5
6
;
run;
proc print data=mo noobs; run;

data tc;
  infile datalines truncover;
  input x y z;
datalines;
10 20 30
40 50
60
;
run;
proc print data=tc noobs; run;
