/* QA tick356 BANKED POSITIVE CONTROL — INPUT record/column pointer seams.
   Every shape below was hand-probed this tick and is CONFORMANT today; it is
   pinned so the concurrent INPUT/io churn cannot quietly move it.

   Doc: Language Reference: Concepts p.516-517 "Reading Raw Data with the INPUT Statement" — the
   @ column pointer, the #n line pointer, trailing @ for a file with varying
   record layouts, and the MISSOVER/TRUNCOVER options table.

   NOT pinned here (currently WRONG, see docs/findings/qa-tick356.md F1/F2):
   INFILE END= when one iteration consumes more than one record, and _INFILE_
   in a step that also ASSIGNS to _INFILE_. Those repros live in the .md, not
   in this fixture, so the shared corpus gate stays green.

   REVERT-infileendmultirec CORRECTION TO THE LINE ABOVE: F1 was NOT a bug.
   Every END= block here reads DATALINES, and DATA Step Statements ref printed
   p.130 restricts END= for "the DATALINES statement … or an INPUT statement
   that reads multiple input data records", with printed p.138 giving the
   behaviour — instream data means UNBUFFERED is in effect, and "SAS never sets
   the END= variable to 1". This fixture was banked as a POSITIVE CONTROL after
   hand-probing, but the probe was checked against Language Reference: Concepts' INFILE-option table
   rather than the Statements ref's END= entry, so it certified as conformant a
   shape the reference restricts. The `end=` column below is now 0 throughout;
   the pointer-seam subjects (@, #n, trailing @, OBS=/FIRSTOBS=, MISSOVER/
   TRUNCOVER) are untouched and are what this fixture still guards. */

/* S1 the one-record-per-iteration shapes: plain read, OBS= cap, FIRSTOBS=
   start. These read DATALINES, so END= is restricted (p.130/p.138) and the
   flag stays 0 on every record INCLUDING the final one — the OBS=/FIRSTOBS=
   compositions are what this block still pins. END= reaching 1 where it is
   legal lives in infile_end.sas block 2 (external file, single INPUT). */
data _null_; infile datalines truncover end=e;
  input a $6.;
  put "S1 a=" a " end=" e;
datalines;
r1aaaa
r2bbbb
r3cccc
;
run;

data _null_; infile datalines truncover obs=2 end=e;
  input a $6.;
  put "S2 a=" a " end=" e;
datalines;
r1aaaa
r2bbbb
r3cccc
;
run;

data _null_; infile datalines truncover firstobs=3 end=e;
  input a $6.;
  put "S3 a=" a " end=" e;
datalines;
r1aaaa
r2bbbb
r3cccc
;
run;

/* S4 the varying-record-layout look-ahead idiom (Language Reference: Concepts p.517 row 2): a bare
   `input @;` holds the record AND publishes it to _INFILE_, so the IF can
   pick the layout before any variable is read. This is the shape F2 breaks
   the moment the same step also writes to _INFILE_ — pinned here in its
   working form as the regression tripwire. */
data _null_; infile datalines truncover;
  input @;
  if _infile_ =: 'H' then do; input type $1. name $6.; put "S4 HEADER " name=; end;
  else do; input type $1. amt 6.; put "S4 DETAIL " amt=; end;
datalines;
Hsmith
D 12.5
D 100
;
run;

/* S5 trailing @ holds the record across two INPUT statements and the pointer
   does NOT rewind: the second INPUT resumes at column 3. Under MISSOVER a
   read that starts past the end of a short record yields a blank, not a
   flow-over to the next record. */
data _null_; infile datalines missover;
  input a $2. @;
  input b $4.;
  put "S5 a=[" a "] b=[" b "]";
datalines;
AB
ABCDEFGH
;
run;

/* S6 an @n column pointer aimed past the end of a short record: TRUNCOVER and
   MISSOVER both give a blank rather than reading the next record. */
data _null_; infile datalines truncover; input @5 a $4.; put "S6 T a=[" a "]";
datalines;
AB
ABCDEFGH
;
run;

data _null_; infile datalines missover; input @5 a $4.; put "S6 M a=[" a "]";
datalines;
AB
ABCDEFGH
;
run;

/* S7 the @ pointer moves BACKWARD within a record, and +n moves relative. */
data _null_; infile datalines truncover;
  input @3 x $2. @1 y $2.;
  put "S7 x=" x " y=" y;
datalines;
r1aaaa
;
run;

data _null_; infile datalines truncover;
  input a $2. +2 b $2.;
  put "S7 a=" a " b=" b;
datalines;
AAxxBB
;
run;

/* S8 the @'string' pointer parks after the searched text. */
data _null_;
  infile datalines truncover;
  input @'=' val $5.;
  put "S8 val=[" val "]";
datalines;
name=abc
zz=defgh
;
run;

/* S9 #n reads a GROUP of records per iteration and _INFILE_ tracks the line
   the pointer currently sits on (line 2 after `#2`). */
data _null_; infile datalines truncover;
  input #1 a $6. #2 b $6.;
  put "S9 a=" a " b=" b " buf=[" _infile_ "]";
datalines;
r1aaaa
r2bbbb
r3cccc
r4dddd
;
run;
