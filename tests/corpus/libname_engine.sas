/* NOTE-libnameengine (D-015 silent superset): the LIBNAME engine keyword is
   now VALIDATED, not skipped — an unknown engine fails loud with SAS's own
   "The <eng> engine cannot be found." (pinned, with the doc-named-but-
   unimplemented JSON arm, by the captured-diagnostics test in src/main.zig).
   POSITIVE CONTROL: the engines for the formats opensas implements must keep
   binding and READING at exit 0 — BASE and its documented alias V9 (native
   dir/.sas7bdat; "V9 is an alias for the BASE engine", Procedures Guide
   p.1032) and XPORT (transport files; "use the XPORT keyword to specify the
   XPORT engine", Procedures Guide p.531), in any case. */
libname gbase BASE "tests/corpus/includes/gsopt";
libname gv9 v9 "tests/corpus/includes/gsopt";
libname gx XPORT "tests/corpus/includes/pc_ae.xpt";
data via_base;
  set gbase.members;
run;
data via_v9;
  set gv9.members;
run;
data via_xpt;
  set gx.ae; /* the .xpt stamps its member name — read it under that name */
run;
proc print data=via_base noobs;
run;
proc print data=via_v9 noobs;
run;
proc print data=via_xpt noobs;
run;
