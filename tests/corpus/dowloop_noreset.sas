/* DOW-loop accumulator WITHOUT a first.-reset: the sum statement `tot + x`
   creates a RETAINED variable initialized to 0 once at compile time and never
   auto-reset between outer DATA-step iterations. So across BY groups it keeps a
   RUNNING total, not a per-group total (contrast dowloop.sas which resets with
   `if first.grp then total=0`). g=1 -> 10+20+5=35; g=2 continues 35+100+1=136.
   Classic silent-wrong trap: forgetting the reset yields cumulative sums.
   Synthesized (no PHI). */
data a;
  input g x @@;
  datalines;
1 10 1 20 1 5 2 100 2 1
;
run;

data sums;
  do until(last.g);
    set a; by g;
    tot + x;
  end;
  keep g tot;
run;

proc print data=sums noobs; run;
