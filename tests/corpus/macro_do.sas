%macro count(n);
  %do i = 1 %to &n;
    data _null_;
      put "i=&i";
    run;
  %end;
%mend;

%count(3)
