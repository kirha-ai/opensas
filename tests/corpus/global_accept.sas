filename myref "/tmp/out.txt";
options linesize=80 pagesize=60;
ods listing;
x "echo hello";

data _null_;
  put "ran ok";
run;

ods listing close;
