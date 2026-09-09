%let s = %str(x y z);
%macro count;
  %local k;
  %let k=0;
  %do %until(&k >= 2);
    %let k=%eval(&k + 1);
  %end;
  %global kout;
  %let kout=&k;
%mend;
%count

data _null_;
  put "s=&s kout=&kout";
run;
