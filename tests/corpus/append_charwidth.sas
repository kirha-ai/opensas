/* BUG-appendcharwidth — PROC APPEND must not store a value wider than the
   BASE= column's declared char width. Base SAS 9.4 Procedures Guide, DATASETS
   APPEND Statement (the PROC APPEND chapter defers to it, printed p.110): the
   FORCE criteria (printed p.588) are a DATA= variable "not in the BASE= data
   set", of a different type, or "longer than the variables in the BASE= data
   set"; and "Appending to Data Sets That Contain Variables with Different
   Attributes" (printed pp.594-595): without FORCE the length case is an ERROR
   and nothing is appended; with FORCE "The length of the variables in the
   BASE= data set takes precedence. SAS truncates values from the DATA= data
   set to fit them into the length that is specified in the BASE= data set."
   The stale ponytail rationale over appendRows claimed char width "isn't
   tracked in this tree"; it has been since GAP-sqldatatypewidth, so the doc's
   LENGTH case was reachable and unchecked — the descriptor said Char 3 while
   the appended cell held 8 bytes, and one table disagreed with itself by
   reader (PRINT/EXPORT render the raw cell, the DATA-step read clips to the
   descriptor). Fixed AT THE STORE like the SQL twin 1ab28654: appended cells
   reconcile to the BASE= declared length, so every surface is right by
   construction. Pinned through FOUR surfaces (PRINT cell, CONTENTS
   descriptor, DATA-step read-back, raw EXPORT bytes) plus controls. The
   no-FORCE ERROR runs LAST — a step ERROR skips all later steps
   (BUG-errhalt); the captured ERROR and the untouched base are pinned in
   proc.zig's BUG-appendcharwidth unit test, numeric lengths too. (no PHI)
   expect-rc: 1 */
data fbase; length s $3; s='abc'; n=1; run;
data fnew;  length s $8; s='abcdefgh'; n=2; run;
proc append base=fbase data=fnew force; run;   /* over-width: 'abc' + WARNING */

data shorter; length s $3; s='pq'; n=3; run;
proc append base=fbase data=shorter; run;      /* control: shorter fits, no FORCE */

data within; length s $3; s='wxy'; n=4; run;
proc append base=fbase data=within; run;       /* control: within width, no FORCE */

data absent; length t $5; t='zz'; n=5; run;
proc append base=fbase data=absent force; run; /* s absent from DATA= -> missing;
                                                  t not in BASE= -> dropped (FORCE) */

proc print data=fbase; run;      /* cell surface: abc abc pq wxy (blank)       */
proc contents data=fbase; run;   /* descriptor surface: s Char 3, n Num 8      */

data chk; set fbase;             /* read-back surface: agrees with PRINT       */
  l = lengthn(s);
  put 'READBACK=[' s +0 '] len=' l;
run;

/* EXPORT reads the raw cells — read the file back RAW so the stored bytes are
   pinned, not a round-trip that could re-clip on import (siov pattern) */
proc export data=fbase outfile="tests/corpus/includes/acw_rt.csv" dbms=csv replace; run;
data raw;
  infile "tests/corpus/includes/acw_rt.csv" truncover;
  length line $32;
  input line $;
run;
proc print data=raw noobs; run;

/* no-FORCE on a declared length mismatch ERRORs and appends nothing — LAST:
   the step ERROR halts the program here (BUG-errhalt). */
data nbase; length s $3; s='abc'; run;
proc append base=nbase data=fnew; run;
