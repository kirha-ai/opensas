/* PROC COMPARE output-shaping options (NOTE-compareoptsnoop). Before the fix
   NOVALUES / NOSUMMARY / BRIEF were parsed then ignored — every one printed the
   full report. Each must now suppress its part of the report:
     NOVALUES  — summaries only, no value-difference detail
     NOSUMMARY — value differences only, no summary sections
     BRIEF     — compact: header + value differences, no summaries
   A plain COMPARE (no options) still prints the full report unchanged.
   One known difference: x in obs 2 (20 vs 25). */
data prod;
  input id x y;
  datalines;
1 10 100
2 20 200
3 30 300
;
run;
data qc;
  input id x y;
  datalines;
1 10 100
2 25 200
3 30 300
;
run;

/* NOVALUES: summaries print, the Value Comparison Results detail is suppressed */
proc compare base=prod compare=qc novalues;
run;

/* NOSUMMARY: summary sections suppressed, value differences still print */
proc compare base=prod compare=qc nosummary;
run;

/* BRIEF: compact — header + value differences, no summaries */
proc compare base=prod compare=qc brief;
run;

/* plain COMPARE: full report, unchanged */
proc compare base=prod compare=qc;
run;
