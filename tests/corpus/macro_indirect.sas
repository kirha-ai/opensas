/* &&var&i macro-array indirection (the core SDTM loop-over-domains pattern) +
   triple &&& resolution. Synthetic. macro-indirect. */
%let dom1 = DM; %let dom2 = AE; %let dom3 = LB;
%macro build;
  %do i = 1 %to 3;
    %let cur = &&dom&i;
    data _null_; put "ROW&i=&cur"; run;
  %end;
%mend;
%build;
%let x = a; %let a = hello;
data _null_; put "TRIPLE=&&&x"; run;
%let pre = 2; %let val2 = TWO;
data _null_; put "TWOLEVEL=&&val&pre"; run;
