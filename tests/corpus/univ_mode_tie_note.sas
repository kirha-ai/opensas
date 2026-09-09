/* NOTE-univallmiss (second half): when values TIE for most frequent, SAS displays
   the smallest mode and prints a note saying so directly under "Basic Statistical
   Measures". Wording, placement and the count semantics all come from printed
   output in Base SAS 9.4 Procedures Guide: Statistical Procedures — Output 4.2.2,
   printed p.473: "Note: The mode displayed is the smallest of 3 modes with a count
   of 4." The rule behind it is "Calculating the Mode", printed p.413: "If a tie
   occurs for the most frequent value, the procedure reports the lowest mode ...
   The WEIGHT statement has no effect on the mode."

   ARM 1 is the book's OWN data (Example 4.2, the Exam data set) so this golden can
   be checked against the printed page: 81, 86 and 97 each occur 4 times, so SAS
   shows Mode 81 and "smallest of 3 modes with a count of 4". Output 4.2.2 is the
   DEFAULT output — the note is not gated on the MODES option.

   ARM 2 pins the guard that matters most, because a tie-counter written the naive
   way fires here: with every value distinct, every run has length 1, so "how many
   values attain the longest run" is 5 — but p.413 says "When no repetitions occur
   in the data (as with truly continuous data), the procedure does not report the
   mode", so there must be NO note and Mode must be missing.

   ARM 3 pins "The WEIGHT statement has no effect on the mode" (p.413): the weights
   are lopsided (1 carries 5 each, 3 carries 9) yet the mode is still the smallest
   of the two values that occur twice, counted UNWEIGHTED — so 2 modes, count 2,
   and Mode 1, not the heavily weighted 3. Only the moments are weighted. */
/* The book's step also carries `label Score = 'Exam Score'`, dropped here on
   purpose: SAS prints it as "Variable: Score (Exam Score)" and we print bare
   "Variable:  Score", so keeping it would bake an UNRELATED divergence (the
   label is absent from the Variable: heading — reported separately, not part of
   this fix) into a golden a future label fix would then have to move. */
data exam;
  input Score @@;
  datalines;
81 97 78 99 77 81 84 86 86 97
85 86 94 76 75 42 91 90 88 86
97 97 89 69 72 82 83 81 80 81
;
run;
proc univariate data=exam;
  var Score;
run;
data unique; input x @@; datalines;
1 2 3 4 5
;
run;
proc univariate data=unique;
  var x;
run;
data wtie; input x w @@; datalines;
1 5 1 5 2 1 2 1 3 9
;
run;
proc univariate data=wtie;
  var x;
  weight w;
run;
