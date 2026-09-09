/* put a[i]=; — named output of an array element: the label is the RESOLVED
   element's own name (a[2] → a2=20). Verified vs SAS 9.4 (FEAT-putarraynamed).
   Plain `put a[2];` and whole-array `put a[*];` stay unchanged. */
data _null_;
  array a[3] a1-a3 (10 20 30);
  put a[2]=;
  i = 3;
  put a[i]= a[1]=;
  put "vals: " a[1]= a[2]= a[3]=;
  put a[2];
  put a[*];
run;
