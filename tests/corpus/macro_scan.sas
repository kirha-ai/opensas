%let s = alpha beta gamma;
%let w = %scan(&s, 2);

data _null_;
  put "w=&w";
run;
