/* MODIFY data-loss audit (docs/findings/modify-dataloss-audit.md) — the three
   conformant behaviours the audit found UNPINNED. Each is load-bearing for a
   defect the audit files, so if one of these drifts the evidence for those
   defects drifts with it.

   R1 RETURN — THE ANCHOR. In a MODIFY step, declining to write must leave the
   STORED observation exactly as it was; it must NOT delete it. MODIFY works
   "in place" and "does not create an additional copy" (Statements Reference
   printed p.240, `=== pdf 251 ===`, offset +11), so an observation the step
   does not write is simply not rewritten — it cannot vanish. opensas gets this
   RIGHT for RETURN today, which is precisely why the audit can call
   `delete;` (F3) and `stop;` (F1) defects rather than judgement calls: three
   statements that all mean "do not write this observation" must not disagree
   about whether the observation still exists afterwards, and today RETURN keeps
   it while DELETE and STOP destroy it. Pinned so the contrast cannot be lost by
   "fixing" DELETE into REMOVE.

   R2 empty transaction — a MODIFY..BY whose transaction data set has no
   observations must leave every master observation untouched. Zero iterations
   must not mean zero rows: that is the F1 mechanism (rebuild from what was
   iterated) in its most extreme form, and it is correct here.

   R3 duplicate BY keys in the MASTER — printed p.245 (`=== pdf 257 ===`): "If
   duplicates exist in the master data set, only the first occurrence is updated
   because the generated WHERE statement always finds the first occurrence in
   the master." Verified conformant; the second duplicate must keep its stored
   value.
   expect-rc: 0 */

/* R1 — RETURN leaves the observation stored and unchanged */
data r1; do k = 1 to 5; x = k*10; output; end; run;
data r1;
  modify r1;
  if k = 3 then return;   /* no write for k=3 */
  x = x + 1;
run;
title "R1 RETURN: five rows, k=3 still 30 while its neighbours moved";
proc print data=r1; run;

/* R2 — an empty transaction changes nothing and loses nothing */
data r2; do k = 1 to 5; x = k*10; output; end; run;
data r2t; stop; length k 8 d 8; run;
data r2;
  modify r2 r2t;
  by k;
  x = x + d;
run;
title "R2 empty transaction: all five rows survive, all values unchanged";
proc print data=r2; run;

/* R3 — only the FIRST duplicate in the master is updated (p.245) */
data r3; k=1;x=10;output; k=2;x=20;output; k=2;x=25;output; k=3;x=30;output; run;
data r3t; k=2; d=100; output; run;
data r3;
  modify r3 r3t;
  by k;
  x = x + d;
run;
title "R3 duplicate master keys: first k=2 becomes 120, second stays 25";
proc print data=r3; run;
