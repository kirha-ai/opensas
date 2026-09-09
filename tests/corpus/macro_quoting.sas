/* %str masks ; and , inside a %let value so the value scan doesn't terminate early
   (building code fragments — common in SDTM macros). Synthetic. macro-quoting. */
%let code = %str(a=1; b=2);
data _null_; length s $20; s = "&code"; put "CODE=[" s "]"; run;
%let list = %str(AE,CM;VS);
data _null_; length s $20; s = "&list"; put "LIST=[" s "]"; run;
%macro frag(d);
  %let f = %str(dom=&d; n=1);
  data _null_; length s $30; s = "&f"; put "FRAG=[" s "]"; run;
%mend;
%frag(LB)
