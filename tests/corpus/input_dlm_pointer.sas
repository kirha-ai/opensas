/* BUG-inputdlmpointer: INPUT pointer controls under DLM=/DSD (Language Reference: Concepts Table 21.5,
   pp.516-517 — pointer controls and delimiter options combine freely). @@ must
   terminate, / and #n move the record, a trailing @ holds the field position,
   and no control may eat a field or emit a nameless column. */
data _null_;
  infile datalines dlm=',';
  input a $ @@;
  put 'ATAT n=' _n_ ' a=' a;
datalines;
x,y,z
p,q
;
run;

data _null_;
  infile datalines dsd;
  length a b $5;
  input a $ / b $;
  put 'SLASH a=[' a '] b=[' b ']';
datalines;
A,B,C
D,E,F
;
run;

data _null_;
  infile datalines dlm=',';
  length a b $5;
  input a $ #2 b $;
  put 'HASH a=[' a '] b=[' b ']';
datalines;
A,B,C
D,E,F
;
run;

data d;
  infile datalines dlm=',';
  length a b $5;
  input a $ @;
  input b $;
datalines;
A,B,C
D,E,F
;
run;
proc print data=d; run;
proc contents data=d; run;
