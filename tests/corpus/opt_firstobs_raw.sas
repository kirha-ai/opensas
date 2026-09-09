/* GAP-optfirstobsraw — `options firstobs=`/`obs=` reach a RAW/INFILE read.

   Language Reference: Concepts printed p.517 (pdf index 534; that page's OWN footer reads "Reading
   Raw Data with the INPUT Statement" / "517"), Table 21.5 "Additional
   Data-Reading Features", the row for reading "some but not all records in
   the file":
       FIRSTOBS=and OBS= options in an INFILE statement; FIRSTOBS= and OBS=
       system options; #n line pointer control.
   ("FIRSTOBS=and" is the volume's own run-together typo.) So the SYSTEM
   options are a documented mechanism for raw input, not data sets only.

   WHAT WAS WRONG: they reached DATASET reads only. `options firstobs=2;` over
   a raw file read the HEADER AS DATA, so the output carried a bogus
   observation (name='name', age=missing) at exit 0 — the canonical
   header-skip idiom silently producing junk.

   HOW TO MEASURE IT — this is the trap and it is why every count below is
   taken with the option RESET. A PROC PRINT of the result re-applies the
   still-active system option to ITS OWN read (the dataset path, working
   correctly), so a sliced listing made the broken case look fixed. The row
   COUNT via nobs, after `options firstobs=1`, is the only honest witness.

   PRECEDENCE IS DOC-SILENT AND IS NOT DECIDED HERE. INFILE's FIRSTOBS=/OBS=
   entries carry no Interaction naming the system options (Statements ref
   printed p.131/p.135), Language Reference: Concepts has no precedence prose for the pair, and SAS
   System Options: Reference is not among our volumes. Block 5 pins TODAY'S
   behaviour for the both-set case (the INFILE option wins) as a status-quo
   record, NOT as a doc claim — see the source comment for the SQL-views
   passage that points the other way.
   expect-rc: 0 */

/* 1 — THE BUG: system firstobs=2 over an external raw file. 4 records in,
   3 observations out, and the header is NOT among them. */
options firstobs=2;
data b;
  infile "tests/corpus/opt_firstobs_raw.dat";
  input name $ age;
run;
options firstobs=1;
data _null_; set b nobs=n; if _n_=1 then put "1 rows=" n; run;
proc print data=b noobs; title "1 header skipped, no bogus observation"; run;

/* 2 — THE STEP BODY MUST NOT RUN ON THE SKIPPED RECORD. Under the old
   behaviour the header was read, _n_ ran 1..4 and a retained accumulator
   absorbed it. _n_ must now be 1,2,3 and the PUT must fire three times. */
options firstobs=2;
data _null_;
  infile "tests/corpus/opt_firstobs_raw.dat";
  input name $ age;
  put "2 read _n_=" _n_ " " name= age=;
run;
options firstobs=1;

/* 3 — system obs= on a raw read caps the RECORD count. Statements ref printed
   p.135 defines OBS= as "the record number of the last record to read", so it
   is an absolute inclusive position, not a quantity. */
options obs=2;
data c;
  infile "tests/corpus/opt_firstobs_raw.dat";
  input name $ age;
run;
options obs=max;
data _null_; set c nobs=n; if _n_=1 then put "3 rows=" n; run;

/* 4 — the pair together: records 2..3 of 4. firstobs=2 obs=3 is TWO records
   (inclusive positions), not three. */
options firstobs=2 obs=3;
data d;
  infile "tests/corpus/opt_firstobs_raw.dat";
  input name $ age;
run;
options firstobs=1 obs=max;
data _null_; set d nobs=n; if _n_=1 then put "4 rows=" n; run;
proc print data=d noobs; title "4 records 2..3 inclusive"; run;

/* 5 — BOTH LEVELS SET (doc-silent). Status-quo record: the INFILE option wins
   and the system value is not composed on top of it. Was already true because
   the system option was ignored outright; pinned so the undecided case cannot
   drift without someone noticing. */
options firstobs=3;
data e;
  infile "tests/corpus/opt_firstobs_raw.dat" firstobs=2;
  input name $ age;
run;
options firstobs=1;
data _null_; set e nobs=n; if _n_=1 then put "5 rows=" n " (3 = infile wins; 1 = composed)"; run;

/* 6 — CONTROLS: the INFILE options alone are untouched by this change. */
data f;
  infile "tests/corpus/opt_firstobs_raw.dat" firstobs=2;
  input name $ age;
run;
data _null_; set f nobs=n; if _n_=1 then put "6 infile firstobs=2 rows=" n; run;
data g;
  infile "tests/corpus/opt_firstobs_raw.dat" obs=2;
  input name $ age;
run;
data _null_; set g nobs=n; if _n_=1 then put "6 infile obs=2 rows=" n; run;

/* 7 — the SIBLING PRODUCER: a bare DATALINES block with no INFILE statement
   at all took a different code path that never saw the record window, so it
   stayed broken after the INFILE path was fixed. Both now share one builder. */
options firstobs=2;
data h;
  input v;
  datalines;
1
2
3
;
run;
options firstobs=1;
data _null_; set h nobs=n; if _n_=1 then put "7 datalines rows=" n; run;
proc print data=h noobs; title "7 datalines: first record skipped"; run;

/* 8 — no options in effect: every record is data, including the header. The
   negative control that proves blocks 1-7 are the option and not a new skip. */
data i;
  infile "tests/corpus/opt_firstobs_raw.dat";
  input name $ age;
run;
data _null_; set i nobs=n; if _n_=1 then put "8 unset rows=" n; run;
proc print data=i noobs; title "8 unset: header IS data"; run;
