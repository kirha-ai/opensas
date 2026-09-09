/* BUG-inputfmtseq: sequential NUMERIC formatted INPUT must advance the column
   cursor by the field width (like the char path), NOT tokenize. `a 4. b 4. c 4.`
   over `  10  20  30` reads cols 1-4, 5-8, 9-12 → 10, 20, 30. And the tight
   `x 2. y 2.` over `1234` → 12, 34. A char/numeric mixed sequence pins that the
   asymmetry is gone: the numeric field advances the same cursor the char reads. */
data cols;
  input a 4. b 4. c 4.;
  put "a=" a " b=" b " c=" c;
datalines;
  10  20  30
;
run;

data tight;
  input x 2. y 2.;
  put "x=" x " y=" y;
datalines;
1234
;
run;

data mixed;
  input name $3. n 3. tag $2.;
  put "name=" name " n=" n " tag=" tag;
datalines;
abc123zz
;
run;

data numthenlist;
  input p 3. q;
  put "p=" p " q=" q;
datalines;
12345 67
;
run;
