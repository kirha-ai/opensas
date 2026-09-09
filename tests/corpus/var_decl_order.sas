/* BUG-varorder: LENGTH/ATTRIB-declared vars were always seeded into the PDV
   FIRST, before RETAIN/assignment vars, regardless of source-statement order.
   SAS establishes a variable at the first statement that mentions it:
   `retain r1 r2; length l1 $3 l2 $3;` must output r1 r2 l1 l2 (not l1 l2 r1 r2).
   LENGTH-first still leads (t2) — only the RETAIN/other-before-LENGTH case moves.
   corpus-varorder. */
data t;
  retain r1 r2;
  length l1 $3 l2 $3;
  r1 = 1; r2 = 2; l1 = "abc"; l2 = "def";
  output;
run;
proc print data=t noobs; run;
data t2;
  length l1 $3 l2 $3;
  retain r1 r2;
  r1 = 1; r2 = 2; l1 = "abc"; l2 = "def";
  output;
run;
proc print data=t2 noobs; run;
