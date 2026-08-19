//+------------------------------------------------------------------+
//|                                  Auto_Martingale_Grid_BB_Mod.mq5 |
//|                                  Versi 3.8 (BB Squeeze Sideways) |
//+------------------------------------------------------------------+
#property copyright "Strategi Trading"
#property link      "https://www.mql5.com"
#property version   "3.80"

#include <Trade\Trade.mqh>

//--- Input Parameters --- 
input group "=== SETTING LOT & GRID ==="
input double   InpInitialLot         = 0.01;     
input double   InpGridDistance       = 3.0;      
input double   InpTakeProfitSingle   = 1.5;      
input double   InpTakeProfitBEP1     = 0.7;      
input int      InpAktifTPBEP2Posisi  = 5;        
input double   InpTakeProfitBEP2     = 0.3;      
input double   InpLotMultiplier      = 1.3;      
input ulong    InpMagicNumber        = 88888;    

input group "=== FILTER SIDEWAYS BOLLINGER BANDS ==="
input ENUM_TIMEFRAMES InpBBTimeFrame = PERIOD_H1;  // Timeframe BB
input int      InpBBPeriod           = 20;         // Periode BB
input double   InpBBDeviation        = 2.0;        // Deviasi BB
input double   InpMaxBandWidthPips   = 25.0;       // Maksimal Lebar BB (Pips) untuk Sideways

input group "=== AKTIVASI SESI TRADING ==="
input bool     InpUseAsia            = true;     
input bool     InpUseEropa           = true;     
input bool     InpUseUS              = true;     
input string   InpAsiaStart          = "09:30";  
input string   InpAsiaEnd            = "12:30";  
input string   InpEropaStart         = "15:30";  
input string   InpEropaEnd           = "17:30";  
input string   InpUSStart            = "22:30";  
input string   InpUSEnd              = "01:30";  

input group "=== SETTING SUPPORT & RESISTANCE ==="
input int      InpSnRPeriod          = 50;       
input int      InpSnROffset          = 5;        
input double   InpSnRBuffer          = 3.0;      

CTrade trade;

int AsiaStartMin, AsiaEndMin, EropaStartMin, EropaEndMin, USStartMin, USEndMin;
int bb_handle; 
double pip_multiplier;

// --- FUNGSI INISIALISASI UTAMA ---
int OnInit()
  {
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(50);
   
   AsiaStartMin = TimeToMinutes(InpAsiaStart); AsiaEndMin = TimeToMinutes(InpAsiaEnd);
   EropaStartMin = TimeToMinutes(InpEropaStart); EropaEndMin = TimeToMinutes(InpEropaEnd);
   USStartMin = TimeToMinutes(InpUSStart); USEndMin = TimeToMinutes(InpUSEnd);
   
   // Tentukan multiplier Pips berdasarkan digit broker
   pip_multiplier = MathPow(10, _Digits % 2 == 1 ? _Digits - 1 : _Digits);
   
   // Inisialisasi Indikator BB
   bb_handle = iBands(_Symbol, InpBBTimeFrame, InpBBPeriod, 0, InpBBDeviation, PRICE_CLOSE);
   if(bb_handle == INVALID_HANDLE) return(INIT_FAILED);
   
   return(INIT_SUCCEEDED);
  }

// --- FUNGSI UTAMA (BERJALAN SETIAP TICK HARGA) ---
void OnTick()
  {
   int buy_count = 0, sell_count = 0;
   double sum_buy_volume = 0, sum_buy_value = 0, sum_sell_volume = 0, sum_sell_value = 0;
   double last_buy_price = 0, last_sell_price = 0, initial_buy_lot = 0, initial_sell_lot = 0;
   datetime latest_buy_time = 0, latest_sell_time = 0, oldest_buy_time = 0, oldest_sell_time = 0;
   
   // --- MEMBACA POSISI TERBUKA ---
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && (PositionGetInteger(POSITION_MAGIC) == 0 || PositionGetInteger(POSITION_MAGIC) == InpMagicNumber))
        {
         long type = PositionGetInteger(POSITION_TYPE);
         double price = PositionGetDouble(POSITION_PRICE_OPEN), vol = PositionGetDouble(POSITION_VOLUME);
         datetime time = (datetime)PositionGetInteger(POSITION_TIME);
         
         if(type == POSITION_TYPE_BUY) 
           { 
            buy_count++; sum_buy_volume += vol; sum_buy_value += (price * vol); 
            if(time >= latest_buy_time) { latest_buy_time = time; last_buy_price = price; } 
            if(oldest_buy_time == 0 || time < oldest_buy_time) { oldest_buy_time = time; initial_buy_lot = vol; } 
           }
         else if(type == POSITION_TYPE_SELL) 
           { 
            sell_count++; sum_sell_volume += vol; sum_sell_value += (price * vol); 
            if(time >= latest_sell_time) { latest_sell_time = time; last_sell_price = price; } 
            if(oldest_sell_time == 0 || time < oldest_sell_time) { oldest_sell_time = time; initial_sell_lot = vol; } 
           }
        }
     }
     
   // --- MENGAMBIL NILAI BB TERBARU ---
   double upper_bb[], lower_bb[];
   ArraySetAsSeries(upper_bb, true); 
   ArraySetAsSeries(lower_bb, true);
   double band_width_pips = 0.0;
   
   if(CopyBuffer(bb_handle, 1, 0, 1, upper_bb) > 0 && CopyBuffer(bb_handle, 2, 0, 1, lower_bb) > 0)
     {
      // Menghitung lebar pita BB dalam satuan pips
      band_width_pips = (upper_bb[0] - lower_bb[0]) * pip_multiplier;
     }
   
   bool is_sideways = (band_width_pips > 0 && band_width_pips < InpMaxBandWidthPips);
   
   // --- LOGIKA OPEN AWAL (PERTAMA KALI) ---
   bool is_trading_time = IsTradingTime();
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID), ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double safe_buy_price = GetSupport(InpSnRPeriod, InpSnROffset) + InpSnRBuffer;
   double safe_sell_price = GetResistance(InpSnRPeriod, InpSnROffset) - InpSnRBuffer;
   
   if(sell_count == 0 && is_trading_time && is_sideways && bid < safe_sell_price)
     {
      trade.Sell(CalculateLot(InpInitialLot), _Symbol, bid, 0, 0, "First Auto Sell");
     }
      
   if(buy_count == 0 && is_trading_time && is_sideways && ask > safe_buy_price)
     {
      trade.Buy(CalculateLot(InpInitialLot), _Symbol, ask, 0, 0, "First Auto Buy");
     }

   // --- DASHBOARD LAYAR ---
   string dashboard = "=== EA MARTINGALE (BB SQUEEZE FILTER) ===\n";
   dashboard += "Waktu Sesi: " + (string)(is_trading_time ? "ON" : "OFF") + "\n\n";
   dashboard += "--- FILTER BOLLINGER BANDS (" + EnumToString(InpBBTimeFrame) + ") ---\n";
   dashboard += "Lebar BB Saat Ini: " + DoubleToString(band_width_pips, 1) + " Pips\n";
   dashboard += "Batas Sideways: < " + DoubleToString(InpMaxBandWidthPips, 1) + " Pips\n";
   dashboard += "Status: " + (string)(is_sideways ? "SIDEWAYS (Aman)" : "TRENDING (Ditahan)") + "\n\n";
   
   // --- AVERAGING & TAKE PROFIT LOGIC (SELL) ---
   if(sell_count > 0 && sum_sell_volume > 0) 
     {
      double bep = sum_sell_value / sum_sell_volume; 
      double tp = (sell_count == 1) ? bep - InpTakeProfitSingle : (sell_count >= InpAktifTPBEP2Posisi ? bep - InpTakeProfitBEP2 : bep - InpTakeProfitBEP1);
      
      if(last_sell_price > 0 && bid >= last_sell_price + InpGridDistance) 
        {
         trade.Sell(CalculateLot(initial_sell_lot * MathPow(InpLotMultiplier, sell_count)), _Symbol, bid, 0, 0, "Averaging");
        }
      if(ask <= tp && tp > 0) 
        {
         CloseAll(POSITION_TYPE_SELL);
        }
     }
     
   // --- AVERAGING & TAKE PROFIT LOGIC (BUY) ---
   if(buy_count > 0 && sum_buy_volume > 0)
     {
      double bep = sum_buy_value / sum_buy_volume; 
      double tp = (buy_count == 1) ? bep + InpTakeProfitSingle : (buy_count >= InpAktifTPBEP2Posisi ? bep + InpTakeProfitBEP2 : bep + InpTakeProfitBEP1);
      
      if(last_buy_price > 0 && ask <= last_buy_price - InpGridDistance) 
        {
         trade.Buy(CalculateLot(initial_buy_lot * MathPow(InpLotMultiplier, buy_count)), _Symbol, ask, 0, 0, "Averaging");
        }
      if(bid >= tp && tp > 0) 
        {
         CloseAll(POSITION_TYPE_BUY);
        }
     }
     
   Comment(dashboard);
  }

// --- FUNGSI MENCARI RESISTANCE ---
double GetResistance(int period, int offset)
  {
   double high[];
   ArraySetAsSeries(high, true);
   if(CopyHigh(_Symbol, _Period, offset, period, high) > 0)
     {
      return high[ArrayMaximum(high)];
     }
   return 0;
  }

// --- FUNGSI MENCARI SUPPORT ---
double GetSupport(int period, int offset)
  {
   double low[];
   ArraySetAsSeries(low, true);
   if(CopyLow(_Symbol, _Period, offset, period, low) > 0)
     {
      return low[ArrayMinimum(low)];
     }
   return 0;
  }

// --- FUNGSI KONVERSI WAKTU ---
int TimeToMinutes(string time_str)
  {
   string arr[];
   if(StringSplit(time_str, ':', arr) == 2)
     {
      return (int)StringToInteger(arr[0]) * 60 + (int)StringToInteger(arr[1]);
     }
   return 0;
  }

// --- FUNGSI CEK SESI TRADING ---
bool CheckSession(int current_min, int start_min, int end_min)
  {
   if(start_min < end_min)
     {
      return (current_min >= start_min && current_min <= end_min);
     }
   else
     {
      return (current_min >= start_min || current_min <= end_min);
     }
  }

// --- FUNGSI VALIDASI WAKTU TRADING ---
bool IsTradingTime()
  {
   MqlDateTime dt;
   TimeToStruct(TimeGMT() + 25200, dt); // Offset +7 Jam untuk WIB
   int current_min = dt.hour * 60 + dt.min;
   
   if(InpUseAsia && CheckSession(current_min, AsiaStartMin, AsiaEndMin)) return true;
   if(InpUseEropa && CheckSession(current_min, EropaStartMin, EropaEndMin)) return true;
   if(InpUseUS && CheckSession(current_min, USStartMin, USEndMin)) return true;
   
   return false;
  }

// --- FUNGSI TUTUP SEMUA POSISI (TAKE PROFIT) ---
void CloseAll(long pos_type)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionGetString(POSITION_SYMBOL) == _Symbol)
        {
         if((PositionGetInteger(POSITION_MAGIC) == 0 || PositionGetInteger(POSITION_MAGIC) == InpMagicNumber) && PositionGetInteger(POSITION_TYPE) == pos_type)
           {
            trade.PositionClose(ticket);
           }
        }
     }
  }

// --- FUNGSI PERHITUNGAN LOT AMAN ---
double CalculateLot(double calc_lot)
  {
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double final_lot = MathRound(calc_lot / step) * step;
   double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   
   return MathMax(min_lot, MathMin(final_lot, max_lot));
  }
//+------------------------------------------------------------------+
