/* BUG-inputfmtnamedtoken (Language Reference: Concepts p.515 "Formatted Input", Table 21.2 rows 1-2):
   a NAMED numeric informat without a colon (comma5., time8., bz4., percent5.,
   hex4.) is a FORMATTED read of w columns — NOT a whitespace token. Adjacent
   fields used to MERGE (`1,1321,187` -> score1=11321187, score2 missing) and
   the byte cursor desynced every following variable (hex4. read the right
   VALUE off the wrong columns). Three oracles agree: the doc, the same record
   under `@n` pointer controls, and the INPUT() function. The `:` form still
   tokenizes (modified list input). */

/* the doc's p.515 program with the fields adjacent — what formatted input is FOR */
data scores;
   infile datalines truncover;
   input name $12. score1 comma5. score2 comma5.;
datalines;
Riley       1,1321,187
;
proc print data=scores; run;

/* value AND cursor, four informats: the char field after must read its own columns */
data _null_; infile datalines truncover; input a comma3. b $3.;
  put "COMMA3+CHAR3 a=" a " b=[" b "]"; datalines;
2,3ABC
;
data _null_; infile datalines truncover; input t time8. tag $3.;
  put "TIME8+CHAR3 t=" t " tag=[" tag "]"; datalines;
12:34:56XYZ
;
data _null_; infile datalines truncover; input h hex4. tag $3.;
  put "HEX4+CHAR3 h=" h " tag=[" tag "]"; datalines;
C4A2XYZ
;
data _null_; infile datalines truncover; input p percent5. tag $3.;
  put "PCT5+CHAR3 p=" p " tag=[" tag "]"; datalines;
 45% XYZ
;

/* Table 21.2 rows 1-2: embedded-blank fields read by COMMA. / BZ.
   `2 3` comma3. -> 23, `- 23` comma4. -> -23, `23  ` bz4. -> 2300 (blanks are
   ZEROS); the trailing `9` proves the cursor lands past the 4-wide BZ field. */
data _null_;
   infile datalines truncover;
   input c3 comma3. c4 comma4. bz bz4. z 1.;
   put "T212: c3=" c3 " c4=" c4 " bz=" bz " z=" z;
datalines;
2 3- 2323  9
;

/* the two read paths agree: INPUT statement == INPUT() function */
data _null_;
   infile datalines truncover;
   input s comma5.;
   f = input('1 234', comma5.);
   put "AGREE: stmt=" s " fn=" f;
datalines;
1 234
;

/* control: the colon (modified list) form still tokenizes */
data _null_; infile datalines truncover; input a :comma3. b $;
  put "COLON: a=" a " b=[" b "]"; datalines;
2,3 ABC
;
