/* doc-finder tick312 — Language Reference: Concepts Ch.21 "Reading Raw Data" (pp.505-524): the parts
   that are CONFORMANT, banked so they cannot regress.  GREEN by construction:
   every block below was probed against the doc before being written here, and
   nothing that currently diverges is included (see
   docs/findings/doc-finder-tick312.md for the divergences).

   Covered:
     Table 21.1 (p.508) all eight standard-numeric rows, "None needed"
     Table 21.2 (p.508) rows 3/4/5 — comma, parentheses, hexadecimal
     p.509      the explicit-decimal-point-overrides-the-informat rule
     Table 21.4 (p.509) row 1 — $CHARw. keeps leading blanks, $w. trims them
     Table 21.4 (p.509) row 2 — DATALINES4 + ;;;; for data containing semicolons
     Table 21.5 (p.516) row 2 — trailing @@, and trailing @ with two INPUT/OUTPUT
     Table 21.5 (p.517) row 5 — varying record layouts via IF-THEN + trailing @
     Table 21.5 (p.517) row 7 — END= on INFILE, and END= is NOT an output column
     Table 21.5 (p.517) row 9 — FIRSTOBS=/OBS= as INFILE options (incl. DATALINES)
     Table 21.5 (p.517) row 11 — @n column pointer with formatted input
     Table 21.5 (p.518) row 15 — DSD + TRUNCOVER missing values
     Table 21.5 (p.517) row 10 — a second `infile datalines` does NOT rewind
     p.510 / p.512 / p.514 / p.515 worked programs                              */

/* ── Table 21.1 (p.508): eight standard numeric forms, all read with no help ── */
data _null_;
  infile datalines truncover;
  input tag $ x;
  put tag= x=;
datalines;
right      23
notaligned 23
left 23
leadzero 00023
decpoint 23.0
enot1 2.3E1
enot2 230E-1
negative -23
;

/* ── Table 21.2 (p.508) rows 3/4/5: comma, parentheses, hex ── */
data _null_;
  c = input('2,341', comma5.);
  p = input('(23)',  comma4.);
  h = input('C4A2',  hex4.);
  put "comma2341=" c " paren23=" p " hexC4A2=" h;
run;

/* ── p.509: "An explicit decimal point in the input data overrides any decimal
      specification in the INPUT statement." ── */
data _null_;
  infile datalines truncover;
  input a 5.2 / b 5.2;
  put "implied=" a " explicit=" b;
datalines;
1234
12.5
;

/* ── Table 21.4 (p.509) row 1: $CHARw. preserves leading blanks, $w. trims ── */
data _null_;
  infile datalines truncover;
  input a $char4. @1 b $4.;
  put "charw=[" a "] plainw=[" b "]";
datalines;
  ab
;

/* ── p.510 worked program (instream data) and p.511 (DATALINES4) ── */
data weight;
  input PatientID $ Week1 Week8 Week16;
  loss = Week1 - Week16;
  datalines;
2477 195 177 163
2431 220 213 198
;
proc print data=weight; run;

data weight4;
  input PatientID $ Week1 Week8 Week16;
  loss = Week1 - Week16;
  datalines4;
24;77 195 177 163
24;31 220 213 198
;;;;
proc print data=weight4; run;

/* ── p.512 list input and p.514 column input, the doc's own programs ── */
data scores;
  length name $ 12;
  input name $ score1 score2;
datalines;
Riley 1132 1187
Henderson 1015 1102
;
proc print data=scores; run;

data colscores;
  infile datalines truncover;
  input name $ 1-12 score2 17-20 score1 27-30;
datalines;
Riley           1132       987
Henderson       1015      1102
;
proc print data=colscores; run;

/* ── p.515 formatted input WITH pointer controls (the doc's own program) and
      Table 21.5 row 11's @n column pointer ── */
data fmtscores;
  input name $12. +4 score1 comma5. +6 score2 comma5.;
datalines;
Riley           1,132      1,187
Henderson       1,015      1,102
;
proc print data=fmtscores; run;

data atscores;
  infile datalines truncover;
  input @1 name $12. @13 score1 comma5. @18 score2 comma5.;
datalines;
Riley       1,1321,187
;
proc print data=atscores; run;

/* ── Table 21.5 (p.516) row 2: trailing @@, then trailing @ with two
      INPUT + OUTPUT statements ── */
data pairs;
  input x y @@;
datalines;
1 2 3 4 5 6
7 8
;
proc print data=pairs; run;

data two;
  input a b @;
  output;
  input c d;
  a = c; b = d;
  output;
datalines;
1 2 3 4
;
proc print data=two; run;

/* ── Table 21.5 (p.517) row 5: a file with varying record layouts ── */
data mixed;
  length kind $1 name $8;
  input kind $ @;
  if kind = 'N' then input name $;
  else input num;
datalines;
N alice
X 42
N bob
;
proc print data=mixed; run;

/* ── Table 21.5 (p.517) row 7: END= flags the last record, and the END=
      variable is NOT added to the output data set.
      REVERT-infileendmultirec — A CROSS-VOLUME INTERACTION, not a failure of
      row 7: Language Reference: Concepts' table LISTS END= among the INFILE options, but the DATA
      Step Statements ref is the specific rule and it restricts the option for
      instream data (printed p.130's Restriction; printed p.138 "When you read
      instream data with a DATALINES statement, UNBUFFERED is in effect" +
      "When you use UNBUFFERED, SAS never sets the END= variable to 1"). The
      specific governs the general, so `done` stays 0 here — this block reads
      DATALINES. Row 7's OTHER half still holds and is still shown: `done` is
      absent from the printed data set. Row 7's FLAGGING half is demonstrated
      on an external file in infile_end.sas block 2. ── */
data endds;
  infile datalines end=done;
  input v;
  put "v=" v " done=" done;
datalines;
10
20
;
proc print data=endds; run;

/* ── Table 21.5 (p.517) row 9: FIRSTOBS= and OBS= as INFILE options, on
      instream data lines (Table 21.5 row 10's "INFILE with DATALINES") ── */
data skiphdr;
  infile datalines firstobs=2;
  input x y;
datalines;
hdr hdr2
101 5
102 10
;
proc print data=skiphdr; run;

data cap2;
  infile datalines obs=2;
  input x;
datalines;
1
2
3
4
;
proc print data=cap2; run;

/* ── Table 21.5 (p.518) row 15: missing values under DSD + TRUNCOVER ── */
data dsdmiss;
  infile datalines dsd truncover;
  input a $ b c;
datalines;
x,,3
y,2,
z
;
proc print data=dsdmiss; run;

/* ── Table 21.5 (p.517) row 10: a second `infile datalines` in the same step
      re-selects the SAME stream — it does not rewind it ── */
data _null_;
  infile datalines;
  input a;
  infile datalines;
  input b;
  put "a=" a " b=" b;
datalines;
1
2
3
4
;
