/* expect-rc: 1 */
data d;w=.5+6000*2**(-53);do z=-1,1;x=z*1e150;output;end;run;proc univariate data=d noprint vardef=wdf;var x;weight w;run;
