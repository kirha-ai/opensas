/* GAP-procbydescending (tick356 F2): one BY keyword, three parsers — the PROC
   statement used to reject DESCENDING ("PROC BY descending is not yet
   supported") while the DATA step and PROC SORT honored it. All three now
   scan the BY list through the ONE shared scanner (parser.scanByList), so
   they can never silently disagree again — that side-by-side shape is the
   point of this fixture. Semantics per SAS 9.4 Statements ref p.39-43:
   DESCENDING is PER-VARIABLE (Example 2 p.43), the input must be sorted in
   the specified direction (p.40), NOTSORTED groups consecutive equal values
   without any order requirement (p.41). The loud arms — descending BY on
   ascending input ("not sorted in descending sequence"), GROUPFORMAT still
   unsupported (GAP-bygroupformat) — are pinned by the captured-diagnostics
   unit tests in src/proc.zig / src/main.zig, never here. */

data have;
  input g x;
  datalines;
3 30
2 20
2 21
1 10
;
run;

/* 1. PROC-statement BY DESCENDING (was the loud hole): sections largest
      first, one per group. */
proc print data=have noobs;
  by descending g;
run;

proc means data=have mean;
  by descending g;
  var x;
run;

/* 2. PROC SORT's own BY DESCENDING (always worked) — must agree. */
proc sort data=have out=srt;
  by descending g;
run;

/* 3. DATA-step BY DESCENDING (always worked) — FIRST./LAST. per group. */
data _null_;
  set srt;
  by descending g;
  put "DS " g= x= " f=" first.g " l=" last.g;
run;

/* 4. MIXED directions across variables: DESCENDING is per-variable —
      `by a descending b` = a ascending, b descending within a. */
data mixed;
  input a b v;
  datalines;
1 3 13
1 2 12
2 1 21
;
run;
proc print data=mixed noobs;
  by a descending b;
run;

/* 5. BY NOTSORTED in a PROC: consecutive runs form groups even when the key
      repeats non-adjacently — no sortedness requirement. */
data ns;
  input g x;
  datalines;
2 20
1 10
2 21
;
run;
proc means data=ns n sum;
  by g notsorted;
  var x;
run;
