options nodate nonumber;
data empty; length b x y w 8; stop; run;
data d; input b x y w; datalines;
. . . 1
. . . 1
1 . 1 0
1 2 2 0
2 . 1 2
2 2 . 3
2 2 2 4
;
run;
proc freq data=empty; tables x / out=e; run;

proc freq data=d; by b; tables x / out=a outcum; run;
proc print data=a; run;
proc freq data=d; by b; tables x / missprint out=m outcum; run;
proc print data=m; run;
proc freq data=d; by b; tables x / missing out=i outcum; run;
proc print data=i; run;
proc freq data=d; by b; weight w; tables x / missprint out=w outcum; run;
proc print data=w; run;
proc freq data=d; by b; weight w / zeros; tables x / missprint out=z outcum; run;
proc print data=z; run;
proc freq data=d; by b; tables x*y / missprint out=c; run;
proc print data=c; run;

proc freq data=d; where b=1; weight w; tables x / out=zero; run;

proc freq data=d; where b=.; tables x*y / out=allcross; run;
proc print data=allcross; run;
proc format; value $mix ' '='Unknown' 'X'='Unknown' 'Y'='Known'; run;
data fm; length c $1; b=1; c=' '; w=1; output; c='X'; w=2; output; c='Y'; w=3; output; run;
proc freq data=fm; format c $mix.; weight w; tables c / out=fdef outcum; run;
proc print data=fdef; format c $1.; run;
proc freq data=fm; format c $mix.; weight w; tables c / missprint out=fmp outcum; run;
proc print data=fmp; format c $1.; run;
proc freq data=fm; format c $mix.; weight w; tables c / missing out=fmi outcum; run;
proc print data=fmi; format c $1.; run;
data cross; input x y; datalines;
. 1
2 .
;
run;
proc freq data=cross; tables x*y / out=xc; run;
proc freq data=cross; tables x*y / missprint; run;
