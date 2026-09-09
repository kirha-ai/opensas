/* BUG-sqlsumwgtallmiss — SUMWGT is 0, not missing, when there is nothing to
   average, and PROC SQL must say what PROC UNIVARIATE says.

   SUMWGT IS ONE STATISTIC SHARED BY BOTH SURFACES, so a disagreement is not a
   judgement call. Base SAS 9.4 Procedures Guide, Table 2.1 (printed p.70-71),
   one row:
     SUMWGT | Sum of weights | CORR, MEANS or SUMMARY, REPORT, SQL, TABULATE,
                               UNIVARIATE
   PROC UNIVARIATE already printed `Sum Weights 0` beside `N 0`; PROC SQL
   returned MISSING, because it computes the statistic independently and its
   "no non-missing values" early-out swallowed SUMWGT along with the statistics
   that genuinely need data.

   That it is 0 is settled twice over:
   - Statistical Procedures printed p.410, "Sum of the Weights": "the sum of the
     weights is calculated as SUM(i=1..n) wi ... If there is no WEIGHT variable,
     the sum of the weights is n." PROC SQL has no WEIGHT clause at all, so the
     sum of the weights is unconditionally n — and n is 0 here.
   - Procedures Guide printed p.72, "Computational Requirements for Statistics",
     lists exactly what needs data: "N and NMISS do not require any nonmissing
     observations", "SUM, MEAN, MAX, MIN, RANGE, USS, and CSS require at least
     one nonmissing observation", "VAR, STD, STDERR, and CV require at least two
     observations". SUMWGT is in NONE of the three lists. The closing rule,
     "Statistics are reported as missing if they cannot be computed", does not
     reach a sum over an empty set: that is computable, and it is 0.

   The same passage is why SUM/USS/CSS/RANGE/STD/VAR stay MISSING below — they
   are named in the lists that require data. Both halves are pinned so neither
   can drift into the other (the DATA-derived twin is NOTE-univallmiss). */

data allmiss;  x=.; output; x=.; output; run;
data somemiss; x=.; output; x=5; output; run;
data emptycol; length x 8; stop; run;

proc sql;
  title 'all-missing: sumwgt 0 = n 0; the data-requiring statistics stay missing';
  select n(x) as n, nmiss(x) as nmiss, sumwgt(x) as sumwgt,
         sum(x) as sum, css(x) as css, uss(x) as uss, range(x) as range,
         std(x) as std, var(x) as var, stderr(x) as stderr, cv(x) as cv
    from allmiss;
  title 'zero-row table, column declared: sumwgt 0 = n 0';
  select n(x) as n, sumwgt(x) as sumwgt from emptycol;
  title 'CONTROL: one non-missing value — sumwgt tracks n, unchanged';
  select n(x) as n, sumwgt(x) as sumwgt, sum(x) as sum from somemiss;
  title 'CONTROL: sumwgt of an EXPRESSION takes the same rule';
  select sumwgt(x*2) as sw_expr from allmiss;
quit;
title;

/* the other surface, on the same data — the numbers must match */
proc univariate data=allmiss; var x; run;
proc univariate data=somemiss; var x; run;
