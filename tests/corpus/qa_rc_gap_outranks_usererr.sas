/* QA tick397 cross-landing sweep — the COMPOSED D-009 invariant that no
   per-landing gate could test: main.zig now carries BOTH rc directions, and
   they were only ever verified in isolation.

   `2a57cc33` moved six USER ERRORS 2 -> 1 (here: "The numeric format 8.2
   cannot be used with character variable c.", audit §2 row 2374/2376) and
   `a248f50f` moved nine GAPS 1 -> 2 in the same file (here: "system option
   NOREPLACE is not supported", audit §5d row 1436). This program fires ONE of
   each. `diag.exitCode` says a gap OUTRANKS a user error, so the process rc is
   2 — "file an opensas issue" wins over "fix your SAS", because the gap means
   opensas cannot vouch for the run at all.

   Discriminates rather than blanket-failing: the clean PROC PRINT above runs
   and prints, so an rc 2 here is the composition and not a dead interpreter.
   OPTIONS validation is a whole-program pre-pass, so the NOREPLACE gap is
   reached even though the format error already tripped syntax-check mode
   (BUG-errhalt) — that ordering is itself part of what is pinned.

   expect-rc: 2 */

data a;
  c = 'ab';
run;

proc print data=a noobs;
run;

proc print data=a;
  format c 8.2;
run;

options noreplace;
