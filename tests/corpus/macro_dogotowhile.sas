/* NOTE-gotodowhilespin (@pi-mo tick293): %GOTO out of a conditional %DO
   (%while/%until) leaves the loop like %return — the label resolves in the
   enclosing body. Was: %do %until SPUN to the 100000-iteration convergence
   cap and errored (a goto suppresses resolveText, so the loop condition came
   back empty/false and the bottom-test never broke); %do %while escaped only
   through that same side effect. Synthetic. */
%macro search(target);
  %let i=0;
  %do %until (&i > 100);
    %let i=%eval(&i + 1);
    %if &i = &target %then %goto found;
  %end;
data _null_;
  put "NOT FOUND";
run;
  %return;
  %found:
data _null_;
  put "FOUND AT &i";
run;
%mend;
%search(3)

%macro forever(target);
  %let i=0;
  %do %while (1);
    %let i=%eval(&i + 1);
    %if &i = &target %then %goto done;
  %end;
  %done:
data _null_;
  put "WHILE LEFT AT &i";
run;
%mend;
%forever(4)
