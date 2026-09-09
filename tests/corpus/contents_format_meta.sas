/* BUG-contentsfmtcol: PROC CONTENTS OUT= must write FORMAT as the uppercase
   format NAME only (DOLLAR, not dollar8.2) and split the width/decimals into
   FORMATL/FORMATD. The printed report uppercases the name too. */
data d;
  format x dollar8.2;
  x = 1234.5;
run;
proc contents data=d out=meta; run;
proc print data=meta noobs; var name format formatl formatd; run;
