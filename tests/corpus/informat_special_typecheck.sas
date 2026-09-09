/* BUG-informatallnotypecheck — the INFORMAT arm of the _ALL_/_NUMERIC_/_CHARACTER_
   special-list expansion must type-check per member exactly like the FORMAT arm
   (bb2de8d4 checked display formats only: the item rides BOTH exec attribute
   lists, so the attrs pass was given check=false to avoid a double report — but
   an informat (\x01 rider) lives on attrs ONLY, so `informat _all_ 8.;` attached
   a NUMERIC informat to CHARACTER variables SILENTLY at rc 0, while the sibling
   `format _all_ 8.;` errored rc 1. QA F1, docs/findings/qa-ghbatch.md; real SAS
   errors on both). The fix keys the check by item class — display formats on the
   .formats pass, informat riders on the .attrs pass — so each expanded member is
   validated EXACTLY ONCE (never twice, never zero).

   The errors ride stderr (stdout-invisible), so the rc pin carries them; the
   once-ness is pinned by the in-file exec.zig test on the captured reporter.
   Case C is LAST because a step ERROR errhalts the rest of the run.
   expect-rc: 1 */

/* A — no-regress: _NUMERIC_ pre-filters by type. BEST8. format + 8. informat
   reach the numeric var only; the char var is untouched; no `_numeric_`
   column. rc 0. */
data a;
  c = "s"; x = 1;
  attrib _numeric_ format=best8.;
  informat _numeric_ 8.;
  stop;
run;
proc contents data=a; run;

/* B — no-regress: an all-numeric PDV takes `length _all_ 8; format _all_ 8.2;`
   — both apply to every var, no `_all_` column. rc 0. */
data b;
  p = 1; q = 2;
  length _all_ 8;
  format _all_ 8.2;
  stop;
run;
proc contents data=b; run;

/* C — the bug and its sibling, one step: `informat _all_ 8.;` over a char var
   is an ERROR ("The numeric informat 8. cannot be used with character
   variable a."), exactly once — and the format arm still fires exactly once
   beside it (the double-report the keyed dedup exists to prevent). The step
   halts before any observation. */
data c;
  a = "x"; b = 1;
  informat _all_ 8.;
  format _all_ best8.;
  stop;
run;
