/* GAP-macrodoindex: the iterative %DO index was a Zig-local counter the loop body
   could never influence, so the documented early-exit idiom silently ran the FULL
   trip count — a wrong answer, not a missing feature.

   Macro Language Reference, printed p.388, `macro-variable`: "You can change the
   value of the index variable during processing. For example, using conditional
   processing to set the value of the index variable beyond the stop value when a
   certain condition is met ends processing of the loop."

   The same page draws the OPPOSITE conclusion for the increment — "%BY ... is
   evaluated before the first iteration of the loop. Therefore, you cannot change it
   as the loop iterates" — so the by-step stays evaluated once and only the index is
   re-read each pass. The `by2` row below is that half of the contract.
   The runaway shape this re-read makes possible (a body pinning the index below
   stop) hits the max_loop_iters backstop with a loud ERROR; asserted in macro.zig
   via the captured reporter (D-003), not here — green fixtures only. */
%macro early;
  %do i=1 %to 5;x&i.%if &i = 2 %then %let i = 99;%end;final=&i
%mend;
%macro plain;
  %do i=1 %to 3;y&i.%end;final=&i
%mend;
%macro by2;
  %do i=1 %to 6 %by 2;z&i.%end;final=&i
%mend;
%macro downward;
  %do i=5 %to 1 %by -1;d&i.%if &i = 4 %then %let i = -7;%end;final=&i
%mend;
/* the inner loop's early exit must not disturb the outer index */
%macro nested;
  %do i=1 %to 3;[i&i.%do j=1 %to 9;j&j.%if &j = 2 %then %let j = 42;%end;]%end;final=&i
%mend;
data _null_;
  put "early   =[%early]";
  put "plain   =[%plain]";
  put "by2     =[%by2]";
  put "downward=[%downward]";
  put "nested  =[%nested]";
run;
