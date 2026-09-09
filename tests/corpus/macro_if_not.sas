/* BUG-macroifnot: %if not(EXPR) / %if ^EXPR must negate the condition
   (was always TRUE — leaked as bare truthiness). a real EPOCH macro guards with
   %if not(%sysfunc(exist(...))), so this unblocks 16 domains. */
data work.have; x=1; run;
%macro chk;
  /* %global: post BUG-macrobareletscope a bare %let in a macro is LOCAL
     (SAS 9.4) — r1-r6 are read at open code, so declare them global. */
  %global r1 r2 r3 r4 r5 r6;
  %if not(1) %then %let r1=BUG; %else %let r1=OK;
  %if not(0) %then %let r2=TRUE; %else %let r2=FALSE;
  %if not 1  %then %let r3=BUG; %else %let r3=OK;
  %if ^(1)   %then %let r4=BUG; %else %let r4=OK;
  %if not(1 or 0) %then %let r5=BUG; %else %let r5=OK;
  %if not(%sysfunc(exist(work.have))) %then %let r6=MISSING; %else %let r6=EXISTS;
%mend;
%chk
data _null_;
  put "r1=&r1";
  put "r2=&r2";
  put "r3=&r3";
  put "r4=&r4";
  put "r5=&r5";
  put "r6=&r6";
run;
