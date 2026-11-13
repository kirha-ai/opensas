data version; length release $64; release="&sysvlong4";run;proc print;run;
%macro candidate(x,n1,n2,r0);
data t; r=1;c=1;n=&x;output;r=1;c=2;n=&n1-&x;output;r=2;c=1;n=&n2;output;r=2;c=2;n=0;output;run;
title "n1=&n1 n2=&n2 x=&x null=&r0";
proc freq data=t; weight n / zeros; tables r*c / relrisk(equal(null=&r0) method=fm); run;
%mend;
%candidate(0,2,5,.249913109375)
%candidate(1,2,5,.249913109375)
%candidate(2,2,5,.249913109375)
%candidate(0,4,3,.11966864267985)
%candidate(1,4,3,.11966864267985)
%candidate(2,4,3,.11966864267985)
%candidate(3,4,3,.11966864267985)
%candidate(4,4,3,.11966864267985)
