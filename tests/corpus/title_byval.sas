/* BUG-byvaltitle: #BYVAL(var)/#BYVAR(var) in a TITLE/FOOTNOTE re-resolve per
   BY group — the current group's FORMATTED value / the variable's label (or
   name) — stamped above each BY group, not printed literally once. */
options nodate nonumber;
data d;
  input g $ x;
  label g = "Treatment Group";
  datalines;
B 3
A 1
A 2
;
run;
proc sort data=d; by g; run;
title "Group: #byval(g)";
title2 "Var: #byvar(g) | first=#byval1";
footnote "End of #byval(g)";
proc print data=d;
  by g;
run;
