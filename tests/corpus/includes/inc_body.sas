%let bodyvar = frombody;
data _null_; put "body sees &mainvar"; run;
