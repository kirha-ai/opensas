options nodate nonumber;
title "KEEPME";
title Hello World;      /* F1: unquoted text SETS the line (must not clear KEEPME to nothing) */

data one;
  input x;
  datalines;
1
;
run;

proc print data=one noobs;
run;

title;                  /* bare cancel still clears all titles */
footnote Bottom Line;   /* F1: unquoted footnote also sets */

proc print data=one noobs;
run;
