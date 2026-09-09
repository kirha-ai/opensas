/* BUG-runtimemacroscope: a macro variable created by CALL SYMPUT in a step is
   visible to MACRO code after the step (interleaved expand+execute). Surfaced via
   DATA step put for stdout capture. Synthetic. */
data _null_; call symput("n", "5"); run;
%let doubled = %eval(&n * 2);
data _null_; put "DOUBLED=&doubled"; run;
%if &n > 0 %then %do; data _null_; put "N_POSITIVE"; run; %end;
/* data-driven loop: count obs into a macro var, then loop over macro-array vars */
data doms; length dom $8; input dom $; datalines;
DM
AE
LB
;
run;
data _null_; set doms end=e;
  call symputx("dom"||strip(put(_n_, best.)), dom);
  if e then call symputx("ndom", _n_);
run;
%macro loopdoms;
  %do i = 1 %to &ndom;
    data _null_; put "DOM&i=&&dom&i"; run;
  %end;
%mend;
%loopdoms
