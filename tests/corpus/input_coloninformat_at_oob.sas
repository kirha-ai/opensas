/* BUG-colonatoob: a colon informat (`:$w.`) after an `@n` pointer positioned PAST
   the end of a short input line must NOT crash (was rc=134 SIGABRT). The `@n`
   cursor is clamped to line.len.

   GAP-inputeofdegrade REVISED WHAT HAPPENS NEXT — see input_plusn_oob for the
   same reasoning and citations. Statements ref printed p.177: a pointer at or
   past the end of the record makes SAS "go to column 1 of the next record to
   read it"; printed p.178: with no next record, execution stops. So the `oob`
   block below writes NO observation (it used to write one with the variable
   missing — MISSOVER's documented job under printed p.133, not FLOWOVER's under
   printed p.132), and the NEW `flow` block carries a following record so the
   clamp is still proved non-crashing against a real flowed value.
   oob:  `@5` on "ab" alone                    → step ends, NO obs (no crash).
   flow: `@5 a :$3.` on "ab" / "hello"          → a = "hel" (flowed to record 2).
   ctrl: `@5` on "XXXXhello" (in range)         → b = "hel"  (unchanged). */
data oob;
  input @5 a :$3. @5 c $3.;
  datalines;
ab
;
run;
data flow;
  input @5 a :$3.;
  datalines;
ab
hello
;
run;
data ctrl;
  input @5 b :$3.;
  datalines;
XXXXhello
;
run;
proc print data=oob noobs; run;
proc print data=flow noobs; run;
proc print data=ctrl noobs; run;
