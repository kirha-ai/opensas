/* QA tick395 cross-landing sweep.  GAP-meanspctlkeywords (678652ac) grew
   computeStatsV's percentile array from 6 to 12 slots and re-indexed EVERY
   existing entry (p90 moved pc[3] -> pc[9], p95 pc[4] -> pc[10], p99 pc[5] ->
   pc[11]).  An index-range change is one of the two shapes most likely to go
   wrong quietly, and the landing's own fixture only checks the six NEW
   keywords -- nothing pinned old and new percentiles side by side on the same
   data, which is the only way a mis-shifted slot shows up.

   Every value below is hand-computed under QNTLDEF=5 (the MEANS default, the
   same rule tests/corpus/means_pctl*.sas pins): with the n values sorted
   ascending and np = p/100 * n, an INTEGER np averages x[np] and x[np+1],
   otherwise take x[ceil(np)].

   n = 5, sorted 2 4 4 6 8:
     p1/p5/p10 -> np < 1        -> x[1] = 2
     p20 np=1   -> (2+4)/2 = 3      p30 np=1.5 -> x[2] = 4
     p40 np=2   -> (4+4)/2 = 4      p60 np=3   -> (4+6)/2 = 5
     p70 np=3.5 -> x[4] = 6         p80 np=4   -> (6+8)/2 = 7
     p90/p95/p99 -> np > 4      -> x[5] = 8
   SUMWGT is n when there is no WEIGHT (Statistical Procedures printed p.410),
   so 5 here and 6 = 1+2+3 under the WEIGHT below. */

data five;
  input x @@;
cards;
2 4 4 6 8
;
run;

/* Old and new percentiles interleaved, so a shifted pc slot cannot hide. */
proc means data=five n p1 p5 p10 p20 p30 p40 p50 p60 p70 p80 p90 p95 p99 sumwgt;
  var x;
run;

/* n = 1 and n = 2: every percentile collapses onto the few values present. */
data one; x = 5; run;
proc means data=one n p10 p20 p30 p40 p60 p70 p80 p90 sumwgt; var x; run;

data two;
  input x @@;
cards;
1 9
;
run;
proc means data=two n p10 p20 p40 p60 p80 p90; var x; run;

/* OUTPUT + AUTONAME: the suffix each new StatKind contributes (statSasName). */
proc means data=five noprint;
  var x;
  output out=auto p20= p80= sumwgt= probt= / autoname;
run;
proc print data=auto; run;

/* WEIGHT: SUMWGT is the sum of the weights, and MEANS must agree with
   UNIVARIATE's `Sum Weights` moment on the same data. */
data wt;
  input x w @@;
cards;
2 1 4 2 6 3
;
run;
proc means data=wt n sumwgt mean sum; var x; weight w; run;
proc univariate data=wt noprint; var x; weight w; output out=uw n=nn sumwgt=sw; run;
proc print data=uw; run;

/* PRT is a MEANS-family alias of PROBT (printed p.1492): both spellings, one
   value, side by side. */
proc means data=five prt probt; var x; run;
