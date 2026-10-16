/* GH#13 GAP-callexecutemacro: CALL EXECUTE MACRO-PROCESSES its argument text,
   and the two timings that produces are DIFFERENT.

   SAS 9.4 Macro Language: Reference printed p.123, "CALL EXECUTE Routine Timing
   Details": "if CALL EXECUTE produces macro language elements, those elements
   execute immediately. If CALL EXECUTE produces SAS language statements, or if
   the macro language elements generate SAS language statements, those statements
   execute after the end of the DATA step's execution."

   Pre-fix the argument was queued VERBATIM and the drain only lexes, so the
   reported program died on its own percent sign: `call execute('%rep(1)')` gave
   ERROR "unexpected character '%'" at rc 1 and took the whole run with it.

   PART 1 is the reported program (the loop form): one macro invocation queued
   per row, then a later step proving the run survived.

   PART 2 pins the ORDERING, not just the values. %PUSH does BOTH halves in one
   invocation — a %LET (macro language, immediate) and a DATA step (SAS
   statements, deferred) — and the calling step prints around them. The expected
   stdout is only producible if both timings hold:
     * the %LET ran DURING the calling step: SYMGET reads A, then AB, mid-step,
       in between the calling step's own PUT lines;
     * the generated DATA steps ran AFTER the step ended, FIFO, each carrying the
       accumulator FROZEN at its own CALL EXECUTE moment ("acc was A", then "acc
       was AB") — i.e. the text was generated at call time, not at drain time.
   A "strip the percent and queue it, expand at drain time" fix prints Part 1 and
   the two deferred lines correctly and still loses both SYMGET lines.

   %PUT is deliberately NOT pinned: it writes to the log (stderr) and the corpus
   runner diffs stdout. Invented data only (D-011). */

/* ── PART 1: the reported program ───────────────────────────────────────── */
%macro rep(id);
  data _null_; put "report for id &id"; run;
%mend rep;

data ids;
  do id = 1 to 2; output; end;
run;

data _null_;
  set ids;
  call execute(cats('%rep(', id, ')'));
run;

data _null_; put 'program finished'; run;

/* ── PART 2: the immediate/deferred split ───────────────────────────────── */
%macro push(v);
  %let acc=&acc.&v;
  %put IMMEDIATE &v - acc is now &acc;
  data _null_; put "deferred: acc was &acc"; run;
%mend push;

%let acc=;

data _null_;
  put 'step: before any call';
  call execute('%push(A)');
  mid1 = symget('acc');   /* immediate: the %LET already ran */
  put mid1=;
  call execute('%push(B)');
  mid2 = symget('acc');
  put mid2=;
  put 'step: after both calls';
run;

/* Pure macro language generates NO statements to defer — only the %LET's
   effect survives, and open code sees it. */
data _null_; put "open code: acc = &acc"; run;

/* ── PART 3: the doc's own "Example of Using CALL EXECUTE Incorrectly" ───── */
/* Printed p.123-124, verbatim program (published sample data, D-011), minus the
   PROC PRINT: "the assignment statement for SALEITEM requires the value of the
   macro variable SPECIAL at DATA step compilation. CALL EXECUTE does not produce
   the value until DATA step execution. Thus, you receive a message about an
   unresolved macro variable, and the value assigned to SALEITEM is &special."

   This is the GUARD RAIL on the fix: "immediately" means immediately at CALL
   EXECUTE time, which is still AFTER this step was compiled. A later attempt to
   be helpful here — resolving the step's own &references late, or draining the
   queue before the step ends — would make SALEITEM come out "football" and break
   the doc. The WARNING is on the log (stderr), so only the value is pinned. */
data prices;
   input code amount;
   datalines;
56 300
99 10000
24 225
;
run;

%macro items;
   %global special;
   %let special=football;
%mend items;

data sales;
   set prices;
   length saleitem $ 20;
   call execute('%items');
   saleitem="&special";
   put saleitem=;
run;
