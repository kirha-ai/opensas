/* docs/findings/rebuild-commit-scope.md — the CONTROL that makes
   BUG-modifystoptruncates a defect rather than a matter of taste, plus the
   two in-place commit paths that must not drift into the MODIFY shape.

   THE DISCRIMINATOR (D1/D2). `stop;` truncating the output is CORRECT for a
   CREATING step, even when the output happens to share the input's name:
   `data d; set d; … stop;` builds a new d and swaps it, so the observations
   never reached were never written and there is nothing to preserve — the STOP
   entry (Statements Reference printed p.346, `=== pdf 358 ===`) says exactly
   this: "SAS writes a data set for the current DATA step. However, the
   observation being processed when STOP executes is not added."

   MODIFY is the opposite case and that is the whole point: printed p.240
   (`=== pdf 251 ===`) says it works "IN PLACE" and "does not create an
   additional copy", so there is no new data set for STOP's sentence to be
   about, and unreached observations must survive. Today they do not
   (BUG-modifystoptruncates).

   So a fix for that bug MUST NOT simply disable truncation: D1 below has to
   keep truncating. This fixture exists so that a global "don't truncate" change
   reddens here instead of silently breaking documented behaviour.

   S1/S2 pin the two commit styles that are structurally immune, so a refactor
   cannot quietly convert them to rebuild-and-swap: PROC SQL's UPDATE mutates
   the live table row by row (rows outside the WHERE keep their stored values),
   and PROC SORT with no OUT= sorts the live rows (every observation survives).
   expect-rc: 0 */

/* D1 — CREATING step, output name == input name: truncation is CORRECT */
data d1; do k = 1 to 5; x = k*10; output; end; run;
data d1; set d1; if k = 3 then stop; x = x + 1; run;
title "D1 same-name creating step + stop: 2 rows is CORRECT, not a bug";
proc print data=d1; run;

/* D2 — different output name: the SOURCE must be untouched */
data d2; do k = 1 to 5; x = k*10; output; end; run;
data d2out; set d2; if k = 3 then stop; x = x + 1; run;
title "D2 source survives whole while the new data set is short";
proc print data=d2; run;
proc print data=d2out; run;

/* S1 — PROC SQL UPDATE mutates in place: rows outside the WHERE keep values */
data s1; do k = 1 to 5; x = k*10; output; end; run;
proc sql;
  update s1 set x = x + 1 where k <= 3;
quit;
title "S1 sql update in place: k=1..3 moved, k=4,5 keep 40 and 50";
proc print data=s1; run;

/* S2 — PROC SORT with no OUT= sorts the live rows; nothing is lost */
data s2; do k = 5 to 1 by -1; x = k*10; output; end; run;
proc sort data=s2; by k; run;
title "S2 in-place sort: all five observations survive, ascending";
proc print data=s2; run;
