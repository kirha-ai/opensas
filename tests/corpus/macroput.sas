%let who=World;
%put Hello &who;
%put G-macroput regression guard;
data _null_;
  msg = "done";
  put msg=;
run;
