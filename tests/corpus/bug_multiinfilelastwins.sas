/* BUG-multiinfilelastwins (doc-finder tick305 F1 + tick312 §8b repros): two
   INFILE statements in one step — the LAST one used to win for the WHOLE step,
   so the first file was never opened (silent wrong values, up to total data
   loss). Language Reference: Concepts Table 20.4 row 5 (p.488): the step stops "when end-of-file is
   first reached on ANY of the files"; p.489: "DATA steps can use a combination
   of some or all of the sources"; p.517 Table 21.5 row 10: a second
   `infile datalines` re-selects the SAME instream — no rewind. */

/* two external files: one record from EACH per iteration; EOF on the first
   (3-record) file stops the step → 3 obs */
data both;
  infile 'tests/corpus/includes/mi_fa.txt';
  input aname $ ax;
  infile 'tests/corpus/includes/mi_fb.txt';
  input bname $ bx;
run;
proc print data=both noobs; run;

/* instream + external mix (p.492's shape): external file and the datalines
   device are independent sources with independent cursors */
data mix;
  infile 'tests/corpus/includes/mi_fb.txt';
  input k $ v;
  infile datalines;
  input d;
datalines;
7
8
;
proc print data=mix noobs; run;

/* conditional INFILE: the executed branch selects the source, and fa's cursor
   survives while fb is read (per-statement read positions) */
data _null_;
   if _n_ <= 2 then infile 'tests/corpus/includes/mi_fa.txt';
   else infile 'tests/corpus/includes/mi_n2.txt';
   input k $ v;
   put "_n_=" _n_ " k=" k " v=" v;
run;

/* END= on EACH infile: per-source flags, and a REFERENCED earlier END= var
   draws no spurious "never been referenced" WARNING / uninitialized NOTE */
data _null_;
   infile 'tests/corpus/includes/mi_fa.txt' end=e1; input k $ v;
   infile 'tests/corpus/includes/mi_fb.txt' end=e2; input k2 $ v2;
   put "k=" k " v=" v " e1=" e1 " | k2=" k2 " v2=" v2 " e2=" e2;
run;
