/* REVERT-infileendmultirec — the MULTI-RECORD-INPUT half of p.130's
   Restriction, on an EXTERNAL file.

   WHY THIS FIXTURE EXISTS: every other END= fixture in the corpus reads
   DATALINES, so they are all caught by the instream rule (p.138) before the
   multi-record rule is ever consulted. Deleting the multi-record clause from
   the guard left the whole suite GREEN at 1818/1818 — measured, not assumed.
   This fixture is the only thing that covers it, and it must read an external
   file so that DATALINES cannot mask the case under test.

   DATA Step Statements ref printed p.130 (pdf 141; footer "130 Chapter 2 /
   Dictionary of SAS DATA Step Statements"), the END= option:
       Restriction  You cannot use the END= option with the UNBUFFERED option,
                    the DATALINES statement, the DATALINES4 statement, or an
                    INPUT statement that reads multiple input data records.
       Tip          Use the option EOF= on page 130 when END= is invalid.
   "Restriction" means a flag stuck at 0, not a diagnostic — printed p.332 uses
   the same construction for SET and spells it out: "END= cannot be used with
   POINT=. When random access is used, the END= variable is never set to 1."

   Blocks 1 and 2 read the SAME four-record file. The only difference is
   whether one INPUT consumes one record or two, so the pair isolates exactly
   the clause under test with the source held constant.
   expect-rc: 0 */

/* 1 — CONTROL: one record per INPUT on an external file. Not restricted by
   p.130 in any clause, so END= behaves normally and reaches 1 on the last
   record. If this block ever goes to 0, the guard has over-reached and broken
   END= where it is legal. */
data _null_;
  infile "tests/corpus/infile_end_extfile_multirec.dat" end=e;
  input a $6.;
  put "single a=" a " end=" e;
run;

/* 2 — THE CASE UNDER TEST: one INPUT statement reading TWO records via `/`,
   on the same external file. p.130's fourth clause applies, so the flag never
   reaches 1 — and the end-of-file totals idiom therefore prints nothing,
   which is the SAS answer here rather than a bug. */
data _null_;
  infile "tests/corpus/infile_end_extfile_multirec.dat" truncover end=e;
  input a $6. / b $6.;
  n + 1;
  put "slash  a=" a " b=" b " end=" e;
  if e then put "NEVER: totals idiom must not fire on a multi-record INPUT";
run;

/* 3 — `#n` is the other record-advance spelling and is restricted the same
   way; same file, absolute line pointer instead of `/`. */
data _null_;
  infile "tests/corpus/infile_end_extfile_multirec.dat" truncover end=e;
  input #1 a $6. #2 b $6.;
  put "hash   a=" a " b=" b " end=" e;
run;
