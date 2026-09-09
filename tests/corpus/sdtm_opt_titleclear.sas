/* A bare TITLE; clears earlier titles for the next listing */
title "First Report";
data a; x = 1; run;
proc print data=a; run;
title;
data b; y = 2; run;
proc print data=b; run;
