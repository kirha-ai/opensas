/* tick241 pin: implicit-vs-explicit OUTPUT interaction inside a DOW loop.
   Rule pinned: any explicit OUTPUT statement in the step suppresses the
   implicit end-of-iteration output (SAS 9.4), so only condition-fired rows
   appear; with no explicit OUTPUT, one implicit row per BY group shows the
   group's LAST record. */
data a; input g v; datalines;
1 10
1 20
1 30
2 5
2 7
;
run;

data explicit_;
  do until(last.g);
    set a; by g;
    if v >= 20 then output;
  end;
run;

data implicit_;
  do until(last.g);
    set a; by g;
    s + v;
  end;
run;

proc print data=explicit_ noobs; run;
proc print data=implicit_ noobs; run;
