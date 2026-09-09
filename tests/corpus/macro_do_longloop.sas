/* QA tick377 F1 — a LEGAL iterative %DO past 100,000 iterations must run to
   completion. The max_loop_iters backstop (96854b8e) was applied to the RAW
   TRIP COUNT, so this loop stopped at 100,000 with a wrong &n plus a hard
   ERROR; the Macro Language Reference places NO upper bound on the trip count
   (the %DO entry's index re-read / early-exit text, printed p.388-389, has
   none). The replacement guard trips on NON-ADVANCEMENT — an index that did
   not move toward `stop` this pass — so a legal long loop never trips.
   110,000 exceeds the old cap while keeping the suite fast.
   The other side (a genuinely non-advancing loop still caught, with its
   stderr message and D-009 rc=2 class) is pinned by a unit test in
   macro.zig — corpus diffs stdout only and cannot see either. */
%macro big;%local n i;%let n=0;%do i=1 %to 110000;%let n=%eval(&n + 1);%end;BIGLOOP_N=&n%mend;
data _null_;
  put "[%big]";
run;
