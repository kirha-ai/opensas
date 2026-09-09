/* QA tick290 — D-014 positive control for PROC COMPARE.
   main.zig hoists a mid-step TITLE/FOOTNOTE/OPTIONS to its own global segment but
   LEAVES ITS TOKENS in the step, so runCompare's D-002 fail-loud statement loop
   must skip a parser.isGlobalKw statement to its semicolon. Without that skip a
   single legal mid-step TITLE becomes a hard ERROR, and errhalt then poisons every
   LATER step of the program (the BUG-transposeglobalstmt shape, fixed for TRANSPOSE
   AND COMPARE in 4c4fefb). TRANSPOSE has qa_transpose_valid_opts; COMPARE had NO
   fixture, so its half of D-014 was unproven. This locks it: the mid-step TITLE and
   FOOTNOTE are honored, COMPARE still runs, and the step AFTER it still executes.
   A genuinely unknown COMPARE statement must still fail loud (compare_failloud_opt). */
data a;
  input id x;
  datalines;
1 10
2 20
;
run;

data b;
  input id x;
  datalines;
1 10
2 20
;
run;

proc compare base=a compare=b;
  title "QA D-014 COMPARE";
  id id;
  footnote2 "hoisted footnote";
run;

/* errhalt canary: this step MUST still run — an ERROR in the step above would
   put the session in syntax-check mode and silently skip everything below. */
title;
footnote;
data after;
  z = 42;
run;

proc print data=after;
run;
