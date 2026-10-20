/* EPIC-charfixedwidth-slice1 (GH#27, MED silent-wrong — validator-probed on
   live SAS 9.4): SAS fixes a char variable's storage width at COMPILE time;
   opensas re-derived it from EVERY stored value (growing 3->6 and shrinking
   6->3 — the silent-wrong this slice kills). Language Reference: Concepts
   p.49: the first reference that gives a variable a length fixes it — for an
   undeclared var first seen in `v = "<literal>"`, that width is the
   literal's. This slice stamps exactly that (assignment arm + retain-init
   path); every later store then truncates at the width via setAt, the SAME
   truncate a declared LENGTH always had.

   CASE1  y="n/a"; x="abcdef"; y=x;        -> y $3, second assign truncates to abc
   CASE2  s6="abcdef"; s6="n/a";           -> keeps $6 (first wins), stores n/a, vlength 6
   CASE3  f="n/a"; f=upcase("abcdef");     -> fn RHS AFTER the literal truncates to ABC
   CASE4  contents Len: first-assign case reports 3 (was the widest value, 6);
          the length-stmt twin stays 3
   CASE5  retain r6 "abcdef"; r6="n/a";    -> the init literal fixes $6, later literals fit
   CASE6  per-row re-execution stamps ONCE: row 2 keeps the row-1 width

   CONTROLS (the slice's hard boundary, pinned so a regression is loud): a
   NON-literal first RHS keeps today's floating width — upcase/cats results
   stay FULL-LENGTH. That computed class is exactly what the REVERTED broad
   width-on-first-assign attempt truncated ('small'->'sma',
   'CARDIAC DISORDERS'->'DISOR'); SQL computed widths are pinned separately
   in charwidth_sql_nonregress.sas. (no PHI) */

/* CASE1 — the GH#27 repro */
data t1;
  y = "n/a";
  x = "abcdef";
  y = x;
  len = length(y);
  vlen = vlength(y);
run;
data _null_;
  set t1;
  put 'CASE1 ' y= 'len=' len 'vlen=' vlen;
run;

/* CASE2 — shrink: first width wins, the short literal does not re-size */
data t2;
  s6 = "abcdef";
  s6 = "n/a";
  len = length(s6);
  vlen = vlength(s6);
run;
data _null_;
  set t2;
  put 'CASE2 ' s6= 'len=' len 'vlen=' vlen;
run;

/* CASE3 — a computed RHS after the literal truncates at the literal's width */
data t3;
  f = "n/a";
  f = upcase("abcdef");
  len = length(f);
  vlen = vlength(f);
run;
data _null_;
  set t3;
  put 'CASE3 ' f= 'len=' len 'vlen=' vlen;
run;

/* CASE4 — CONTENTS Len: the descriptor carries the fixed width.
   w1: first-assign literal (3) + a wider store (truncates) -> Char 3, abc.
   w2: the length-stmt twin stays Char 3. */
data w1;
  f = "n/a";
  f = "abcdef";
run;
data w2;
  length f $3;
  f = "n/a";
  f = "abcdef";
run;
proc contents data=w1; run;
proc contents data=w2; run;
proc print data=w1 noobs; run;

/* CASE5 — the retain-init store path stamps the same way */
data t5;
  retain r6 "abcdef";
  r6 = "n/a";
  len = length(r6);
  vlen = vlength(r6);
run;
data _null_;
  set t5;
  put 'CASE5 ' r6= 'len=' len 'vlen=' vlen;
run;

/* CASE6 — the stamp persists across iterations: row 2's literal re-store is
   a no-op and the wider computed store still truncates */
data t6;
  input id $1.;
  c = "ab";
  c = upcase("xyz12");
  put 'CASE6 ' id= c=;
  datalines;
1
2
;
run;

/* CONTROLS — non-literal first RHS: width keeps floating (full-length), the
   acknowledged partial the rest of EPIC-charfixedwidth owns */
data t7;
  g = upcase("small");
  h = cats('CARDIAC',' DISORDERS');
  put 'CTRL ' g=;
  put 'CTRL ' h=;
run;
