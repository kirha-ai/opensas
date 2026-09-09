/* Conditionally emit an extra record via %IF in a macro */
%macro gen(withhigh);
  data d;
    grp = "LOW"; x = 10; output;
    %if &withhigh = 1 %then %do;
      grp = "HIGH"; x = 100; output;
    %end;
  run;
%mend;
%gen(1)
proc print data=d; run;
