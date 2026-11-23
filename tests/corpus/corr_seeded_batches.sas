/* Base SAS Statistical Procedures, Example 2.4, Output 2.4.2.
   The two batches consume the same RANNOR stream across three call sites. */
data sim;
  do i=1 to 300;
    x=rannor(135791);
    batch=1+(i>150);
    if batch=1 then y=.3*x+.9*rannor(246791);
    else y=.25*x+sqrt(.8375)*rannor(246791);
    output;
  end;
run;
proc corr data=sim noprint outp=correlations;
  by batch;
  var x y;
run;
data _null_;
  set correlations;
  if _type_='CORR' and upcase(_name_)='X' then put 'Batch ' batch 1. '  r=' y 7.5;
run;
