/* BUG-inputfmtseq: formatted `w.d` INPUT is COLUMN-based (fixed width), not
   tokenized. x reads cols 1-8 "12345 12" (embedded blank → invalid → . + NOTE),
   y reads cols 9-13 "3" → 0.3. (Was wrongly tokenizing to 123.45 / 12.3.) */
data _null_;
  input x 8.2 y 5.1;
  put "x=" x " y=" y;
  datalines;
12345 123
;
run;
