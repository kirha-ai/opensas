/* REG013: invented replicated design; S154 physical8642-44,8647-48.
   Group means 2,3,8; beta=(4/3,3); SSE=34/3; SST=142/3;
   G=(5/12,-1/4;-1/4,1/4). Pure SS=6, lack SS=16/3,
   F(1,3)=8/3. Its exact tail is (2/pi)*(theta-sin(theta)cos(theta)),
   sin(theta)^2=9/17. DW=42/17, autocorrelation=-37/102.
   HC3=(86,-52;-52,52)/49. Standard errors are diagonal square roots.
   Ordinary t4 two-sided tail is 1-(3*s-s^3)/2, s=t/sqrt(t*t+4).
   Robust slope Wald=441/52; chi1 tail=erfc(sqrt(441/104)).
   These exact identities determine the complete expected listing independently. */
data sample;
input x y;
datalines;
0 1
0 3
1 2
1 4
2 7
2 9
;
proc reg data=sample;
model y=x / dw lackfit acov hccmethod=3;
slope: test x=0;
run;
