data sample; input g r c f; datalines;
1 1 1 1
1 1 2 3
1 2 1 4
1 2 2 3
;
run;
ods output NLevels=captured;
proc freq data=sample nlevels; tables r; weight f;
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

data _null_;
  length line $512 text $256;
  id=open('work.captured','i');
  if id>0 then do;
    do row=1 to attrn(id,'NLOBS');
      rc=fetchobs(id,row);
      do pos=1 to attrn(id,'NVARS');
        if vartype(id,pos)='N' then text=put(getvarn(id,pos),best32.);
        else text=getvarc(id,pos);
        line=cats('ODS_VALUE|',put(row,best12.),'|',varname(id,pos),'|',text);
        put line;
      end;
    end;
    rc=close(id);
  end;
run;
