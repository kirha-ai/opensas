/* BUG-filelibrefmember (doc-finder tick220 F6 + F9-sidecar): a libref pointed
   straight at ONE .sas7bdat FILE must apply the sibling `.labels` sidecar on
   read — labels/formats/informats survive exactly like a directory-libref
   read (F9) — and must serve ONLY the member the file actually holds (F6; the
   wrong-name "ERROR: File ... does not exist" half is asserted by the
   captured-diag test in src/main.zig — corpus diffs stdout only). PROC COPY
   through a directory libname stamps src.sas7bdat + src.labels eagerly; the
   FILE libref then reads the member back by its correct name. */
data src;
  input usubjid $ age;
  label usubjid="Unique Subject" age="Age (years)";
  format age 3.;
datalines;
S1 34
S2 28
;
run;
libname w "tests/corpus/includes/flm";
proc copy in=work out=w;
  select src;
run;
libname f "tests/corpus/includes/flm/src.sas7bdat";
data back;
  set f.src;
run;
data _null_;
  dsid = open("back");
  l = varlabel(dsid, 1);
  fm = varfmt(dsid, 2);
  put "VARLABEL(usubjid)=" l;
  put "VARFMT(age)=" fm;
  rc = close(dsid);
run;
proc print data=back;
run;
