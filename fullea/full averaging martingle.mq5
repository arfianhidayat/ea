//+------------------------------------------------------------------+
//|                                  Auto_Martingale_Grid_BB_Mod.mq5 |
//|                     Versi 3.9 (BB Squeeze + Dynamic Grid & SnR)  |
//+------------------------------------------------------------------+
#property copyright "Strategi Trading"
#property link      "https://www.mql5.com"
#property version   "3.90"

#include <Trade\Trade.mqh>

//--- Input Parameters --- 
input group "=== SETTING LOT & GRID ==="
input double   InpInitialLot         = 0.01;
input double   InpGridDistance       = 4.0;      // Jarak Averaging Dasar
input double   InpGridMultiplier     = 1.4;      // Pengali Jarak (jarak melebar tiap posisi)
input int      InpMaxPositions       = 99;       // Maksimal Posisi Averaging
input double   InpTakeProfitSingle   = 2.0;
input double   InpTakeProfitBEP1     = 1.0;
input int      InpAktifTPBEP2Posisi  = 5;
input double   InpTakeProfitBEP2     = 0.7;
input double   InpLotMultiplier      = 1.3;
input ulong    InpMagicNumber        = 88888;

input group "=== FILTER SIDEWAYS BOLLINGER BANDS ==="
input ENUM_TIMEFRAMES InpBBTimeFrame = PERIOD_M15;  // Timeframe BB
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

input group "=== SETTING SUPPORT & RESISTANCE (ENTRY AWAL) ==="
input int      InpSnRPeriod          = 4;
input int      InpSnROffset          = 0;
input double   InpSnRBuffer          = 1.0;

input group "=== SMART SNR FILTER AVERAGING (ANTI-BREAKOUT) ==="
input int      InpSnRAvgPeriod       = 30;       // Periode SnR Averaging (dikali jumlah posisi)
input double   InpSnRTolerance       = 0.5;      // Toleransi Sentuh SnR

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
   double floating_buy = 0, floating_sell = 0;
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
            floating_buy += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
            buy_count++; sum_buy_volume += vol; sum_buy_value += (price * vol);
            if(time >= latest_buy_time) { latest_buy_time = time; last_buy_price = price; }
            if(oldest_buy_time == 0 || time < oldest_buy_time) { oldest_buy_time = time; initial_buy_lot = vol; }
           }
         else if(type == POSITION_TYPE_SELL)
           {
            floating_sell += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
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
      if(!trade.Sell(CalculateLot(InpInitialLot), _Symbol, bid, 0, 0, "First Auto Sell"))
         Print("Gagal First Auto Sell: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
     }

   if(buy_count == 0 && is_trading_time && is_sideways && ask > safe_buy_price)
     {
      if(!trade.Buy(CalculateLot(InpInitialLot), _Symbol, ask, 0, 0, "First Auto Buy"))
         Print("Gagal First Auto Buy: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
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
      double tp;
      string tp_mode_sell = "";

      // Logika Penentuan 3 Level Take Profit SELL
      if(sell_count == 1)
        {
         tp = bep - InpTakeProfitSingle;
         tp_mode_sell = "Mode Single Posisi";
        }
      else if(sell_count >= InpAktifTPBEP2Posisi)
        {
         tp = bep - InpTakeProfitBEP2;
         tp_mode_sell = "Mode Averaging (BEP 2 - Rescue)";
        }
      else
        {
         tp = bep - InpTakeProfitBEP1;
         tp_mode_sell = "Mode Averaging (BEP 1)";
        }

      // Hitung Jarak Dinamis (melebar tiap penambahan posisi)
      double current_dynamic_distance = InpGridDistance * MathPow(InpGridMultiplier, sell_count - 1);
      double next_sell_price = last_sell_price + current_dynamic_distance;

      // Smart SnR Filter: periode dilipatgandakan sesuai jumlah posisi,
      // hanya melihat data historis SEBELUM posisi pertama terbuka
      int current_snr_period = InpSnRAvgPeriod * sell_count;
      double current_resistance = GetHighestHigh(_Symbol, PERIOD_CURRENT, current_snr_period, oldest_sell_time);
      bool is_near_resistance = (current_resistance > 0 && bid >= (current_resistance - InpSnRTolerance));

      dashboard += "--- STATUS SELL ---\n";
      dashboard += "Total Posisi: " + IntegerToString(sell_count) + " / " + IntegerToString(InpMaxPositions) + " (" + tp_mode_sell + ")\n";
      dashboard += "Total Lot: " + DoubleToString(sum_sell_volume, 2) + " | Floating: $" + DoubleToString(floating_sell, 2) + "\n";
      dashboard += "Syarat Jarak Buka Berikutnya: " + DoubleToString(next_sell_price, _Digits) + "\n";
      dashboard += "Resistance (SnR " + IntegerToString(current_snr_period) + " Candle): " + DoubleToString(current_resistance, _Digits) + (is_near_resistance ? " [TERCAPAI]" : "") + "\n";
      dashboard += "Harga BEP Rata-rata: " + DoubleToString(bep, _Digits) + "\n";
      dashboard += "Target Close (TP) di Harga: " + DoubleToString(tp, _Digits) + "\n\n";

      // Buka Posisi Martingale Baru
      if(sell_count < InpMaxPositions && last_sell_price > 0 && bid >= next_sell_price && is_near_resistance)
        {
         double new_lot = CalculateLot(initial_sell_lot * MathPow(InpLotMultiplier, sell_count));
         if(!trade.Sell(new_lot, _Symbol, bid, 0, 0, "Auto Averaging Sell"))
            Print("Gagal Averaging Sell: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
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
      double tp;
      string tp_mode_buy = "";

      // Logika Penentuan 3 Level Take Profit BUY
      if(buy_count == 1)
        {
         tp = bep + InpTakeProfitSingle;
         tp_mode_buy = "Mode Single Posisi";
        }
      else if(buy_count >= InpAktifTPBEP2Posisi)
        {
         tp = bep + InpTakeProfitBEP2;
         tp_mode_buy = "Mode Averaging (BEP 2 - Rescue)";
        }
      else
        {
         tp = bep + InpTakeProfitBEP1;
         tp_mode_buy = "Mode Averaging (BEP 1)";
        }

      // Hitung Jarak Dinamis (melebar tiap penambahan posisi)
      double current_dynamic_distance = InpGridDistance * MathPow(InpGridMultiplier, buy_count - 1);
      double next_buy_price = last_buy_price - current_dynamic_distance;

      // Smart SnR Filter: periode dilipatgandakan sesuai jumlah posisi,
      // hanya melihat data historis SEBELUM posisi pertama terbuka
      int current_snr_period = InpSnRAvgPeriod * buy_count;
      double current_support = GetLowestLow(_Symbol, PERIOD_CURRENT, current_snr_period, oldest_buy_time);
      bool is_near_support = (current_support > 0 && ask <= (current_support + InpSnRTolerance));

      dashboard += "--- STATUS BUY ---\n";
      dashboard += "Total Posisi: " + IntegerToString(buy_count) + " / " + IntegerToString(InpMaxPositions) + " (" + tp_mode_buy + ")\n";
      dashboard += "Total Lot: " + DoubleToString(sum_buy_volume, 2) + " | Floating: $" + DoubleToString(floating_buy, 2) + "\n";
      dashboard += "Syarat Jarak Buka Berikutnya: " + DoubleToString(next_buy_price, _Digits) + "\n";
      dashboard += "Support (SnR " + IntegerToString(current_snr_period) + " Candle): " + DoubleToString(current_support, _Digits) + (is_near_support ? " [TERCAPAI]" : "") + "\n";
      dashboard += "Harga BEP Rata-rata: " + DoubleToString(bep, _Digits) + "\n";
      dashboard += "Target Close (TP) di Harga: " + DoubleToString(tp, _Digits) + "\n\n";

      // Buka Posisi Martingale Baru
      if(buy_count < InpMaxPositions && last_buy_price > 0 && ask <= next_buy_price && is_near_support)
        {
         double new_lot = CalculateLot(initial_buy_lot * MathPow(InpLotMultiplier, buy_count));
         if(!trade.Buy(new_lot, _Symbol, ask, 0, 0, "Auto Averaging Buy"))
            Print("Gagal Averaging Buy: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
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

// --- FUNGSI SNR AVERAGING: HARGA TERTINGGI SEBELUM POSISI PERTAMA ---
double GetHighestHigh(string symbol, ENUM_TIMEFRAMES timeframe, int period, datetime ref_time)
  {
   int shift = 1; // Default
   if(ref_time > 0)
     {
      shift = iBarShift(symbol, timeframe, ref_time);
      if(shift < 0) shift = 0;
     }

   double high[];
   ArraySetAsSeries(high, true);
   int copied = CopyHigh(symbol, timeframe, shift + 1, period, high); // Dimulai sebelum candle posisi pertama
   if(copied > 0)
     {
      int max_idx = ArrayMaximum(high, 0, copied);
      return high[max_idx];
     }
   return 0;
  }

// --- FUNGSI SNR AVERAGING: HARGA TERENDAH SEBELUM POSISI PERTAMA ---
double GetLowestLow(string symbol, ENUM_TIMEFRAMES timeframe, int period, datetime ref_time)
  {
   int shift = 1; // Default
   if(ref_time > 0)
     {
      shift = iBarShift(symbol, timeframe, ref_time);
      if(shift < 0) shift = 0;
     }

   double low[];
   ArraySetAsSeries(low, true);
   int copied = CopyLow(symbol, timeframe, shift + 1, period, low); // Dimulai sebelum candle posisi pertama
   if(copied > 0)
     {
      int min_idx = ArrayMinimum(low, 0, copied);
      return low[min_idx];
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
