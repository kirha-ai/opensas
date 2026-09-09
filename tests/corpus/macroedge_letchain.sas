/* %let captures its RHS at definition: redefining the source does not retro-update
   an earlier copy; a later %let can chain on an already-defined var. corpus-macroedge. */
%let first = Ada;
%let greet = Hi &first;
%let first = Grace;
%let sig = &greet from &first;
data _null_;
  put "greet=&greet";
  put "sig=&sig";
run;
