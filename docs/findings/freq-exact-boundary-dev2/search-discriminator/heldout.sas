ods exclude all;
data t;input r c n;datalines;
1 1 0
1 2 3
2 1 4
2 2 0
;
run;
ods output RelRisk1ExactCL=o0noscore;proc freq data=t;weight n / zeros;tables r*c / relrisk alpha=0.939;exact relrisk(method=noscore);run;
data _null_;set o0noscore;if Name1="XU_RRC1" then put "HOLD,3,4,0.939,noscore," nValue1 best32.;run;
ods output RelRisk1ExactCL=o0score;proc freq data=t;weight n / zeros;tables r*c / relrisk alpha=0.939;exact relrisk(method=score);run;
data _null_;set o0score;if Name1="XU_RRC1" then put "HOLD,3,4,0.939,score," nValue1 best32.;run;
data t;input r c n;datalines;
1 1 0
1 2 3
2 1 4
2 2 0
;
run;
ods output RelRisk1ExactCL=o1noscore;proc freq data=t;weight n / zeros;tables r*c / relrisk alpha=0.94;exact relrisk(method=noscore);run;
data _null_;set o1noscore;if Name1="XU_RRC1" then put "HOLD,3,4,0.94,noscore," nValue1 best32.;run;
ods output RelRisk1ExactCL=o1score;proc freq data=t;weight n / zeros;tables r*c / relrisk alpha=0.94;exact relrisk(method=score);run;
data _null_;set o1score;if Name1="XU_RRC1" then put "HOLD,3,4,0.94,score," nValue1 best32.;run;
data t;input r c n;datalines;
1 1 0
1 2 3
2 1 4
2 2 0
;
run;
ods output RelRisk1ExactCL=o2noscore;proc freq data=t;weight n / zeros;tables r*c / relrisk alpha=0.941;exact relrisk(method=noscore);run;
data _null_;set o2noscore;if Name1="XU_RRC1" then put "HOLD,3,4,0.941,noscore," nValue1 best32.;run;
ods output RelRisk1ExactCL=o2score;proc freq data=t;weight n / zeros;tables r*c / relrisk alpha=0.941;exact relrisk(method=score);run;
data _null_;set o2score;if Name1="XU_RRC1" then put "HOLD,3,4,0.941,score," nValue1 best32.;run;
data t;input r c n;datalines;
1 1 0
1 2 5
2 1 2
2 2 0
;
run;
ods output RelRisk1ExactCL=o3noscore;proc freq data=t;weight n / zeros;tables r*c / relrisk alpha=0.949;exact relrisk(method=noscore);run;
data _null_;set o3noscore;if Name1="XU_RRC1" then put "HOLD,5,2,0.949,noscore," nValue1 best32.;run;
ods output RelRisk1ExactCL=o3score;proc freq data=t;weight n / zeros;tables r*c / relrisk alpha=0.949;exact relrisk(method=score);run;
data _null_;set o3score;if Name1="XU_RRC1" then put "HOLD,5,2,0.949,score," nValue1 best32.;run;
data t;input r c n;datalines;
1 1 0
1 2 5
2 1 2
2 2 0
;
run;
ods output RelRisk1ExactCL=o4noscore;proc freq data=t;weight n / zeros;tables r*c / relrisk alpha=0.95;exact relrisk(method=noscore);run;
data _null_;set o4noscore;if Name1="XU_RRC1" then put "HOLD,5,2,0.95,noscore," nValue1 best32.;run;
ods output RelRisk1ExactCL=o4score;proc freq data=t;weight n / zeros;tables r*c / relrisk alpha=0.95;exact relrisk(method=score);run;
data _null_;set o4score;if Name1="XU_RRC1" then put "HOLD,5,2,0.95,score," nValue1 best32.;run;
data t;input r c n;datalines;
1 1 0
1 2 5
2 1 2
2 2 0
;
run;
ods output RelRisk1ExactCL=o5noscore;proc freq data=t;weight n / zeros;tables r*c / relrisk alpha=0.951;exact relrisk(method=noscore);run;
data _null_;set o5noscore;if Name1="XU_RRC1" then put "HOLD,5,2,0.951,noscore," nValue1 best32.;run;
ods output RelRisk1ExactCL=o5score;proc freq data=t;weight n / zeros;tables r*c / relrisk alpha=0.951;exact relrisk(method=score);run;
data _null_;set o5score;if Name1="XU_RRC1" then put "HOLD,5,2,0.951,score," nValue1 best32.;run;
data t;input r c n;datalines;
1 1 0
1 2 2
2 1 7
2 2 0
;
run;
ods output RelRisk1ExactCL=o6noscore;proc freq data=t;weight n / zeros;tables r*c / relrisk alpha=0.937;exact relrisk(method=noscore);run;
data _null_;set o6noscore;if Name1="XU_RRC1" then put "HOLD,2,7,0.937,noscore," nValue1 best32.;run;
ods output RelRisk1ExactCL=o6score;proc freq data=t;weight n / zeros;tables r*c / relrisk alpha=0.937;exact relrisk(method=score);run;
data _null_;set o6score;if Name1="XU_RRC1" then put "HOLD,2,7,0.937,score," nValue1 best32.;run;
data t;input r c n;datalines;
1 1 0
1 2 2
2 1 7
2 2 0
;
run;
ods output RelRisk1ExactCL=o7noscore;proc freq data=t;weight n / zeros;tables r*c / relrisk alpha=0.94;exact relrisk(method=noscore);run;
data _null_;set o7noscore;if Name1="XU_RRC1" then put "HOLD,2,7,0.94,noscore," nValue1 best32.;run;
ods output RelRisk1ExactCL=o7score;proc freq data=t;weight n / zeros;tables r*c / relrisk alpha=0.94;exact relrisk(method=score);run;
data _null_;set o7score;if Name1="XU_RRC1" then put "HOLD,2,7,0.94,score," nValue1 best32.;run;
data t;input r c n;datalines;
1 1 0
1 2 2
2 1 7
2 2 0
;
run;
ods output RelRisk1ExactCL=o8noscore;proc freq data=t;weight n / zeros;tables r*c / relrisk alpha=0.943;exact relrisk(method=noscore);run;
data _null_;set o8noscore;if Name1="XU_RRC1" then put "HOLD,2,7,0.943,noscore," nValue1 best32.;run;
ods output RelRisk1ExactCL=o8score;proc freq data=t;weight n / zeros;tables r*c / relrisk alpha=0.943;exact relrisk(method=score);run;
data _null_;set o8score;if Name1="XU_RRC1" then put "HOLD,2,7,0.943,score," nValue1 best32.;run;