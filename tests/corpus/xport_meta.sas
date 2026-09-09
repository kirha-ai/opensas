/* BUG-xportmeta: the .xpt (FDA transport) round-trip keeps variable LABEL,
   FORMAT, INFORMAT and the DECLARED char length — a $20 var holding "Alice"
   must come back Len 20, not the data max 5. Write srcm → xport_meta.xpt,
   read it back fresh through a second libname, then print the metadata.
   Cites docs/findings/qa-findings-tick113.md. */
data src;
  length name $20 grp $3;
  input name $ grp $ age wt;
datalines;
Alice A 12 45.5
Bob B 13 50.25
;
run;
data srcm;
  set src;
  format wt 8.2 age 3.;
  informat name $20.;
  label name="Full Name" wt="Weight (kg)";
run;
libname xp xport "tests/corpus/includes/xport_meta.xpt";
proc copy in=work out=xp;
  select srcm;
run;
libname rd xport "tests/corpus/includes/xport_meta.xpt";
data back; set rd.srcm; run;
proc contents data=back; run;
data _null_;
  dsid = open("back");
  vi = varinfmt(dsid, 1);
  vl = varlen(dsid, 1);
  vf = varfmt(dsid, 4);
  put "VARINFMT(name)=" vi;
  put "VARLEN(name)=" vl;
  put "VARFMT(wt)=" vf;
  rc = close(dsid);
run;
