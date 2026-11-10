options nodate nonumber;
data d;
input x y;
datalines;
1 2
2 5
3 5
4 9
5 8
6 13
7 12
8 17
;
proc corr data=d outp=r noprint; var x y; run;
data _null_; set r; file print; put _type_ ' ' _name_ ' ' x best32. ' ' y best32.; run;
