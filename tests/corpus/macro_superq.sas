/* %superq returns a macro var's raw value with &/% masked (no rescan); empty for
   an undefined var. Synthetic. macro-superq. */
%let a = %nrstr(x&y z);
data _null_; length s $20; s = "%superq(a)"; put "MASKED=" s; run;
data _null_; length s $10; s = "%superq(undef)"; put "UNDEF=[" s "]"; run;
%let vn = a;
data _null_; length s $20; s = "%superq(&vn)"; put "INDIRECT=" s; run;
