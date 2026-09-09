/* NOTE-temparraylabel (doc-finder tick146): named PUT of a _TEMPORARY_ array
   element must not leak the synthesized internal name (_temp_x_6). Label with
   the array-ref form (x[2]= / x[6]= flat); the value is unchanged. Normal
   (non-temp) named array PUT keeps the resolved-name label (a2=). */
data _null_;
   array x{3} _temporary_ (10 20 30);
   array m{2,2} _temporary_ (1 2 3 4);
   array a{3} (7 8 9);
   do i = 1 to 3;
      put x[i]=;
   end;
   put m[2,1]=;
   put a[2]=;
run;
