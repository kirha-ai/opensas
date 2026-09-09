/* Substring vs whole-word search (INDEX finds 'head' inside 'headache'; INDEXW
   only matches a standalone word) */
data ae;
  length TERM $20;
  TERM = "severe headache"; output;
  TERM = "mild nausea";     output;
  TERM = "head cold";       output;
run;
data d;
  set ae;
  pos  = index(TERM, "head");
  wpos = indexw(TERM, "head");
run;
proc print data=d; var TERM pos wpos; run;
