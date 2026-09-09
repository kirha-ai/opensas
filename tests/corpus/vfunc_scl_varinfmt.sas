/* VARINFMT(dsid, n) returns a dataset variable's read informat, now that informats
   persist onto the output Column (EXEC-varattr). corpus-vfuncs. */
data one;
  x = 5;
  informat x comma8.;
  format x dollar10.2;
  label x = "Ex";
  output;
run;
data _null_;
  dsid = open("one");
  vi = varinfmt(dsid, 1);
  vf = varfmt(dsid, 1);
  vl = varlabel(dsid, 1);
  put "VARINFMT="  vi;
  put "VARFMT="    vf;
  put "VARLABEL="  vl;
  rc = close(dsid);
run;
