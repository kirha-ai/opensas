data d;do x=1 to 65527;output;end;run;
proc univariate data=d noprint outtable=t;var x;run;
data _null_;set t;file print;put _NOBS_= _QN_= _STDQN_= _SN_= _STDSN_=;run;
