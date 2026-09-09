/* BUG-modifystoptruncates (F1+F2, and F3/F4/F5 fall out of the same repair) —
   a MODIFY step that ends its loop early must NOT truncate the stored master.

   THE ROOT CAUSE, in QA's words (docs/findings/modify-dataloss-audit.md):
   opensas committed a MODIFY by REBUILDING the master from the observations the
   step actually iterated and swapping it in, so the stored data set was only ever
   as complete as the loop that produced it — and anything ending the loop early
   silently truncated the file. A `stop;` on the FIRST observation EMPTIED a
   five-observation master at exit 0 with nothing in the log.

   It contradicts the statement's own abstract. Statements ref printed p.240
   (footer "240 Chapter 2 / Dictionary of SAS DATA Step Statements"): MODIFY
   "Replaces, deletes, and appends observations in an existing SAS data set IN
   PLACE but DOES NOT CREATE AN ADDITIONAL COPY." Observations the step never
   reached were neither replaced, deleted nor appended, so they must still exist.

   THE FIX IS THE COMMIT, NOT THE STATEMENTS, and QA's asymmetry is what localises
   it: a real ERROR mid-step never truncated (rc 1, all rows present) — only the
   statements that end the loop early did. So the sequential MODIFY now commits the
   way its MODIFY-BY sibling already did, through modifyReplace/modifyFlush: the
   loop records overrides BY MASTER ROW and the flush re-emits the whole master,
   applying them. One repair, five findings.

   WHY A ROW COUNT IS THE PIN: the damage was to the COMMITTED member, so reading
   it back after the step witnesses it — proven by mutation below, and separately
   proven PERMANENT by a two-process probe against a `libname` on disk (5 rows ->
   0 rows stored, then read back by a fresh process). WORK is used here so the
   fixture leaves no residue (D-017).

   POINT= CONSTRAINT, recorded so it travels with the code: the reference REQUIRES
   a STOP with POINT= ("Requirement a STOP statement", printed p.335), so the
   documented random-access idiom would have destroyed the master on first use.
   The only thing preventing that today is that POINT= on a MODIFY is gapped loudly
   at rc 2 before it can run. THIS FIX MUST STAY GREEN BEFORE MODIFY POINT= IS EVER
   IMPLEMENTED.
   expect-rc: 0 */

/* ---- F1: stop on the FIRST observation. Was 0 rows. ---- */
data m1; do k = 1 to 5; x = k*10; output; end; run;
data m1; modify m1; if k = 1 then stop; x = x + 1; run;
data _null_; set m1 nobs=n; if _n_=1 then put "F1 rows=" n; run;
proc print data=m1 noobs; title "F1 stop@1: 5 rows, ALL unmodified"; run;

/* ---- F1b: stop mid-loop — rows before it are edited, rows at and after it
        are re-emitted untouched. Loss used to be proportional. ---- */
data m2; do k = 1 to 5; x = k*10; output; end; run;
data m2; modify m2; if k = 3 then stop; x = x + 1; run;
data _null_; set m2 nobs=n; if _n_=1 then put "F1b rows=" n; run;
proc print data=m2 noobs; title "F1b stop@3: 11 21 30 40 50"; run;

/* ---- F3: DELETE means "not written" (printed p.65), which for an in-place
        step leaves the STORED observation at its old value. REMOVE (p.312) is
        the statement that deletes. opensas conflated them. ---- */
data m3; do k = 1 to 5; x = k*10; output; end; run;
data m3; modify m3; if k = 3 then delete; x = x + 1; run;
data _null_; set m3 nobs=n; if _n_=1 then put "F3 rows=" n; run;
proc print data=m3 noobs; title "F3 delete@3: k=3 survives at 30"; run;

/* ---- F4: a second REPLACE writes the SAME physical location, so it cannot
        add a row. Printed p.317 Comparisons: "REPLACE writes the observation to
        the same physical location. OUTPUT writes a new observation to the end of
        the data set." Was 10 rows for 5. ---- */
data m4; do k = 1 to 5; x = k*10; output; end; run;
data m4; modify m4; x = x + 1; replace; replace; run;
data _null_; set m4 nobs=n; if _n_=1 then put "F4 rows=" n; run;
proc print data=m4 noobs; title "F4 replace twice: 5 rows, not 10"; run;

/* ---- F5: REPLACE then REMOVE — printed p.317: "The OUTPUT, REPLACE, and
        REMOVE statements are independent of each other. More than one statement
        can apply to the same observation". Both apply to one location, so the
        row ends up REMOVED. The REMOVE used to be dropped. ---- */
data m5; do k = 1 to 3; x = k*10; output; end; run;
data m5; modify m5; if k = 2 then do; x = 999; replace; remove; end; run;
data _null_; set m5 nobs=n; if _n_=1 then put "F5 rows=" n; run;
proc print data=m5 noobs; title "F5 replace+remove: k=2 removed"; run;

/* ---- ANCHOR (QA's modify_notwritten_survives, restated here so this fixture
        cannot pass by making everything survive): RETURN leaves the observation
        intact. This is what makes F1/F3 defects rather than opinions — two
        spellings of "do not write this observation" must agree. ---- */
data m6; do k = 1 to 3; x = k*10; output; end; run;
data m6; modify m6; if k = 2 then return; x = x + 1; run;
proc print data=m6 noobs; title "anchor return@2: k=2 stays 20, others edited"; run;

/* ---- CONTROL: the ordinary case must still WRITE. A MODIFY with no early exit
        edits every row — if this block ever stops editing, the flush has started
        ignoring the loop instead of applying it. ---- */
data m7; do k = 1 to 3; x = k*10; output; end; run;
data m7; modify m7; x = x + 1; run;
proc print data=m7 noobs; title "control: all rows edited"; run;

/* ---- CONTROL: REMOVE alone still deletes, so the fix did not turn the flush
        into a blanket "preserve everything". ---- */
data m8; do k = 1 to 3; x = k*10; output; end; run;
data m8; modify m8; if k = 2 then remove; run;
data _null_; set m8 nobs=n; if _n_=1 then put "control remove rows=" n; run;
proc print data=m8 noobs; title "control: remove@2 deletes"; run;

/* ---- CONTROL: an ordinary SET step with stop; legitimately produces a SHORT
        NEW data set. Identical mechanism, opposite acceptability — this is why
        the rebuild was wrong only for MODIFY. ---- */
data src; do k = 1 to 5; x = k*10; output; end; run;
data shortnew; set src; if k = 3 then stop; run;
data _null_; set shortnew nobs=n; if _n_=1 then put "control set-stop rows=" n; run;

/* ---- BOUNDARY CONTROL, the one that matters most, from QA's rebuild-commit
        scope audit: the SAME-NAME creating step. `data d; set d; if k=3 then
        stop;` MUST still truncate to 2 — it CREATES a data set, so STOP's own
        sentence applies (printed p.346: "SAS writes a data set for the current
        DATA step. However, the observation being processed when STOP executes is
        not added"), and only MODIFY is the opposite case because printed p.240
        says in place, no additional copy. A fix that made "stop no longer
        truncates" globally would break documented behaviour while still making
        every block above green, so this is the boundary the repair has to
        respect. It is safe here by CONSTRUCTION and not by luck: the commit state
        is created only inside buildDriver's MODIFY arm, which a `set` step never
        reaches. QA's rebuild_commit_discriminator fixture guards the same line. */
data samename; do k = 1 to 5; x = k*10; output; end; run;
data samename; set samename; if k = 3 then stop; run;
data _null_; set samename nobs=n; if _n_=1 then put "boundary same-name set-stop rows=" n; run;
