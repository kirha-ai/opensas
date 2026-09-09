/* GAP-macrogotocomputed — a COMPUTED %GOTO destination.

   SAS 9.4 Macro Language: Reference, Fifth Edition, printed p.396 (pdf 411),
   "%GOTO Macro Statement", Required Argument `label`: "is either the name of the
   label that you want execution to branch to or a text expression that generates
   the label. A text expression that generates a label in a %GOTO statement is
   called a computed %GOTO destination." The documented form is a macro
   variable reference standing where the label name would go. Footnote: "A computed %GOTO contains % or & and resolves to a label."

   Was: handleGoto read the operand with isNameChar only, so it stopped dead at
   the `&` and the target was the EMPTY string — which process() can never match,
   so the empty target swallowed the whole rest of the macro body and the run
   still exited 0. Two DATA steps vanished with only "WARNING: %goto label :
   not found" (note the empty label) to show for it.

   Every assertion here is a DATA-step `put`, i.e. STDOUT: the corpus diffs
   stdout only, so a %put-based fixture would pass vacuously. The diagnostic TEXT
   of the two p.500/p.501 error cases is asserted in macro.zig's in-file test
   against the captured reporter.
   expect-rc: 1 */

/* ── 1. `%goto &var;` — the p.396 form. ─────────────────────────────────────── */
%macro cg_amp;
  %local jump;
  %let jump = landing;
  %goto &jump;
data _null_; put "T1-BAD-not-skipped"; run;
  %landing:
data _null_; put "T1-OK-reached-landing"; run;
%mend;
%cg_amp

/* ── 2. `%goto %mac;` — a macro CALL generating the label text. The CAUTION on
   printed p.396 is that no % precedes the LABEL NAME; a % here is a macro
   invocation whose RESULT is the label, which is the other half of the
   footnote's "contains % or &". ─────────────────────────────────────────── */
%macro cg_lbl; ender %mend;
%macro cg_call;
  %goto %cg_lbl;
data _null_; put "T2-BAD-not-skipped"; run;
  %ender:
data _null_; put "T2-OK-reached-ender"; run;
%mend;
%cg_call

/* ── 3. Indirect: the label is assembled from two references, and picked at
   run time — the reason a computed %GOTO exists at all. ──────────────────── */
%macro cg_pick(n);
  %local stem;
  %let stem = leg;
  %goto &stem.&n;
  %leg1:
data _null_; put "T3-OK-leg1"; run;
  %goto cg_done;
  %leg2:
data _null_; put "T3-OK-leg2"; run;
  %cg_done:
%mend;
%cg_pick(1)
%cg_pick(2)

/* ── 4. NULL destination: printed p.500 — "A macro variable was used as the
   label in a %GOTO statement but has a null value" → "Error: The %GOTO statement
   has no target. The statement will be ignored." IGNORED is load-bearing: the
   body after it must SURVIVE. Before the fix every %goto with an unreadable
   operand set an empty target and deleted the rest of the body instead. ──── */
%macro cg_null;
  %local h;
  %goto &h;
data _null_; put "T4-OK-body-survived-null-target"; run;
%mend;
%cg_null

/* ── 5. Resolves to something that is not a SAS name (printed p.501: a label
   with a hyphen in it): same ignore-and-report, body survives. ─────────────── */
%macro cg_badname;
  %local h;
  %let h = q-7;
  %goto &h;
data _null_; put "T5-OK-body-survived-bad-label"; run;
%mend;
%cg_badname

/* ── 6. CONTROLS — the pre-existing literal-label paths must be untouched. ── */
%macro cg_lit(flag);
  %if &flag = 1 %then %goto skip;
data _null_; put "T6-OK-goto-not-taken"; run;
  %skip:
data _null_; put "T6-OK-tail"; run;
%mend;
%cg_lit(0)
%cg_lit(1)

/* ── 7. D-004 / BUG-macrointerleave crossed with a computed %GOTO: the label is
   produced by CALL SYMPUT in an EARLIER step of the SAME macro body, so the
   step must have executed (and its var reached the macro table) before the
   %goto operand resolves. If interleaving regressed, &dest is unresolved here
   and the run takes the error path instead of the branch. ─────────────────── */
%macro cg_symput;
  %local dest;
data _null_;
  call symput('dest', 'viasymput');
run;
  %goto &dest;
data _null_; put "T7-BAD-not-skipped"; run;
  %viasymput:
data _null_; put "T7-OK-label-came-from-symput"; run;
%mend;
%cg_symput

data _null_; put "END"; run;
