/* STAT-RAND-001: RAND seeded streams after CALL STREAMINIT (default generator).
 * Every expected line is the hex16. text of a SAS 9.4 run of this program.
 * Pins: the uniform (one 32-bit MT word per draw), NORMAL (Marsaglia polar
 * pairs, partner kept across other distributions), EXPONENTIAL (-log U),
 * BERNOULLI (U < p), parameterised NORMAL/EXPONENTIAL, STREAMINIT reseeding,
 * and the seeds/draws used by the SURVEYLOGISTIC-001, SURVEYPHREG-001,
 * RMSTREG-001, CAUSALTRT-001 and PSMATCH-001 originals (invented data).
 */
data _null_;
  call streaminit(218);
  do i = 1 to 5; x = rand('UNIFORM'); put x hex16.; end;
run;
data _null_;
  call streaminit(218);
  do i = 1 to 7; x = rand('NORMAL'); put x hex16.; end;
run;
data _null_;
  call streaminit(722);
  do i = 1 to 7; x = rand('EXPONENTIAL'); put x hex16.; end;
run;
data _null_;
  /* PSMATCH-001's draws: equal to the bits exported from SAS in
     stat_psmatch001_greedy.sas */
  length bits $100;
  call streaminit(419);
  do i = 1 to 100; bits = cats(bits, rand('BERNOULLI', 0.5)); end;
  put bits;
run;
data _null_;
  length bits $60;
  call streaminit(193);
  do i = 1 to 60; bits = cats(bits, rand('BERNOULLI', 0.3)); end;
  put bits;
run;

data _null_;
  call streaminit(193);
  do i = 1 to 6;
    a = rand('NORMAL'); b = rand('UNIFORM'); c = rand('EXPONENTIAL');
    d = rand('BERNOULLI', 0.5); e = rand('NORMAL', 10, 2); f = rand('EXPONENTIAL', 3);
    put a hex16. +1 b hex16. +1 c hex16. +1 d 1. +1 e hex16. +1 f hex16.;
  end;
run;

data _null_;
  /* SAS ignores a second STREAMINIT in the same DATA step: z2 is z1's polar
     partner and z3 starts the next pair */
  call streaminit(5);
  z1 = rand('NORMAL');
  call streaminit(5);
  z2 = rand('NORMAL');
  z3 = rand('NORMAL');
  put z1 hex16. +1 z2 hex16. +1 z3 hex16.;
run;
