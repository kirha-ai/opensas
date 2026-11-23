/* Capture the structure and row count of TABLES OUT= for an empty input. */
options nodate nonumber linesize=120 pagesize=max nostimer nofullstimer;
data sample;
  length group $4; label group="Study arm";
  stop;
run;

proc freq data=sample noprint;
  tables group / out=no_cells;
run;
proc contents data=no_cells out=columns(keep=varnum name type length label format) noprint; run;
proc sort data=columns; by varnum; run;
proc print data=columns noobs;
  var varnum name type length format label;
run;
proc sql; select count(*) as rows from no_cells; quit;
