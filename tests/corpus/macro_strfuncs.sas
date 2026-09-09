%let s = alpha beta gamma;
%let len = %length(&s);
%let pos = %index(&s, beta);
%let w1 = %scan(&s, 1);
%let up = %upcase(&w1);

data _null_;
  put "len=&len pos=&pos up=&up";
run;
