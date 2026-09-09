/* BUG-missovertruncover-partial (doc-finder tick154): a short record that ends
   MID-FIELD. SAS 9.4: TRUNCOVER keeps the truncated partial value; MISSOVER does
   not accept a partially-read field — that variable is set to MISSING. The three
   records exercise: full line, partial char field (+ absent numeric), partial
   numeric field. (no PHI) */
data mo;
  infile datalines missover;
  input @1 id 2. @3 name $8. @11 score 3.;
datalines;
42ALICE   100
99BO
55CAROLINE9
;
run;
proc print data=mo noobs; run;

data tc;
  infile datalines truncover;
  input @1 id 2. @3 name $8. @11 score 3.;
datalines;
42ALICE   100
99BO
55CAROLINE9
;
run;
proc print data=tc noobs; run;
