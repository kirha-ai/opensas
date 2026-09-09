%macro greet(who);
  data _null_;
    put "Hi, &who";
  run;
%mend;

%greet(Alice)
%greet(Bob)
