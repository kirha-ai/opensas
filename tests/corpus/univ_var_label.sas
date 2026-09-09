/* NOTE-univvarlabel: UNIVARIATE's "Variable:" heading carries the analysis
   variable's LABEL in parentheses when it has one, and we printed the bare name.
   Base SAS 9.4 Procedures Guide: Statistical Procedures shows the labelled form
   20+ times; two verified against their own page headers —
     Output 4.2.1, printed p.473 : "Variable: Score (Exam Score)"
     Getting Started, printed p.291: "Variable: LoanToValueRatio (Loan to Value Ratio)"
   and the UNLABELLED control is on the facing example, Output 4.1.1 printed p.471:
   "Variable: Systolic", a bare name. PROC PRINT already resolved the same label, so
   the value was on the column all along — only this one heading ignored it.

   ARM 1 is the book's own Example 4.2 step, label INCLUDED this time. Its sibling
   fixture univ_mode_tie_note.sas deliberately drops the label, precisely so that
   fixing this heading would not have to move that golden; the differential confirms
   it did not — zero movers across 1826 files.

   ARM 2 is the control that keeps the fix honest: no label, so the bare name must
   still print with nothing appended.

   ARM 3 pins the edge case the doc cannot settle — a label explicitly set to the
   empty string is treated as ABSENT, not rendered as an empty "()" suffix.

   Not pinned here: the TWO spaces after "Variable:". The text extraction collapses
   runs of spaces (the Moments rows come out single-spaced too), so it cannot settle
   one space versus two; the existing width is left exactly as it was. */
data exam;
  label Score = 'Exam Score';
  input Score @@;
  datalines;
81 97 78 99 77 81
;
run;
proc univariate data=exam;
  var Score;
run;
data plain; input x @@; datalines;
1 2 3 4 5
;
run;
proc univariate data=plain;
  var x;
run;
data blanklab;
  label y = '';
  input y @@;
  datalines;
2 4 6
;
run;
proc univariate data=blanklab;
  var y;
run;
