/* REVERT-infileendmultirec — this fixture's SUBJECT IS REVERSED, deliberately.

   It was written for BUG-infileendmultirec (e7ac8ee7, off QA tick356 F1) to
   pin that INFILE END= FIRES for `/`, `#n` and two INPUTs in one iteration.
   The doc says it must not. Every block below is `infile datalines`, and DATA
   Step Statements ref printed p.138 (pdf 149; footer "138 Chapter 2 / …")
   makes that unconditional:
       Interaction  When you use UNBUFFERED, SAS never sets the END= variable
                    to 1.
       Tip          When you read instream data with a DATALINES statement,
                    UNBUFFERED is in effect.
   and printed p.130 (footer "130 Chapter 2 / …") names both the DATALINES and
   the multi-record-INPUT cases in ONE sentence:
       Restriction  You cannot use the END= option with the UNBUFFERED option,
                    the DATALINES statement, the DATALINES4 statement, or an
                    INPUT statement that reads multiple input data records.
       Tip          Use the option EOF= on page 130 when END= is invalid.
   That "Restriction" means a flag stuck at 0, not a diagnostic: printed p.332
   uses the identical construction for SET and spells it out — "END= cannot be
   used with POINT=. When random access is used, the END= variable is never
   set to 1" — which opensas already implemented the never-set way.

   So `TOTAL groups=2` is GONE from the golden below. That line was QA tick356
   F1's stated expectation, and a QA expectation is not an oracle; per p.130 the
   SAS answer is that the idiom produces no output at all here. The fixture now
   pins the RESTRICTION instead of the feature — which is the regression net
   this revert needs, since nothing else would notice the flag creeping back.

   END= FIRING is still pinned where it is LEGAL, and that case deliberately
   did not move: tests/corpus/infile_end.sas block 2, an EXTERNAL file with a
   single INPUT (`seen` = 0,0,1).

   THIS FIXTURE IS ALSO THE LIVE-SAS EXPERIMENT (@coder-or's discriminating
   probe, kept executable rather than left in a findings file). Blocks 1 and 2
   are exactly its two blocks. Run them on real SAS 9.4:
     - every line `end=0`  => the doc is right and this golden is correct;
     - `one … r4dddd end=1` => the manual is stale for DATALINES, and this
       whole revert should be undone against p.138 rather than re-filed;
     - the two blocks disagree => the Restriction is per-clause and a finer
       rule is needed than "instream, or a record advance".
   The golden below IS the first outcome, so overturning this is a one-run
   experiment with a pre-declared diff. */
data _null_;
  infile datalines end=e;
  input a $6.;
  put "one  a=" a " end=" e;
  datalines;
r1aaaa
r2bbbb
r3cccc
r4dddd
;
run;

data _null_;
  infile datalines truncover end=e;
  input a $6. / b $6.;
  n + 1;
  put "slsh a=" a " b=" b " end=" e;
  if e then put "TOTAL groups=" n;
  datalines;
r1aaaa
r2bbbb
r3cccc
r4dddd
;
run;

data _null_;
  infile datalines truncover end=e;
  input #1 a $6. #2 b $6.;
  put "hfwd a=" a " b=" b " end=" e;
  datalines;
r1aaaa
r2bbbb
r3cccc
r4dddd
;
run;

data _null_;
  infile datalines truncover end=e;
  input #2 b $6. #1 a $6.;
  put "hbak a=" a " b=" b " end=" e;
  datalines;
r1aaaa
r2bbbb
r3cccc
r4dddd
;
run;

data _null_;
  infile datalines truncover end=e;
  input a $6.;
  put "two1 a=" a " end=" e;
  input b $6.;
  put "two2 b=" b " end=" e;
  datalines;
r1aaaa
r2bbbb
r3cccc
r4dddd
;
run;
