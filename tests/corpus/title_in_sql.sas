/* GAP-titleinsql: TITLE / FOOTNOTE inside PROC SQL are valid SAS 9.4 and must
   stamp the SELECT listing (title atop, footnote below), like other report
   procs. Also proves a TITLE set BEFORE the proc is still active inside it. */
data pets;
  input name $ legs;
  datalines;
cat 4
duck 2
ant 6
;
run;

title "Before PROC";
proc sql;
  footnote "counted";
  select name, legs from pets order by legs;
  title "Changed Inside";
  select name from pets where legs > 3;
quit;
