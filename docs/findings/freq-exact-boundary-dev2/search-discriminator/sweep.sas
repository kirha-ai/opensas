ods exclude all; data release; v="&sysvlong4";run;
data t; input r c n; datalines;
1 1 0
1 2 2
2 1 3
2 2 0
;
run;
ods output RelRisk1ExactCL=o0a RelRisk2ExactCL=o0b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.49; exact relrisk(method=noscore column=both) / ;run;
data _null_;set o0a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,0,2,3,0.49,noscore,0,1,," Name1 "," nValue1 best32.;run;
data _null_;set o0b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,0,2,3,0.49,noscore,0,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 3
1 2 0
2 1 0
2 2 2
;
run;
ods output RelRisk1ExactCL=o1a RelRisk2ExactCL=o1b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.49; exact relrisk(method=noscore column=both) / ;run;
data _null_;set o1a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,1,2,3,0.49,noscore,1,1,," Name1 "," nValue1 best32.;run;
data _null_;set o1b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,1,2,3,0.49,noscore,1,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 2
2 1 3
2 2 0
;
run;
ods output RelRisk1ExactCL=o2a RelRisk2ExactCL=o2b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.499; exact relrisk(method=noscore column=both) / ;run;
data _null_;set o2a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,2,2,3,0.499,noscore,0,1,," Name1 "," nValue1 best32.;run;
data _null_;set o2b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,2,2,3,0.499,noscore,0,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 3
1 2 0
2 1 0
2 2 2
;
run;
ods output RelRisk1ExactCL=o3a RelRisk2ExactCL=o3b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.499; exact relrisk(method=noscore column=both) / ;run;
data _null_;set o3a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,3,2,3,0.499,noscore,1,1,," Name1 "," nValue1 best32.;run;
data _null_;set o3b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,3,2,3,0.499,noscore,1,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 2
2 1 3
2 2 0
;
run;
ods output RelRisk1ExactCL=o4a RelRisk2ExactCL=o4b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.5; exact relrisk(method=noscore column=both) / ;run;
data _null_;set o4a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,4,2,3,0.5,noscore,0,1,," Name1 "," nValue1 best32.;run;
data _null_;set o4b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,4,2,3,0.5,noscore,0,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 3
1 2 0
2 1 0
2 2 2
;
run;
ods output RelRisk1ExactCL=o5a RelRisk2ExactCL=o5b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.5; exact relrisk(method=noscore column=both) / ;run;
data _null_;set o5a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,5,2,3,0.5,noscore,1,1,," Name1 "," nValue1 best32.;run;
data _null_;set o5b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,5,2,3,0.5,noscore,1,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 2
2 1 3
2 2 0
;
run;
ods output RelRisk1ExactCL=o6a RelRisk2ExactCL=o6b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.501; exact relrisk(method=noscore column=both) / ;run;
data _null_;set o6a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,6,2,3,0.501,noscore,0,1,," Name1 "," nValue1 best32.;run;
data _null_;set o6b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,6,2,3,0.501,noscore,0,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 3
1 2 0
2 1 0
2 2 2
;
run;
ods output RelRisk1ExactCL=o7a RelRisk2ExactCL=o7b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.501; exact relrisk(method=noscore column=both) / ;run;
data _null_;set o7a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,7,2,3,0.501,noscore,1,1,," Name1 "," nValue1 best32.;run;
data _null_;set o7b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,7,2,3,0.501,noscore,1,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 2
2 1 3
2 2 0
;
run;
ods output RelRisk1ExactCL=o8a RelRisk2ExactCL=o8b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.51; exact relrisk(method=noscore column=both) / ;run;
data _null_;set o8a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,8,2,3,0.51,noscore,0,1,," Name1 "," nValue1 best32.;run;
data _null_;set o8b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,8,2,3,0.51,noscore,0,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 3
1 2 0
2 1 0
2 2 2
;
run;
ods output RelRisk1ExactCL=o9a RelRisk2ExactCL=o9b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.51; exact relrisk(method=noscore column=both) / ;run;
data _null_;set o9a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,9,2,3,0.51,noscore,1,1,," Name1 "," nValue1 best32.;run;
data _null_;set o9b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,9,2,3,0.51,noscore,1,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 2
2 1 3
2 2 0
;
run;
ods output RelRisk1ExactCL=o10a RelRisk2ExactCL=o10b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.79; exact relrisk(method=noscore column=both) / ;run;
data _null_;set o10a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,10,2,3,0.79,noscore,0,1,," Name1 "," nValue1 best32.;run;
data _null_;set o10b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,10,2,3,0.79,noscore,0,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 3
1 2 0
2 1 0
2 2 2
;
run;
ods output RelRisk1ExactCL=o11a RelRisk2ExactCL=o11b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.79; exact relrisk(method=noscore column=both) / ;run;
data _null_;set o11a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,11,2,3,0.79,noscore,1,1,," Name1 "," nValue1 best32.;run;
data _null_;set o11b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,11,2,3,0.79,noscore,1,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 2
2 1 3
2 2 0
;
run;
ods output RelRisk1ExactCL=o12a RelRisk2ExactCL=o12b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.8; exact relrisk(method=noscore column=both) / ;run;
data _null_;set o12a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,12,2,3,0.8,noscore,0,1,," Name1 "," nValue1 best32.;run;
data _null_;set o12b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,12,2,3,0.8,noscore,0,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 3
1 2 0
2 1 0
2 2 2
;
run;
ods output RelRisk1ExactCL=o13a RelRisk2ExactCL=o13b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.8; exact relrisk(method=noscore column=both) / ;run;
data _null_;set o13a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,13,2,3,0.8,noscore,1,1,," Name1 "," nValue1 best32.;run;
data _null_;set o13b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,13,2,3,0.8,noscore,1,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 2
2 1 3
2 2 0
;
run;
ods output RelRisk1ExactCL=o14a RelRisk2ExactCL=o14b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.81; exact relrisk(method=noscore column=both) / ;run;
data _null_;set o14a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,14,2,3,0.81,noscore,0,1,," Name1 "," nValue1 best32.;run;
data _null_;set o14b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,14,2,3,0.81,noscore,0,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 3
1 2 0
2 1 0
2 2 2
;
run;
ods output RelRisk1ExactCL=o15a RelRisk2ExactCL=o15b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.81; exact relrisk(method=noscore column=both) / ;run;
data _null_;set o15a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,15,2,3,0.81,noscore,1,1,," Name1 "," nValue1 best32.;run;
data _null_;set o15b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,15,2,3,0.81,noscore,1,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 2
2 1 3
2 2 0
;
run;
ods output RelRisk1ExactCL=o16a RelRisk2ExactCL=o16b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.94; exact relrisk(method=noscore column=both) / ;run;
data _null_;set o16a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,16,2,3,0.94,noscore,0,1,," Name1 "," nValue1 best32.;run;
data _null_;set o16b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,16,2,3,0.94,noscore,0,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 3
1 2 0
2 1 0
2 2 2
;
run;
ods output RelRisk1ExactCL=o17a RelRisk2ExactCL=o17b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.94; exact relrisk(method=noscore column=both) / ;run;
data _null_;set o17a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,17,2,3,0.94,noscore,1,1,," Name1 "," nValue1 best32.;run;
data _null_;set o17b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,17,2,3,0.94,noscore,1,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 2
2 1 3
2 2 0
;
run;
ods output RelRisk1ExactCL=o18a RelRisk2ExactCL=o18b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.949; exact relrisk(method=noscore column=both) / ;run;
data _null_;set o18a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,18,2,3,0.949,noscore,0,1,," Name1 "," nValue1 best32.;run;
data _null_;set o18b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,18,2,3,0.949,noscore,0,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 3
1 2 0
2 1 0
2 2 2
;
run;
ods output RelRisk1ExactCL=o19a RelRisk2ExactCL=o19b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.949; exact relrisk(method=noscore column=both) / ;run;
data _null_;set o19a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,19,2,3,0.949,noscore,1,1,," Name1 "," nValue1 best32.;run;
data _null_;set o19b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,19,2,3,0.949,noscore,1,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 2
2 1 3
2 2 0
;
run;
ods output RelRisk1ExactCL=o20a RelRisk2ExactCL=o20b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.95; exact relrisk(method=noscore column=both) / ;run;
data _null_;set o20a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,20,2,3,0.95,noscore,0,1,," Name1 "," nValue1 best32.;run;
data _null_;set o20b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,20,2,3,0.95,noscore,0,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 3
1 2 0
2 1 0
2 2 2
;
run;
ods output RelRisk1ExactCL=o21a RelRisk2ExactCL=o21b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.95; exact relrisk(method=noscore column=both) / ;run;
data _null_;set o21a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,21,2,3,0.95,noscore,1,1,," Name1 "," nValue1 best32.;run;
data _null_;set o21b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,21,2,3,0.95,noscore,1,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 2
2 1 3
2 2 0
;
run;
ods output RelRisk1ExactCL=o22a RelRisk2ExactCL=o22b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.951; exact relrisk(method=noscore column=both) / ;run;
data _null_;set o22a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,22,2,3,0.951,noscore,0,1,," Name1 "," nValue1 best32.;run;
data _null_;set o22b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,22,2,3,0.951,noscore,0,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 3
1 2 0
2 1 0
2 2 2
;
run;
ods output RelRisk1ExactCL=o23a RelRisk2ExactCL=o23b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.951; exact relrisk(method=noscore column=both) / ;run;
data _null_;set o23a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,23,2,3,0.951,noscore,1,1,," Name1 "," nValue1 best32.;run;
data _null_;set o23b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,23,2,3,0.951,noscore,1,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 2
2 1 3
2 2 0
;
run;
ods output RelRisk1ExactCL=o24a RelRisk2ExactCL=o24b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.96; exact relrisk(method=noscore column=both) / ;run;
data _null_;set o24a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,24,2,3,0.96,noscore,0,1,," Name1 "," nValue1 best32.;run;
data _null_;set o24b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,24,2,3,0.96,noscore,0,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 3
1 2 0
2 1 0
2 2 2
;
run;
ods output RelRisk1ExactCL=o25a RelRisk2ExactCL=o25b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.96; exact relrisk(method=noscore column=both) / ;run;
data _null_;set o25a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,25,2,3,0.96,noscore,1,1,," Name1 "," nValue1 best32.;run;
data _null_;set o25b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,25,2,3,0.96,noscore,1,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 2
2 1 3
2 2 0
;
run;
ods output RelRisk1ExactCL=o26a RelRisk2ExactCL=o26b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.49; exact relrisk(method=score column=both) / ;run;
data _null_;set o26a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,26,2,3,0.49,score,0,1,," Name1 "," nValue1 best32.;run;
data _null_;set o26b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,26,2,3,0.49,score,0,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 3
1 2 0
2 1 0
2 2 2
;
run;
ods output RelRisk1ExactCL=o27a RelRisk2ExactCL=o27b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.49; exact relrisk(method=score column=both) / ;run;
data _null_;set o27a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,27,2,3,0.49,score,1,1,," Name1 "," nValue1 best32.;run;
data _null_;set o27b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,27,2,3,0.49,score,1,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 2
2 1 3
2 2 0
;
run;
ods output RelRisk1ExactCL=o28a RelRisk2ExactCL=o28b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.499; exact relrisk(method=score column=both) / ;run;
data _null_;set o28a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,28,2,3,0.499,score,0,1,," Name1 "," nValue1 best32.;run;
data _null_;set o28b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,28,2,3,0.499,score,0,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 3
1 2 0
2 1 0
2 2 2
;
run;
ods output RelRisk1ExactCL=o29a RelRisk2ExactCL=o29b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.499; exact relrisk(method=score column=both) / ;run;
data _null_;set o29a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,29,2,3,0.499,score,1,1,," Name1 "," nValue1 best32.;run;
data _null_;set o29b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,29,2,3,0.499,score,1,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 2
2 1 3
2 2 0
;
run;
ods output RelRisk1ExactCL=o30a RelRisk2ExactCL=o30b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.5; exact relrisk(method=score column=both) / ;run;
data _null_;set o30a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,30,2,3,0.5,score,0,1,," Name1 "," nValue1 best32.;run;
data _null_;set o30b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,30,2,3,0.5,score,0,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 3
1 2 0
2 1 0
2 2 2
;
run;
ods output RelRisk1ExactCL=o31a RelRisk2ExactCL=o31b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.5; exact relrisk(method=score column=both) / ;run;
data _null_;set o31a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,31,2,3,0.5,score,1,1,," Name1 "," nValue1 best32.;run;
data _null_;set o31b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,31,2,3,0.5,score,1,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 2
2 1 3
2 2 0
;
run;
ods output RelRisk1ExactCL=o32a RelRisk2ExactCL=o32b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.501; exact relrisk(method=score column=both) / ;run;
data _null_;set o32a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,32,2,3,0.501,score,0,1,," Name1 "," nValue1 best32.;run;
data _null_;set o32b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,32,2,3,0.501,score,0,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 3
1 2 0
2 1 0
2 2 2
;
run;
ods output RelRisk1ExactCL=o33a RelRisk2ExactCL=o33b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.501; exact relrisk(method=score column=both) / ;run;
data _null_;set o33a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,33,2,3,0.501,score,1,1,," Name1 "," nValue1 best32.;run;
data _null_;set o33b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,33,2,3,0.501,score,1,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 2
2 1 3
2 2 0
;
run;
ods output RelRisk1ExactCL=o34a RelRisk2ExactCL=o34b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.51; exact relrisk(method=score column=both) / ;run;
data _null_;set o34a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,34,2,3,0.51,score,0,1,," Name1 "," nValue1 best32.;run;
data _null_;set o34b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,34,2,3,0.51,score,0,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 3
1 2 0
2 1 0
2 2 2
;
run;
ods output RelRisk1ExactCL=o35a RelRisk2ExactCL=o35b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.51; exact relrisk(method=score column=both) / ;run;
data _null_;set o35a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,35,2,3,0.51,score,1,1,," Name1 "," nValue1 best32.;run;
data _null_;set o35b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,35,2,3,0.51,score,1,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 2
2 1 3
2 2 0
;
run;
ods output RelRisk1ExactCL=o36a RelRisk2ExactCL=o36b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.79; exact relrisk(method=score column=both) / ;run;
data _null_;set o36a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,36,2,3,0.79,score,0,1,," Name1 "," nValue1 best32.;run;
data _null_;set o36b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,36,2,3,0.79,score,0,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 3
1 2 0
2 1 0
2 2 2
;
run;
ods output RelRisk1ExactCL=o37a RelRisk2ExactCL=o37b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.79; exact relrisk(method=score column=both) / ;run;
data _null_;set o37a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,37,2,3,0.79,score,1,1,," Name1 "," nValue1 best32.;run;
data _null_;set o37b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,37,2,3,0.79,score,1,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 2
2 1 3
2 2 0
;
run;
ods output RelRisk1ExactCL=o38a RelRisk2ExactCL=o38b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.8; exact relrisk(method=score column=both) / ;run;
data _null_;set o38a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,38,2,3,0.8,score,0,1,," Name1 "," nValue1 best32.;run;
data _null_;set o38b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,38,2,3,0.8,score,0,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 3
1 2 0
2 1 0
2 2 2
;
run;
ods output RelRisk1ExactCL=o39a RelRisk2ExactCL=o39b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.8; exact relrisk(method=score column=both) / ;run;
data _null_;set o39a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,39,2,3,0.8,score,1,1,," Name1 "," nValue1 best32.;run;
data _null_;set o39b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,39,2,3,0.8,score,1,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 2
2 1 3
2 2 0
;
run;
ods output RelRisk1ExactCL=o40a RelRisk2ExactCL=o40b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.81; exact relrisk(method=score column=both) / ;run;
data _null_;set o40a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,40,2,3,0.81,score,0,1,," Name1 "," nValue1 best32.;run;
data _null_;set o40b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,40,2,3,0.81,score,0,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 3
1 2 0
2 1 0
2 2 2
;
run;
ods output RelRisk1ExactCL=o41a RelRisk2ExactCL=o41b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.81; exact relrisk(method=score column=both) / ;run;
data _null_;set o41a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,41,2,3,0.81,score,1,1,," Name1 "," nValue1 best32.;run;
data _null_;set o41b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,41,2,3,0.81,score,1,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 2
2 1 3
2 2 0
;
run;
ods output RelRisk1ExactCL=o42a RelRisk2ExactCL=o42b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.94; exact relrisk(method=score column=both) / ;run;
data _null_;set o42a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,42,2,3,0.94,score,0,1,," Name1 "," nValue1 best32.;run;
data _null_;set o42b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,42,2,3,0.94,score,0,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 3
1 2 0
2 1 0
2 2 2
;
run;
ods output RelRisk1ExactCL=o43a RelRisk2ExactCL=o43b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.94; exact relrisk(method=score column=both) / ;run;
data _null_;set o43a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,43,2,3,0.94,score,1,1,," Name1 "," nValue1 best32.;run;
data _null_;set o43b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,43,2,3,0.94,score,1,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 2
2 1 3
2 2 0
;
run;
ods output RelRisk1ExactCL=o44a RelRisk2ExactCL=o44b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.949; exact relrisk(method=score column=both) / ;run;
data _null_;set o44a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,44,2,3,0.949,score,0,1,," Name1 "," nValue1 best32.;run;
data _null_;set o44b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,44,2,3,0.949,score,0,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 3
1 2 0
2 1 0
2 2 2
;
run;
ods output RelRisk1ExactCL=o45a RelRisk2ExactCL=o45b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.949; exact relrisk(method=score column=both) / ;run;
data _null_;set o45a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,45,2,3,0.949,score,1,1,," Name1 "," nValue1 best32.;run;
data _null_;set o45b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,45,2,3,0.949,score,1,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 2
2 1 3
2 2 0
;
run;
ods output RelRisk1ExactCL=o46a RelRisk2ExactCL=o46b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.95; exact relrisk(method=score column=both) / ;run;
data _null_;set o46a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,46,2,3,0.95,score,0,1,," Name1 "," nValue1 best32.;run;
data _null_;set o46b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,46,2,3,0.95,score,0,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 3
1 2 0
2 1 0
2 2 2
;
run;
ods output RelRisk1ExactCL=o47a RelRisk2ExactCL=o47b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.95; exact relrisk(method=score column=both) / ;run;
data _null_;set o47a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,47,2,3,0.95,score,1,1,," Name1 "," nValue1 best32.;run;
data _null_;set o47b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,47,2,3,0.95,score,1,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 2
2 1 3
2 2 0
;
run;
ods output RelRisk1ExactCL=o48a RelRisk2ExactCL=o48b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.951; exact relrisk(method=score column=both) / ;run;
data _null_;set o48a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,48,2,3,0.951,score,0,1,," Name1 "," nValue1 best32.;run;
data _null_;set o48b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,48,2,3,0.951,score,0,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 3
1 2 0
2 1 0
2 2 2
;
run;
ods output RelRisk1ExactCL=o49a RelRisk2ExactCL=o49b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.951; exact relrisk(method=score column=both) / ;run;
data _null_;set o49a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,49,2,3,0.951,score,1,1,," Name1 "," nValue1 best32.;run;
data _null_;set o49b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,49,2,3,0.951,score,1,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 2
2 1 3
2 2 0
;
run;
ods output RelRisk1ExactCL=o50a RelRisk2ExactCL=o50b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.96; exact relrisk(method=score column=both) / ;run;
data _null_;set o50a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,50,2,3,0.96,score,0,1,," Name1 "," nValue1 best32.;run;
data _null_;set o50b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,50,2,3,0.96,score,0,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 3
1 2 0
2 1 0
2 2 2
;
run;
ods output RelRisk1ExactCL=o51a RelRisk2ExactCL=o51b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.96; exact relrisk(method=score column=both) / ;run;
data _null_;set o51a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,51,2,3,0.96,score,1,1,," Name1 "," nValue1 best32.;run;
data _null_;set o51b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,51,2,3,0.96,score,1,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 2
2 1 3
2 2 0
;
run;
ods output RelRisk1ExactCL=o52a RelRisk2ExactCL=o52b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.49; exact relrisk(method=score2 column=both) / ;run;
data _null_;set o52a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,52,2,3,0.49,score2,0,1,," Name1 "," nValue1 best32.;run;
data _null_;set o52b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,52,2,3,0.49,score2,0,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 3
1 2 0
2 1 0
2 2 2
;
run;
ods output RelRisk1ExactCL=o53a RelRisk2ExactCL=o53b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.49; exact relrisk(method=score2 column=both) / ;run;
data _null_;set o53a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,53,2,3,0.49,score2,1,1,," Name1 "," nValue1 best32.;run;
data _null_;set o53b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,53,2,3,0.49,score2,1,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 2
2 1 3
2 2 0
;
run;
ods output RelRisk1ExactCL=o54a RelRisk2ExactCL=o54b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.499; exact relrisk(method=score2 column=both) / ;run;
data _null_;set o54a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,54,2,3,0.499,score2,0,1,," Name1 "," nValue1 best32.;run;
data _null_;set o54b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,54,2,3,0.499,score2,0,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 3
1 2 0
2 1 0
2 2 2
;
run;
ods output RelRisk1ExactCL=o55a RelRisk2ExactCL=o55b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.499; exact relrisk(method=score2 column=both) / ;run;
data _null_;set o55a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,55,2,3,0.499,score2,1,1,," Name1 "," nValue1 best32.;run;
data _null_;set o55b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,55,2,3,0.499,score2,1,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 2
2 1 3
2 2 0
;
run;
ods output RelRisk1ExactCL=o56a RelRisk2ExactCL=o56b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.5; exact relrisk(method=score2 column=both) / ;run;
data _null_;set o56a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,56,2,3,0.5,score2,0,1,," Name1 "," nValue1 best32.;run;
data _null_;set o56b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,56,2,3,0.5,score2,0,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 3
1 2 0
2 1 0
2 2 2
;
run;
ods output RelRisk1ExactCL=o57a RelRisk2ExactCL=o57b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.5; exact relrisk(method=score2 column=both) / ;run;
data _null_;set o57a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,57,2,3,0.5,score2,1,1,," Name1 "," nValue1 best32.;run;
data _null_;set o57b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,57,2,3,0.5,score2,1,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 2
2 1 3
2 2 0
;
run;
ods output RelRisk1ExactCL=o58a RelRisk2ExactCL=o58b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.501; exact relrisk(method=score2 column=both) / ;run;
data _null_;set o58a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,58,2,3,0.501,score2,0,1,," Name1 "," nValue1 best32.;run;
data _null_;set o58b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,58,2,3,0.501,score2,0,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 3
1 2 0
2 1 0
2 2 2
;
run;
ods output RelRisk1ExactCL=o59a RelRisk2ExactCL=o59b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.501; exact relrisk(method=score2 column=both) / ;run;
data _null_;set o59a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,59,2,3,0.501,score2,1,1,," Name1 "," nValue1 best32.;run;
data _null_;set o59b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,59,2,3,0.501,score2,1,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 2
2 1 3
2 2 0
;
run;
ods output RelRisk1ExactCL=o60a RelRisk2ExactCL=o60b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.51; exact relrisk(method=score2 column=both) / ;run;
data _null_;set o60a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,60,2,3,0.51,score2,0,1,," Name1 "," nValue1 best32.;run;
data _null_;set o60b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,60,2,3,0.51,score2,0,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 3
1 2 0
2 1 0
2 2 2
;
run;
ods output RelRisk1ExactCL=o61a RelRisk2ExactCL=o61b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.51; exact relrisk(method=score2 column=both) / ;run;
data _null_;set o61a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,61,2,3,0.51,score2,1,1,," Name1 "," nValue1 best32.;run;
data _null_;set o61b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,61,2,3,0.51,score2,1,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 2
2 1 3
2 2 0
;
run;
ods output RelRisk1ExactCL=o62a RelRisk2ExactCL=o62b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.79; exact relrisk(method=score2 column=both) / ;run;
data _null_;set o62a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,62,2,3,0.79,score2,0,1,," Name1 "," nValue1 best32.;run;
data _null_;set o62b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,62,2,3,0.79,score2,0,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 3
1 2 0
2 1 0
2 2 2
;
run;
ods output RelRisk1ExactCL=o63a RelRisk2ExactCL=o63b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.79; exact relrisk(method=score2 column=both) / ;run;
data _null_;set o63a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,63,2,3,0.79,score2,1,1,," Name1 "," nValue1 best32.;run;
data _null_;set o63b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,63,2,3,0.79,score2,1,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 2
2 1 3
2 2 0
;
run;
ods output RelRisk1ExactCL=o64a RelRisk2ExactCL=o64b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.8; exact relrisk(method=score2 column=both) / ;run;
data _null_;set o64a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,64,2,3,0.8,score2,0,1,," Name1 "," nValue1 best32.;run;
data _null_;set o64b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,64,2,3,0.8,score2,0,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 3
1 2 0
2 1 0
2 2 2
;
run;
ods output RelRisk1ExactCL=o65a RelRisk2ExactCL=o65b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.8; exact relrisk(method=score2 column=both) / ;run;
data _null_;set o65a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,65,2,3,0.8,score2,1,1,," Name1 "," nValue1 best32.;run;
data _null_;set o65b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,65,2,3,0.8,score2,1,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 2
2 1 3
2 2 0
;
run;
ods output RelRisk1ExactCL=o66a RelRisk2ExactCL=o66b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.81; exact relrisk(method=score2 column=both) / ;run;
data _null_;set o66a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,66,2,3,0.81,score2,0,1,," Name1 "," nValue1 best32.;run;
data _null_;set o66b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,66,2,3,0.81,score2,0,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 3
1 2 0
2 1 0
2 2 2
;
run;
ods output RelRisk1ExactCL=o67a RelRisk2ExactCL=o67b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.81; exact relrisk(method=score2 column=both) / ;run;
data _null_;set o67a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,67,2,3,0.81,score2,1,1,," Name1 "," nValue1 best32.;run;
data _null_;set o67b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,67,2,3,0.81,score2,1,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 2
2 1 3
2 2 0
;
run;
ods output RelRisk1ExactCL=o68a RelRisk2ExactCL=o68b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.94; exact relrisk(method=score2 column=both) / ;run;
data _null_;set o68a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,68,2,3,0.94,score2,0,1,," Name1 "," nValue1 best32.;run;
data _null_;set o68b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,68,2,3,0.94,score2,0,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 3
1 2 0
2 1 0
2 2 2
;
run;
ods output RelRisk1ExactCL=o69a RelRisk2ExactCL=o69b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.94; exact relrisk(method=score2 column=both) / ;run;
data _null_;set o69a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,69,2,3,0.94,score2,1,1,," Name1 "," nValue1 best32.;run;
data _null_;set o69b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,69,2,3,0.94,score2,1,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 2
2 1 3
2 2 0
;
run;
ods output RelRisk1ExactCL=o70a RelRisk2ExactCL=o70b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.949; exact relrisk(method=score2 column=both) / ;run;
data _null_;set o70a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,70,2,3,0.949,score2,0,1,," Name1 "," nValue1 best32.;run;
data _null_;set o70b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,70,2,3,0.949,score2,0,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 3
1 2 0
2 1 0
2 2 2
;
run;
ods output RelRisk1ExactCL=o71a RelRisk2ExactCL=o71b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.949; exact relrisk(method=score2 column=both) / ;run;
data _null_;set o71a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,71,2,3,0.949,score2,1,1,," Name1 "," nValue1 best32.;run;
data _null_;set o71b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,71,2,3,0.949,score2,1,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 2
2 1 3
2 2 0
;
run;
ods output RelRisk1ExactCL=o72a RelRisk2ExactCL=o72b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.95; exact relrisk(method=score2 column=both) / ;run;
data _null_;set o72a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,72,2,3,0.95,score2,0,1,," Name1 "," nValue1 best32.;run;
data _null_;set o72b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,72,2,3,0.95,score2,0,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 3
1 2 0
2 1 0
2 2 2
;
run;
ods output RelRisk1ExactCL=o73a RelRisk2ExactCL=o73b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.95; exact relrisk(method=score2 column=both) / ;run;
data _null_;set o73a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,73,2,3,0.95,score2,1,1,," Name1 "," nValue1 best32.;run;
data _null_;set o73b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,73,2,3,0.95,score2,1,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 2
2 1 3
2 2 0
;
run;
ods output RelRisk1ExactCL=o74a RelRisk2ExactCL=o74b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.951; exact relrisk(method=score2 column=both) / ;run;
data _null_;set o74a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,74,2,3,0.951,score2,0,1,," Name1 "," nValue1 best32.;run;
data _null_;set o74b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,74,2,3,0.951,score2,0,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 3
1 2 0
2 1 0
2 2 2
;
run;
ods output RelRisk1ExactCL=o75a RelRisk2ExactCL=o75b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.951; exact relrisk(method=score2 column=both) / ;run;
data _null_;set o75a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,75,2,3,0.951,score2,1,1,," Name1 "," nValue1 best32.;run;
data _null_;set o75b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,75,2,3,0.951,score2,1,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 2
2 1 3
2 2 0
;
run;
ods output RelRisk1ExactCL=o76a RelRisk2ExactCL=o76b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.96; exact relrisk(method=score2 column=both) / ;run;
data _null_;set o76a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,76,2,3,0.96,score2,0,1,," Name1 "," nValue1 best32.;run;
data _null_;set o76b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,76,2,3,0.96,score2,0,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 3
1 2 0
2 1 0
2 2 2
;
run;
ods output RelRisk1ExactCL=o77a RelRisk2ExactCL=o77b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.96; exact relrisk(method=score2 column=both) / ;run;
data _null_;set o77a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,77,2,3,0.96,score2,1,1,," Name1 "," nValue1 best32.;run;
data _null_;set o77b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,77,2,3,0.96,score2,1,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 2
2 1 5
2 2 0
;
run;
ods output RelRisk1ExactCL=o78a RelRisk2ExactCL=o78b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.93; exact relrisk(method=noscore column=both) / ;run;
data _null_;set o78a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,78,2,5,0.93,noscore,0,1,," Name1 "," nValue1 best32.;run;
data _null_;set o78b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,78,2,5,0.93,noscore,0,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 5
1 2 0
2 1 0
2 2 2
;
run;
ods output RelRisk1ExactCL=o79a RelRisk2ExactCL=o79b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.93; exact relrisk(method=noscore column=both) / ;run;
data _null_;set o79a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,79,2,5,0.93,noscore,1,1,," Name1 "," nValue1 best32.;run;
data _null_;set o79b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,79,2,5,0.93,noscore,1,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 2
2 1 5
2 2 0
;
run;
ods output RelRisk1ExactCL=o80a RelRisk2ExactCL=o80b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.939; exact relrisk(method=noscore column=both) / ;run;
data _null_;set o80a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,80,2,5,0.939,noscore,0,1,," Name1 "," nValue1 best32.;run;
data _null_;set o80b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,80,2,5,0.939,noscore,0,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 5
1 2 0
2 1 0
2 2 2
;
run;
ods output RelRisk1ExactCL=o81a RelRisk2ExactCL=o81b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.939; exact relrisk(method=noscore column=both) / ;run;
data _null_;set o81a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,81,2,5,0.939,noscore,1,1,," Name1 "," nValue1 best32.;run;
data _null_;set o81b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,81,2,5,0.939,noscore,1,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 2
2 1 5
2 2 0
;
run;
ods output RelRisk1ExactCL=o82a RelRisk2ExactCL=o82b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.94; exact relrisk(method=noscore column=both) / ;run;
data _null_;set o82a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,82,2,5,0.94,noscore,0,1,," Name1 "," nValue1 best32.;run;
data _null_;set o82b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,82,2,5,0.94,noscore,0,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 5
1 2 0
2 1 0
2 2 2
;
run;
ods output RelRisk1ExactCL=o83a RelRisk2ExactCL=o83b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.94; exact relrisk(method=noscore column=both) / ;run;
data _null_;set o83a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,83,2,5,0.94,noscore,1,1,," Name1 "," nValue1 best32.;run;
data _null_;set o83b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,83,2,5,0.94,noscore,1,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 2
2 1 5
2 2 0
;
run;
ods output RelRisk1ExactCL=o84a RelRisk2ExactCL=o84b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.941; exact relrisk(method=noscore column=both) / ;run;
data _null_;set o84a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,84,2,5,0.941,noscore,0,1,," Name1 "," nValue1 best32.;run;
data _null_;set o84b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,84,2,5,0.941,noscore,0,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 5
1 2 0
2 1 0
2 2 2
;
run;
ods output RelRisk1ExactCL=o85a RelRisk2ExactCL=o85b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.941; exact relrisk(method=noscore column=both) / ;run;
data _null_;set o85a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,85,2,5,0.941,noscore,1,1,," Name1 "," nValue1 best32.;run;
data _null_;set o85b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,85,2,5,0.941,noscore,1,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 2
2 1 5
2 2 0
;
run;
ods output RelRisk1ExactCL=o86a RelRisk2ExactCL=o86b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.95; exact relrisk(method=noscore column=both) / ;run;
data _null_;set o86a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,86,2,5,0.95,noscore,0,1,," Name1 "," nValue1 best32.;run;
data _null_;set o86b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,86,2,5,0.95,noscore,0,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 5
1 2 0
2 1 0
2 2 2
;
run;
ods output RelRisk1ExactCL=o87a RelRisk2ExactCL=o87b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.95; exact relrisk(method=noscore column=both) / ;run;
data _null_;set o87a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,87,2,5,0.95,noscore,1,1,," Name1 "," nValue1 best32.;run;
data _null_;set o87b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,87,2,5,0.95,noscore,1,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 2
2 1 5
2 2 0
;
run;
ods output RelRisk1ExactCL=o88a RelRisk2ExactCL=o88b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.98; exact relrisk(method=noscore column=both) / ;run;
data _null_;set o88a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,88,2,5,0.98,noscore,0,1,," Name1 "," nValue1 best32.;run;
data _null_;set o88b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,88,2,5,0.98,noscore,0,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 5
1 2 0
2 1 0
2 2 2
;
run;
ods output RelRisk1ExactCL=o89a RelRisk2ExactCL=o89b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.98; exact relrisk(method=noscore column=both) / ;run;
data _null_;set o89a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,89,2,5,0.98,noscore,1,1,," Name1 "," nValue1 best32.;run;
data _null_;set o89b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,89,2,5,0.98,noscore,1,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 2
2 1 5
2 2 0
;
run;
ods output RelRisk1ExactCL=o90a RelRisk2ExactCL=o90b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.989; exact relrisk(method=noscore column=both) / ;run;
data _null_;set o90a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,90,2,5,0.989,noscore,0,1,," Name1 "," nValue1 best32.;run;
data _null_;set o90b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,90,2,5,0.989,noscore,0,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 5
1 2 0
2 1 0
2 2 2
;
run;
ods output RelRisk1ExactCL=o91a RelRisk2ExactCL=o91b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.989; exact relrisk(method=noscore column=both) / ;run;
data _null_;set o91a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,91,2,5,0.989,noscore,1,1,," Name1 "," nValue1 best32.;run;
data _null_;set o91b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,91,2,5,0.989,noscore,1,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 2
2 1 5
2 2 0
;
run;
ods output RelRisk1ExactCL=o92a RelRisk2ExactCL=o92b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.99; exact relrisk(method=noscore column=both) / ;run;
data _null_;set o92a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,92,2,5,0.99,noscore,0,1,," Name1 "," nValue1 best32.;run;
data _null_;set o92b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,92,2,5,0.99,noscore,0,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 5
1 2 0
2 1 0
2 2 2
;
run;
ods output RelRisk1ExactCL=o93a RelRisk2ExactCL=o93b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.99; exact relrisk(method=noscore column=both) / ;run;
data _null_;set o93a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,93,2,5,0.99,noscore,1,1,," Name1 "," nValue1 best32.;run;
data _null_;set o93b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,93,2,5,0.99,noscore,1,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 2
2 1 5
2 2 0
;
run;
ods output RelRisk1ExactCL=o94a RelRisk2ExactCL=o94b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.991; exact relrisk(method=noscore column=both) / ;run;
data _null_;set o94a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,94,2,5,0.991,noscore,0,1,," Name1 "," nValue1 best32.;run;
data _null_;set o94b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,94,2,5,0.991,noscore,0,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 5
1 2 0
2 1 0
2 2 2
;
run;
ods output RelRisk1ExactCL=o95a RelRisk2ExactCL=o95b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.991; exact relrisk(method=noscore column=both) / ;run;
data _null_;set o95a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,95,2,5,0.991,noscore,1,1,," Name1 "," nValue1 best32.;run;
data _null_;set o95b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,95,2,5,0.991,noscore,1,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 2
2 1 5
2 2 0
;
run;
ods output RelRisk1ExactCL=o96a RelRisk2ExactCL=o96b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.999; exact relrisk(method=noscore column=both) / ;run;
data _null_;set o96a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,96,2,5,0.999,noscore,0,1,," Name1 "," nValue1 best32.;run;
data _null_;set o96b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,96,2,5,0.999,noscore,0,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 5
1 2 0
2 1 0
2 2 2
;
run;
ods output RelRisk1ExactCL=o97a RelRisk2ExactCL=o97b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.999; exact relrisk(method=noscore column=both) / ;run;
data _null_;set o97a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,97,2,5,0.999,noscore,1,1,," Name1 "," nValue1 best32.;run;
data _null_;set o97b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,97,2,5,0.999,noscore,1,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 2
2 1 5
2 2 0
;
run;
ods output RelRisk1ExactCL=o98a RelRisk2ExactCL=o98b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.93; exact relrisk(method=score column=both) / ;run;
data _null_;set o98a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,98,2,5,0.93,score,0,1,," Name1 "," nValue1 best32.;run;
data _null_;set o98b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,98,2,5,0.93,score,0,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 5
1 2 0
2 1 0
2 2 2
;
run;
ods output RelRisk1ExactCL=o99a RelRisk2ExactCL=o99b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.93; exact relrisk(method=score column=both) / ;run;
data _null_;set o99a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,99,2,5,0.93,score,1,1,," Name1 "," nValue1 best32.;run;
data _null_;set o99b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,99,2,5,0.93,score,1,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 2
2 1 5
2 2 0
;
run;
ods output RelRisk1ExactCL=o100a RelRisk2ExactCL=o100b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.939; exact relrisk(method=score column=both) / ;run;
data _null_;set o100a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,100,2,5,0.939,score,0,1,," Name1 "," nValue1 best32.;run;
data _null_;set o100b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,100,2,5,0.939,score,0,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 5
1 2 0
2 1 0
2 2 2
;
run;
ods output RelRisk1ExactCL=o101a RelRisk2ExactCL=o101b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.939; exact relrisk(method=score column=both) / ;run;
data _null_;set o101a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,101,2,5,0.939,score,1,1,," Name1 "," nValue1 best32.;run;
data _null_;set o101b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,101,2,5,0.939,score,1,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 2
2 1 5
2 2 0
;
run;
ods output RelRisk1ExactCL=o102a RelRisk2ExactCL=o102b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.94; exact relrisk(method=score column=both) / ;run;
data _null_;set o102a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,102,2,5,0.94,score,0,1,," Name1 "," nValue1 best32.;run;
data _null_;set o102b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,102,2,5,0.94,score,0,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 5
1 2 0
2 1 0
2 2 2
;
run;
ods output RelRisk1ExactCL=o103a RelRisk2ExactCL=o103b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.94; exact relrisk(method=score column=both) / ;run;
data _null_;set o103a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,103,2,5,0.94,score,1,1,," Name1 "," nValue1 best32.;run;
data _null_;set o103b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,103,2,5,0.94,score,1,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 2
2 1 5
2 2 0
;
run;
ods output RelRisk1ExactCL=o104a RelRisk2ExactCL=o104b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.941; exact relrisk(method=score column=both) / ;run;
data _null_;set o104a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,104,2,5,0.941,score,0,1,," Name1 "," nValue1 best32.;run;
data _null_;set o104b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,104,2,5,0.941,score,0,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 5
1 2 0
2 1 0
2 2 2
;
run;
ods output RelRisk1ExactCL=o105a RelRisk2ExactCL=o105b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.941; exact relrisk(method=score column=both) / ;run;
data _null_;set o105a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,105,2,5,0.941,score,1,1,," Name1 "," nValue1 best32.;run;
data _null_;set o105b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,105,2,5,0.941,score,1,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 2
2 1 5
2 2 0
;
run;
ods output RelRisk1ExactCL=o106a RelRisk2ExactCL=o106b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.95; exact relrisk(method=score column=both) / ;run;
data _null_;set o106a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,106,2,5,0.95,score,0,1,," Name1 "," nValue1 best32.;run;
data _null_;set o106b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,106,2,5,0.95,score,0,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 5
1 2 0
2 1 0
2 2 2
;
run;
ods output RelRisk1ExactCL=o107a RelRisk2ExactCL=o107b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.95; exact relrisk(method=score column=both) / ;run;
data _null_;set o107a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,107,2,5,0.95,score,1,1,," Name1 "," nValue1 best32.;run;
data _null_;set o107b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,107,2,5,0.95,score,1,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 2
2 1 5
2 2 0
;
run;
ods output RelRisk1ExactCL=o108a RelRisk2ExactCL=o108b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.98; exact relrisk(method=score column=both) / ;run;
data _null_;set o108a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,108,2,5,0.98,score,0,1,," Name1 "," nValue1 best32.;run;
data _null_;set o108b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,108,2,5,0.98,score,0,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 5
1 2 0
2 1 0
2 2 2
;
run;
ods output RelRisk1ExactCL=o109a RelRisk2ExactCL=o109b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.98; exact relrisk(method=score column=both) / ;run;
data _null_;set o109a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,109,2,5,0.98,score,1,1,," Name1 "," nValue1 best32.;run;
data _null_;set o109b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,109,2,5,0.98,score,1,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 2
2 1 5
2 2 0
;
run;
ods output RelRisk1ExactCL=o110a RelRisk2ExactCL=o110b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.989; exact relrisk(method=score column=both) / ;run;
data _null_;set o110a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,110,2,5,0.989,score,0,1,," Name1 "," nValue1 best32.;run;
data _null_;set o110b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,110,2,5,0.989,score,0,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 5
1 2 0
2 1 0
2 2 2
;
run;
ods output RelRisk1ExactCL=o111a RelRisk2ExactCL=o111b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.989; exact relrisk(method=score column=both) / ;run;
data _null_;set o111a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,111,2,5,0.989,score,1,1,," Name1 "," nValue1 best32.;run;
data _null_;set o111b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,111,2,5,0.989,score,1,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 2
2 1 5
2 2 0
;
run;
ods output RelRisk1ExactCL=o112a RelRisk2ExactCL=o112b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.99; exact relrisk(method=score column=both) / ;run;
data _null_;set o112a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,112,2,5,0.99,score,0,1,," Name1 "," nValue1 best32.;run;
data _null_;set o112b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,112,2,5,0.99,score,0,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 5
1 2 0
2 1 0
2 2 2
;
run;
ods output RelRisk1ExactCL=o113a RelRisk2ExactCL=o113b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.99; exact relrisk(method=score column=both) / ;run;
data _null_;set o113a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,113,2,5,0.99,score,1,1,," Name1 "," nValue1 best32.;run;
data _null_;set o113b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,113,2,5,0.99,score,1,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 2
2 1 5
2 2 0
;
run;
ods output RelRisk1ExactCL=o114a RelRisk2ExactCL=o114b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.991; exact relrisk(method=score column=both) / ;run;
data _null_;set o114a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,114,2,5,0.991,score,0,1,," Name1 "," nValue1 best32.;run;
data _null_;set o114b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,114,2,5,0.991,score,0,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 5
1 2 0
2 1 0
2 2 2
;
run;
ods output RelRisk1ExactCL=o115a RelRisk2ExactCL=o115b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.991; exact relrisk(method=score column=both) / ;run;
data _null_;set o115a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,115,2,5,0.991,score,1,1,," Name1 "," nValue1 best32.;run;
data _null_;set o115b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,115,2,5,0.991,score,1,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 2
2 1 5
2 2 0
;
run;
ods output RelRisk1ExactCL=o116a RelRisk2ExactCL=o116b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.999; exact relrisk(method=score column=both) / ;run;
data _null_;set o116a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,116,2,5,0.999,score,0,1,," Name1 "," nValue1 best32.;run;
data _null_;set o116b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,116,2,5,0.999,score,0,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 5
1 2 0
2 1 0
2 2 2
;
run;
ods output RelRisk1ExactCL=o117a RelRisk2ExactCL=o117b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.999; exact relrisk(method=score column=both) / ;run;
data _null_;set o117a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,117,2,5,0.999,score,1,1,," Name1 "," nValue1 best32.;run;
data _null_;set o117b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,117,2,5,0.999,score,1,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 2
2 1 5
2 2 0
;
run;
ods output RelRisk1ExactCL=o118a RelRisk2ExactCL=o118b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.93; exact relrisk(method=score2 column=both) / ;run;
data _null_;set o118a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,118,2,5,0.93,score2,0,1,," Name1 "," nValue1 best32.;run;
data _null_;set o118b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,118,2,5,0.93,score2,0,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 5
1 2 0
2 1 0
2 2 2
;
run;
ods output RelRisk1ExactCL=o119a RelRisk2ExactCL=o119b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.93; exact relrisk(method=score2 column=both) / ;run;
data _null_;set o119a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,119,2,5,0.93,score2,1,1,," Name1 "," nValue1 best32.;run;
data _null_;set o119b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,119,2,5,0.93,score2,1,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 2
2 1 5
2 2 0
;
run;
ods output RelRisk1ExactCL=o120a RelRisk2ExactCL=o120b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.939; exact relrisk(method=score2 column=both) / ;run;
data _null_;set o120a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,120,2,5,0.939,score2,0,1,," Name1 "," nValue1 best32.;run;
data _null_;set o120b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,120,2,5,0.939,score2,0,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 5
1 2 0
2 1 0
2 2 2
;
run;
ods output RelRisk1ExactCL=o121a RelRisk2ExactCL=o121b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.939; exact relrisk(method=score2 column=both) / ;run;
data _null_;set o121a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,121,2,5,0.939,score2,1,1,," Name1 "," nValue1 best32.;run;
data _null_;set o121b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,121,2,5,0.939,score2,1,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 2
2 1 5
2 2 0
;
run;
ods output RelRisk1ExactCL=o122a RelRisk2ExactCL=o122b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.94; exact relrisk(method=score2 column=both) / ;run;
data _null_;set o122a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,122,2,5,0.94,score2,0,1,," Name1 "," nValue1 best32.;run;
data _null_;set o122b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,122,2,5,0.94,score2,0,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 5
1 2 0
2 1 0
2 2 2
;
run;
ods output RelRisk1ExactCL=o123a RelRisk2ExactCL=o123b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.94; exact relrisk(method=score2 column=both) / ;run;
data _null_;set o123a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,123,2,5,0.94,score2,1,1,," Name1 "," nValue1 best32.;run;
data _null_;set o123b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,123,2,5,0.94,score2,1,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 2
2 1 5
2 2 0
;
run;
ods output RelRisk1ExactCL=o124a RelRisk2ExactCL=o124b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.941; exact relrisk(method=score2 column=both) / ;run;
data _null_;set o124a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,124,2,5,0.941,score2,0,1,," Name1 "," nValue1 best32.;run;
data _null_;set o124b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,124,2,5,0.941,score2,0,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 5
1 2 0
2 1 0
2 2 2
;
run;
ods output RelRisk1ExactCL=o125a RelRisk2ExactCL=o125b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.941; exact relrisk(method=score2 column=both) / ;run;
data _null_;set o125a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,125,2,5,0.941,score2,1,1,," Name1 "," nValue1 best32.;run;
data _null_;set o125b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,125,2,5,0.941,score2,1,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 2
2 1 5
2 2 0
;
run;
ods output RelRisk1ExactCL=o126a RelRisk2ExactCL=o126b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.95; exact relrisk(method=score2 column=both) / ;run;
data _null_;set o126a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,126,2,5,0.95,score2,0,1,," Name1 "," nValue1 best32.;run;
data _null_;set o126b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,126,2,5,0.95,score2,0,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 5
1 2 0
2 1 0
2 2 2
;
run;
ods output RelRisk1ExactCL=o127a RelRisk2ExactCL=o127b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.95; exact relrisk(method=score2 column=both) / ;run;
data _null_;set o127a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,127,2,5,0.95,score2,1,1,," Name1 "," nValue1 best32.;run;
data _null_;set o127b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,127,2,5,0.95,score2,1,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 2
2 1 5
2 2 0
;
run;
ods output RelRisk1ExactCL=o128a RelRisk2ExactCL=o128b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.98; exact relrisk(method=score2 column=both) / ;run;
data _null_;set o128a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,128,2,5,0.98,score2,0,1,," Name1 "," nValue1 best32.;run;
data _null_;set o128b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,128,2,5,0.98,score2,0,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 5
1 2 0
2 1 0
2 2 2
;
run;
ods output RelRisk1ExactCL=o129a RelRisk2ExactCL=o129b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.98; exact relrisk(method=score2 column=both) / ;run;
data _null_;set o129a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,129,2,5,0.98,score2,1,1,," Name1 "," nValue1 best32.;run;
data _null_;set o129b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,129,2,5,0.98,score2,1,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 2
2 1 5
2 2 0
;
run;
ods output RelRisk1ExactCL=o130a RelRisk2ExactCL=o130b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.989; exact relrisk(method=score2 column=both) / ;run;
data _null_;set o130a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,130,2,5,0.989,score2,0,1,," Name1 "," nValue1 best32.;run;
data _null_;set o130b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,130,2,5,0.989,score2,0,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 5
1 2 0
2 1 0
2 2 2
;
run;
ods output RelRisk1ExactCL=o131a RelRisk2ExactCL=o131b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.989; exact relrisk(method=score2 column=both) / ;run;
data _null_;set o131a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,131,2,5,0.989,score2,1,1,," Name1 "," nValue1 best32.;run;
data _null_;set o131b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,131,2,5,0.989,score2,1,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 2
2 1 5
2 2 0
;
run;
ods output RelRisk1ExactCL=o132a RelRisk2ExactCL=o132b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.99; exact relrisk(method=score2 column=both) / ;run;
data _null_;set o132a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,132,2,5,0.99,score2,0,1,," Name1 "," nValue1 best32.;run;
data _null_;set o132b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,132,2,5,0.99,score2,0,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 5
1 2 0
2 1 0
2 2 2
;
run;
ods output RelRisk1ExactCL=o133a RelRisk2ExactCL=o133b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.99; exact relrisk(method=score2 column=both) / ;run;
data _null_;set o133a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,133,2,5,0.99,score2,1,1,," Name1 "," nValue1 best32.;run;
data _null_;set o133b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,133,2,5,0.99,score2,1,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 2
2 1 5
2 2 0
;
run;
ods output RelRisk1ExactCL=o134a RelRisk2ExactCL=o134b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.991; exact relrisk(method=score2 column=both) / ;run;
data _null_;set o134a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,134,2,5,0.991,score2,0,1,," Name1 "," nValue1 best32.;run;
data _null_;set o134b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,134,2,5,0.991,score2,0,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 5
1 2 0
2 1 0
2 2 2
;
run;
ods output RelRisk1ExactCL=o135a RelRisk2ExactCL=o135b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.991; exact relrisk(method=score2 column=both) / ;run;
data _null_;set o135a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,135,2,5,0.991,score2,1,1,," Name1 "," nValue1 best32.;run;
data _null_;set o135b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,135,2,5,0.991,score2,1,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 2
2 1 5
2 2 0
;
run;
ods output RelRisk1ExactCL=o136a RelRisk2ExactCL=o136b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.999; exact relrisk(method=score2 column=both) / ;run;
data _null_;set o136a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,136,2,5,0.999,score2,0,1,," Name1 "," nValue1 best32.;run;
data _null_;set o136b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,136,2,5,0.999,score2,0,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 5
1 2 0
2 1 0
2 2 2
;
run;
ods output RelRisk1ExactCL=o137a RelRisk2ExactCL=o137b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.999; exact relrisk(method=score2 column=both) / ;run;
data _null_;set o137a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,137,2,5,0.999,score2,1,1,," Name1 "," nValue1 best32.;run;
data _null_;set o137b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,137,2,5,0.999,score2,1,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 4
2 1 3
2 2 0
;
run;
ods output RelRisk1ExactCL=o138a RelRisk2ExactCL=o138b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.98; exact relrisk(method=noscore column=both) / ;run;
data _null_;set o138a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,138,4,3,0.98,noscore,0,1,," Name1 "," nValue1 best32.;run;
data _null_;set o138b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,138,4,3,0.98,noscore,0,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 3
1 2 0
2 1 0
2 2 4
;
run;
ods output RelRisk1ExactCL=o139a RelRisk2ExactCL=o139b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.98; exact relrisk(method=noscore column=both) / ;run;
data _null_;set o139a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,139,4,3,0.98,noscore,1,1,," Name1 "," nValue1 best32.;run;
data _null_;set o139b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,139,4,3,0.98,noscore,1,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 4
2 1 3
2 2 0
;
run;
ods output RelRisk1ExactCL=o140a RelRisk2ExactCL=o140b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.989; exact relrisk(method=noscore column=both) / ;run;
data _null_;set o140a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,140,4,3,0.989,noscore,0,1,," Name1 "," nValue1 best32.;run;
data _null_;set o140b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,140,4,3,0.989,noscore,0,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 3
1 2 0
2 1 0
2 2 4
;
run;
ods output RelRisk1ExactCL=o141a RelRisk2ExactCL=o141b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.989; exact relrisk(method=noscore column=both) / ;run;
data _null_;set o141a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,141,4,3,0.989,noscore,1,1,," Name1 "," nValue1 best32.;run;
data _null_;set o141b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,141,4,3,0.989,noscore,1,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 4
2 1 3
2 2 0
;
run;
ods output RelRisk1ExactCL=o142a RelRisk2ExactCL=o142b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.99; exact relrisk(method=noscore column=both) / ;run;
data _null_;set o142a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,142,4,3,0.99,noscore,0,1,," Name1 "," nValue1 best32.;run;
data _null_;set o142b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,142,4,3,0.99,noscore,0,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 3
1 2 0
2 1 0
2 2 4
;
run;
ods output RelRisk1ExactCL=o143a RelRisk2ExactCL=o143b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.99; exact relrisk(method=noscore column=both) / ;run;
data _null_;set o143a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,143,4,3,0.99,noscore,1,1,," Name1 "," nValue1 best32.;run;
data _null_;set o143b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,143,4,3,0.99,noscore,1,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 4
2 1 3
2 2 0
;
run;
ods output RelRisk1ExactCL=o144a RelRisk2ExactCL=o144b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.991; exact relrisk(method=noscore column=both) / ;run;
data _null_;set o144a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,144,4,3,0.991,noscore,0,1,," Name1 "," nValue1 best32.;run;
data _null_;set o144b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,144,4,3,0.991,noscore,0,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 3
1 2 0
2 1 0
2 2 4
;
run;
ods output RelRisk1ExactCL=o145a RelRisk2ExactCL=o145b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.991; exact relrisk(method=noscore column=both) / ;run;
data _null_;set o145a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,145,4,3,0.991,noscore,1,1,," Name1 "," nValue1 best32.;run;
data _null_;set o145b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,145,4,3,0.991,noscore,1,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 4
2 1 3
2 2 0
;
run;
ods output RelRisk1ExactCL=o146a RelRisk2ExactCL=o146b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.999; exact relrisk(method=noscore column=both) / ;run;
data _null_;set o146a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,146,4,3,0.999,noscore,0,1,," Name1 "," nValue1 best32.;run;
data _null_;set o146b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,146,4,3,0.999,noscore,0,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 3
1 2 0
2 1 0
2 2 4
;
run;
ods output RelRisk1ExactCL=o147a RelRisk2ExactCL=o147b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.999; exact relrisk(method=noscore column=both) / ;run;
data _null_;set o147a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,147,4,3,0.999,noscore,1,1,," Name1 "," nValue1 best32.;run;
data _null_;set o147b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,147,4,3,0.999,noscore,1,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 4
2 1 3
2 2 0
;
run;
ods output RelRisk1ExactCL=o148a RelRisk2ExactCL=o148b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.98; exact relrisk(method=score column=both) / ;run;
data _null_;set o148a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,148,4,3,0.98,score,0,1,," Name1 "," nValue1 best32.;run;
data _null_;set o148b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,148,4,3,0.98,score,0,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 3
1 2 0
2 1 0
2 2 4
;
run;
ods output RelRisk1ExactCL=o149a RelRisk2ExactCL=o149b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.98; exact relrisk(method=score column=both) / ;run;
data _null_;set o149a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,149,4,3,0.98,score,1,1,," Name1 "," nValue1 best32.;run;
data _null_;set o149b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,149,4,3,0.98,score,1,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 4
2 1 3
2 2 0
;
run;
ods output RelRisk1ExactCL=o150a RelRisk2ExactCL=o150b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.989; exact relrisk(method=score column=both) / ;run;
data _null_;set o150a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,150,4,3,0.989,score,0,1,," Name1 "," nValue1 best32.;run;
data _null_;set o150b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,150,4,3,0.989,score,0,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 3
1 2 0
2 1 0
2 2 4
;
run;
ods output RelRisk1ExactCL=o151a RelRisk2ExactCL=o151b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.989; exact relrisk(method=score column=both) / ;run;
data _null_;set o151a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,151,4,3,0.989,score,1,1,," Name1 "," nValue1 best32.;run;
data _null_;set o151b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,151,4,3,0.989,score,1,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 4
2 1 3
2 2 0
;
run;
ods output RelRisk1ExactCL=o152a RelRisk2ExactCL=o152b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.99; exact relrisk(method=score column=both) / ;run;
data _null_;set o152a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,152,4,3,0.99,score,0,1,," Name1 "," nValue1 best32.;run;
data _null_;set o152b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,152,4,3,0.99,score,0,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 3
1 2 0
2 1 0
2 2 4
;
run;
ods output RelRisk1ExactCL=o153a RelRisk2ExactCL=o153b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.99; exact relrisk(method=score column=both) / ;run;
data _null_;set o153a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,153,4,3,0.99,score,1,1,," Name1 "," nValue1 best32.;run;
data _null_;set o153b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,153,4,3,0.99,score,1,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 4
2 1 3
2 2 0
;
run;
ods output RelRisk1ExactCL=o154a RelRisk2ExactCL=o154b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.991; exact relrisk(method=score column=both) / ;run;
data _null_;set o154a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,154,4,3,0.991,score,0,1,," Name1 "," nValue1 best32.;run;
data _null_;set o154b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,154,4,3,0.991,score,0,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 3
1 2 0
2 1 0
2 2 4
;
run;
ods output RelRisk1ExactCL=o155a RelRisk2ExactCL=o155b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.991; exact relrisk(method=score column=both) / ;run;
data _null_;set o155a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,155,4,3,0.991,score,1,1,," Name1 "," nValue1 best32.;run;
data _null_;set o155b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,155,4,3,0.991,score,1,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 4
2 1 3
2 2 0
;
run;
ods output RelRisk1ExactCL=o156a RelRisk2ExactCL=o156b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.999; exact relrisk(method=score column=both) / ;run;
data _null_;set o156a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,156,4,3,0.999,score,0,1,," Name1 "," nValue1 best32.;run;
data _null_;set o156b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,156,4,3,0.999,score,0,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 3
1 2 0
2 1 0
2 2 4
;
run;
ods output RelRisk1ExactCL=o157a RelRisk2ExactCL=o157b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.999; exact relrisk(method=score column=both) / ;run;
data _null_;set o157a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,157,4,3,0.999,score,1,1,," Name1 "," nValue1 best32.;run;
data _null_;set o157b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,157,4,3,0.999,score,1,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 4
2 1 3
2 2 0
;
run;
ods output RelRisk1ExactCL=o158a RelRisk2ExactCL=o158b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.98; exact relrisk(method=score2 column=both) / ;run;
data _null_;set o158a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,158,4,3,0.98,score2,0,1,," Name1 "," nValue1 best32.;run;
data _null_;set o158b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,158,4,3,0.98,score2,0,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 3
1 2 0
2 1 0
2 2 4
;
run;
ods output RelRisk1ExactCL=o159a RelRisk2ExactCL=o159b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.98; exact relrisk(method=score2 column=both) / ;run;
data _null_;set o159a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,159,4,3,0.98,score2,1,1,," Name1 "," nValue1 best32.;run;
data _null_;set o159b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,159,4,3,0.98,score2,1,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 4
2 1 3
2 2 0
;
run;
ods output RelRisk1ExactCL=o160a RelRisk2ExactCL=o160b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.989; exact relrisk(method=score2 column=both) / ;run;
data _null_;set o160a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,160,4,3,0.989,score2,0,1,," Name1 "," nValue1 best32.;run;
data _null_;set o160b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,160,4,3,0.989,score2,0,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 3
1 2 0
2 1 0
2 2 4
;
run;
ods output RelRisk1ExactCL=o161a RelRisk2ExactCL=o161b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.989; exact relrisk(method=score2 column=both) / ;run;
data _null_;set o161a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,161,4,3,0.989,score2,1,1,," Name1 "," nValue1 best32.;run;
data _null_;set o161b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,161,4,3,0.989,score2,1,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 4
2 1 3
2 2 0
;
run;
ods output RelRisk1ExactCL=o162a RelRisk2ExactCL=o162b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.99; exact relrisk(method=score2 column=both) / ;run;
data _null_;set o162a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,162,4,3,0.99,score2,0,1,," Name1 "," nValue1 best32.;run;
data _null_;set o162b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,162,4,3,0.99,score2,0,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 3
1 2 0
2 1 0
2 2 4
;
run;
ods output RelRisk1ExactCL=o163a RelRisk2ExactCL=o163b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.99; exact relrisk(method=score2 column=both) / ;run;
data _null_;set o163a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,163,4,3,0.99,score2,1,1,," Name1 "," nValue1 best32.;run;
data _null_;set o163b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,163,4,3,0.99,score2,1,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 4
2 1 3
2 2 0
;
run;
ods output RelRisk1ExactCL=o164a RelRisk2ExactCL=o164b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.991; exact relrisk(method=score2 column=both) / ;run;
data _null_;set o164a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,164,4,3,0.991,score2,0,1,," Name1 "," nValue1 best32.;run;
data _null_;set o164b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,164,4,3,0.991,score2,0,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 3
1 2 0
2 1 0
2 2 4
;
run;
ods output RelRisk1ExactCL=o165a RelRisk2ExactCL=o165b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.991; exact relrisk(method=score2 column=both) / ;run;
data _null_;set o165a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,165,4,3,0.991,score2,1,1,," Name1 "," nValue1 best32.;run;
data _null_;set o165b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,165,4,3,0.991,score2,1,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 4
2 1 3
2 2 0
;
run;
ods output RelRisk1ExactCL=o166a RelRisk2ExactCL=o166b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.999; exact relrisk(method=score2 column=both) / ;run;
data _null_;set o166a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,166,4,3,0.999,score2,0,1,," Name1 "," nValue1 best32.;run;
data _null_;set o166b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,166,4,3,0.999,score2,0,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 3
1 2 0
2 1 0
2 2 4
;
run;
ods output RelRisk1ExactCL=o167a RelRisk2ExactCL=o167b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.999; exact relrisk(method=score2 column=both) / ;run;
data _null_;set o167a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,167,4,3,0.999,score2,1,1,," Name1 "," nValue1 best32.;run;
data _null_;set o167b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,167,4,3,0.999,score2,1,2,," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 2
2 1 3
2 2 0
;
run;
ods output RelRisk1ExactCL=o168a RelRisk2ExactCL=o168b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.95; exact relrisk(method=noscore column=both) / maxtime=1;run;
data _null_;set o168a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,168,2,3,0.95,noscore,0,1,maxtime=1," Name1 "," nValue1 best32.;run;
data _null_;set o168b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,168,2,3,0.95,noscore,0,2,maxtime=1," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 2
2 1 3
2 2 0
;
run;
ods output RelRisk1ExactCL=o169a RelRisk2ExactCL=o169b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.95; exact relrisk(method=score column=both) / maxtime=1;run;
data _null_;set o169a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,169,2,3,0.95,score,0,1,maxtime=1," Name1 "," nValue1 best32.;run;
data _null_;set o169b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,169,2,3,0.95,score,0,2,maxtime=1," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 2
2 1 3
2 2 0
;
run;
ods output RelRisk1ExactCL=o170a RelRisk2ExactCL=o170b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.95; exact relrisk(method=score2 column=both) / maxtime=1;run;
data _null_;set o170a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,170,2,3,0.95,score2,0,1,maxtime=1," Name1 "," nValue1 best32.;run;
data _null_;set o170b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,170,2,3,0.95,score2,0,2,maxtime=1," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 2
2 1 5
2 2 0
;
run;
ods output RelRisk1ExactCL=o171a RelRisk2ExactCL=o171b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.94; exact relrisk(method=noscore column=both) / maxtime=1;run;
data _null_;set o171a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,171,2,5,0.94,noscore,0,1,maxtime=1," Name1 "," nValue1 best32.;run;
data _null_;set o171b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,171,2,5,0.94,noscore,0,2,maxtime=1," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 2
2 1 5
2 2 0
;
run;
ods output RelRisk1ExactCL=o172a RelRisk2ExactCL=o172b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.94; exact relrisk(method=score column=both) / maxtime=1;run;
data _null_;set o172a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,172,2,5,0.94,score,0,1,maxtime=1," Name1 "," nValue1 best32.;run;
data _null_;set o172b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,172,2,5,0.94,score,0,2,maxtime=1," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 2
2 1 5
2 2 0
;
run;
ods output RelRisk1ExactCL=o173a RelRisk2ExactCL=o173b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.94; exact relrisk(method=score2 column=both) / maxtime=1;run;
data _null_;set o173a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,173,2,5,0.94,score2,0,1,maxtime=1," Name1 "," nValue1 best32.;run;
data _null_;set o173b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,173,2,5,0.94,score2,0,2,maxtime=1," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 2
2 1 5
2 2 0
;
run;
ods output RelRisk1ExactCL=o174a RelRisk2ExactCL=o174b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.99; exact relrisk(method=noscore column=both) / maxtime=1;run;
data _null_;set o174a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,174,2,5,0.99,noscore,0,1,maxtime=1," Name1 "," nValue1 best32.;run;
data _null_;set o174b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,174,2,5,0.99,noscore,0,2,maxtime=1," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 2
2 1 5
2 2 0
;
run;
ods output RelRisk1ExactCL=o175a RelRisk2ExactCL=o175b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.99; exact relrisk(method=score column=both) / maxtime=1;run;
data _null_;set o175a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,175,2,5,0.99,score,0,1,maxtime=1," Name1 "," nValue1 best32.;run;
data _null_;set o175b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,175,2,5,0.99,score,0,2,maxtime=1," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 2
2 1 5
2 2 0
;
run;
ods output RelRisk1ExactCL=o176a RelRisk2ExactCL=o176b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.99; exact relrisk(method=score2 column=both) / maxtime=1;run;
data _null_;set o176a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,176,2,5,0.99,score2,0,1,maxtime=1," Name1 "," nValue1 best32.;run;
data _null_;set o176b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,176,2,5,0.99,score2,0,2,maxtime=1," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 4
2 1 3
2 2 0
;
run;
ods output RelRisk1ExactCL=o177a RelRisk2ExactCL=o177b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.99; exact relrisk(method=noscore column=both) / maxtime=1;run;
data _null_;set o177a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,177,4,3,0.99,noscore,0,1,maxtime=1," Name1 "," nValue1 best32.;run;
data _null_;set o177b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,177,4,3,0.99,noscore,0,2,maxtime=1," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 4
2 1 3
2 2 0
;
run;
ods output RelRisk1ExactCL=o178a RelRisk2ExactCL=o178b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.99; exact relrisk(method=score column=both) / maxtime=1;run;
data _null_;set o178a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,178,4,3,0.99,score,0,1,maxtime=1," Name1 "," nValue1 best32.;run;
data _null_;set o178b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,178,4,3,0.99,score,0,2,maxtime=1," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 4
2 1 3
2 2 0
;
run;
ods output RelRisk1ExactCL=o179a RelRisk2ExactCL=o179b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.99; exact relrisk(method=score2 column=both) / maxtime=1;run;
data _null_;set o179a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,179,4,3,0.99,score2,0,1,maxtime=1," Name1 "," nValue1 best32.;run;
data _null_;set o179b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,179,4,3,0.99,score2,0,2,maxtime=1," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 2
2 1 3
2 2 0
;
run;
ods output RelRisk1ExactCL=o180a RelRisk2ExactCL=o180b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.95; exact relrisk(method=noscore column=both) / maxtime=60;run;
data _null_;set o180a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,180,2,3,0.95,noscore,0,1,maxtime=60," Name1 "," nValue1 best32.;run;
data _null_;set o180b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,180,2,3,0.95,noscore,0,2,maxtime=60," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 2
2 1 3
2 2 0
;
run;
ods output RelRisk1ExactCL=o181a RelRisk2ExactCL=o181b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.95; exact relrisk(method=score column=both) / maxtime=60;run;
data _null_;set o181a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,181,2,3,0.95,score,0,1,maxtime=60," Name1 "," nValue1 best32.;run;
data _null_;set o181b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,181,2,3,0.95,score,0,2,maxtime=60," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 2
2 1 3
2 2 0
;
run;
ods output RelRisk1ExactCL=o182a RelRisk2ExactCL=o182b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.95; exact relrisk(method=score2 column=both) / maxtime=60;run;
data _null_;set o182a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,182,2,3,0.95,score2,0,1,maxtime=60," Name1 "," nValue1 best32.;run;
data _null_;set o182b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,182,2,3,0.95,score2,0,2,maxtime=60," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 2
2 1 5
2 2 0
;
run;
ods output RelRisk1ExactCL=o183a RelRisk2ExactCL=o183b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.94; exact relrisk(method=noscore column=both) / maxtime=60;run;
data _null_;set o183a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,183,2,5,0.94,noscore,0,1,maxtime=60," Name1 "," nValue1 best32.;run;
data _null_;set o183b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,183,2,5,0.94,noscore,0,2,maxtime=60," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 2
2 1 5
2 2 0
;
run;
ods output RelRisk1ExactCL=o184a RelRisk2ExactCL=o184b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.94; exact relrisk(method=score column=both) / maxtime=60;run;
data _null_;set o184a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,184,2,5,0.94,score,0,1,maxtime=60," Name1 "," nValue1 best32.;run;
data _null_;set o184b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,184,2,5,0.94,score,0,2,maxtime=60," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 2
2 1 5
2 2 0
;
run;
ods output RelRisk1ExactCL=o185a RelRisk2ExactCL=o185b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.94; exact relrisk(method=score2 column=both) / maxtime=60;run;
data _null_;set o185a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,185,2,5,0.94,score2,0,1,maxtime=60," Name1 "," nValue1 best32.;run;
data _null_;set o185b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,185,2,5,0.94,score2,0,2,maxtime=60," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 2
2 1 5
2 2 0
;
run;
ods output RelRisk1ExactCL=o186a RelRisk2ExactCL=o186b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.99; exact relrisk(method=noscore column=both) / maxtime=60;run;
data _null_;set o186a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,186,2,5,0.99,noscore,0,1,maxtime=60," Name1 "," nValue1 best32.;run;
data _null_;set o186b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,186,2,5,0.99,noscore,0,2,maxtime=60," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 2
2 1 5
2 2 0
;
run;
ods output RelRisk1ExactCL=o187a RelRisk2ExactCL=o187b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.99; exact relrisk(method=score column=both) / maxtime=60;run;
data _null_;set o187a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,187,2,5,0.99,score,0,1,maxtime=60," Name1 "," nValue1 best32.;run;
data _null_;set o187b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,187,2,5,0.99,score,0,2,maxtime=60," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 2
2 1 5
2 2 0
;
run;
ods output RelRisk1ExactCL=o188a RelRisk2ExactCL=o188b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.99; exact relrisk(method=score2 column=both) / maxtime=60;run;
data _null_;set o188a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,188,2,5,0.99,score2,0,1,maxtime=60," Name1 "," nValue1 best32.;run;
data _null_;set o188b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,188,2,5,0.99,score2,0,2,maxtime=60," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 4
2 1 3
2 2 0
;
run;
ods output RelRisk1ExactCL=o189a RelRisk2ExactCL=o189b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.99; exact relrisk(method=noscore column=both) / maxtime=60;run;
data _null_;set o189a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,189,4,3,0.99,noscore,0,1,maxtime=60," Name1 "," nValue1 best32.;run;
data _null_;set o189b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,189,4,3,0.99,noscore,0,2,maxtime=60," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 4
2 1 3
2 2 0
;
run;
ods output RelRisk1ExactCL=o190a RelRisk2ExactCL=o190b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.99; exact relrisk(method=score column=both) / maxtime=60;run;
data _null_;set o190a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,190,4,3,0.99,score,0,1,maxtime=60," Name1 "," nValue1 best32.;run;
data _null_;set o190b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,190,4,3,0.99,score,0,2,maxtime=60," Name1 "," nValue1 best32.;run;
data t; input r c n; datalines;
1 1 0
1 2 4
2 1 3
2 2 0
;
run;
ods output RelRisk1ExactCL=o191a RelRisk2ExactCL=o191b;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=0.99; exact relrisk(method=score2 column=both) / maxtime=60;run;
data _null_;set o191a;if Name1 in ("XL_RRC1","XU_RRC1") then put "RESULT,191,4,3,0.99,score2,0,1,maxtime=60," Name1 "," nValue1 best32.;run;
data _null_;set o191b;if Name1 in ("XL_RRC2","XU_RRC2") then put "RESULT,191,4,3,0.99,score2,0,2,maxtime=60," Name1 "," nValue1 best32.;run;
ods exclude none;proc print data=release;run;