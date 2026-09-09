/* GH#62 ISS-varnamev7: PROC IMPORT xlsx generates variable names per
   VALIDVARNAME=V7 — each invalid char → one `_` (runs kept, trailing kept),
   leading digit → `_` prefix, and duplicate headers deduped. */
proc import out=d datafile="tests/corpus/includes/import_varname_v7.xlsx" dbms=xlsx replace;
  sheet="S1";
run;
proc contents data=d out=c(keep=name varnum) noprint; run;
proc sort data=c; by varnum; run;
data _null_; set c; put "NAME=[" name "]"; run;
