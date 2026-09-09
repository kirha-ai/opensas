/* GAP-ofcolonprefix: `sum(of x:)` — the name-prefix variable list in OF
   context. Language Reference: Concepts printed p.70 Table 4.5: "Function(OF x:) Performs the
   function on all the variables that begin with 'x'"; funcref printed p.6:
   OF's variable-list "can be any form of a SAS variable list". The parser
   defers the prefix to eval as a synthetic __ofprefix("x") argument (the
   __dimchk pattern), expanded against the runtime PDV beside `of _numeric_`
   — the SAME expansion site, not a second expander. */
data _null_;
  x1 = 10; x2 = 20; x3 = 30; y = 99;
  s = sum(of x:);        /* 60 — y is not swept in */
  m = mean(of X:);       /* 20 — the prefix match is case-insensitive */
  n = n(of x:);          /* 3 */
  u = sum(of x: y);      /* 159 — prefix mixed with a plain name */
  v = sum(of x:, of y);  /* 159 — comma-separated OF lists */
  put s= m= n= u= v=;
run;

/* the prefix matches DATASET-read PDV vars too (Language Reference: Concepts p.69's own example
   shape: sum(of Sales:) over Sales_Jan, Sales_Feb, …) */
data t;
  input sales_jan sales_feb other;
  datalines;
100 200 9
300 400 8
;

data _null_;
  set t;
  tot = sum(of sales:);
  put tot=;
run;

/* control: the DROP/KEEP prefix wildcard (GAP-dropcolon) is unchanged */
data k;
  x1 = 1; x2 = 2; other = 9;
  keep x:;
run;

data _null_;
  set k;
  put x1= x2=;
run;
