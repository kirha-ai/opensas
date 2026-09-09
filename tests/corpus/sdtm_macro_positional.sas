/* Generate a dose series with positional %macro params + %DO */
%macro doseseries(n, base);
  data ex;
    %do i = 1 %to &n;
      VISITNUM = &i;
      DOSE = &base * &i;
      output;
    %end;
  run;
%mend;
%doseseries(4, 25)
proc print data=ex; var VISITNUM DOSE; run;
