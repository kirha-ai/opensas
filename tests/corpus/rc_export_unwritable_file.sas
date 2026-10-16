/* BUG-procmissingfilerc (GH#21) — an OUTFILE= that cannot be written is the
   USER's error, exit 1: a missing directory, a read-only target or a full disk
   is all caller-side, and EXPORT itself worked (the CSV was serialized before
   the write was attempted). It used to exit 2, telling a downstream agent to
   file an opensas issue about its own bad path.

   The directory below does not exist, so the write fails without needing any
   permission setup. Same arm shape as the five BUG-procmissingrc2 absent-input
   reports: a plain ERROR, the step-halt NOTE, exit 1 — never a silent no-op
   and never exit 0 (D-002 fail-loud).

   Nothing reaches stdout: the ERROR and the NOTE go to stderr, and the PROC
   PRINT that would have shown the data is skipped by the post-error stop-all
   (BUG-errhalt) — which is itself worth pinning here, since the failing EXPORT
   must not let a pipeline flow on as if the file had been written.
   expect-rc: 1 */
data test;
  x = 1;
  output;
run;

proc export data=test outfile="/no/such/dir/rc_export.csv" dbms=csv replace;
run;

proc print data=test noobs;
run;
