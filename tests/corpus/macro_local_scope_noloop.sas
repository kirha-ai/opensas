/* Regression: BUG-makeemptyhang — a %local name-list once spun forever in the
   scope handler (cursor never advanced). Expansion must terminate and let the
   following step run. */
%macro m; %local a b c; %let a=1; %mend;
%m
data _null_; put "scope ok"; run;
