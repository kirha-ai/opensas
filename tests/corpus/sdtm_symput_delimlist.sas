/* Build a delimited value list across rows (manual SEPARATED BY via RETAIN+CATX) */
data ae; input AESEV $; datalines;
MILD
SEVERE
MODERATE
;
run;
data _null_;
  length lst $50;
  retain lst "";
  set ae end=last;
  lst = catx(", ", lst, AESEV);
  if last then call symputx("sevlist", lst);
run;
data show;
  length severities $50;
  severities = "&sevlist";
run;
proc print data=show; run;
