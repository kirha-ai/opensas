/* ISS-specialmissing: numeric special missing (.A-.Z, ._) must survive text
   ingestion (list input, plain informat, INPUT()); `ne .` counts them present. */
data a;
  input x;
  datalines;
1
.
.K
.A
;
run;
data b; set a; if x ne . then output; run;
proc sql; select count(*) as n_output from b; quit;

data _null_;
  a = input(".A", 8.);
  k = input(".K", 8.);
  d = input(".",  8.);
  ap = (a ne .);
  put "a=" a "k=" k "d=" d;
  put "a_present=" ap;
run;
