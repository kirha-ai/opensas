/* GAP-dsmgmt-tick262-264 (doc-finder tick262, F5/F6/F7): DATASETS/SORT surface.
   The fail-loud halves (COPY/SAVE/EXCHANGE/AGE naming themselves, BY
   GROUPFORMAT naming the option, CONTENTS DATA=_ALL_ naming the whole-library
   gap) are pinned by the GAP-dsmgmt-tick262-264 test in src/proc.zig — a green
   corpus run cannot contain an ERROR. This fixture is the POSITIVE control:
   every implemented sub-statement below must keep working, and a mid-step
   TITLE/FOOTNOTE/OPTIONS inside PROC DATASETS is hoisted by main.zig and its
   leftover tokens skipped (D-014/D-014a), never mistaken for a sub-statement. */
data d;
  input x v;
  datalines;
2 20
1 10
1 99
3 30
;
run;
/* SORT: benign perf hints + NODUPKEY + DUPOUT all still function */
proc sort data=d nodupkey threads noequals dupout=dups;
  by x;
run;
proc print data=d;
run;
proc print data=dups;
run;
/* DATASETS: implemented verbs + mid-step globals between sub-statements */
data keep1; a=1; b=2; run;
data keep2; a=3; run;
data scratch; a=9; run;
proc datasets library=work nolist;
  title "datasets positive control";
  change keep2=renamed;
  footnote1 "still mid-step";
  delete scratch;
  options notes;
  modify keep1;
    format a 8.2;
  contents data=keep1;
quit;
/* the renamed/deleted members really changed state */
proc print data=renamed;
run;
