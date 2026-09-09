/* BUG-importnoreplace: REPLACE still overwrites an existing OUT=, and a new
   OUT= imports without REPLACE. (The no-REPLACE-to-existing ERROR is pinned by
   the captured-diag test in src/proc.zig — a failing step halts the run under
   errhalt, so its stdout would be empty here.) */
data keep_me;
  important=1;
run;
proc import datafile="tests/corpus/includes/ei_roundtrip.csv" out=keep_me dbms=csv replace; run;
proc print data=keep_me noobs; run;
proc import datafile="tests/corpus/includes/ei_roundtrip.csv" out=new_ds dbms=csv; run;
proc print data=new_ds noobs; run;
