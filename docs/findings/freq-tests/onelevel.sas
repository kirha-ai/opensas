options nodate nonumber;
data d;
 do i=1 to 3; g=1; output; end;
run;
proc freq data=d; tables g / chisq; run;
