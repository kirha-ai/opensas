ods exclude all;
data t;input r c n;datalines;
1 1 2
1 2 0
2 1 0
2 2 3
;
run;
ods output RelRisk1ExactCL=o0a RelRisk2ExactCL=o0b;proc freq data=t;weight n / zeros;tables r*c / relrisk alpha=0.95;exact relrisk(method=noscore column=both);run;
data _null_;set o0a;if Name1 in ("XL_RRC1","XU_RRC1") then put "CHECK,2,3,0.95,noscore,columns,1," Name1 "," nValue1 best32.;run;
data _null_;set o0b;if Name1 in ("XL_RRC2","XU_RRC2") then put "CHECK,2,3,0.95,noscore,columns,2," Name1 "," nValue1 best32.;run;
data t;input r c n;datalines;
1 1 0
1 2 3
2 1 2
2 2 0
;
run;
ods output RelRisk1ExactCL=o1a RelRisk2ExactCL=o1b;proc freq data=t;weight n / zeros;tables r*c / relrisk alpha=0.95;exact relrisk(method=noscore column=both);run;
data _null_;set o1a;if Name1 in ("XL_RRC1","XU_RRC1") then put "CHECK,2,3,0.95,noscore,both,1," Name1 "," nValue1 best32.;run;
data _null_;set o1b;if Name1 in ("XL_RRC2","XU_RRC2") then put "CHECK,2,3,0.95,noscore,both,2," Name1 "," nValue1 best32.;run;
data t;input r c n;datalines;
1 1 0
1 2 2
2 1 3
2 2 0
;
run;
ods output RelRisk1ExactCL=o2a RelRisk2ExactCL=o2b;proc freq data=t;weight n / zeros;tables r*c / relrisk alpha=0.95;exact relrisk(method=noscore column=both);run;
data _null_;set o2a;if Name1 in ("XL_RRC1","XU_RRC1") then put "CHECK,2,3,0.95,noscore,repeat,1," Name1 "," nValue1 best32.;run;
data _null_;set o2b;if Name1 in ("XL_RRC2","XU_RRC2") then put "CHECK,2,3,0.95,noscore,repeat,2," Name1 "," nValue1 best32.;run;
data t;input r c n;datalines;
1 1 2
1 2 0
2 1 0
2 2 3
;
run;
ods output RelRisk1ExactCL=o3a RelRisk2ExactCL=o3b;proc freq data=t;weight n / zeros;tables r*c / relrisk alpha=0.95;exact relrisk(method=score column=both);run;
data _null_;set o3a;if Name1 in ("XL_RRC1","XU_RRC1") then put "CHECK,2,3,0.95,score,columns,1," Name1 "," nValue1 best32.;run;
data _null_;set o3b;if Name1 in ("XL_RRC2","XU_RRC2") then put "CHECK,2,3,0.95,score,columns,2," Name1 "," nValue1 best32.;run;
data t;input r c n;datalines;
1 1 0
1 2 3
2 1 2
2 2 0
;
run;
ods output RelRisk1ExactCL=o4a RelRisk2ExactCL=o4b;proc freq data=t;weight n / zeros;tables r*c / relrisk alpha=0.95;exact relrisk(method=score column=both);run;
data _null_;set o4a;if Name1 in ("XL_RRC1","XU_RRC1") then put "CHECK,2,3,0.95,score,both,1," Name1 "," nValue1 best32.;run;
data _null_;set o4b;if Name1 in ("XL_RRC2","XU_RRC2") then put "CHECK,2,3,0.95,score,both,2," Name1 "," nValue1 best32.;run;
data t;input r c n;datalines;
1 1 0
1 2 2
2 1 3
2 2 0
;
run;
ods output RelRisk1ExactCL=o5a RelRisk2ExactCL=o5b;proc freq data=t;weight n / zeros;tables r*c / relrisk alpha=0.95;exact relrisk(method=score column=both);run;
data _null_;set o5a;if Name1 in ("XL_RRC1","XU_RRC1") then put "CHECK,2,3,0.95,score,repeat,1," Name1 "," nValue1 best32.;run;
data _null_;set o5b;if Name1 in ("XL_RRC2","XU_RRC2") then put "CHECK,2,3,0.95,score,repeat,2," Name1 "," nValue1 best32.;run;
data t;input r c n;datalines;
1 1 2
1 2 0
2 1 0
2 2 3
;
run;
ods output RelRisk1ExactCL=o6a RelRisk2ExactCL=o6b;proc freq data=t;weight n / zeros;tables r*c / relrisk alpha=0.95;exact relrisk(method=score2 column=both);run;
data _null_;set o6a;if Name1 in ("XL_RRC1","XU_RRC1") then put "CHECK,2,3,0.95,score2,columns,1," Name1 "," nValue1 best32.;run;
data _null_;set o6b;if Name1 in ("XL_RRC2","XU_RRC2") then put "CHECK,2,3,0.95,score2,columns,2," Name1 "," nValue1 best32.;run;
data t;input r c n;datalines;
1 1 0
1 2 3
2 1 2
2 2 0
;
run;
ods output RelRisk1ExactCL=o7a RelRisk2ExactCL=o7b;proc freq data=t;weight n / zeros;tables r*c / relrisk alpha=0.95;exact relrisk(method=score2 column=both);run;
data _null_;set o7a;if Name1 in ("XL_RRC1","XU_RRC1") then put "CHECK,2,3,0.95,score2,both,1," Name1 "," nValue1 best32.;run;
data _null_;set o7b;if Name1 in ("XL_RRC2","XU_RRC2") then put "CHECK,2,3,0.95,score2,both,2," Name1 "," nValue1 best32.;run;
data t;input r c n;datalines;
1 1 0
1 2 2
2 1 3
2 2 0
;
run;
ods output RelRisk1ExactCL=o8a RelRisk2ExactCL=o8b;proc freq data=t;weight n / zeros;tables r*c / relrisk alpha=0.95;exact relrisk(method=score2 column=both);run;
data _null_;set o8a;if Name1 in ("XL_RRC1","XU_RRC1") then put "CHECK,2,3,0.95,score2,repeat,1," Name1 "," nValue1 best32.;run;
data _null_;set o8b;if Name1 in ("XL_RRC2","XU_RRC2") then put "CHECK,2,3,0.95,score2,repeat,2," Name1 "," nValue1 best32.;run;
data t;input r c n;datalines;
1 1 2
1 2 0
2 1 0
2 2 5
;
run;
ods output RelRisk1ExactCL=o9a RelRisk2ExactCL=o9b;proc freq data=t;weight n / zeros;tables r*c / relrisk alpha=0.94;exact relrisk(method=noscore column=both);run;
data _null_;set o9a;if Name1 in ("XL_RRC1","XU_RRC1") then put "CHECK,2,5,0.94,noscore,columns,1," Name1 "," nValue1 best32.;run;
data _null_;set o9b;if Name1 in ("XL_RRC2","XU_RRC2") then put "CHECK,2,5,0.94,noscore,columns,2," Name1 "," nValue1 best32.;run;
data t;input r c n;datalines;
1 1 0
1 2 5
2 1 2
2 2 0
;
run;
ods output RelRisk1ExactCL=o10a RelRisk2ExactCL=o10b;proc freq data=t;weight n / zeros;tables r*c / relrisk alpha=0.94;exact relrisk(method=noscore column=both);run;
data _null_;set o10a;if Name1 in ("XL_RRC1","XU_RRC1") then put "CHECK,2,5,0.94,noscore,both,1," Name1 "," nValue1 best32.;run;
data _null_;set o10b;if Name1 in ("XL_RRC2","XU_RRC2") then put "CHECK,2,5,0.94,noscore,both,2," Name1 "," nValue1 best32.;run;
data t;input r c n;datalines;
1 1 0
1 2 2
2 1 5
2 2 0
;
run;
ods output RelRisk1ExactCL=o11a RelRisk2ExactCL=o11b;proc freq data=t;weight n / zeros;tables r*c / relrisk alpha=0.94;exact relrisk(method=noscore column=both);run;
data _null_;set o11a;if Name1 in ("XL_RRC1","XU_RRC1") then put "CHECK,2,5,0.94,noscore,repeat,1," Name1 "," nValue1 best32.;run;
data _null_;set o11b;if Name1 in ("XL_RRC2","XU_RRC2") then put "CHECK,2,5,0.94,noscore,repeat,2," Name1 "," nValue1 best32.;run;
data t;input r c n;datalines;
1 1 2
1 2 0
2 1 0
2 2 5
;
run;
ods output RelRisk1ExactCL=o12a RelRisk2ExactCL=o12b;proc freq data=t;weight n / zeros;tables r*c / relrisk alpha=0.94;exact relrisk(method=score column=both);run;
data _null_;set o12a;if Name1 in ("XL_RRC1","XU_RRC1") then put "CHECK,2,5,0.94,score,columns,1," Name1 "," nValue1 best32.;run;
data _null_;set o12b;if Name1 in ("XL_RRC2","XU_RRC2") then put "CHECK,2,5,0.94,score,columns,2," Name1 "," nValue1 best32.;run;
data t;input r c n;datalines;
1 1 0
1 2 5
2 1 2
2 2 0
;
run;
ods output RelRisk1ExactCL=o13a RelRisk2ExactCL=o13b;proc freq data=t;weight n / zeros;tables r*c / relrisk alpha=0.94;exact relrisk(method=score column=both);run;
data _null_;set o13a;if Name1 in ("XL_RRC1","XU_RRC1") then put "CHECK,2,5,0.94,score,both,1," Name1 "," nValue1 best32.;run;
data _null_;set o13b;if Name1 in ("XL_RRC2","XU_RRC2") then put "CHECK,2,5,0.94,score,both,2," Name1 "," nValue1 best32.;run;
data t;input r c n;datalines;
1 1 0
1 2 2
2 1 5
2 2 0
;
run;
ods output RelRisk1ExactCL=o14a RelRisk2ExactCL=o14b;proc freq data=t;weight n / zeros;tables r*c / relrisk alpha=0.94;exact relrisk(method=score column=both);run;
data _null_;set o14a;if Name1 in ("XL_RRC1","XU_RRC1") then put "CHECK,2,5,0.94,score,repeat,1," Name1 "," nValue1 best32.;run;
data _null_;set o14b;if Name1 in ("XL_RRC2","XU_RRC2") then put "CHECK,2,5,0.94,score,repeat,2," Name1 "," nValue1 best32.;run;
data t;input r c n;datalines;
1 1 2
1 2 0
2 1 0
2 2 5
;
run;
ods output RelRisk1ExactCL=o15a RelRisk2ExactCL=o15b;proc freq data=t;weight n / zeros;tables r*c / relrisk alpha=0.94;exact relrisk(method=score2 column=both);run;
data _null_;set o15a;if Name1 in ("XL_RRC1","XU_RRC1") then put "CHECK,2,5,0.94,score2,columns,1," Name1 "," nValue1 best32.;run;
data _null_;set o15b;if Name1 in ("XL_RRC2","XU_RRC2") then put "CHECK,2,5,0.94,score2,columns,2," Name1 "," nValue1 best32.;run;
data t;input r c n;datalines;
1 1 0
1 2 5
2 1 2
2 2 0
;
run;
ods output RelRisk1ExactCL=o16a RelRisk2ExactCL=o16b;proc freq data=t;weight n / zeros;tables r*c / relrisk alpha=0.94;exact relrisk(method=score2 column=both);run;
data _null_;set o16a;if Name1 in ("XL_RRC1","XU_RRC1") then put "CHECK,2,5,0.94,score2,both,1," Name1 "," nValue1 best32.;run;
data _null_;set o16b;if Name1 in ("XL_RRC2","XU_RRC2") then put "CHECK,2,5,0.94,score2,both,2," Name1 "," nValue1 best32.;run;
data t;input r c n;datalines;
1 1 0
1 2 2
2 1 5
2 2 0
;
run;
ods output RelRisk1ExactCL=o17a RelRisk2ExactCL=o17b;proc freq data=t;weight n / zeros;tables r*c / relrisk alpha=0.94;exact relrisk(method=score2 column=both);run;
data _null_;set o17a;if Name1 in ("XL_RRC1","XU_RRC1") then put "CHECK,2,5,0.94,score2,repeat,1," Name1 "," nValue1 best32.;run;
data _null_;set o17b;if Name1 in ("XL_RRC2","XU_RRC2") then put "CHECK,2,5,0.94,score2,repeat,2," Name1 "," nValue1 best32.;run;
data t;input r c n;datalines;
1 1 2
1 2 0
2 1 0
2 2 5
;
run;
ods output RelRisk1ExactCL=o18a RelRisk2ExactCL=o18b;proc freq data=t;weight n / zeros;tables r*c / relrisk alpha=0.99;exact relrisk(method=noscore column=both);run;
data _null_;set o18a;if Name1 in ("XL_RRC1","XU_RRC1") then put "CHECK,2,5,0.99,noscore,columns,1," Name1 "," nValue1 best32.;run;
data _null_;set o18b;if Name1 in ("XL_RRC2","XU_RRC2") then put "CHECK,2,5,0.99,noscore,columns,2," Name1 "," nValue1 best32.;run;
data t;input r c n;datalines;
1 1 0
1 2 5
2 1 2
2 2 0
;
run;
ods output RelRisk1ExactCL=o19a RelRisk2ExactCL=o19b;proc freq data=t;weight n / zeros;tables r*c / relrisk alpha=0.99;exact relrisk(method=noscore column=both);run;
data _null_;set o19a;if Name1 in ("XL_RRC1","XU_RRC1") then put "CHECK,2,5,0.99,noscore,both,1," Name1 "," nValue1 best32.;run;
data _null_;set o19b;if Name1 in ("XL_RRC2","XU_RRC2") then put "CHECK,2,5,0.99,noscore,both,2," Name1 "," nValue1 best32.;run;
data t;input r c n;datalines;
1 1 0
1 2 2
2 1 5
2 2 0
;
run;
ods output RelRisk1ExactCL=o20a RelRisk2ExactCL=o20b;proc freq data=t;weight n / zeros;tables r*c / relrisk alpha=0.99;exact relrisk(method=noscore column=both);run;
data _null_;set o20a;if Name1 in ("XL_RRC1","XU_RRC1") then put "CHECK,2,5,0.99,noscore,repeat,1," Name1 "," nValue1 best32.;run;
data _null_;set o20b;if Name1 in ("XL_RRC2","XU_RRC2") then put "CHECK,2,5,0.99,noscore,repeat,2," Name1 "," nValue1 best32.;run;
data t;input r c n;datalines;
1 1 2
1 2 0
2 1 0
2 2 5
;
run;
ods output RelRisk1ExactCL=o21a RelRisk2ExactCL=o21b;proc freq data=t;weight n / zeros;tables r*c / relrisk alpha=0.99;exact relrisk(method=score column=both);run;
data _null_;set o21a;if Name1 in ("XL_RRC1","XU_RRC1") then put "CHECK,2,5,0.99,score,columns,1," Name1 "," nValue1 best32.;run;
data _null_;set o21b;if Name1 in ("XL_RRC2","XU_RRC2") then put "CHECK,2,5,0.99,score,columns,2," Name1 "," nValue1 best32.;run;
data t;input r c n;datalines;
1 1 0
1 2 5
2 1 2
2 2 0
;
run;
ods output RelRisk1ExactCL=o22a RelRisk2ExactCL=o22b;proc freq data=t;weight n / zeros;tables r*c / relrisk alpha=0.99;exact relrisk(method=score column=both);run;
data _null_;set o22a;if Name1 in ("XL_RRC1","XU_RRC1") then put "CHECK,2,5,0.99,score,both,1," Name1 "," nValue1 best32.;run;
data _null_;set o22b;if Name1 in ("XL_RRC2","XU_RRC2") then put "CHECK,2,5,0.99,score,both,2," Name1 "," nValue1 best32.;run;
data t;input r c n;datalines;
1 1 0
1 2 2
2 1 5
2 2 0
;
run;
ods output RelRisk1ExactCL=o23a RelRisk2ExactCL=o23b;proc freq data=t;weight n / zeros;tables r*c / relrisk alpha=0.99;exact relrisk(method=score column=both);run;
data _null_;set o23a;if Name1 in ("XL_RRC1","XU_RRC1") then put "CHECK,2,5,0.99,score,repeat,1," Name1 "," nValue1 best32.;run;
data _null_;set o23b;if Name1 in ("XL_RRC2","XU_RRC2") then put "CHECK,2,5,0.99,score,repeat,2," Name1 "," nValue1 best32.;run;
data t;input r c n;datalines;
1 1 2
1 2 0
2 1 0
2 2 5
;
run;
ods output RelRisk1ExactCL=o24a RelRisk2ExactCL=o24b;proc freq data=t;weight n / zeros;tables r*c / relrisk alpha=0.99;exact relrisk(method=score2 column=both);run;
data _null_;set o24a;if Name1 in ("XL_RRC1","XU_RRC1") then put "CHECK,2,5,0.99,score2,columns,1," Name1 "," nValue1 best32.;run;
data _null_;set o24b;if Name1 in ("XL_RRC2","XU_RRC2") then put "CHECK,2,5,0.99,score2,columns,2," Name1 "," nValue1 best32.;run;
data t;input r c n;datalines;
1 1 0
1 2 5
2 1 2
2 2 0
;
run;
ods output RelRisk1ExactCL=o25a RelRisk2ExactCL=o25b;proc freq data=t;weight n / zeros;tables r*c / relrisk alpha=0.99;exact relrisk(method=score2 column=both);run;
data _null_;set o25a;if Name1 in ("XL_RRC1","XU_RRC1") then put "CHECK,2,5,0.99,score2,both,1," Name1 "," nValue1 best32.;run;
data _null_;set o25b;if Name1 in ("XL_RRC2","XU_RRC2") then put "CHECK,2,5,0.99,score2,both,2," Name1 "," nValue1 best32.;run;
data t;input r c n;datalines;
1 1 0
1 2 2
2 1 5
2 2 0
;
run;
ods output RelRisk1ExactCL=o26a RelRisk2ExactCL=o26b;proc freq data=t;weight n / zeros;tables r*c / relrisk alpha=0.99;exact relrisk(method=score2 column=both);run;
data _null_;set o26a;if Name1 in ("XL_RRC1","XU_RRC1") then put "CHECK,2,5,0.99,score2,repeat,1," Name1 "," nValue1 best32.;run;
data _null_;set o26b;if Name1 in ("XL_RRC2","XU_RRC2") then put "CHECK,2,5,0.99,score2,repeat,2," Name1 "," nValue1 best32.;run;
data t;input r c n;datalines;
1 1 4
1 2 0
2 1 0
2 2 3
;
run;
ods output RelRisk1ExactCL=o27a RelRisk2ExactCL=o27b;proc freq data=t;weight n / zeros;tables r*c / relrisk alpha=0.99;exact relrisk(method=noscore column=both);run;
data _null_;set o27a;if Name1 in ("XL_RRC1","XU_RRC1") then put "CHECK,4,3,0.99,noscore,columns,1," Name1 "," nValue1 best32.;run;
data _null_;set o27b;if Name1 in ("XL_RRC2","XU_RRC2") then put "CHECK,4,3,0.99,noscore,columns,2," Name1 "," nValue1 best32.;run;
data t;input r c n;datalines;
1 1 0
1 2 3
2 1 4
2 2 0
;
run;
ods output RelRisk1ExactCL=o28a RelRisk2ExactCL=o28b;proc freq data=t;weight n / zeros;tables r*c / relrisk alpha=0.99;exact relrisk(method=noscore column=both);run;
data _null_;set o28a;if Name1 in ("XL_RRC1","XU_RRC1") then put "CHECK,4,3,0.99,noscore,both,1," Name1 "," nValue1 best32.;run;
data _null_;set o28b;if Name1 in ("XL_RRC2","XU_RRC2") then put "CHECK,4,3,0.99,noscore,both,2," Name1 "," nValue1 best32.;run;
data t;input r c n;datalines;
1 1 0
1 2 4
2 1 3
2 2 0
;
run;
ods output RelRisk1ExactCL=o29a RelRisk2ExactCL=o29b;proc freq data=t;weight n / zeros;tables r*c / relrisk alpha=0.99;exact relrisk(method=noscore column=both);run;
data _null_;set o29a;if Name1 in ("XL_RRC1","XU_RRC1") then put "CHECK,4,3,0.99,noscore,repeat,1," Name1 "," nValue1 best32.;run;
data _null_;set o29b;if Name1 in ("XL_RRC2","XU_RRC2") then put "CHECK,4,3,0.99,noscore,repeat,2," Name1 "," nValue1 best32.;run;
data t;input r c n;datalines;
1 1 4
1 2 0
2 1 0
2 2 3
;
run;
ods output RelRisk1ExactCL=o30a RelRisk2ExactCL=o30b;proc freq data=t;weight n / zeros;tables r*c / relrisk alpha=0.99;exact relrisk(method=score column=both);run;
data _null_;set o30a;if Name1 in ("XL_RRC1","XU_RRC1") then put "CHECK,4,3,0.99,score,columns,1," Name1 "," nValue1 best32.;run;
data _null_;set o30b;if Name1 in ("XL_RRC2","XU_RRC2") then put "CHECK,4,3,0.99,score,columns,2," Name1 "," nValue1 best32.;run;
data t;input r c n;datalines;
1 1 0
1 2 3
2 1 4
2 2 0
;
run;
ods output RelRisk1ExactCL=o31a RelRisk2ExactCL=o31b;proc freq data=t;weight n / zeros;tables r*c / relrisk alpha=0.99;exact relrisk(method=score column=both);run;
data _null_;set o31a;if Name1 in ("XL_RRC1","XU_RRC1") then put "CHECK,4,3,0.99,score,both,1," Name1 "," nValue1 best32.;run;
data _null_;set o31b;if Name1 in ("XL_RRC2","XU_RRC2") then put "CHECK,4,3,0.99,score,both,2," Name1 "," nValue1 best32.;run;
data t;input r c n;datalines;
1 1 0
1 2 4
2 1 3
2 2 0
;
run;
ods output RelRisk1ExactCL=o32a RelRisk2ExactCL=o32b;proc freq data=t;weight n / zeros;tables r*c / relrisk alpha=0.99;exact relrisk(method=score column=both);run;
data _null_;set o32a;if Name1 in ("XL_RRC1","XU_RRC1") then put "CHECK,4,3,0.99,score,repeat,1," Name1 "," nValue1 best32.;run;
data _null_;set o32b;if Name1 in ("XL_RRC2","XU_RRC2") then put "CHECK,4,3,0.99,score,repeat,2," Name1 "," nValue1 best32.;run;
data t;input r c n;datalines;
1 1 4
1 2 0
2 1 0
2 2 3
;
run;
ods output RelRisk1ExactCL=o33a RelRisk2ExactCL=o33b;proc freq data=t;weight n / zeros;tables r*c / relrisk alpha=0.99;exact relrisk(method=score2 column=both);run;
data _null_;set o33a;if Name1 in ("XL_RRC1","XU_RRC1") then put "CHECK,4,3,0.99,score2,columns,1," Name1 "," nValue1 best32.;run;
data _null_;set o33b;if Name1 in ("XL_RRC2","XU_RRC2") then put "CHECK,4,3,0.99,score2,columns,2," Name1 "," nValue1 best32.;run;
data t;input r c n;datalines;
1 1 0
1 2 3
2 1 4
2 2 0
;
run;
ods output RelRisk1ExactCL=o34a RelRisk2ExactCL=o34b;proc freq data=t;weight n / zeros;tables r*c / relrisk alpha=0.99;exact relrisk(method=score2 column=both);run;
data _null_;set o34a;if Name1 in ("XL_RRC1","XU_RRC1") then put "CHECK,4,3,0.99,score2,both,1," Name1 "," nValue1 best32.;run;
data _null_;set o34b;if Name1 in ("XL_RRC2","XU_RRC2") then put "CHECK,4,3,0.99,score2,both,2," Name1 "," nValue1 best32.;run;
data t;input r c n;datalines;
1 1 0
1 2 4
2 1 3
2 2 0
;
run;
ods output RelRisk1ExactCL=o35a RelRisk2ExactCL=o35b;proc freq data=t;weight n / zeros;tables r*c / relrisk alpha=0.99;exact relrisk(method=score2 column=both);run;
data _null_;set o35a;if Name1 in ("XL_RRC1","XU_RRC1") then put "CHECK,4,3,0.99,score2,repeat,1," Name1 "," nValue1 best32.;run;
data _null_;set o35b;if Name1 in ("XL_RRC2","XU_RRC2") then put "CHECK,4,3,0.99,score2,repeat,2," Name1 "," nValue1 best32.;run;