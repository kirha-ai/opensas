/* BUG-titlecancel: a NUMBERED title-cancel (`title2;`) clears line 2 AND all
   higher-numbered lines; same rule for FOOTNOTE. */
options nodate nonumber;
title1 "Keep Me";
title2 "Drop Two";
title3 "Drop Three";
footnote1 "Keep Foot";
footnote2 "Drop Foot Two";
footnote3 "Drop Foot Three";
data a; x = 1; run;
title2;
footnote2;
proc print data=a noobs;
run;
