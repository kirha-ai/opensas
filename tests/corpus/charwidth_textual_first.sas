/* EPIC-charfixedwidth slice-1 REMAINDER (GH#31, HIGH silent-wrong — a
   regression from the slice's runtime stamping, validator-probed on live
   SAS 9.4): SAS fixes an undeclared char variable's width at COMPILE time
   from the first TEXTUAL occurrence — Language Reference: Concepts p.49,
   "Creating Variables": the first reference that gives a variable a length
   is its first occurrence in the DATA step, in SOURCE order, INCLUDING
   branches that never run. opensas stamped at the first EXECUTED literal
   instead, so the width was data-order dependent and dead code never
   stamped — silent truncation at rc 0, no NOTE. The seven probes:

   P1  if/else ladder, THEN wider but executed second   -> $6: ab / abcdef
   P2  severity ladder, first row takes the last arm    -> $6: MILD/MODERA/SEVERE
   P3  dead branch `if 0 then y='…'` still stamps       -> $8: abcdef
   P4  CONTROL short textual first, wider branch later  -> $2: ab (already right)
   P5  CONTROL retain init textually first              -> $2: ab (already right)
   P6  CONTROL then-branch literal runs first too       -> $6: abcdef / ab
   P7  assignment textually BEFORE the retain statement -> $6: abcdef

   This closes the textual-vs-executed remainder of EPIC-charfixedwidth
   slice-1 (GH#27); the computed-RHS width class stays out of scope
   (charwidth_literal_fix.sas CTRL + charwidth_sql_nonregress.sas pin that
   boundary). (no PHI) */

/* P1 — the GH#31 repro: the THEN branch is textually first ($6) even though
   the ELSE executes first */
data p1;
  do i = 1 to 2;
    if i = 2 then y = 'abcdef';
    else          y = 'ab';
    vl = vlength(y);
    put 'P1 i=' i 'y=' y 'vl=' vl;
    output;
  end;
  keep i y;
run;

/* P2 — the severity ladder: the first row takes MILD (the LAST arm), but
   SEVERE is textually first -> $6, so MODERATE renders MODERA */
data p2in;
  input sev;
  datalines;
1
2
3
;
run;
data p2;
  set p2in;
  if sev = 3 then grade = 'SEVERE';
  else if sev = 2 then grade = 'MODERATE';
  else                 grade = 'MILD';
  vl = vlength(grade);
  put 'P2 sev=' sev 'grade=' grade 'vl=' vl;
run;

/* P3 — dead code stamps: `if 0` never executes, its literal is still the
   first TEXTUAL occurrence -> $8, both live literals fit */
data p3;
  if 0 then y = 'abcdefgh';
  y = 'ab';
  y = 'abcdef';
  vl = vlength(y);
  put 'P3 y=' y 'vl=' vl;
run;

/* P4 — CONTROL (correct before GH#31, pinned so a regression is loud): the
   short literal is textually first -> $2, the later branch's wider literal
   truncates */
data p4;
  y = 'ab';
  if 0 then y = 'abcdef';
  vl = vlength(y);
  put 'P4 y=' y 'vl=' vl;
run;

/* P5 — CONTROL (correct before GH#31, pinned): the retain init is textually
   first -> $2, the later assignment truncates */
data p5;
  retain y 'ab';
  y = 'abcdef';
  vl = vlength(y);
  put 'P5 y=' y 'vl=' vl;
run;

/* P6 — CONTROL: then-branch literal is textually AND executably first; the
   stamp persists across rows (row 2's shorter literal fits, does not resize) */
data p6;
  do i = 1 to 2;
    if i = 1 then z = 'abcdef';
    else          z = 'ab';
    vl = vlength(z);
    put 'P6 i=' i 'z=' z 'vl=' vl;
    output;
  end;
  keep i z;
run;

/* P7 — the retain twin of P5: the assignment is textually BEFORE the retain
   statement, so IT wins -> $6; slice-1 stamped the init literal in runtime
   order and left $2 */
data p7;
  y = 'abcdef';
  retain y 'ab';
  vl = vlength(y);
  put 'P7 y=' y 'vl=' vl;
run;
