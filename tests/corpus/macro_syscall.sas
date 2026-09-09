/* %syscall SORTN/SORTC — sort macro-array variables in place (a common driver-macro
   idiom for ordering domains/params). Synthetic. macro-syscall. */
%let a1=30; %let a2=10; %let a3=20;
%syscall sortn(a1, a2, a3);
data _null_; put "SORTN=&a1 &a2 &a3"; run;
%let d1=CM; %let d2=AE; %let d3=LB;
%syscall sortc(d1, d2, d3);
data _null_; put "SORTC=&d1 &d2 &d3"; run;
