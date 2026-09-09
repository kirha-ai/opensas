/* BUG-prefixreadflags (QA tick322 F2): the read-flag automatics are RETAINED
   across iterations, never set to missing — Language Reference: Concepts p.79: "The values of
   automatic variables are retained from one iteration of the DATA step to the
   next, rather than set to missing"; p.553: LAST. is 0 or 1 (never missing).
   The driver split made statements before the SET user-visible pre-read code,
   so the top-of-iteration wipe showed up as `.` before the read and 0 after
   it, within ONE iteration, with nothing ever assigning missing (plus four
   spurious missing-value NOTEs on `e + 1`).
   Step o1: the end= var starts at 0, so z = e + 1 is 1 on every row (the last
   read's e=1 only shows on the EOF pass, which writes nothing).
   Step o2: first./last. before the read are the PREVIOUS read's flags
   (initially 0/0) — not the current row's, not missing.
   Step o3: in= flags before the read likewise (concatenated sources).
   COLUMN ORDER (GAP-varorder-assignset): z / pf pl / pia pib are all defined by
   statements TEXTUALLY before the SET, so they own the earlier slots — Language Reference: Concepts
   printed p.47, "position in observation is determined by the order in which
   the variables are defined in the DATA step". The read-flag automatics they
   read (e, first./last., in=) are not output columns, so only the assignment
   targets move; sia/sib stay after g k, defined after the SET. */
data a; input g $ k; datalines;
x 1
x 2
y 3
;
run;
data b; input g $ k; datalines;
z 4
;
run;
data o1;
  z = e + 1;
  set a end=e;
run;
proc print data=o1; run;
data o2;
  pf = first.g;
  pl = last.g;
  set a;
  by g;
run;
proc print data=o2; run;
data o3;
  pia = ina;
  pib = inb;
  set a(in=ina) b(in=inb);
  sia = ina;
  sib = inb;
run;
proc print data=o3; run;
