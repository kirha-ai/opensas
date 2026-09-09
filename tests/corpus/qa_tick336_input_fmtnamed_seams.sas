/* QA tick336 BANKED POSITIVE CONTROL for BUG-inputfmtnamedtoken (38e5dc8f).
   Every NAMED numeric informat in INPUT now reads its w COLUMNS instead of a
   whitespace token (Language Reference: Concepts p.515 "Formatted Input", Table 21.2 rows 1-2). QA
   probed the seams the ticket's own fixture does not cover and found all of
   them conformant; this pins them so a future INPUT change cannot quietly
   re-tokenize. Every value below is column arithmetic, not a token split:
   the pointer after a w-column read sits at column w+1 and NO blank is
   skipped, so S1's `b` deliberately reads " 5,67" (cols 6-10) -> 567, which
   is the whole point of formatted input and the shape that regressed. */

/* S1 blank-separated, each field exactly its declared width: the SECOND field
   starts at column 6 (the blank), not at the token — COMMA5. strips the blank
   and the comma, so 567, NOT 5678. */
data _null_; infile datalines truncover;
  input a comma5. b comma5.;
  put "S1 a=" a " b=" b;
datalines;
1,234 5,678
;
run;

/* S2 adjacent fields must NOT merge (the ticket's failure: a=12345678, b=.) */
data _null_; infile datalines truncover;
  input a comma5. b comma5.;
  put "S2 a=" a " b=" b;
datalines;
1,2345,678
;
run;

/* S3 the COLON form still TOKENIZES — widths are max lengths, not columns */
data _null_; infile datalines truncover;
  input a :comma5. b :comma5.;
  put "S3 a=" a " b=" b;
datalines;
1,234 5,678,999
;
run;

/* S4 @n absolute pointer then a named informat */
data _null_; infile datalines truncover;
  input @4 a comma5. @1 b 3.;
  put "S4 a=" a " b=" b;
datalines;
1231,234
;
run;

/* S5 +n relative pointer then a named informat */
data _null_; infile datalines truncover;
  input z 3. +2 a comma5.;
  put "S5 z=" z " a=" a;
datalines;
123XX1,234
;
run;

/* S6 BZ: blanks are ZEROS, including an ALL-blank field -> 0, and the cursor
   still lands past the 4-wide field (c reads the trailing 9). */
data _null_; infile datalines truncover;
  input a bz4. b bz4. c bz4.;
  put "S6 a=" a " b=" b " c=" c;
datalines;
12       9
;
run;

/* S7 embedded blanks inside the COMMA family (Table 21.2): both strip */
data _null_; infile datalines truncover;
  input a comma6. b dollar6.;
  put "S7 a=" a " b=" b;
datalines;
1 2 3 $ 4 5
;
run;

/* S8 an informat WIDER than the remaining record reads short, not past */
data _null_; infile datalines truncover;
  input a comma10.;
  put "S8 a=" a;
datalines;
1,23
;
run;

/* S9 char field then named numeric, and list token then named numeric */
data _null_; infile datalines truncover;
  input nm $5. v comma6.;
  put "S9 nm=[" nm "] v=" v;
datalines;
Riley 1,234
;
run;

/* S10 DATALINES with NO infile statement must agree with the infile form (S2) */
data _null_;
  input a comma5. b comma5.;
  put "S10 a=" a " b=" b;
datalines;
1,2345,678
;
run;

/* S11 adjacent TIME8. and adjacent HEX4. — value AND cursor */
data _null_; infile datalines truncover;
  input t1 time8. t2 time8.;
  put "S11 t1=" t1 " t2=" t2;
datalines;
01:00:0002:00:00
;
run;

data _null_; infile datalines truncover;
  input h1 hex4. h2 hex4.;
  put "S12 h1=" h1 " h2=" h2;
datalines;
000A000B
;
run;

/* S13 PERCENT5. then a plain w. — the following field must get its own cols */
data _null_; infile datalines truncover;
  input p percent5. n 2.;
  put "S13 p=" p " n=" n;
datalines;
 45% 77
;
run;

/* S14 named informat, `/` record advance, named informat */
data _null_; infile datalines truncover;
  input a comma5. / b comma5.;
  put "S14 a=" a " b=" b;
datalines;
1,111
2,222
;
run;

/* S15 the two read paths agree: INPUT statement == INPUT() function */
data _null_;
  f1 = input('1,234', comma5.);
  f2 = input('23  ', bz4.);
  f3 = input('12:34:56', time8.);
  put "S15 fn comma5=" f1 " bz4=" f2 " time8=" f3;
run;
