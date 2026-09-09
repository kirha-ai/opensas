/* QA tick395 cross-landing sweep.  Five landings in one push batch all touched
   the PROC statistic machinery and were gated only against each other's absence:
     2bc94e52  SUMWGT decoded as a statistic keyword (MEANS family + UNIVARIATE)
     9bc08694  SUMWGT hoisted ABOVE statAgg's `n == 0` early-out (PROC SQL)
     678652ac  six new percentile StatKinds, computeStatsV's pc array 6 -> 12
   The hoist and the widened array meet on exactly one input class: the
   all-missing / zero-row group.  No fixture exercised the three surfaces on the
   SAME data, so this pins them agreeing.

   SUMWGT is 0 and NOT missing when nothing is non-missing: Base SAS 9.4
   Procedures Guide "Computational Requirements for Statistics" (printed p.72)
   enumerates what needs data -- N/NMISS need none, SUM/MEAN/MAX/MIN/RANGE/USS/CSS
   need one, VAR/STD/STDERR/CV need two -- and SUMWGT is in NONE of the three
   lists.  Table 2.1 (printed pp.70-71) puts SQL and UNIVARIATE on ONE row for
   SUMWGT, so the surfaces are not free to disagree.  The percentiles stay
   missing on the same data, which is the control: the hoist must lift SUMWGT
   only, never the statistics that genuinely require an observation. */

data allmiss;
  length x 8;
  x = .; output;
  x = .; output;
run;

data norows;
  length x 8;
  stop;
run;

/* MEANS: SUMWGT 0 beside N 0, all six new percentiles missing. */
proc means data=allmiss n nmiss sumwgt p20 p30 p40 p60 p70 p80; var x; run;
proc means data=norows n nmiss sumwgt p20 p80; var x; run;

/* UNIVARIATE OUTPUT: SUMWGT is a Table 4.14 keyword (printed p.354). */
proc univariate data=allmiss noprint; var x; output out=uni1 n=nn sumwgt=sw; run;
proc print data=uni1; run;

/* PROC SQL: the surface the hoist fixed -- same two numbers. */
proc sql; select n(x) as nn, sumwgt(x) as sw from allmiss; quit;
proc sql; select n(x) as nn, sumwgt(x) as sw from norows; quit;

/* And per GROUP, where every group is all-missing. */
data bygrp;
  length g $1 x 8;
  g = 'a'; x = .; output;
  g = 'b'; x = .; output;
  g = 'b'; x = 4; output;
run;
proc sql; select g, n(x) as nn, sumwgt(x) as sw from bygrp group by g; quit;
proc means data=bygrp nway n nmiss sumwgt p20 p80; class g; var x; run;
