/* QA tick364 cross-landing: BUG-lengthaftersetinput x MERGE x BY. The
   established-length guard used to fire only on the assignment path; it now
   fires on the SET and INPUT paths too. bug_lengthaftersetinput pins SET /
   INPUT / assign with PUT; this pins the two shapes it does not reach — a
   MERGE-established variable, and a SET step that also carries a BY — and it
   pins them through CONCATENATION, which is where a wrong storage length
   actually corrupts data rather than merely warning.

   Language Reference: Concepts p.49 note 1: "You cannot change the length of a character variable
   with a subsequent LENGTH or ATTRIB statement within the same DATA step."
   So the FIRST length stands and `s || 'X'` must not acquire the padding of
   the ignored later length. The warning arms live in the captured-diagnostics
   unit tests, never here. */

data a; length s $3; s='abc'; k=1; run;

/* 1. MERGE establishes s at $3; the later LENGTH $10 is ignored, so the
      concatenation is 'abcX', not 'abc' + 7 blanks + 'X'. */
data m1;
  merge a a;
  length s $10;
  t = s || 'X';
run;
proc print data=m1 noobs; run;

/* 2. Same rule in a step that also carries a BY — the BY rework routed PROC
      and DATA-step BY through one scanner in this same batch, so the pair is
      worth pinning together. */
data m2;
  set a;
  by s;
  length s $10;
  t = s || 'X';
run;
proc print data=m2 noobs; run;

/* 3. Control: LENGTH placed FIRST still pins the schema at $10, so the SAME
      expression pads to 10 and t is 11 wide. If arm 1/2 ever regressed to
      honoring the late LENGTH, they would print this row's shape instead. */
data m3;
  length s $10;
  set a;
  t = s || 'X';
run;
proc print data=m3 noobs; run;
