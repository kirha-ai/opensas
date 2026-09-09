/* GAP-proccopy(a): PROC COPY writes the selected member as XPORT v5 through
   the out= libref, eagerly. The out path uses Windows `\` separators (as the
   study programs do) — parseLibnames normalizes them. Round-trip through a
   read libname proves the file and its BARE member name (not `work.ae`). */
data ae;
  input usubjid $ aeterm $;
  datalines;
S1 HEADACHE
S2 NAUSEA
;
run;
libname xptfile xport "tests/corpus\includes\pc_ae.xpt";
proc copy in=work out=xptfile;
  select ae;
run;
libname back xport "tests/corpus/includes/pc_ae.xpt";
data _null_;
  set back.ae;
  put usubjid= aeterm=;
run;
