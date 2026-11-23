data sample; input g r c f; datalines;
1 1 1 1
1 1 2 3
1 1 3 1
1 2 1 4
1 2 2 3
1 2 3 2
1 3 1 3
1 3 2 3
1 3 3 3
;
run;
ods output FishersExactMC=captured;
proc freq data=sample; tables r*c; exact fisher / mc n=500 seed=12; weight f;
run;
data _null_;
  length line $512 nm $32 kind $4 fmt infmt $49 lab $256;
  id=open('work.captured','i');
  if id>0 then do;
    n=attrn(id,'NLOBS');
    line=cats('ODS_ROWS|',put(n,best12.));
    put line;
    do pos=1 to attrn(id,'NVARS');
      nm=varname(id,pos);
      if vartype(id,pos)='C' then kind='char';
      else kind='num';
      width=varlen(id,pos);
      fmt=varfmt(id,pos);
      infmt=varinfmt(id,pos);
      lab=varlabel(id,pos);
      line=cats('ODS_COL|',put(pos,best12.),'|',nm,'|',kind,'|',put(width,best12.),'|',fmt,'|',infmt,'|',lab);
      put line;
    end;
    rc=close(id);
  end;
run;
