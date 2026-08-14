//+------------------------------------------------------------------+
//|                                   BTC MINER EA - SMART DELAY.mq5 |
//|                         Converted for BTCUSD Exness (Safe Delay) |
//+------------------------------------------------------------------+
#property copyright "BTC MINER Exness - Smart Delay (Direct MQL5)"
#property link      ""
#property version   "3.30"
#property description "MARTI PRO SCALPER - CLEAN & MINUTE DELAY"

#include <Trade\Trade.mqh>
CTrade trade;

//--- Input Parameters ---
input bool MARtiScalper = true;
input string xxSETTINGSxx = "==>>MONEY MANAGEMENT SETTINGS<<==";
input double Lots = 0.01;
input double LotExponent = 1.30;
input int Gi_108 = 2;
input double MaxLots = 50.0;
input bool MM = false;

// --- PARAMETER SKALA BTCUSD ---
input double TakeProfit = 15000.0; 
input string xRiskSetting = "==>> PROTEKSI ANTI-MC (EQUITY STOP) <<==";
input bool UseEquityStop = true;          // Aktifkan Cut-Loss otomatis
input double TotalEquityRisk = 30.0;      // Maksimal Drawdown 30% dari Balance

// --- PENGATURAN JEDA WAKTU (SATUAN MENIT) ---
input string xDelaySetting = "==>> JEDA WAKTU ANTAR SIKLUS <<==";
input bool UseTimeDelay = true;
input double TimeoutMinutes = 30.0;       // Jeda waktu dalam Menit (Contoh: 30 = 30 menit)

input string xxxxxxxxxxxx = "Set Current Trade & Orders";
input int MaxTrades_Hilo = 7;             // Dibatasi 7 lapis
input bool UseTrailingStop_Hilo = false;

// --- STRATEGI 1: HILO ---
input double TrailStart_Hilo = 1000.0;
input double TrailStop_Hilo = 500.0; 
input double PipStep_Hilo = 25000.0;      
input double slip_Hilo = 300.0; 
input int MagicNumber_Hilo = 11111;

// Global Variables 
double G_price_280, Gd_288, G_price_312, G_bid_320, G_ask_328, Gd_336, Gd_344, Gd_352;
bool Gi_360; string Gs_364 = "BTC_Hilo";
int Gi_372 = 123, Gi_380 = 123; double Gd_384;
datetime Gi_376 = 0; // Waktu jeda
int G_pos_392 = 123, Gi_396;
bool Gi_408 = false, Gi_412 = false, Gi_416 = false; 
bool Gi_424 = false;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   Gd_352 = SymbolInfoInteger(Symbol(), SYMBOL_SPREAD) * Point();
   trade.SetExpertMagicNumber(MagicNumber_Hilo);
   Comment(""); 
   
   if((ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
     {
      Alert("PERINGATAN: EA Ini butuh akun Hedging MT5!");
      return(INIT_FAILED);
     }
     
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   Comment("");
  }

//+------------------------------------------------------------------+
//| Fungsi Pengganti Untuk Menghitung Total Posisi Hilo              |
//+------------------------------------------------------------------+
int f0_4()
  {
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == MagicNumber_Hilo)
         count++;
     }
   return count;
  }

//+------------------------------------------------------------------+
// Harga Open Buy Terakhir
//+------------------------------------------------------------------+
double f0_32()
  {
   double p = 0; ulong t = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == MagicNumber_Hilo && PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
        {
         if(ticket > t) { p = PositionGetDouble(POSITION_PRICE_OPEN); t = ticket; }
        }
     }
   return p;
  }

//+------------------------------------------------------------------+
// Harga Open Sell Terakhir
//+------------------------------------------------------------------+
double f0_20()
  {
   double p = 0; ulong t = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == MagicNumber_Hilo && PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
        {
         if(ticket > t) { p = PositionGetDouble(POSITION_PRICE_OPEN); t = ticket; }
        }
     }
   return p;
  }

//+------------------------------------------------------------------+
//| Fungsi Penutup Semua Posisi (Untuk Equity Stop)                  |
//+------------------------------------------------------------------+
void CloseAllPositions()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == MagicNumber_Hilo)
        {
         trade.PositionClose(ticket);
        }
     }
   Print("Semua posisi ditutup paksa oleh sistem Equity Stop!");
  }

//+------------------------------------------------------------------+
//| Fungsi Pengecekan Equity (Anti-MC)                               |
//+------------------------------------------------------------------+
void CheckEquityStop()
  {
   if(!UseEquityStop) return;
   
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   
   if(equity < balance) 
     {
      double floatingLoss = balance - equity;
      double lossPercent = (floatingLoss / balance) * 100.0;
      
      if(lossPercent >= TotalEquityRisk)
        {
         Print("!!! PERINGATAN DRAWDOWN: ", DoubleToString(lossPercent, 2), "% mencapai batas ", TotalEquityRisk, "% !!!");
         CloseAllPositions();
         
         // Jeda waktu menggunakan menit (TimeoutMinutes * 60 detik)
         if(UseTimeDelay) Gi_376 = TimeCurrent() + (datetime)(TimeoutMinutes * 60);
        }
     }
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   CheckEquityStop();
   
   double CurrentLots = Lots;
   if(CurrentLots > MaxLots) CurrentLots = MaxLots;
   
   Comment("");

   double Ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double Bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // ================= STRATEGI 1: HILO =================
   double Ld_1160 = LotExponent;
   int Li_1168 = Gi_108;
   double Ld_1172 = TakeProfit;
   double Ld_1192 = CurrentLots; 
   
   Gi_396 = f0_4();
   if(Gi_396 == 0) Gi_360 = false;
   
   Gi_412 = false; Gi_416 = false;
   for(G_pos_392 = PositionsTotal() - 1; G_pos_392 >= 0; G_pos_392--) 
     {
      ulong ticket = PositionGetTicket(G_pos_392);
      if(PositionGetString(POSITION_SYMBOL) != _Symbol || PositionGetInteger(POSITION_MAGIC) != MagicNumber_Hilo) continue;
      
      if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) { Gi_412 = true; Gi_416 = false; break; }
      if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL) { Gi_412 = false; Gi_416 = true; break; }
     }
   
   if(Gi_396 > 0 && Gi_396 <= MaxTrades_Hilo) 
     {
      Gd_336 = f0_32(); Gd_344 = f0_20();
      if(Gi_412 && Gd_336 - Ask >= PipStep_Hilo * _Point) Gi_408 = true;
      if(Gi_416 && Bid - Gd_344 >= PipStep_Hilo * _Point) Gi_408 = true;
     }
   
   if(Gi_396 < 1) { Gi_416 = false; Gi_412 = false; Gi_408 = true; }
   
   // LOGIKA GRID LANJUTAN SAAT FLOATING
   if(Gi_408 && Gi_396 > 0) 
     {
      Gd_336 = f0_32();
      Gd_344 = f0_20();
      if(Gi_416) 
        {
         Gi_380 = Gi_396;
         Gd_384 = NormalizeDouble(Ld_1192 * MathPow(Ld_1160, Gi_380), Li_1168);
         trade.Sell(Gd_384, _Symbol, 0, 0, 0, Gs_364 + "-" + IntegerToString(Gi_380));
         Gi_408 = false; Gi_424 = true;
        } 
      else if(Gi_412) 
        {
         Gi_380 = Gi_396;
         Gd_384 = NormalizeDouble(Ld_1192 * MathPow(Ld_1160, Gi_380), Li_1168);
         trade.Buy(Gd_384, _Symbol, 0, 0, 0, Gs_364 + "-" + IntegerToString(Gi_380));
         Gi_408 = false; Gi_424 = true;
        }
     }
   
   // ENTRY PERTAMA DENGAN FILTER JEDA WAKTU (TIMEOUT MENIT)
   if(Gi_408 && Gi_396 < 1) 
     {
      bool canTrade = true;
      if(UseTimeDelay && TimeCurrent() < Gi_376) canTrade = false;
      
      if(canTrade && !Gi_416 && !Gi_412) 
        {
         Gi_380 = 0;
         Gd_384 = NormalizeDouble(Ld_1192, Li_1168);
         if(iHigh(_Symbol, PERIOD_CURRENT, 1) > iLow(_Symbol, PERIOD_CURRENT, 2)) 
           {
            if(trade.Sell(Gd_384, _Symbol, 0, 0, 0, Gs_364 + "-0"))
               if(UseTimeDelay) Gi_376 = TimeCurrent() + (datetime)(TimeoutMinutes * 60);
           } 
         else 
           {
            if(trade.Buy(Gd_384, _Symbol, 0, 0, 0, Gs_364 + "-0"))
               if(UseTimeDelay) Gi_376 = TimeCurrent() + (datetime)(TimeoutMinutes * 60);
           }
         
         Gi_408 = false; Gi_424 = true;
        }
     }
   
   // Kalkulasi BEP & TP Hilo
   Gi_396 = f0_4();
   G_price_312 = 0; double Ld_1208 = 0;
   
   for(G_pos_392 = PositionsTotal() - 1; G_pos_392 >= 0; G_pos_392--) 
     {
      ulong ticket = PositionGetTicket(G_pos_392);
      if(PositionGetString(POSITION_SYMBOL) != _Symbol || PositionGetInteger(POSITION_MAGIC) != MagicNumber_Hilo) continue;
      
      G_price_312 += PositionGetDouble(POSITION_PRICE_OPEN) * PositionGetDouble(POSITION_VOLUME);
      Ld_1208 += PositionGetDouble(POSITION_VOLUME); 
     }
     
   if(Gi_396 > 0 && Ld_1208 > 0) G_price_312 = NormalizeDouble(G_price_312 / Ld_1208, _Digits);
   
   if(Gi_424 && Gi_396 > 0) 
     {
      for(G_pos_392 = PositionsTotal() - 1; G_pos_392 >= 0; G_pos_392--) 
        {
         ulong ticket = PositionGetTicket(G_pos_392);
         if(PositionGetString(POSITION_SYMBOL) != _Symbol || PositionGetInteger(POSITION_MAGIC) != MagicNumber_Hilo) continue;
         
         double current_sl = PositionGetDouble(POSITION_SL);
         if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) 
           {
            G_price_280 = G_price_312 + Ld_1172 * _Point;
            trade.PositionModify(ticket, current_sl, G_price_280); 
           } 
         if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL) 
           {
            G_price_280 = G_price_312 - Ld_1172 * _Point;
            trade.PositionModify(ticket, current_sl, G_price_280); 
           } 
        }
      Gi_424 = false;
     }
  }
//+------------------------------------------------------------------+
