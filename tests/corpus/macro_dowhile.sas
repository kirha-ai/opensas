%global list;
%let list=;
%macro build;
  %let i=1;
  %do %while(&i <= 3);
    %let list=&list-&i;
    %let i=%eval(&i + 1);
  %end;
%mend;
%build

data _null_;
  put "list=&list";
run;
