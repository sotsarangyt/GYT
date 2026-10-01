//+------------------------------------------------------------------+
//|                                             GYT_DataExport.mq5    |
//|  Exports M1 history (OHLC, tick volume, spread) for gold and the  |
//|  context symbols to CSV, one file per symbol per year, so the     |
//|  intraday "move strength" research can be done offline.           |
//|  Files go to: <Data Folder>/MQL5/Files/GYT_export/                |
//+------------------------------------------------------------------+
#property copyright "GYT"
#property version   "1.00"
#property script_show_inputs

input string          InpSymbols   = "XAUUSD,XAGUSD,EURUSD,USDJPY,GBPUSD,USDCAD,USDSEK,USDCHF"; // Symbols (comma separated)
input string          InpSuffix    = "";                 // Symbol suffix (e.g. "m"), empty for Exness Pro
input datetime        InpFrom      = D'2020.01.01';      // From
input datetime        InpTo        = D'2030.01.01';      // To (clipped to now)
input ENUM_TIMEFRAMES InpTF        = PERIOD_M1;          // Timeframe

bool LoadRates(const string sym,const datetime from,const datetime to,MqlRates &rates[])
  {
   for(int attempt=0;attempt<10;attempt++)
     {
      int n=CopyRates(sym,InpTF,from,to,rates);
      if(n>=0) return true;
      Sleep(1000);                       // history may still be downloading from the server
     }
   return false;
  }

void ExportSymbol(const string sym)
  {
   if(!SymbolSelect(sym,true)) { PrintFormat("GYT export: symbol %s not found, skipped",sym); return; }
   int digits=(int)SymbolInfoInteger(sym,SYMBOL_DIGITS);
   datetime end=MathMin(InpTo,TimeCurrent());

   MqlDateTime d; TimeToStruct(InpFrom,d);
   for(int year=d.year; ; year++)
     {
      datetime ys=StringToTime(IntegerToString(year)+".01.01 00:00");
      if(ys>end) break;
      datetime ye=StringToTime(IntegerToString(year+1)+".01.01 00:00")-1;
      if(ys<InpFrom) ys=InpFrom;
      if(ye>end) ye=end;

      string fn="GYT_export\\"+sym+"_"+EnumToString(InpTF)+"_"+IntegerToString(year)+".csv";
      int fh=FileOpen(fn,FILE_WRITE|FILE_CSV|FILE_ANSI,',');
      if(fh==INVALID_HANDLE) { PrintFormat("GYT export: cannot open %s (%d)",fn,GetLastError()); return; }
      FileWrite(fh,"time","open","high","low","close","tick_volume","spread");

      long rows=0;
      // month by month to keep memory small
      for(datetime ms=ys; ms<=ye; )
        {
         MqlDateTime m; TimeToStruct(ms,m);
         m.mon++; if(m.mon>12) { m.mon=1; m.year++; }
         m.day=1; m.hour=0; m.min=0; m.sec=0;
         datetime me=MathMin(StructToTime(m)-1,ye);

         MqlRates r[];
         if(!LoadRates(sym,ms,me,r)) PrintFormat("GYT export: %s %s no data",sym,TimeToString(ms,TIME_DATE));
         for(int i=0;i<ArraySize(r);i++)
           {
            FileWrite(fh,TimeToString(r[i].time,TIME_DATE|TIME_MINUTES),
                      DoubleToString(r[i].open,digits),DoubleToString(r[i].high,digits),
                      DoubleToString(r[i].low,digits),DoubleToString(r[i].close,digits),
                      IntegerToString(r[i].tick_volume),IntegerToString(r[i].spread));
            rows++;
           }
         ms=me+1;
        }
      FileClose(fh);
      PrintFormat("GYT export: %s %d -> %I64d rows",sym,year,rows);
     }
  }

void OnStart()
  {
   string syms[];
   int n=StringSplit(InpSymbols,',',syms);
   for(int i=0;i<n;i++)
     {
      string s=syms[i];
      StringTrimLeft(s); StringTrimRight(s);
      if(s!="") ExportSymbol(s+InpSuffix);
     }
   PrintFormat("GYT export: done. Server GMT offset now = %d h. Files are in MQL5\\Files\\GYT_export",
               (int)MathRound((double)(TimeTradeServer()-TimeGMT())/3600.0));
  }
//+------------------------------------------------------------------+
