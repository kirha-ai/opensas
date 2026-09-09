/* BUG-dv1trace: a comment between the last statement and run; must not hide
   the step boundary from interleaved expansion — the step has to execute
   BEFORE the next expansion-time %sysfunc(exist()) probes its output
   (a real epoch-derivation macro pattern; also the BUG-ae2register symptom). */
%macro m(v=);
  y = &v.;
%mend m;

data a; x = 1; run;

data b; set a; %m(v=x); /* trailing comment */ run;
%let eb = %sysfunc(exist(work.b));

data c; set a; z = 0; /* no macro call in the step */
run;
%let ec = %sysfunc(exist(work.c));

data _null_;
  put "b_exists=&eb";
  put "c_exists=&ec";
run;
