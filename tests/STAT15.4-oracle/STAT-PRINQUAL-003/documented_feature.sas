/* STAT-PRINQUAL-003: PRINQUAL — TRANSFORM / The Three Methods of Variable Transformation / Understanding How PROC PRINQUAL Works
 * Source: S154 / Chapter 99 / `TRANSFORM Statement` (PDF pp. 8049–8057); S154 / Chapter 99 / `The Three Methods of Variable Transformation` (PDF pp. 8057–8058); S154 / Chapter 99 / `Understanding How PROC PRINQUAL Works` (PDF pp. 8058–8062).
 * Discriminates: Example 99.1: Multidimensional Preference Analysis of Automobile Data; explicit statements: TRANSFORM
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

title 'Preference Ratings for Automobiles Manufactured in 1980';
options validvarname=any;
data CarPref;
input Make $ 1-10 Model $ 12-22 @25 ('1'n-'25'n) (1.);
datalines;
Cadillac   Eldorado     8007990491240508971093809
Chevrolet  Chevette     0051200423451043003515698
Chevrolet  Citation     4053305814161643544747795
Chevrolet  Malibu       6027400723121345545668658
Ford       Fairmont     2024006715021443530648655
Ford       Mustang      5007197705021101850657555
Ford       Pinto        0021000303030201500514078
Honda      Accord       5956897609699952998975078
Honda      Civic        4836709507488852567765075
Lincoln    Continental  7008990592230409962091909
Plymouth   Gran Fury    7006000434101107333458708
Plymouth   Horizon      3005005635461302444675655
Plymouth   Volare       4005003614021602754476555
Pontiac    Firebird     0107895613201206958265907
Volkswagen Dasher       4858696508877795377895000
Volkswagen Rabbit       4858509709695795487885000
Volvo      DL           9989998909999987989919000
;
ods graphics on;
* Principal Component Analysis of the Original Data;
proc princomp data=CarPref;
ods select ScreePlot;
var '1'n-'25'n;
run;
* Transform the Data to Better Fit a Two Component Model;
proc prinqual data=CarPref out=Results n=2 replace mdpref;
title2 'Multidimensional Preference (MDPREF) Analysis';
title3 'Optimal Monotonic Transformation of Preference Data';
id model;
transform monotone('1'n-'25'n);
run;
* Final Principal Component Analysis;
proc princomp data=Results;
ods select ScreePlot;
var '1'n-'25'n;
where _TYPE_='SCORE';
run;
ods trace on;
proc prinqual data=CarPref out=Results n=2 replace mdpref;
title2 'Multidimensional Preference (MDPREF) Analysis';
title3 'Optimal Monotonic Transformation of Preference Data';
id model;
transform monotone('1'n-'25'n);
run;
proc template;
source Stat.Prinqual.Graphics.MDPref;
run;
proc template;
define statgraph Stat.Prinqual.Graphics.MDPref;
notes "Multidimensional Preference Analysis Plot";
dynamic xVar yVar xVec yVec ylab xlab yshortlab xshortlab xOri yOri
stretch;
begingraph;
entrytitle "Multidimensional Preference Analysis";
layout overlayequated / equatetype=fit xaxisopts=(label=XLAB shortlabel
=XSHORTLAB offsetmin=0.1 offsetmax=0.1) yaxisopts=(label=YLAB
shortlabel=YSHORTLAB offsetmin=0.1 offsetmax=0.1);
scatterplot y=YVAR x=XVAR / datalabel=IDLAB1 rolename=(_tip1=
OBSNUMVAR _id2=IDLAB2 _id3=IDLAB3 _id4=IDLAB4 _id5=IDLAB5 _id6=
IDLAB6 _id7=IDLAB7 _id8=IDLAB8 _id9=IDLAB9 _id10=IDLAB10 _id11=
IDLAB11 _id12=IDLAB12 _id13=IDLAB13 _id14=IDLAB14 _id15=IDLAB15
_id16=IDLAB16 _id17=IDLAB17 _id18=IDLAB18 _id19=IDLAB19 _id20=
IDLAB20) tip=(y x datalabel _tip1 _id2 _id3 _id4 _id5 _id6 _id7
_id8 _id9 _id10 _id11 _id12 _id13 _id14 _id15 _id16 _id17 _id18
_id19 _id20)
group=idlab2 name='s';
*<==== add the group variable ====<<<<;
vectorplot y=YVEC x=XVEC xorigin=0 yorigin=0 / datalabel=LABEL2VAR
shaftprotected=false rolename=(_tip1=VNAME _tip2=VLABEL _tip3=
YORI _tip4=XORI _tip5=LENGTH _tip6=LENGTH2) tip=(y x datalabel
_tip1 _tip2 _tip3 _tip4 _tip5 _tip6) datalabelattrs=
GRAPHVALUETEXT (color=GraphData2:ContrastColor) lineattrs=
GRAPHDATA2 (pattern=solid) primary=true;
discretelegend 's';
*<==== add a legend ====<<<<;
if (0)
entry "Vector Stretch = " STRETCH / autoalign=(topright topleft
bottomright bottomleft right left top bottom);
endif;
endlayout;
endgraph;
end;
run;
proc prinqual data=CarPref out=Results n=2 replace mdpref;
title2 'Multidimensional Preference (MDPREF) Analysis';
title3 'Optimal Monotonic Transformation of Preference Data';
id model make;
transform monotone('1'n-'25'n);
run;
