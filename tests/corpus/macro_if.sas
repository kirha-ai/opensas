%macro tag(x);
  data _null_;
  %if &x > 0 %then %do;
    put "&x is positive";
  %end;
  %else %do;
    put "&x is nonpositive";
  %end;
  run;
%mend;

%tag(5)
%tag(-2)
