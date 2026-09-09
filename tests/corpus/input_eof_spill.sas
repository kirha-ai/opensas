/* GAP-inputeofdegrade (part 3/3) — a FLOWOVER list-input SPILL that runs out of
   records ends the step; it does not write the partial observation.

   FLOWOVER is the default. Statements ref printed p.132 (footer "132 Chapter 2 /
   Dictionary of SAS DATA Step Statements"):
       FLOWOVER causes an INPUT statement to continue to read the next input data
       record if it does not find values in the current input line for all the
       variables in the statement. FLOWOVER is the default behavior of the INPUT
       statement.
   So when values run out, FLOWOVER's ONLY move is to take another record. If
   there is none, printed p.178 (footer "178 Chapter 2 / …") governs:
       If a DATA step tries to read another record after it reaches an
       end-of-file, then execution stops.

   WHAT WAS WRONG, stated precisely: opensas assigned the remaining variables
   MISSING and wrote the observation — which is MISSOVER's documented behaviour,
   printed p.133: "prevents an INPUT statement from reading a new input data
   record ... variables without any values assigned are set to missing." The two
   options are defined by contrast, and opensas was silently giving FLOWOVER
   MISSOVER's semantics. That is why block 4 below matters: choosing MISSOVER must
   still produce the missing-value observation, and it does.

   THE OBSERVATION COUNT IS DOC-PRINTED, not inferred. Printed p.145 (footer
   "INFILE Statement 145") gives a three-data-line program and states "the data
   set SCORES contains two, not three, observations" — an iteration that reaches
   EOF mid-observation contributes NOTHING.
   expect-rc: 0 */

/* 1 — the spill at EOF. Record 2 holds only 2 of the 3 values, so FLOWOVER wants
   a record 3. There is none: ONE observation, and no `4 5 .` row. */
data one;
  infile datalines;
  input p q r;
  put "1 iter p=" p " q=" q " r=" r;
  datalines;
1 2 3
4 5
;
run;
proc print data=one noobs; title "1 no partial row"; run;

/* 2 — the spill ACROSS records still works when a record IS available: this is
   FLOWOVER doing its documented job, and it must not be collateral damage.
   Three records of one token each, `input a b;` → ONE observation a=1 b=2, then
   iteration 2 takes record 3 and stops. */
data spill;
  infile datalines;
  input a b;
  put "2 iter a=" a " b=" b;
  datalines;
1
2
3
;
run;
proc print data=spill noobs; title "2 spill works; odd tail drops"; run;

/* 3 — EVEN token count: fully satisfied, nothing to stop for. The control that
   proves blocks 1-2 are the EOF rule and not a lost observation. */
data even;
  infile datalines;
  input a b;
  datalines;
1
2
3
4
;
run;
proc print data=even noobs; title "3 even: two obs, unchanged"; run;

/* 4 — MISSOVER: the option whose JOB is the behaviour block 1 removed. It is
   handed a one-record window, so it never consults the next record and assigns
   missing instead — observation KEPT. If this block ever loses its row, the fix
   has leaked out of FLOWOVER and broken the documented option (D-014). */
data mo;
  infile datalines missover;
  input p q r;
  put "4 iter p=" p " q=" q " r=" r;
  datalines;
1 2 3
4 5
;
run;
proc print data=mo noobs; title "4 MISSOVER keeps the partial obs"; run;

/* 5 — TRUNCOVER, the same contrast on the other short-record option. */
data tc;
  infile datalines truncover;
  input p q r;
  datalines;
1 2 3
4 5
;
run;
proc print data=tc noobs; title "5 TRUNCOVER keeps the partial obs"; run;
