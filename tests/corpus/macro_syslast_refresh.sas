/* BUG-syslastrefresh — &SYSLAST and &SYSNOBS refresh when a data set is created.

   They were seeded once at session start and NEVER updated, so `&syslast` read
   `_NULL_` and `&sysnobs` read `0` for the whole run. Macro Language ref printed
   p.266 (marker `=== pdf 281 ===`; offset -15, and that page's own footer
   verified), SYSLAST's Details:
       The name is stored in the form libref.dataset. You can insert a reference
       to SYSLAST directly into SAS code in place of a data set name. … If no SAS
       data set has been created in the current program, the value of SYSLAST is
       _NULL_, with no leading or trailing blanks.
   so `_NULL_` is right ONLY until something is created. Printed p.272 for
   &SYSNOBS: "the number of observations that exist in the last data set that was
   closed by the previous procedure or DATA step."

   THE DANGEROUS HALF IS &SYSNOBS, and block G is the single most important
   assertion in this fixture. `%if &sysnobs = 0 %then %return;` is the standard
   guard in SDTM domain drivers; with &sysnobs frozen at 0 the guard fired on
   EVERY data set, so a populated clinical domain was silently NOT PRODUCED — no
   diagnostic, no bad exit code. An earlier partial fix made this worse rather
   than better: it added the SEEDING without the refresh, converting a LOUD
   unresolved-reference warning into a SILENT stale 0.

   ONE PRODUCER, so there are no per-PROC rules to get wrong: every creator routes
   through Library.put — the DATA-step commit, all 151 proc.zig OUT= writes, PROC
   SORT, SQL CREATE TABLE, PROC APPEND. Blocks S/Q/M/A pin five of them and they
   agree by construction, not by five separate patches.
   expect-rc: 1 */

/* ---- the charter's sequence: DATA, DATA-from-SET, PROC SORT OUT= ---- */
data one; x=1; output; x=2; output; run;
data _null_; file print; put "A1 [&syslast] [&sysnobs]"; run;
data two; set one; run;
data _null_; file print; put "A2 [&syslast] [&sysnobs]"; run;
proc sort data=two out=three; by x; run;
data _null_; file print; put "A3 [&syslast] [&sysnobs]"; run;

/* ---- G: THE CLINICAL GUARD. Must take the PROCESS branch on a populated
        data set. This is the assertion the whole ticket exists for. ---- */
%macro chk;
  %if &sysnobs = 0 %then %let br = SKIP - no observations;
  %else %let br = PROCESS &sysnobs obs;
  data _null_; file print; put "GUARD: &br"; run;
%mend;
%chk

/* ---- the documented substitution: &SYSLAST used IN PLACE OF a data set name
        ("You can insert a reference to SYSLAST directly into SAS code in place
        of a data set name", printed p.266). Reads WORK.THREE's 2 rows. ---- */
data viaref; set &syslast; run;
/* literal title on purpose: `&syslast` inside a TITLE resolves at the LATER
   step-flush, so echoing it here would print WORK.VIAREF and read like a bug. */
proc print data=viaref noobs; title "viaref built via syslast: WORK.THREE rows"; run;
title;

/* ---- N: `data _NULL_;` creates nothing, so the pair must NOT advance. No
        special case does this — main.zig never commits _NULL_, so it never
        reaches the choke point. ---- */
data _null_; junk=1; run;
data _null_; file print; put "N1 after-_null_ [&syslast] [&sysnobs]"; run;

/* ---- Z: a REAL zero-observation data set. &sysnobs = 0 here is a GENUINE
        count, and it is distinguishable from the old frozen 0 because &syslast
        moves with it — conflating the two was the original trap. ---- */
data emptyds; stop; run;
data _null_; file print; put "Z1 real-zero [&syslast] [&sysnobs]"; run;

/* ---- five creators, one rule ---- */
proc sql; create table sqlt as select * from one; quit;
data _null_; file print; put "Q1 sql-create-table [&syslast] [&sysnobs]"; run;
proc means data=one noprint; var x; output out=meanout mean=m; run;
data _null_; file print; put "M1 means-out [&syslast] [&sysnobs]"; run;
/* PROC APPEND creating BASE= is the ONE case the doc states explicitly
   (Procedures Guide printed p.109: "When the BASE= data set does not exist and
   PROC APPEND creates it, PROC APPEND sets _LAST_ to the name of the BASE= data
   set") — and it comes free from the shared choke point. */
proc append base=newbase data=one; run;
data _null_; file print; put "A4 append-creates-base [&syslast] [&sysnobs]"; run;

/* ---- P: a PROC that creates NOTHING leaves the pair alone. ---- */
proc print data=one noobs; title "print creates nothing"; run;
data _null_; file print; put "P1 after-print [&syslast] [&sysnobs]"; run;

/* ---- T: a two-level name keeps its OWN libref, uppercased — the doc's form is
        libref.dataset, demonstrated as FIRSTLIB.SALESRPT from mixed-case input. */
data work.mixedCase; c=1; output; c=2; output; c=3; output; run;
data _null_; file print; put "T1 [&syslast] [&sysnobs]"; run;

/* ---- E: DOC-SILENT, settled on INTERNAL CONSISTENCY and labelled as such.
        The volumes say nothing about a step that ERRORS. opensas's own
        GAP-errgatereplaces rule (Language Reference: Concepts printed p.175, Example Code 8.6) is that a
        stopped step still CREATES a new member — a following PROC PRINT reports
        "No variables in data set" and not "does not exist". So the member DOES
        exist, and naming it is consistent; the pair follows the member store
        exactly. Last, because errhalt ends the run here.

        WHAT IS AND IS NOT PINNED HERE, stated because the difference is easy to
        miss: E1 pins the value BEFORE the failing step, and the rc-1 pins that the
        step failed. The value AFTER it is NOT pinnable in a corpus fixture — the
        error stops every later step, including any probe — so the sharper case
        (output name ALREADY EXISTS, live member NOT replaced, `put` never called,
        pair correctly left naming WORK.MARKER) was verified by hand probe instead
        and is recorded in the commit message. No unreachable probe is left below
        pretending to cover it. ---- */
data keeper; k=1; output; run;
data marker; m=1; output; run;
data _null_; file print; put "E1 before-fail [&syslast] [&sysnobs]"; run;
data keeper; set nosuchdataset; run;
