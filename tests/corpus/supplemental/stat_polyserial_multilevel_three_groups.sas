data probe; input x y w; datalines;
0 0 2
1 0 3
4 1 2
5 1 1
7 1 3
11 2 1
13 2 3
;
run;

%macro fit(id,scale,freq,converge,iter);
data sample; set probe; x=x*&scale; w=w*&freq; run;
proc corr data=sample outpls=fit polyserial(converge=&converge maxiter=&iter) nosimple;
var x; with y; freq w; run;
data _null_; set fit; file print;
if _TYPE_='CORR' then put "SERIAL &id " x best32.; run;

%mend;
%fit(three-groups-c0.0001-m1,1,1,0.0001,1);
%fit(three-groups-c0.0001-m5,1,1,0.0001,5);
%fit(three-groups-c0.0001-m200,1,1,0.0001,200);
%fit(three-groups-c0.5-m1,1,1,0.5,1);
%fit(three-groups-c0.5-m3,1,1,0.5,3);
%fit(three-groups-c0.5-m200,1,1,0.5,200);
%fit(three-groups-c0.01-m1,1,1,0.01,1);
%fit(three-groups-c0.01-m5,1,1,0.01,5);
%fit(three-groups-c0.01-m200,1,1,0.01,200);
%fit(three-groups-c0.1-m1,1,1,0.1,1);
%fit(three-groups-c0.1-m5,1,1,0.1,5);
%fit(three-groups-c0.1-m200,1,1,0.1,200);
