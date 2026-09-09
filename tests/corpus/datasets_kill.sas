/* PROC DATASETS ... KILL removes every WORK member: exist() reads 0 for the
   killed members and only the post-KILL dataset remains readable. (SET of a
   killed member is a hard error per BUG-setmissingquiet, matching real SAS.) */
data one; v = 1; run;
data two; v = 2; run;
proc datasets library=work kill nolist;
quit;
data three; v = 3; run;
data _null_; e1 = exist("one"); e2 = exist("two"); put "killed=" e1 e2; run;
data allrows;
  set three;
run;
proc print data=allrows; var v; run;
