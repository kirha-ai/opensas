/* Language Reference: Concepts Ch.22 "BY-Group Processing in the DATA Step" (pp.534-535, p.538
   Example 3) + Ch.4 Table 4.6 (p.72) — stated rules opensas already gets RIGHT
   that nothing else in the corpus pinned (doc-finder tick300).
   Deliberately EXCLUDES the statement-form RENAME across multiple output data
   sets (Table 4.6: statements "effect all output data sets") — that is this
   pass's HIGH finding, and pinning today's output would DEFEND the bug.
   Also avoids the `put var=` named form: it echoes the reference-site case
   rather than the stored name (this pass's LOW), so a PUT-based golden here
   would pin that too. */

/* p.535: "For the last observation in a data set, the value of all
   LAST.variable variables are set to 1." A FIRSTOBS=/OBS= slice REDEFINES which
   observation is first and last, so the BY flags must follow the SLICED stream,
   not the physical one. */
data grp;
  input k v;
  datalines;
1 1
1 2
1 3
2 9
;
run;

data cut;
  set grp(obs=2);   /* obs 2 becomes the LAST obs -> lk=1 mid-group */
  by k;
  fk = first.k;
  lk = last.k;
run;
proc print data=cut noobs; run;

data tail;
  set grp(firstobs=2);  /* obs 2 becomes the FIRST obs -> fk=1 mid-group */
  by k;
  fk = first.k;
  lk = last.k;
run;
proc print data=tail noobs; run;

/* p.534: a BY group holding exactly ONE observation has BOTH flags 1.
   p.538 Example 3: a change in an OUTER BY variable sets FIRST. on every inner
   level too, even when the inner variable's VALUE did not change (obs 3: y goes
   banana->blueberry, so FIRST.z=1 although z stays 'citron' ... and obs 4: x
   changes, so all six flags are 1). Values are the doc's own table. */
data fruit;
  input x $ y $ 10-18 z $ 21-29;
  datalines;
apple    banana      coconut
apple    banana      coconut
apple    blueberry   citron
apricot  blueberry   citron
;
run;

data flags;
  set fruit;
  by x y z;
  fx = first.x; lx = last.x;
  fy = first.y; ly = last.y;
  fz = first.z; lz = last.z;
run;
proc print data=flags; run;

/* Ch.4 Table 4.6 (p.72): the DROP and KEEP STATEMENTS "effect all output data
   sets" (unlike DROP=/KEEP= options, which "effect individual data sets"). */
data three;
  input a b c;
  datalines;
1 2 3
;
run;

data d1 d2;
  set three;
  drop b;
  output d1;
  output d2;
run;
proc print data=d1 noobs; run;
proc print data=d2 noobs; run;

data k1 k2;
  set three;
  keep a;
  output k1;
  output k2;
run;
proc print data=k1 noobs; run;
proc print data=k2 noobs; run;
