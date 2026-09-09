/* BUG-setinflag: SET honors the IN= dataset option — the flag is 1 while its
   dataset contributes the current obs, 0 for the others (was: always missing).
   Also: `if from_a;` subsetting keeps only a's rows. */
data a;
  x = 1; output;
  x = 2; output;
run;
data b;
  x = 9;
run;
data both;
  set a(in=from_a) b(in=from_b);
  put x= from_a= from_b=;
run;
data only_a;
  set a(in=from_a) b(in=from_b);
  if from_a;
  put x=;
run;
