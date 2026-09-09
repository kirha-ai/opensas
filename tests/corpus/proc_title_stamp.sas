/* BUG-proctitlestamp-univcontents: a user TITLE stamps atop (and FOOTNOTE below)
   PROC UNIVARIATE and PROC CONTENTS listings, exactly as PRINT/MEANS/FREQ do —
   both were silently skipping the shared title-emit path. n=3 keeps the moments
   trivial; the point is the "Hdr" line above each proc and "ftr" below. */
title "Hdr";
footnote "ftr";
data d;
  input x @@;
  datalines;
1 2 3
;
run;
proc univariate data=d; var x; run;
proc contents data=d; run;
