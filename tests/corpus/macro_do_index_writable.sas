/* GAP-macrooracle-tick284 F8 — CLOSED AS NOT-A-DEFECT (@pi-f8 tick412), pinned by
   the manager so it cannot be "fixed" back.

   The ticket claimed the iterative %DO index must be an INTERNAL COUNTER that macro
   code cannot influence, and that opensas was wrong to re-read the macro variable.
   The reference says the OPPOSITE, and says it in the %DO entry itself — Macro
   Language: Reference, printed p.389 (=== pdf 404 ===, offset -15):

     "You can change the value of the index variable during processing. For example,
      using conditional processing to set the value of the index variable beyond the
      stop value when a certain condition is met ENDS PROCESSING OF THE LOOP."

   Two independent corroborations in the same volume:
     - printed p.509, the error appendix: "The index variable of a macro %DO statement
       has been set to missing or given a non-numeric value WITHIN THE LOOP." An
       internal-untouchable-counter model could never raise that error at all.
     - printed p.72: after `%do n=1 %to 5;` completes, N is 6 — the variable-as-index
       increment model, not a hidden counter.

   So writing the index is a DOCUMENTED early-exit technique. Implementing the
   ticket would have broken it and turned terminating loops into runaways — the very
   hazard the ticket warned of, while asserting the runaway direction was correct.

   T1 pins the documented early exit AND the after-loop value; T2 pins the ordinary
   loop's sequence and its after-value (p.72's rule: after `%do n=1 %to 5;`, N is 6).
   Both are asserted on STDOUT via a DATA step rather than with %put, because %put
   writes to the LOG and the corpus diffs stdout only — a %put-based fixture here
   would have passed vacuously. @pi-f8 separately verified that a non-numeric index
   (`%let i=abc;`) already fails loud at rc 1 with p.509's own message; that stays in
   the findings rather than here, since this fixture is an rc-0 pin. */

%macro earlyexit;
  %global t1seq t1after;
  %let t1seq =;
  %do i = 1 %to 3;
    %let t1seq = &t1seq.[&i];
    %let i = 99;
  %end;
  %let t1after = &i;
%mend;
%earlyexit

%macro plainloop;
  %global t2seq t2after;
  %let t2seq =;
  %do n = 1 %to 5;
    %let t2seq = &t2seq.[&n];
  %end;
  %let t2after = &n;
%mend;
%plainloop

data _null_;
  put "T1-SEQ=&t1seq";
  put "T1-AFTER=&t1after";
  put "T2-SEQ=&t2seq";
  put "T2-AFTER=&t2after";
run;
