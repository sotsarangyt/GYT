//+------------------------------------------------------------------+
//|                                            GYT_MultiEngine.mq5   |
//|  XAUUSD multi-engine EA for MetaTrader 5 (built for Exness Pro)   |
//|                                                                  |
//|  Layers:                                                         |
//|   1. Regime Detector   (H4 Efficiency Ratio + ATR ratio)          |
//|   2. Engine A          Trend Breakout  (H1 Donchian)             |
//|   3. Engine B          Trend Pullback  (H1 EMA20 rejection)      |
//|   4. Engine C          Range Reversion (H1 Bollinger + RSI)      |
//|   5. Risk Brain        %-risk sizing, portfolio cap, loss limits, |
//|                        engine health, volatility scaling         |
//|   6. Market Context    News Shield (MT5 calendar), USD Pulse      |
//|                        (synthetic DXY), Silver divergence,        |
//|                        Shock Breaker, Daily Macro Bias (web)      |
//|                                                                  |
//|  No martingale, no grid, every trade has a stop loss.             |
//+------------------------------------------------------------------+
#property copyright "GYT"
#property version   "1.21"
#property description "GYT Multi-Engine gold EA: regime-aware trend/pullback/range engines with risk brain and macro context."

#include <Trade/Trade.mqh>

//--- engine ids (magic = InpMagic + id)
#define ENG_A 1
#define ENG_B 2
#define ENG_C 3
#define ENG_P1 4   // Pulse: TP1 leg
#define ENG_P2 5   // Pulse: runner leg

enum ENUM_REGIME { REG_NEUTRAL=0, REG_TREND=1, REG_RANGE=2, REG_CHAOS=3 };

//==================================================================
// Inputs
//==================================================================
input group "=== General ==="
input long   InpMagic              = 770000;   // Base magic number
input bool   InpTradeEnabled       = true;     // Allow new trades (false = manage only)
input string InpComment            = "GYT";    // Order comment prefix

input group "=== Risk Brain ==="
input double InpRiskBalance        = 10000;    // Size/limits as if balance = this (0 = real equity)
input double InpRiskPerTradePct    = 0.5;      // Risk per trade (% of base balance)
input double InpMaxTotalRiskPct    = 1.5;      // Max open risk, all positions (%)
input int    InpMaxPositions       = 3;        // Max open positions (all engines)
input double InpDailyLossPct       = 2.0;      // Daily loss limit (% of day-start equity)
input double InpWeeklyLossPct      = 5.0;      // Weekly loss limit (% of week-start equity)
input bool   InpCloseOnLossLimit   = true;     // Close all positions when a loss limit is hit
input double InpMinRiskFactor      = 0.25;     // Skip trade if combined multiplier below this
input double InpMaxSpreadUSD       = 0.50;     // Max spread in price units ($)
input int    InpSlippagePoints     = 30;       // Max slippage (points)
input int    InpHealthLookback     = 20;       // Engine health: last N closed trades
input int    InpHealthMinTrades    = 10;       // Engine health: min trades before judging
input double InpHealthBadMult      = 0.5;      // Engine health: multiplier when PF < 1

input group "=== Sessions (GMT) ==="
input int    InpServerGMTOffset    = 0;        // Server GMT offset used in Strategy Tester (Exness = 0)
input int    InpSessionStartGMT    = 7;        // New entries from (GMT hour)
input int    InpSessionEndGMT      = 17;       // New entries until (GMT hour)
input int    InpFridayNoEntryGMT   = 16;       // Friday: no new entries after (GMT hour)
input int    InpFridayCloseGMT     = 20;       // Friday: close all at (GMT hour), -1 = off

input group "=== Regime Detector (H4) ==="
input int    InpERPeriod           = 20;       // Efficiency Ratio period
input double InpERTrend            = 0.30;     // ER >= this -> TREND
input double InpERRange            = 0.20;     // ER <= this -> RANGE
input int    InpATRAvgPeriod       = 50;       // ATR average period (H4 bars)
input double InpChaosATRRatio      = 2.2;      // ATR / avg ATR above this -> CHAOS
input double InpHighVolATRRatio    = 1.6;      // ATR ratio above this -> half size
input int    InpD1EMA              = 50;       // D1 bias EMA period

input group "=== Engine A: Trend Breakout (H1) ==="
input bool   InpUseA               = true;     // Enable Engine A
input int    InpA_Donchian         = 20;       // Donchian lookback (bars)
input double InpA_SL_ATR           = 2.0;      // Stop loss (x ATR)
input double InpA_Trail_ATR        = 3.0;      // Trailing stop after +1R (x ATR)
input int    InpA_TimeStopBars     = 30;       // Close if < +0.5R after N H1 bars

input group "=== Engine B: Trend Pullback (H1) ==="
input bool   InpUseB               = true;     // Enable Engine B
input int    InpB_FastEMA          = 20;       // Fast EMA
input int    InpB_SlowEMA          = 50;       // Slow EMA
input double InpB_RSIMin           = 45;       // Buy: RSI >= (sell: RSI <= 100-x)
input double InpB_RSIMax           = 65;       // Buy: RSI <= (sell: RSI >= 100-x)
input double InpB_TP_R             = 2.0;      // Take profit (R multiple)
input double InpB_Trail_ATR        = 2.0;      // Trailing stop after +1.5R (x ATR)
input int    InpB_TimeStopBars     = 24;       // Close if < +0.5R after N H1 bars

input group "=== Engine C: Range Reversion (H1) ==="
input bool   InpUseC               = true;     // Enable Engine C
input int    InpC_BBPeriod         = 20;       // Bollinger period
input double InpC_BBDev            = 2.0;      // Bollinger deviation
input double InpC_RSIBuy           = 40;       // Buy: RSI below (sell: above 100-x)
input double InpC_MinRR            = 0.8;      // Min reward:risk to mid band
input int    InpC_TimeStopBars     = 12;       // Close after N H1 bars if not at target

input group "=== Engine P: Pulse intraday (M5) ==="
input bool   InpUseP               = true;     // Enable Engine P
input ENUM_TIMEFRAMES InpP_TF      = PERIOD_M5;// Signal timeframe
input int    InpP_MaxTradesDay     = 10;       // Max Pulse trades per day
input double InpP_RiskPct          = 0.2;      // Risk per Pulse trade (% of base balance, both legs)
input double InpP_MinScore         = 70;       // Max entry threshold (0-100); adaptive threshold never goes above
input bool   InpP_Adaptive         = true;     // Adaptive threshold: enter on the strongest moves of recent bars
input double InpP_TopPct           = 12.0;     // Adaptive: enter when score is in the top X% of recent bars
input double InpP_ScoreFloor       = 55;       // Adaptive: never enter below this score
input int    InpP_AdaptBars        = 144;      // Adaptive: number of recent bars (144 x M5 = 12 h)
input double InpP_TP1_R            = 0.7;      // TP1 leg target (R multiple)
input double InpP_SL_MinATR        = 0.8;      // Min stop (x ATR of signal TF)
input double InpP_SL_MaxATR        = 2.0;      // Max stop (x ATR of signal TF)
input double InpP_MaxExtATR        = 4.0;      // Skip if price is this far from EMA20 (x ATR)
input double InpP_RunTrailATR      = 2.0;      // Runner trailing stop after +1R (x ATR)
input double InpP_ExitScore        = 60;       // Close runner on opposite strength >= this
input int    InpP_TP1MaxMin        = 90;       // Close TP1 leg if not hit after N minutes
input int    InpP_MaxHoldMin       = 360;      // Close runner after N minutes
input int    InpP_StartGMT         = 7;        // Pulse entries from (GMT hour)
input int    InpP_EndGMT           = 20;       // Pulse entries until (GMT hour)
input int    InpP_FlatGMT          = 21;       // Close all Pulse positions at (GMT hour)
input int    InpP_MaxLossStreak    = 3;        // Stop Pulse for the day after N losses in a row
input bool   InpP_Log              = true;     // Log every signal to MQL5/Files/GYT_pulse_log.csv

input group "=== Market Context: News Shield ==="
input bool   InpUseNews            = true;     // Block entries around high-impact USD news (live only)
input int    InpNewsBeforeMin      = 30;       // Minutes before event
input int    InpNewsAfterMin       = 30;       // Minutes after event

input group "=== Market Context: USD Pulse & Silver ==="
input bool   InpUseUSDPulse        = true;     // Use synthetic DXY filter
input int    InpUSDLookbackH4      = 20;       // DXY change lookback (H4 bars)
input double InpUSDThreshPct       = 0.8;      // Strong USD move threshold (%)
input double InpUSDMult            = 0.5;      // Multiplier against strong USD move
input bool   InpUseSilver          = true;     // Use silver divergence filter
input double InpSilverThreshPct    = 0.5;      // Divergence threshold (%)
input double InpSilverMult         = 0.75;     // Multiplier on divergence
input string InpSymbolSuffix       = "AUTO";   // Symbol suffix ("AUTO" = copy from chart symbol)

input group "=== Market Context: Shock Breaker ==="
input bool   InpUseShock           = true;     // Pause after violent spikes
input double InpShockATRMult       = 1.5;      // 5-min range > x * ATR(H1) -> pause
input int    InpShockPauseMin      = 30;       // Pause length (minutes)
input double InpSpreadShockMult    = 3.0;      // Spread > x * max spread -> pause 10 min

input group "=== Market Context: Daily Macro Bias (web) ==="
input bool   InpUseMacroBias       = true;     // Read daily bias file (live only)
input string InpBiasURL            = "https://raw.githubusercontent.com/sotsarangyt/GYT/main/bias/xau_bias.txt"; // Bias file URL
input int    InpBiasRefreshMin     = 30;       // Refresh interval (minutes)
input double InpBiasMaxMult        = 1.0;      // Max multiplier a bias may apply (1.0 = reduce-only)
input double InpBiasCounterMult    = 0.5;      // Multiplier for trades against the bias
input double InpBiasStaleMult      = 0.75;     // Multiplier when bias is stale/unavailable

input group "=== Display ==="
input bool   InpShowPanel          = true;     // Show status panel

//==================================================================
// Globals
//==================================================================
CTrade   trade;

int  hEMA_D1, hATR_H1, hATR_H4, hEMAf_H1, hEMAs_H1, hRSI_H1, hBB_H1;
int  hATR_P, hEMA_P, hEMA_P15;

datetime g_lastH1Bar      = 0;
datetime g_pauseUntil     = 0;
string   g_pauseReason    = "";
ENUM_REGIME g_regime      = REG_NEUTRAL;
double   g_er             = 0.0;
double   g_atrRatio       = 1.0;
int      g_d1Dir          = 0;

// risk state
long     g_dayId          = -1;
long     g_weekId         = -1;
double   g_dayPnl         = 0.0;       // this EA only
double   g_weekPnl        = 0.0;       // this EA only
datetime g_lastPnlCalc    = 0;
bool     g_haltDay        = false;
bool     g_haltWeek       = false;
double   g_health[6]      = {1.0,1.0,1.0,1.0,1.0,1.0};

// context state
double   g_usdChangePct   = 0.0;
bool     g_usdOK          = false;
double   g_goldRetPct     = 0.0;
double   g_silverRetPct   = 0.0;
bool     g_silverOK       = false;
string   g_suffix         = "";

// news
datetime g_newsTimes[];
string   g_newsNames[];
datetime g_lastNewsFetch  = 0;

// macro bias
string   g_biasName       = "N/A";
double   g_biasRiskMult   = 1.0;
datetime g_biasValidUntil = 0;
string   g_biasDate       = "";
string   g_biasNote       = "";
datetime g_lastBiasFetch  = 0;
bool     g_biasLoaded     = false;
string   g_biasError      = "";

datetime g_lastPanel      = 0;

// pulse state
datetime g_lastPBar       = 0;
int      g_pTradesToday   = 0;
int      g_pTP1Today      = 0;
int      g_pLossToday     = 0;
int      g_pLossStreak    = 0;
double   g_pLiveScore     = 0.0;
int      g_pLiveDir       = 0;
string   g_pLastSignal    = "none";
double   g_pScores[];                  // recent closed-bar scores (oldest first)
double   g_pThreshold     = 70.0;
bool     g_isTester       = false;

//==================================================================
// Utilities
//==================================================================
double Val(const int handle,const int buffer,const int shift)
  {
   double a[1];
   if(handle==INVALID_HANDLE) return EMPTY_VALUE;
   if(CopyBuffer(handle,buffer,shift,1,a)!=1) return EMPTY_VALUE;
   return a[0];
  }

bool Ok(const double v) { return (v!=EMPTY_VALUE && MathIsValidNumber(v)); }

int ServerOffsetHours()
  {
   if(g_isTester) return InpServerGMTOffset;
   return (int)MathRound((double)(TimeTradeServer()-TimeGMT())/3600.0);
  }

datetime GMTNow() { return TimeTradeServer()-ServerOffsetHours()*3600; }

int GMTHour() { MqlDateTime t; TimeToStruct(GMTNow(),t); return t.hour; }
int GMTDow()  { MqlDateTime t; TimeToStruct(GMTNow(),t); return t.day_of_week; }

string GVName(const string key) { return "GYT_"+IntegerToString(InpMagic)+"_"+key; }

bool IsOurMagic(const long magic) { return (magic>InpMagic && magic<=InpMagic+5); }
int  EngineOf(const long magic)    { return (int)(magic-InpMagic); }

string EngineName(const int e)
  {
   if(e==ENG_A) return "A-Breakout";
   if(e==ENG_B) return "B-Pullback";
   if(e==ENG_C) return "C-Range";
   if(e==ENG_P1) return "P-Pulse-TP";
   if(e==ENG_P2) return "P-Pulse-Run";
   return "?";
  }

string RegimeName(const ENUM_REGIME r)
  {
   switch(r)
     {
      case REG_TREND: return "TREND";
      case REG_RANGE: return "RANGE";
      case REG_CHAOS: return "CHAOS";
      default:        return "NEUTRAL";
     }
  }

double Spread() { return SymbolInfoDouble(_Symbol,SYMBOL_ASK)-SymbolInfoDouble(_Symbol,SYMBOL_BID); }

double ATR_H1(const int shift=1) { return Val(hATR_H1,0,shift); }

//==================================================================
// Init / Deinit
//==================================================================
int OnInit()
  {
   g_isTester=(bool)MQLInfoInteger(MQL_TESTER);

   if(StringFind(_Symbol,"XAU")<0 && StringFind(_Symbol,"GOLD")<0)
      Print("GYT: warning - EA is designed for XAUUSD, attached to ",_Symbol);

   // symbol suffix for context symbols (Exness Pro usually has none)
   if(InpSymbolSuffix=="AUTO")
     {
      int p=StringFind(_Symbol,"XAUUSD");
      g_suffix=(p==0 ? StringSubstr(_Symbol,6) : "");
     }
   else g_suffix=InpSymbolSuffix;

   hEMA_D1 = iMA(_Symbol,PERIOD_D1,InpD1EMA,0,MODE_EMA,PRICE_CLOSE);
   hATR_H1 = iATR(_Symbol,PERIOD_H1,14);
   hATR_H4 = iATR(_Symbol,PERIOD_H4,14);
   hEMAf_H1= iMA(_Symbol,PERIOD_H1,InpB_FastEMA,0,MODE_EMA,PRICE_CLOSE);
   hEMAs_H1= iMA(_Symbol,PERIOD_H1,InpB_SlowEMA,0,MODE_EMA,PRICE_CLOSE);
   hRSI_H1 = iRSI(_Symbol,PERIOD_H1,14,PRICE_CLOSE);
   hBB_H1  = iBands(_Symbol,PERIOD_H1,InpC_BBPeriod,0,InpC_BBDev,PRICE_CLOSE);
   hATR_P  = iATR(_Symbol,InpP_TF,14);
   hEMA_P  = iMA(_Symbol,InpP_TF,20,0,MODE_EMA,PRICE_CLOSE);
   hEMA_P15= iMA(_Symbol,PERIOD_M15,50,0,MODE_EMA,PRICE_CLOSE);

   if(hEMA_D1==INVALID_HANDLE || hATR_H1==INVALID_HANDLE || hATR_H4==INVALID_HANDLE ||
      hEMAf_H1==INVALID_HANDLE || hEMAs_H1==INVALID_HANDLE || hRSI_H1==INVALID_HANDLE ||
      hBB_H1==INVALID_HANDLE || hATR_P==INVALID_HANDLE || hEMA_P==INVALID_HANDLE ||
      hEMA_P15==INVALID_HANDLE)
     {
      Print("GYT: failed to create indicator handles");
      return INIT_FAILED;
     }

   trade.SetDeviationInPoints(InpSlippagePoints);
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetMarginMode();

   // make sure context symbols are in Market Watch
   if(InpUseUSDPulse)
     {
      string fx[6]={"EURUSD","USDJPY","GBPUSD","USDCAD","USDSEK","USDCHF"};
      for(int i=0;i<6;i++) SymbolSelect(fx[i]+g_suffix,true);
     }
   if(InpUseSilver) SymbolSelect("XAGUSD"+g_suffix,true);

   EventSetTimer(60);
   RefreshContext();
   if(!g_isTester)
     {
      if(InpUseNews)      RefreshNews();
      if(InpUseMacroBias) RefreshBias();
     }
   Print("GYT: initialised on ",_Symbol,", server GMT offset ",ServerOffsetHours(),
         "h, tester=",g_isTester);
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   IndicatorRelease(hEMA_D1); IndicatorRelease(hATR_H1); IndicatorRelease(hATR_H4);
   IndicatorRelease(hEMAf_H1); IndicatorRelease(hEMAs_H1); IndicatorRelease(hRSI_H1);
   IndicatorRelease(hBB_H1); IndicatorRelease(hATR_P); IndicatorRelease(hEMA_P);
   IndicatorRelease(hEMA_P15);
   Comment("");
  }

void OnTimer()
  {
   if(g_isTester) return;
   datetime now=TimeTradeServer();
   if(InpUseNews && now-g_lastNewsFetch>=15*60) RefreshNews();
   if(InpUseMacroBias && now-g_lastBiasFetch>=InpBiasRefreshMin*60) RefreshBias();
  }

//==================================================================
// Main loop
//==================================================================
void OnTick()
  {
   UpdateLossLimits();
   FridayClose();
   ShockCheck();
   ManagePositions();

   datetime h1=iTime(_Symbol,PERIOD_H1,0);
   if(h1!=0 && h1!=g_lastH1Bar)
     {
      g_lastH1Bar=h1;
      UpdateRegime();
      RefreshContext();
      UpdateEngineHealth();
      if(InpTradeEnabled) RunEngines();
     }

   datetime pb=iTime(_Symbol,InpP_TF,0);
   if(pb!=0 && pb!=g_lastPBar)
     {
      g_lastPBar=pb;
      PulseOnNewBar();
     }

   if(InpShowPanel && TimeLocal()-g_lastPanel>=1) { DrawPanel(); g_lastPanel=TimeLocal(); }
  }

//==================================================================
// Layer 1: Regime detector
//==================================================================
void UpdateRegime()
  {
   // Efficiency ratio on closed H4 bars
   double net=MathAbs(iClose(_Symbol,PERIOD_H4,1)-iClose(_Symbol,PERIOD_H4,1+InpERPeriod));
   double path=0.0;
   for(int i=1;i<=InpERPeriod;i++)
      path+=MathAbs(iClose(_Symbol,PERIOD_H4,i)-iClose(_Symbol,PERIOD_H4,i+1));
   g_er=(path>0 ? net/path : 0.0);

   // ATR ratio
   double atr[];
   ArraySetAsSeries(atr,true);
   g_atrRatio=1.0;
   if(CopyBuffer(hATR_H4,0,1,InpATRAvgPeriod,atr)==InpATRAvgPeriod)
     {
      double s=0; for(int i=0;i<InpATRAvgPeriod;i++) s+=atr[i];
      double avg=s/InpATRAvgPeriod;
      if(avg>0) g_atrRatio=atr[0]/avg;
     }

   if(g_atrRatio>=InpChaosATRRatio) g_regime=REG_CHAOS;
   else if(g_er>=InpERTrend)        g_regime=REG_TREND;
   else if(g_er<=InpERRange)        g_regime=REG_RANGE;
   else                             g_regime=REG_NEUTRAL;

   // D1 directional bias: close vs EMA and EMA slope
   double c1=iClose(_Symbol,PERIOD_D1,1);
   double e1=Val(hEMA_D1,0,1), e6=Val(hEMA_D1,0,6);
   g_d1Dir=0;
   if(Ok(e1) && Ok(e6) && c1>0)
     {
      if(c1>e1 && e1>e6) g_d1Dir=1;
      else if(c1<e1 && e1<e6) g_d1Dir=-1;
     }
  }

//==================================================================
// Layer 6: Market context
//==================================================================
double CloseOf(const string sym,const ENUM_TIMEFRAMES tf,const int shift)
  {
   double c[1];
   if(CopyClose(sym,tf,shift,1,c)!=1) return 0.0;
   return c[0];
  }

double SyntheticDXY(const int shift) { return SyntheticDXYTF(PERIOD_H4,shift); }

double SyntheticDXYTF(const ENUM_TIMEFRAMES tf,const int shift)
  {
   double eu=CloseOf("EURUSD"+g_suffix,tf,shift);
   double uj=CloseOf("USDJPY"+g_suffix,tf,shift);
   double gu=CloseOf("GBPUSD"+g_suffix,tf,shift);
   double uc=CloseOf("USDCAD"+g_suffix,tf,shift);
   double us=CloseOf("USDSEK"+g_suffix,tf,shift);
   double uf=CloseOf("USDCHF"+g_suffix,tf,shift);
   if(eu<=0||uj<=0||gu<=0||uc<=0||us<=0||uf<=0) return 0.0;
   return 50.14348112*MathPow(eu,-0.576)*MathPow(uj,0.136)*MathPow(gu,-0.119)*
          MathPow(uc,0.091)*MathPow(us,0.042)*MathPow(uf,0.036);
  }

void RefreshContext()
  {
   g_usdOK=false;
   if(InpUseUSDPulse)
     {
      double now=SyntheticDXY(1), then=SyntheticDXY(1+InpUSDLookbackH4);
      if(now>0 && then>0) { g_usdChangePct=(now/then-1.0)*100.0; g_usdOK=true; }
     }
   g_silverOK=false;
   if(InpUseSilver)
     {
      double g1=CloseOf(_Symbol,PERIOD_H4,1), g0=CloseOf(_Symbol,PERIOD_H4,1+InpUSDLookbackH4);
      double s1=CloseOf("XAGUSD"+g_suffix,PERIOD_H4,1), s0=CloseOf("XAGUSD"+g_suffix,PERIOD_H4,1+InpUSDLookbackH4);
      if(g1>0&&g0>0&&s1>0&&s0>0)
        {
         g_goldRetPct=(g1/g0-1.0)*100.0;
         g_silverRetPct=(s1/s0-1.0)*100.0;
         g_silverOK=true;
        }
     }
  }

// News shield: load high-impact USD events for the next 24h (server time)
void RefreshNews()
  {
   g_lastNewsFetch=TimeTradeServer();
   ArrayResize(g_newsTimes,0);
   ArrayResize(g_newsNames,0);
   MqlCalendarValue vals[];
   datetime from=TimeTradeServer()-3600*2, to=TimeTradeServer()+3600*24;
   if(CalendarValueHistory(vals,from,to,NULL,"USD")<=0) return;
   for(int i=0;i<ArraySize(vals);i++)
     {
      MqlCalendarEvent ev;
      if(!CalendarEventById(vals[i].event_id,ev)) continue;
      if(ev.importance!=CALENDAR_IMPORTANCE_HIGH) continue;
      int n=ArraySize(g_newsTimes);
      ArrayResize(g_newsTimes,n+1);
      ArrayResize(g_newsNames,n+1);
      g_newsTimes[n]=vals[i].time;
      g_newsNames[n]=ev.name;
     }
  }

bool NewsBlocked(string &why)
  {
   if(!InpUseNews || g_isTester) return false;
   datetime now=TimeTradeServer();
   for(int i=0;i<ArraySize(g_newsTimes);i++)
     {
      if(now>=g_newsTimes[i]-InpNewsBeforeMin*60 && now<=g_newsTimes[i]+InpNewsAfterMin*60)
        {
         why=g_newsNames[i];
         return true;
        }
     }
   return false;
  }

string NextNews()
  {
   datetime now=TimeTradeServer(), best=0; string name="";
   for(int i=0;i<ArraySize(g_newsTimes);i++)
      if(g_newsTimes[i]>=now-InpNewsAfterMin*60 && (best==0 || g_newsTimes[i]<best))
        { best=g_newsTimes[i]; name=g_newsNames[i]; }
   if(best==0) return "none in 24h";
   return name+" @ "+TimeToString(best,TIME_DATE|TIME_MINUTES)+" (server)";
  }

// Daily macro bias from web file (key=value lines)
void RefreshBias()
  {
   g_lastBiasFetch=TimeTradeServer();
   char req[], res[]; string hdr;
   ResetLastError();
   int code=WebRequest("GET",InpBiasURL+"?t="+IntegerToString((long)TimeGMT()),"",5000,req,res,hdr);
   if(code!=200)
     {
      int err=GetLastError();
      if(code==-1 && err==4014)
         g_biasError="Add https://raw.githubusercontent.com to Tools>Options>Expert Advisors>Allow WebRequest";
      else
         g_biasError="HTTP "+IntegerToString(code)+" err "+IntegerToString(err);
      Print("GYT bias: ",g_biasError);
      return;
     }
   string txt=CharArrayToString(res,0,WHOLE_ARRAY,CP_UTF8);
   string lines[];
   int n=StringSplit(txt,'\n',lines);
   string bias=""; double rm=-1; long vu=0; string date="", note="";
   for(int i=0;i<n;i++)
     {
      string ln=lines[i];
      StringTrimLeft(ln); StringTrimRight(ln);
      if(StringLen(ln)==0 || StringGetCharacter(ln,0)=='#') continue;
      int eq=StringFind(ln,"=");
      if(eq<=0) continue;
      string k=StringSubstr(ln,0,eq), v=StringSubstr(ln,eq+1);
      StringTrimLeft(k); StringTrimRight(k); StringTrimLeft(v); StringTrimRight(v);
      StringToLower(k);
      if(k=="bias")        { bias=v; StringToUpper(bias); }
      else if(k=="risk_mult")   rm=StringToDouble(v);
      else if(k=="valid_until") vu=StringToInteger(v);
      else if(k=="date")        date=v;
      else if(k=="note")        note=v;
     }
   if(bias!="BULL" && bias!="BEAR" && bias!="NEUTRAL" && bias!="OFF")
     {
      g_biasError="bad bias value '"+bias+"'";
      Print("GYT bias: ",g_biasError);
      return;
     }
   g_biasName=bias;
   g_biasRiskMult=(rm<0 ? 1.0 : MathMax(0.0,rm));
   g_biasValidUntil=(datetime)vu;
   g_biasDate=date;
   g_biasNote=note;
   g_biasLoaded=true;
   g_biasError="";
  }

bool BiasFresh() { return (g_biasLoaded && (datetime)TimeGMT()<=g_biasValidUntil); }

// multiplier from macro bias for a direction (+1 buy, -1 sell); -1 => blocked
double BiasMult(const int dir)
  {
   if(!InpUseMacroBias || g_isTester) return 1.0;
   if(!BiasFresh()) return InpBiasStaleMult;
   if(g_biasName=="OFF") return 0.0;
   double rm=MathMin(g_biasRiskMult,InpBiasMaxMult);
   if(g_biasName=="BULL") return (dir>0 ? rm : rm*InpBiasCounterMult);
   if(g_biasName=="BEAR") return (dir<0 ? rm : rm*InpBiasCounterMult);
   return rm; // NEUTRAL
  }

double ContextMult(const int dir,string &detail)
  {
   double m=1.0;
   double b=BiasMult(dir);
   m*=b;
   detail="bias x"+DoubleToString(b,2);
   if(InpUseUSDPulse && g_usdOK)
     {
      if(dir>0 && g_usdChangePct>= InpUSDThreshPct) { m*=InpUSDMult; detail+=" usd-up x"+DoubleToString(InpUSDMult,2); }
      if(dir<0 && g_usdChangePct<=-InpUSDThreshPct) { m*=InpUSDMult; detail+=" usd-down x"+DoubleToString(InpUSDMult,2); }
     }
   if(InpUseSilver && g_silverOK)
     {
      bool div=(g_goldRetPct*g_silverRetPct<0 &&
                MathAbs(g_goldRetPct)>=InpSilverThreshPct && MathAbs(g_silverRetPct)>=InpSilverThreshPct);
      if(div) { m*=InpSilverMult; detail+=" ag-div x"+DoubleToString(InpSilverMult,2); }
     }
   if(g_atrRatio>=InpHighVolATRRatio) { m*=0.5; detail+=" hi-vol x0.50"; }
   return m;
  }

void ShockCheck()
  {
   if(!InpUseShock) return;
   datetime now=TimeTradeServer();
   if(Spread()>InpMaxSpreadUSD*InpSpreadShockMult && now>=g_pauseUntil)
     {
      g_pauseUntil=now+10*60;
      g_pauseReason="spread spike "+DoubleToString(Spread(),2);
     }
   double atr=ATR_H1(1);
   if(!Ok(atr) || atr<=0) return;
   int hi=iHighest(_Symbol,PERIOD_M1,MODE_HIGH,5,0);
   int lo=iLowest(_Symbol,PERIOD_M1,MODE_LOW,5,0);
   if(hi<0 || lo<0) return;
   double range=iHigh(_Symbol,PERIOD_M1,hi)-iLow(_Symbol,PERIOD_M1,lo);
   if(range>InpShockATRMult*atr && now>=g_pauseUntil)
     {
      g_pauseUntil=now+InpShockPauseMin*60;
      g_pauseReason="price shock "+DoubleToString(range,2)+" in 5m";
      Print("GYT: shock breaker - ",g_pauseReason);
     }
  }

//==================================================================
// Layer 5: Risk brain
//==================================================================
// Base capital for sizing and loss limits. With InpRiskBalance > 0 the EA behaves as if
// the account held that balance, so it can share an account with other EAs.
double BaseEquity()
  {
   if(InpRiskBalance>0) return InpRiskBalance;
   return AccountInfoDouble(ACCOUNT_EQUITY);
  }

// Net P/L of this EA only (closed deals since 'from' + floating of open positions)
double OwnPnL(const datetime from)
  {
   double pnl=0.0;
   if(HistorySelect(from,TimeTradeServer()+60))
     {
      int total=HistoryDealsTotal();
      for(int i=0;i<total;i++)
        {
         ulong t=HistoryDealGetTicket(i);
         if(t==0) continue;
         if(HistoryDealGetString(t,DEAL_SYMBOL)!=_Symbol) continue;
         if(!IsOurMagic(HistoryDealGetInteger(t,DEAL_MAGIC))) continue;
         pnl+=HistoryDealGetDouble(t,DEAL_PROFIT)+HistoryDealGetDouble(t,DEAL_SWAP)+
              HistoryDealGetDouble(t,DEAL_COMMISSION);
        }
     }
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong t=PositionGetTicket(i);
      if(t==0 || PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if(!IsOurMagic(PositionGetInteger(POSITION_MAGIC))) continue;
      pnl+=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
     }
   return pnl;
  }

void UpdateLossLimits()
  {
   datetime g=GMTNow();
   long day=(long)(g/86400);
   long week=(day+3)/7;                 // Monday-based week number
   int off=ServerOffsetHours()*3600;

   if(day!=g_dayId)
     {
      g_dayId=day;
      g_haltDay=false;
      GlobalVariablesDeleteAll("GYT_R_",TimeCurrent()-86400*30);
     }
   if(week!=g_weekId) { g_weekId=week; g_haltWeek=false; }

   // recompute own P/L at most every 5 seconds (HistorySelect is not free)
   if(TimeLocal()-g_lastPnlCalc<5) return;
   g_lastPnlCalc=TimeLocal();
   datetime dayStart =(datetime)(day*86400+off);          // GMT midnight, in server time
   datetime weekStart=(datetime)((week*7-3)*86400+off);   // Monday 00:00 GMT, in server time
   g_dayPnl =OwnPnL(dayStart);
   g_weekPnl=OwnPnL(weekStart);
   double base=BaseEquity();

   if(!g_haltDay && base>0 && -g_dayPnl/base*100.0>=InpDailyLossPct)
     {
      g_haltDay=true;
      Print("GYT: daily loss limit hit (",DoubleToString(g_dayPnl,2),") - no new trades today");
      if(InpCloseOnLossLimit) CloseAll("daily loss limit");
     }
   if(!g_haltWeek && base>0 && -g_weekPnl/base*100.0>=InpWeeklyLossPct)
     {
      g_haltWeek=true;
      Print("GYT: weekly loss limit hit (",DoubleToString(g_weekPnl,2),") - no new trades this week");
      if(InpCloseOnLossLimit) CloseAll("weekly loss limit");
     }
  }

void UpdateEngineHealth()
  {
   for(int e=1;e<=3;e++) g_health[e]=1.0;
   if(!HistorySelect(TimeCurrent()-86400*180,TimeCurrent())) return;
   int total=HistoryDealsTotal();
   for(int e=1;e<=3;e++)
     {
      double win=0, loss=0; int cnt=0;
      for(int i=total-1;i>=0 && cnt<InpHealthLookback;i--)
        {
         ulong t=HistoryDealGetTicket(i);
         if(t==0) continue;
         if(HistoryDealGetString(t,DEAL_SYMBOL)!=_Symbol) continue;
         if(HistoryDealGetInteger(t,DEAL_MAGIC)!=InpMagic+e) continue;
         long entry=HistoryDealGetInteger(t,DEAL_ENTRY);
         if(entry!=DEAL_ENTRY_OUT && entry!=DEAL_ENTRY_OUT_BY) continue;
         double p=HistoryDealGetDouble(t,DEAL_PROFIT)+HistoryDealGetDouble(t,DEAL_SWAP)+
                  HistoryDealGetDouble(t,DEAL_COMMISSION);
         if(p>=0) win+=p; else loss-=p;
         cnt++;
        }
      if(cnt>=InpHealthMinTrades)
        {
         double pf=(loss>0 ? win/loss : 99.0);
         if(pf<1.0) g_health[e]=InpHealthBadMult;
        }
     }
  }

// money lost if price moves from entry to sl with given volume
double LossAt(const bool isBuy,const double vol,const double entry,const double sl)
  {
   double p=0.0;
   if(!OrderCalcProfit(isBuy?ORDER_TYPE_BUY:ORDER_TYPE_SELL,_Symbol,vol,entry,sl,p)) return 0.0;
   return MathAbs(MathMin(p,0.0));
  }

double OpenRiskMoney()
  {
   double r=0.0;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong t=PositionGetTicket(i);
      if(t==0 || PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if(!IsOurMagic(PositionGetInteger(POSITION_MAGIC))) continue;
      bool buy=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY);
      double op=PositionGetDouble(POSITION_PRICE_OPEN), sl=PositionGetDouble(POSITION_SL);
      double v=PositionGetDouble(POSITION_VOLUME);
      if(sl<=0) { r+=BaseEquity()*InpRiskPerTradePct/100.0; continue; }
      if((buy && sl<op) || (!buy && sl>op)) r+=LossAt(buy,v,op,sl);
     }
   return r;
  }

int CountOurPositions(const int engine,int &dirOut)
  {
   int n=0; dirOut=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong t=PositionGetTicket(i);
      if(t==0 || PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      long mg=PositionGetInteger(POSITION_MAGIC);
      if(!IsOurMagic(mg)) continue;
      if(engine>0 && EngineOf(mg)!=engine) continue;
      n++;
      dirOut=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY ? 1 : -1);
     }
   return n;
  }

bool HasOpposite(const int dir)
  {
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong t=PositionGetTicket(i);
      if(t==0 || PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if(!IsOurMagic(PositionGetInteger(POSITION_MAGIC))) continue;
      int d=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY ? 1 : -1);
      if(d!=dir) return true;
     }
   return false;
  }

double NormalizeVolume(double v)
  {
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   double mn=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double mx=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   if(step<=0) step=0.01;
   v=MathFloor(v/step+1e-9)*step;
   if(v<mn) return 0.0;
   if(v>mx) v=mx;
   return NormalizeDouble(v,2);
  }

//==================================================================
// Entry gates
//==================================================================
bool CanOpen(string &why)
  {
   if(g_haltDay)  { why="daily loss limit"; return false; }
   if(g_haltWeek) { why="weekly loss limit"; return false; }
   if(TimeTradeServer()<g_pauseUntil) { why="paused: "+g_pauseReason; return false; }
   int h=GMTHour(), dow=GMTDow();
   if(dow==0 || dow==6) { why="weekend"; return false; }
   if(h<InpSessionStartGMT || h>=InpSessionEndGMT) { why="outside session"; return false; }
   if(dow==5 && h>=InpFridayNoEntryGMT) { why="Friday cutoff"; return false; }
   if(Spread()>InpMaxSpreadUSD) { why="spread "+DoubleToString(Spread(),2); return false; }
   string nw;
   if(NewsBlocked(nw)) { why="news: "+nw; return false; }
   if(g_regime==REG_CHAOS) { why="regime CHAOS"; return false; }
   if(CountCorePositions()>=InpMaxPositions) { why="max positions"; return false; }
   return true;
  }

int CountCorePositions()
  {
   int n=0, d;
   for(int e=ENG_A;e<=ENG_C;e++) n+=CountOurPositions(e,d);
   return n;
  }

bool OpenTrade(const int engine,const int dir,const double slDist,const double tpDist)
  {
   string ctx;
   double mult=ContextMult(dir,ctx)*g_health[engine];
   if(mult<InpMinRiskFactor)
     {
      Print("GYT ",EngineName(engine),": skipped, risk multiplier ",DoubleToString(mult,2)," (",ctx,")");
      return false;
     }
   if(HasOpposite(dir))
     {
      Print("GYT ",EngineName(engine),": skipped, opposite position open");
      return false;
     }

   double eq=BaseEquity();
   double riskMoney=eq*InpRiskPerTradePct/100.0*MathMin(mult,1.5);
   double room=eq*InpMaxTotalRiskPct/100.0-OpenRiskMoney();
   if(room<=0) { Print("GYT: portfolio risk cap reached"); return false; }
   riskMoney=MathMin(riskMoney,room);

   bool buy=(dir>0);
   double price=buy ? SymbolInfoDouble(_Symbol,SYMBOL_ASK) : SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double pt=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   int digits=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   double minStop=(SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)+5)*pt+Spread();
   double sd=MathMax(slDist,minStop);

   double sl=NormalizeDouble(buy ? price-sd : price+sd,digits);
   double tp=0.0;
   if(tpDist>0) tp=NormalizeDouble(buy ? price+MathMax(tpDist,minStop) : price-MathMax(tpDist,minStop),digits);

   double lossPerLot=LossAt(buy,1.0,price,sl);
   if(lossPerLot<=0) { Print("GYT: cannot compute loss per lot"); return false; }
   double vol=NormalizeVolume(riskMoney/lossPerLot);
   if(vol<=0)
     {
      double mn=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
      if(mn*lossPerLot<=riskMoney*1.2) vol=mn;
      else { Print("GYT: min lot exceeds risk budget, skipped"); return false; }
     }

   double margin=0.0;
   if(OrderCalcMargin(buy?ORDER_TYPE_BUY:ORDER_TYPE_SELL,_Symbol,vol,price,margin) &&
      margin>AccountInfoDouble(ACCOUNT_MARGIN_FREE)*0.8)
     {
      Print("GYT: not enough free margin");
      return false;
     }

   trade.SetExpertMagicNumber(InpMagic+engine);
   string cm=InpComment+"-"+EngineName(engine);
   bool ok=buy ? trade.Buy(vol,_Symbol,0.0,sl,tp,cm) : trade.Sell(vol,_Symbol,0.0,sl,tp,cm);
   if(ok && (trade.ResultRetcode()==TRADE_RETCODE_DONE || trade.ResultRetcode()==TRADE_RETCODE_PLACED))
     {
      PrintFormat("GYT %s: %s %.2f lots SL=%.2f TP=%.2f risk=$%.2f mult=%.2f [%s] regime=%s",
                  EngineName(engine),buy?"BUY":"SELL",vol,sl,tp,vol*lossPerLot,mult,ctx,RegimeName(g_regime));
      return true;
     }
   Print("GYT: order failed ",trade.ResultRetcode()," ",trade.ResultRetcodeDescription());
   return false;
  }

//==================================================================
// Engines (evaluated once per closed H1 bar)
//==================================================================
void RunEngines()
  {
   string why;
   if(!CanOpen(why)) return;

   double atr=ATR_H1(1);
   if(!Ok(atr) || atr<=0) return;
   int d;

   if(InpUseA && (g_regime==REG_TREND || g_regime==REG_NEUTRAL) && g_d1Dir!=0 && CountOurPositions(ENG_A,d)==0)
      EngineA(atr);
   if(InpUseB && g_regime==REG_TREND && g_d1Dir!=0 && CountOurPositions(ENG_B,d)==0)
      EngineB(atr);
   if(InpUseC && g_regime==REG_RANGE && CountOurPositions(ENG_C,d)==0)
      EngineC(atr);
  }

// A: close of last bar breaks the prior N-bar Donchian channel in D1 direction
void EngineA(const double atr)
  {
   int hh=iHighest(_Symbol,PERIOD_H1,MODE_HIGH,InpA_Donchian,2);
   int ll=iLowest(_Symbol,PERIOD_H1,MODE_LOW,InpA_Donchian,2);
   if(hh<0 || ll<0) return;
   double hi=iHigh(_Symbol,PERIOD_H1,hh), lo=iLow(_Symbol,PERIOD_H1,ll);
   double c1=iClose(_Symbol,PERIOD_H1,1), c2=iClose(_Symbol,PERIOD_H1,2);

   if(g_d1Dir>0 && c1>hi && c2<=hi) OpenTrade(ENG_A, 1,InpA_SL_ATR*atr,0.0);
   if(g_d1Dir<0 && c1<lo && c2>=lo) OpenTrade(ENG_A,-1,InpA_SL_ATR*atr,0.0);
  }

// B: pullback into fast EMA and rejection candle, in trend direction
void EngineB(const double atr)
  {
   double ef=Val(hEMAf_H1,0,1), es=Val(hEMAs_H1,0,1), rsi=Val(hRSI_H1,0,1);
   if(!Ok(ef)||!Ok(es)||!Ok(rsi)) return;
   double o1=iOpen(_Symbol,PERIOD_H1,1), h1=iHigh(_Symbol,PERIOD_H1,1);
   double l1=iLow(_Symbol,PERIOD_H1,1),  c1=iClose(_Symbol,PERIOD_H1,1);
   double l2=iLow(_Symbol,PERIOD_H1,2),  h2=iHigh(_Symbol,PERIOD_H1,2);

   if(g_d1Dir>0 && ef>es && l1<=ef && c1>ef && c1>o1 && rsi>=InpB_RSIMin && rsi<=InpB_RSIMax)
     {
      double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      double sd=ask-(MathMin(l1,l2)-0.3*atr);
      if(sd<1.0*atr) sd=1.0*atr;
      if(sd<=3.0*atr) OpenTrade(ENG_B,1,sd,InpB_TP_R*sd);
     }
   if(g_d1Dir<0 && ef<es && h1>=ef && c1<ef && c1<o1 && rsi<=100-InpB_RSIMin && rsi>=100-InpB_RSIMax)
     {
      double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
      double sd=(MathMax(h1,h2)+0.3*atr)-bid;
      if(sd<1.0*atr) sd=1.0*atr;
      if(sd<=3.0*atr) OpenTrade(ENG_B,-1,sd,InpB_TP_R*sd);
     }
  }

// C: false break of Bollinger band with RSI stretch, target = mid band
void EngineC(const double atr)
  {
   double mid=Val(hBB_H1,0,1), up=Val(hBB_H1,1,1), dn=Val(hBB_H1,2,1), rsi=Val(hRSI_H1,0,1);
   if(!Ok(mid)||!Ok(up)||!Ok(dn)||!Ok(rsi)) return;
   double h1=iHigh(_Symbol,PERIOD_H1,1), l1=iLow(_Symbol,PERIOD_H1,1), c1=iClose(_Symbol,PERIOD_H1,1);

   if(l1<dn && c1>dn && rsi<InpC_RSIBuy)
     {
      double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      double sd=MathMax(ask-(l1-0.5*atr),0.8*atr);
      double td=mid-ask;
      if(td>=InpC_MinRR*sd) OpenTrade(ENG_C,1,sd,td);
     }
   if(h1>up && c1<up && rsi>100-InpC_RSIBuy)
     {
      double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
      double sd=MathMax((h1+0.5*atr)-bid,0.8*atr);
      double td=bid-mid;
      if(td>=InpC_MinRR*sd) OpenTrade(ENG_C,-1,sd,td);
     }
  }

//==================================================================
// Engine P: Pulse (intraday, M5) - Strength Meter, TP1 leg + runner
//==================================================================
// Strength Meter 0-100 for bar 'shift' of the signal timeframe.
// Components: displacement 25, range expansion 15, tick-volume surge 20,
// close location 10, trend alignment 20, DXY confirmation 10.
double PulseScore(const int shift,int &dir,string &parts)
  {
   dir=0; parts="";
   double o=iOpen(_Symbol,InpP_TF,shift), h=iHigh(_Symbol,InpP_TF,shift);
   double l=iLow(_Symbol,InpP_TF,shift),  c=iClose(_Symbol,InpP_TF,shift);
   double atr=Val(hATR_P,0,shift+1);
   if(o<=0 || h<=l || !Ok(atr) || atr<=0) return 0.0;
   double body=c-o;
   if(MathAbs(body)<1e-9) return 0.0;
   dir=(body>0 ? 1 : -1);

   double disp=MathMin(MathAbs(body)/atr,2.0)/2.0;
   double rng =MathMin((h-l)/atr,2.5)/2.5;

   double vsum=0; int vn=0;
   for(int i=shift+1;i<=shift+48;i++) { long v=iVolume(_Symbol,InpP_TF,i); if(v>0) { vsum+=(double)v; vn++; } }
   double vavg=(vn>0 ? vsum/vn : 0);
   double vol=(vavg>0 ? MathMin((double)iVolume(_Symbol,InpP_TF,shift)/vavg,3.0)/3.0 : 0.5);

   double loc=(dir>0 ? (c-l)/(h-l) : (h-c)/(h-l));

   double trend=0.0;
   double e0=Val(hEMA_P,0,shift), e3=Val(hEMA_P,0,shift+3);
   if(Ok(e0) && Ok(e3) && ((dir>0 && c>e0 && e0>e3) || (dir<0 && c<e0 && e0<e3))) trend+=0.5;
   double m1=Val(hEMA_P15,0,1), m4=Val(hEMA_P15,0,4);
   if(Ok(m1) && Ok(m4) && ((dir>0 && m1>m4) || (dir<0 && m1<m4))) trend+=0.5;

   double dxy=0.5;
   double d0=SyntheticDXYTF(InpP_TF,shift), d1=SyntheticDXYTF(InpP_TF,shift+1);
   if(d0>0 && d1>0)
     {
      double ch=(d0/d1-1.0)*10000.0;               // basis points
      if(MathAbs(ch)<0.5) dxy=0.5;
      else dxy=((ch<0 && dir>0) || (ch>0 && dir<0)) ? 1.0 : 0.0;
     }

   double score=25*disp+15*rng+20*vol+10*loc+20*trend+10*dxy;
   parts=StringFormat("%.2f,%.2f,%.2f,%.2f,%.2f,%.2f",disp,rng,vol,loc,trend,dxy);
   return score;
  }

// today's Pulse statistics from history (TP1 legs define a trade)
void PulseStats()
  {
   g_pTradesToday=0; g_pTP1Today=0; g_pLossToday=0; g_pLossStreak=0;
   datetime dayStart=(datetime)((long)(GMTNow()/86400)*86400+ServerOffsetHours()*3600);
   if(!HistorySelect(dayStart,TimeTradeServer()+60)) return;
   int total=HistoryDealsTotal();
   for(int i=0;i<total;i++)
     {
      ulong t=HistoryDealGetTicket(i);
      if(t==0 || HistoryDealGetString(t,DEAL_SYMBOL)!=_Symbol) continue;
      if(HistoryDealGetInteger(t,DEAL_MAGIC)!=InpMagic+ENG_P1) continue;
      long entry=HistoryDealGetInteger(t,DEAL_ENTRY);
      if(entry==DEAL_ENTRY_IN) { g_pTradesToday++; continue; }
      if(entry!=DEAL_ENTRY_OUT && entry!=DEAL_ENTRY_OUT_BY) continue;
      double p=HistoryDealGetDouble(t,DEAL_PROFIT)+HistoryDealGetDouble(t,DEAL_SWAP)+HistoryDealGetDouble(t,DEAL_COMMISSION);
      if(p>0) { g_pTP1Today++; g_pLossStreak=0; }
      else    { g_pLossToday++; g_pLossStreak++; }
     }
  }

int CountPulse(const int engine)
  {
   int d;
   return CountOurPositions(engine,d);
  }

void ClosePulse(const string reason)
  {
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong t=PositionGetTicket(i);
      if(t==0 || PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      long mg=PositionGetInteger(POSITION_MAGIC);
      if(mg!=InpMagic+ENG_P1 && mg!=InpMagic+ENG_P2) continue;
      trade.SetExpertMagicNumber(mg);
      trade.PositionClose(t);
     }
   Print("GYT Pulse: closed all Pulse positions (",reason,")");
  }

void PulseLog(const string line)
  {
   if(!InpP_Log) return;
   int fh=FileOpen("GYT_pulse_log.csv",FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_SHARE_READ);
   if(fh==INVALID_HANDLE) return;
   if(FileSize(fh)==0)
      FileWriteString(fh,"server_time,dir,score,disp,range,volume,closeloc,trend,dxy,action,entry,sl,tp1,lots\r\n");
   FileSeek(fh,0,SEEK_END);
   FileWriteString(fh,line+"\r\n");
   FileClose(fh);
  }

bool CanOpenPulse(string &why)
  {
   if(!InpUseP || !InpTradeEnabled) { why="disabled"; return false; }
   if(g_haltDay)  { why="daily loss limit"; return false; }
   if(g_haltWeek) { why="weekly loss limit"; return false; }
   if(TimeTradeServer()<g_pauseUntil) { why="paused: "+g_pauseReason; return false; }
   int h=GMTHour(), dow=GMTDow();
   if(dow==0 || dow==6) { why="weekend"; return false; }
   if(h<InpP_StartGMT || h>=InpP_EndGMT) { why="outside pulse session"; return false; }
   if(dow==5 && h>=InpFridayNoEntryGMT) { why="Friday cutoff"; return false; }
   if(Spread()>InpMaxSpreadUSD) { why="spread"; return false; }
   string nw;
   if(NewsBlocked(nw)) { why="news: "+nw; return false; }
   if(g_regime==REG_CHAOS) { why="regime CHAOS"; return false; }
   if(g_pTradesToday>=InpP_MaxTradesDay) { why="max trades today"; return false; }
   if(g_pLossStreak>=InpP_MaxLossStreak) { why="loss streak"; return false; }
   if(CountPulse(ENG_P1)>0) { why="TP1 leg open"; return false; }
   if(CountPulse(ENG_P2)>=2) { why="2 runners open"; return false; }
   return true;
  }

// adaptive entry threshold from the distribution of recent scores
void PulseUpdateThreshold(const double newest)
  {
   int n=ArraySize(g_pScores);
   if(n==0)
     {
      // seed with history on the first call
      for(int sh=InpP_AdaptBars+1;sh>=2;sh--)
        {
         int d; string pp;
         double sc=PulseScore(sh,d,pp);
         int k=ArraySize(g_pScores);
         ArrayResize(g_pScores,k+1);
         g_pScores[k]=sc;
        }
      n=ArraySize(g_pScores);
     }
   ArrayResize(g_pScores,n+1);
   g_pScores[n]=newest;
   n++;
   if(n>InpP_AdaptBars) { ArrayRemove(g_pScores,0,n-InpP_AdaptBars); n=InpP_AdaptBars; }

   if(!InpP_Adaptive || n<20) { g_pThreshold=InpP_MinScore; return; }
   double tmp[];
   ArrayCopy(tmp,g_pScores);
   ArraySort(tmp);
   int idx=(int)MathFloor((1.0-InpP_TopPct/100.0)*(n-1));
   idx=(int)MathMax(0,MathMin(n-1,idx));
   g_pThreshold=MathMin(InpP_MinScore,MathMax(InpP_ScoreFloor,tmp[idx]));
  }

void PulseOnNewBar()
  {
   PulseStats();

   // live meter for the panel (forming bar)
   string lp;
   g_pLiveScore=PulseScore(0,g_pLiveDir,lp);

   // flatten time / Friday
   int h=GMTHour();
   if((h>=InpP_FlatGMT || (GMTDow()==5 && h>=InpFridayCloseGMT && InpFridayCloseGMT>=0)) &&
      (CountPulse(ENG_P1)+CountPulse(ENG_P2))>0)
      ClosePulse("end of pulse day");

   int dir; string parts;
   double score=PulseScore(1,dir,parts);
   PulseUpdateThreshold(score);
   if(dir==0) return;

   // runner exit on strong opposite move
   if(score>=InpP_ExitScore)
     {
      for(int i=PositionsTotal()-1;i>=0;i--)
        {
         ulong t=PositionGetTicket(i);
         if(t==0 || PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
         if(PositionGetInteger(POSITION_MAGIC)!=InpMagic+ENG_P2) continue;
         int pd=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY ? 1 : -1);
         if(pd!=dir)
           {
            trade.SetExpertMagicNumber(InpMagic+ENG_P2);
            if(trade.PositionClose(t)) PrintFormat("GYT Pulse: runner closed, opposite strength %.0f",score);
           }
        }
     }

   if(score<g_pThreshold) return;
   string stamp=TimeToString(iTime(_Symbol,InpP_TF,1),TIME_DATE|TIME_MINUTES);
   string head=stamp+","+(dir>0?"BUY":"SELL")+","+DoubleToString(score,1)+","+parts;
   g_pLastSignal=stamp+" "+(dir>0?"BUY":"SELL")+" score "+DoubleToString(score,0);

   string why;
   if(!CanOpenPulse(why)) { PulseLog(head+",skip:"+why+",,,,"); g_pLastSignal+=" (skip: "+why+")"; return; }

   double atr=Val(hATR_P,0,1), ema=Val(hEMA_P,0,1);
   double c1=iClose(_Symbol,InpP_TF,1), l1=iLow(_Symbol,InpP_TF,1), h1=iHigh(_Symbol,InpP_TF,1);
   if(!Ok(atr) || atr<=0 || !Ok(ema)) return;
   if(MathAbs(c1-ema)>InpP_MaxExtATR*atr) { PulseLog(head+",skip:overextended,,,,"); g_pLastSignal+=" (skip: overextended)"; return; }
   if(HasOpposite(dir)) { PulseLog(head+",skip:opposite open,,,,"); g_pLastSignal+=" (skip: opposite open)"; return; }

   string ctx;
   double mult=ContextMult(dir,ctx);
   if(mult<InpMinRiskFactor) { PulseLog(head+",skip:context x"+DoubleToString(mult,2)+",,,,"); g_pLastSignal+=" (skip: context)"; return; }

   bool buy=(dir>0);
   double price=buy ? SymbolInfoDouble(_Symbol,SYMBOL_ASK) : SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double sd=buy ? price-(l1-0.2*atr) : (h1+0.2*atr)-price;
   double pt=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   double minStop=(SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)+5)*pt+Spread();
   sd=MathMax(MathMin(MathMax(sd,InpP_SL_MinATR*atr),InpP_SL_MaxATR*atr),minStop);
   int digits=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   double sl =NormalizeDouble(buy ? price-sd : price+sd,digits);
   double tp1=NormalizeDouble(buy ? price+MathMax(InpP_TP1_R*sd,minStop) : price-MathMax(InpP_TP1_R*sd,minStop),digits);

   double base=BaseEquity();
   double riskMoney=base*InpP_RiskPct/100.0*MathMin(mult,1.0);
   double room=base*InpMaxTotalRiskPct/100.0-OpenRiskMoney();
   if(room<=0) { PulseLog(head+",skip:risk cap,,,,"); return; }
   riskMoney=MathMin(riskMoney,room);
   double lossPerLot=LossAt(buy,1.0,price,sl);
   if(lossPerLot<=0) return;

   double mn=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double total=riskMoney/lossPerLot;
   double v1=NormalizeVolume(total/2.0);
   double v2=NormalizeVolume(total-v1);
   if(v1<=0)
     {
      if(mn*lossPerLot<=riskMoney*1.2) { v1=mn; v2=0; }
      else { PulseLog(head+",skip:min lot > risk,,,,"); return; }
     }

   double margin=0.0;
   if(OrderCalcMargin(buy?ORDER_TYPE_BUY:ORDER_TYPE_SELL,_Symbol,v1+v2,price,margin) &&
      margin>AccountInfoDouble(ACCOUNT_MARGIN_FREE)*0.8) { PulseLog(head+",skip:margin,,,,"); return; }

   string tag=" s"+DoubleToString(score,0);
   trade.SetExpertMagicNumber(InpMagic+ENG_P1);
   bool ok1=buy ? trade.Buy(v1,_Symbol,0.0,sl,tp1,InpComment+"-P-TP"+tag) : trade.Sell(v1,_Symbol,0.0,sl,tp1,InpComment+"-P-TP"+tag);
   bool ok2=true;
   if(ok1 && v2>0)
     {
      trade.SetExpertMagicNumber(InpMagic+ENG_P2);
      ok2=buy ? trade.Buy(v2,_Symbol,0.0,sl,0.0,InpComment+"-P-Run"+tag) : trade.Sell(v2,_Symbol,0.0,sl,0.0,InpComment+"-P-Run"+tag);
     }
   PulseLog(head+","+(ok1?"OPEN":"FAIL "+IntegerToString(trade.ResultRetcode()))+","+
            DoubleToString(price,digits)+","+DoubleToString(sl,digits)+","+DoubleToString(tp1,digits)+","+
            DoubleToString(v1+v2,2));
   if(ok1)
     {
      g_pTradesToday++;
      PrintFormat("GYT Pulse: %s score %.0f lots %.2f+%.2f SL=%.2f TP1=%.2f risk=$%.2f [%s]",
                  buy?"BUY":"SELL",score,v1,v2,sl,tp1,(v1+v2)*lossPerLot,ctx);
     }
   else Print("GYT Pulse: order failed ",trade.ResultRetcode()," ",trade.ResultRetcodeDescription());
   if(!ok2) Print("GYT Pulse: runner order failed ",trade.ResultRetcode());
  }

//==================================================================
// Position management: breakeven, trailing, time stops
//==================================================================
void ManagePositions()
  {
   double atrH=ATR_H1(1), atrP=Val(hATR_P,0,1);
   if(!Ok(atrH) || atrH<=0) return;
   if(!Ok(atrP) || atrP<=0) atrP=atrH/3.0;
   double pt=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   int digits=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   double minStop=(SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)+5)*pt;

   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong t=PositionGetTicket(i);
      if(t==0 || PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      long mg=PositionGetInteger(POSITION_MAGIC);
      if(!IsOurMagic(mg)) continue;
      int e=EngineOf(mg);
      double atr=(e>=ENG_P1 ? atrP : atrH);
      bool buy=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY);
      double op=PositionGetDouble(POSITION_PRICE_OPEN);
      double sl=PositionGetDouble(POSITION_SL), tp=PositionGetDouble(POSITION_TP);
      double px=buy ? SymbolInfoDouble(_Symbol,SYMBOL_BID) : SymbolInfoDouble(_Symbol,SYMBOL_ASK);

      // initial risk (price distance), remembered per ticket
      string rk="GYT_R_"+IntegerToString((long)t);
      double R;
      if(GlobalVariableCheck(rk)) R=GlobalVariableGet(rk);
      else
        {
         R=(sl>0 ? MathAbs(op-sl) : 2.0*atr);
         GlobalVariableSet(rk,R);
        }
      if(R<=0) R=2.0*atr;
      double profR=(buy ? px-op : op-px)/R;

      // time stops
      int bars=iBarShift(_Symbol,PERIOD_H1,(datetime)PositionGetInteger(POSITION_TIME),false);
      bool timeUp=false;
      if(e==ENG_A && bars>=InpA_TimeStopBars && profR<0.5) timeUp=true;
      if(e==ENG_B && bars>=InpB_TimeStopBars && profR<0.5) timeUp=true;
      if(e==ENG_C && bars>=InpC_TimeStopBars) timeUp=true;
      int mins=(int)((TimeTradeServer()-(datetime)PositionGetInteger(POSITION_TIME))/60);
      if(e==ENG_P1 && mins>=InpP_TP1MaxMin) timeUp=true;
      if(e==ENG_P2 && mins>=InpP_MaxHoldMin) timeUp=true;
      if(timeUp)
        {
         trade.SetExpertMagicNumber(mg);
         if(trade.PositionClose(t)) Print("GYT ",EngineName(e),": time stop, closed at ",DoubleToString(profR,2),"R");
         continue;
        }

      // stop management
      double newSL=sl;
      if(e==ENG_P2 && profR>=InpP_TP1_R)                 // TP1 reached: runner can no longer lose
        {
         double be=buy ? op+0.05*R : op-0.05*R;
         if(buy ? (sl<be) : (sl>be || sl==0)) newSL=be;
        }
      if(profR>=1.0)
        {
         double be=buy ? op+0.1*R : op-0.1*R;            // breakeven + a little
         if(buy ? (sl<be) : (sl>be || sl==0)) newSL=be;
        }
      double trailK=0.0;
      if(e==ENG_A && profR>=1.0) trailK=InpA_Trail_ATR;
      if(e==ENG_B && profR>=1.5) trailK=InpB_Trail_ATR;
      if(e==ENG_P2 && profR>=1.0) trailK=InpP_RunTrailATR;
      if(trailK>0)
        {
         double tr=buy ? px-trailK*atr : px+trailK*atr;
         if(buy ? (tr>newSL) : (tr<newSL || newSL==0)) newSL=tr;
        }
      if(newSL==sl) continue;

      newSL=NormalizeDouble(newSL,digits);
      if(buy  && newSL>px-minStop) continue;
      if(!buy && newSL<px+minStop) continue;
      if(sl>0 && MathAbs(newSL-sl)<0.05*atr) continue;   // avoid spamming tiny modifications

      trade.SetExpertMagicNumber(mg);
      trade.PositionModify(t,newSL,tp);
     }
  }

void CloseAll(const string reason)
  {
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong t=PositionGetTicket(i);
      if(t==0 || PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      long mg=PositionGetInteger(POSITION_MAGIC);
      if(!IsOurMagic(mg)) continue;
      trade.SetExpertMagicNumber(mg);
      trade.PositionClose(t);
     }
   Print("GYT: closed all positions (",reason,")");
  }

void FridayClose()
  {
   if(InpFridayCloseGMT<0) return;
   if(GMTDow()==5 && GMTHour()>=InpFridayCloseGMT)
     {
      int d;
      if(CountOurPositions(0,d)>0) CloseAll("Friday close");
     }
  }

//==================================================================
// Panel
//==================================================================
void DrawPanel()
  {
   string why="ready";
   bool can=CanOpen(why);
   string s="";
   s+="GYT Multi-Engine v1.21  |  "+_Symbol+"\n";
   s+="Regime: "+RegimeName(g_regime)+"  ER="+DoubleToString(g_er,2)+"  ATRx="+DoubleToString(g_atrRatio,2)+
      "  D1 dir="+(g_d1Dir>0?"UP":(g_d1Dir<0?"DOWN":"FLAT"))+"\n";
   s+="Entries: "+(InpTradeEnabled?(can?"ALLOWED":"BLOCKED - "+why):"DISABLED")+"\n";
   s+="GYT Day P/L: "+DoubleToString(g_dayPnl,2)+"  Week P/L: "+DoubleToString(g_weekPnl,2)+
      "  Base: $"+DoubleToString(BaseEquity(),0)+
      "  Open risk: $"+DoubleToString(OpenRiskMoney(),2)+"\n";
   s+="Health A/B/C: "+DoubleToString(g_health[1],2)+" / "+DoubleToString(g_health[2],2)+" / "+DoubleToString(g_health[3],2)+"\n";
   s+="USD pulse: "+(g_usdOK?DoubleToString(g_usdChangePct,2)+"%":"n/a")+
      "   Gold/Silver 20xH4: "+(g_silverOK?DoubleToString(g_goldRetPct,2)+"% / "+DoubleToString(g_silverRetPct,2)+"%":"n/a")+"\n";
   if(g_isTester) s+="Macro bias: off in tester   News: off in tester\n";
   else
     {
      s+="Macro bias: "+g_biasName+" x"+DoubleToString(g_biasRiskMult,2)+" ("+g_biasDate+")"+
         (BiasFresh()?"":"  STALE")+(g_biasError!=""?"  ["+g_biasError+"]":"")+"\n";
      if(g_biasNote!="") s+="  "+g_biasNote+"\n";
      s+="Next USD news: "+NextNews()+"\n";
     }
   s+="Mult buy/sell: "+DoubleToString(BiasMult(1),2)+" / "+DoubleToString(BiasMult(-1),2)+"\n";
   if(InpUseP)
     {
      s+="Pulse strength (live "+EnumToString(InpP_TF)+"): "+DoubleToString(g_pLiveScore,0)+" "+
         (g_pLiveDir>0?"UP":(g_pLiveDir<0?"DOWN":"-"))+"   entry >= "+DoubleToString(g_pThreshold,0)+(InpP_Adaptive?" (adaptive)":"")+"\n";
      s+="Pulse today: trades "+IntegerToString(g_pTradesToday)+"/"+IntegerToString(InpP_MaxTradesDay)+
         "  TP1 hit "+IntegerToString(g_pTP1Today)+"  losses "+IntegerToString(g_pLossToday)+
         "  streak "+IntegerToString(g_pLossStreak)+"\n";
      s+="Pulse last signal: "+g_pLastSignal;
     }
   Comment(s);
  }
//+------------------------------------------------------------------+
