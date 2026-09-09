/* Pins Language Reference: Concepts Ch.20 Table 20.4 "Causes That Stop DATA
   Step Execution" (p.488) row by row, plus the step-boundary list at
   pp.486-487. Every count below follows from the stop condition the table
   states for that row, not from what opensas happened to print.
   doc-finder tick305.

   DELIBERATELY EXCLUDED, because pinning today's output would DEFEND a filed bug:
   Table 20.4's "multiple external files ... when end-of-file is first reached on
   any of the files" row (BUG-multiinfilelastwins), the SET+INPUT combination of
   p.489 (BUG-setinputinert), the POINT=+STOP idiom of p.488 (BUG-pointnoiterate),
   and any sum statement on the raw-INPUT path (BUG-sumvarorderinput). */

/* Row 1 -- "no data / any / after only one iteration": a step that reads no input
   iterates exactly ONCE, however many observations its DO loop writes (p.493
   makes the same point with a loop that writes one row per year). */
data looped;
  do k = 1 to 3; output; end;
  put 'iterations=' _n_;
run;

/* Row 3 -- "raw data / instream data lines / INPUT statement / after the last data
   line is read": 3 data lines in, 3 observations out. */
data cards;
  input dose;
  datalines;
11
12
13
;
run;
data _null_; set cards; put 'cards dose=' dose; run;

/* Row 2 -- "any data / when it executes STOP or ABORT": STOP ends the step before
   the source is exhausted AND the current observation is not written. */
data halted;
  set cards;
  if dose = 13 then stop;
run;
data _null_; set halted; put 'halted dose=' dose; run;

/* Rows 6 and 7 -- "one SAS data set / SET / after the last observation is read"
   and "multiple SAS data sets / ONE SET, MERGE, MODIFY, or UPDATE statement /
   when ALL input data sets are exhausted": 3 + 2 = 5 observations. Both sources
   carry the SAME variable on purpose, so this block cannot encode the separate
   in-flight BUG-setsourcereset (a source switch must blank the columns the new
   source lacks). */
data extra;
  input dose;
  datalines;
71
72
;
run;
data joined; set cards extra; run;
data _null_; set joined; put 'joined dose=' dose; run;

data short;
  input site;
  datalines;
7101
7102
;
run;

/* Row 8 -- "multiple SAS data sets / MULTIPLE SET, MERGE, MODIFY, or UPDATE
   statements / when end-of-file is reached by ANY of the data-reading statements":
   the SHORTER source decides in either textual order, and the extra observation of
   the longer one never reaches the output. 3 and 2 rows -> 2 observations. */
data zipa; set cards; set short; run;
data _null_; set zipa; put 'zipa dose=' dose ' site=' site; run;
data zipb; set short; set cards; run;
data _null_; set zipb; put 'zipb site=' site ' dose=' dose; run;

/* pp.486-487 step boundaries. The first DATA statement below has NO RUN: the next
   DATA statement is itself the boundary (p.486 illustrates exactly this), and a
   PROC statement is the boundary for the second. */
data edge1;
  set short;
data edge2;
  set short;
proc print data=edge1 noobs; run;
proc print data=edge2 noobs; run;

/* p.487: four semicolons close a DATALINES4 block and are that step's boundary. */
data quad;
  input seq;
  datalines4;
1
2
;;;;
data _null_; set quad; put 'quad seq=' seq; run;
