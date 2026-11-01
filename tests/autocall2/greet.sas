%macro greet(who);
data _null_; put "DIR2 &who";
run;
%mend greet;
