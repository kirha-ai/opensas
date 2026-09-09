/* NOTE-truncreadmsg POSITIVE CONTROL: loadLibInputs now distinguishes a
   MISSING member file (silent here; SET's "File X does not exist" is truthful)
   from a PRESENT-but-damaged one (one captured ERROR naming the real cause —
   "the file exists but is damaged or truncated" — reported at the referencing
   token's line, then the step errhalt-skips; pinned by the captured-
   diagnostics test in src/main.zig, truncated sas7bdat + xpt + the
   no-stale-.csv-fallthrough arm). The HEALTHY arms restructured by that fix
   must keep reading at exit 0: file-libref straight at a .sas7bdat, dir-libref
   probe order (.sas7bdat preferred over the .csv sidecar), file-libref .xpt. */
libname d "tests/corpus/includes/dslabel";
libname f "tests/corpus/includes/dslabel/d.sas7bdat";
libname x "tests/corpus/includes/pc_ae.xpt";
data via_dir;
  set d.d; /* dir probe arm (d.sas7bdat present; E-sas7write-hookup owns the
              sas7bdat-over-csv preference pin — here just: healthy read) */
run;
data via_file;
  set f.d;
run;
data via_xpt;
  set x.ae; /* the .xpt stamps its member name */
run;
proc print data=via_dir noobs;
run;
proc print data=via_file noobs;
run;
proc print data=via_xpt noobs;
run;
