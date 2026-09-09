/* ISS-sqlupdate #42: `update m as x set col=(select … where s.id=x.id) where …`
   must skip the alias, split SET/WHERE paren-aware, and run the correlated
   scalar subquery per row. Plain `update … set c='x'` must keep working. */
data m;  length id $3 entpt $40; id='001'; entpt='TO BE COMPLETED'; output; run;
data dm; length id $3 rficdtc $16; id='001'; rficdtc='2022-10-03'; output; run;
proc sql;
  update m as x set entpt=(select distinct rficdtc from dm as s where s.id=x.id)
    where entpt='TO BE COMPLETED';
quit;
proc print data=m noobs; run;
