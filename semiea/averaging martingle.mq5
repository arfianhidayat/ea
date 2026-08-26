//+------------------------------------------------------------------+
//|                                     SemiAuto_Martingale_Grid.mq5 |
//|                                     Versi 2.3 (Pro Scalper M1)   |
//+------------------------------------------------------------------+
//| CARA KERJA EA (PRO SCALPING M1):                                 |
//| 1. Posisi Pertama (Initial Trade): Dibuka secara manual oleh     |
//|    user. EA akan mengambil alih jika posisi tersebut floating -. |
//| 2. Jarak Averaging Dinamis: Menggunakan multiplier jarak agar    |
//|    jarak antar posisi makin melebar jika tren berlawanan kuat.   |
//| 3. Smart SnR Filter (Anti-Breakout):                             |
//|    - Buka averaging HANYA jika harga menyentuh Support/Resistance|
//|    - Periode SnR dilipatgandakan sesuai jumlah posisi (Posisi ke-|
//|      3 melihat SnR lebih jauh dibanding posisi ke-2).            |
//|    - SnR HANYA melihat data historis SEBELUM posisi pertama      |
//|      terbuka, sehingga kebal terhadap tipuan candle breakout.    |
//| 4. Multi-Level Take Profit: TP mengecil secara bertahap (Single, |
//|    Averaging, dan Rescue) agar cepat lolos dari market.          |
//+------------------------------------------------------------------+
#property copyright "Strategi Trading"
#property link      "https://www.mql5.com"
#property version   "2.30" // Update versi: Pro Scalper M1 & Dynamic SnR

#include <Trade\Trade.mqh>

//--- Input Parameters (SETINGAN SCALPING M1) ---
input double   InpGridDistance       = 4.0;      // Jarak Buka Posisi Awal (Lebih rapat)
input double   InpGridMultiplier     = 1.4;      // Pengali Jarak (Cepat melebar agar aman)
input int      InpMaxPositions       = 99;        // Maksimal Posisi Averaging (Batas Aman)
input int      InpSnRPeriod          = 15;       // Periode SnR M1 (15 Menit terakhir)
input double   InpSnRTolerance       = 0.5;      // Toleransi SnR diperkecil
input double   InpTakeProfitSingle   = 1.5;      // TP Posisi Tunggal (Sangat Kecil & Cepat)
input double   InpTakeProfitBEP1     = 0.7;      // TP Averaging Awal (Cepat Keluar)
input int      InpAktifTPBEP2Posisi  = 4;        // Aktif TP Rescue pada Posisi ke-
input double   InpTakeProfitBEP2     = 0.4;     // TP Penyelamatan (Hanya Balik Modal + Extra Tipis)
input double   InpLotMultiplier      = 1.3;      // Multiplier Martingale
input ulong    InpMagicNumber        = 88888;    // Magic Number EA

CTrade trade;

int OnInit()
  {
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(50); // Toleransi slippage
   return(INIT_SUCCEEDED);
  }

void OnTick()
  {
   int buy_count = 0;
   int sell_count = 0;
   
   double sum_buy_volume = 0, sum_buy_value = 0;
   double sum_sell_volume = 0, sum_sell_value = 0;
   
   double last_buy_price = 0, last_sell_price = 0;
   
   // Tambahan Variabel untuk menyimpan Lot Awal dan Profit
   double initial_buy_lot = 0, initial_sell_lot = 0;
   double floating_buy = 0, floating_sell = 0;
   datetime latest_buy_time = 0, latest_sell_time = 0;
   datetime oldest_buy_time = 0, oldest_sell_time = 0;
   
   // 1. Membaca Posisi Terbuka
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionGetString(POSITION_SYMBOL) == _Symbol)
        {
         ulong magic = PositionGetInteger(POSITION_MAGIC);
         if(magic == 0 || magic == InpMagicNumber)
           {
            long type = PositionGetInteger(POSITION_TYPE);
            double price = PositionGetDouble(POSITION_PRICE_OPEN);
            double vol = PositionGetDouble(POSITION_VOLUME);
            datetime time = (datetime)PositionGetInteger(POSITION_TIME);
            
            if(type == POSITION_TYPE_BUY)
              {
               floating_buy += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
               buy_count++; sum_buy_volume += vol; sum_buy_value += (price * vol); 
               
               // Mencari Harga Terakhir (Untuk Jarak Grid)
               if(time >= latest_buy_time) { latest_buy_time = time; last_buy_price = price; }
               // Mencari Lot Awal (Posisi Paling Lama) untuk rumus eksponensial
               if(oldest_buy_time == 0 || time < oldest_buy_time) { oldest_buy_time = time; initial_buy_lot = vol; }
              }
            else if(type == POSITION_TYPE_SELL)
              {
               floating_sell += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
               sell_count++; sum_sell_volume += vol; sum_sell_value += (price * vol); 
               
               // Mencari Harga Terakhir (Untuk Jarak Grid)
               if(time >= latest_sell_time) { latest_sell_time = time; last_sell_price = price; }
               // Mencari Lot Awal (Posisi Paling Lama) untuk rumus eksponensial
               if(oldest_sell_time == 0 || time < oldest_sell_time) { oldest_sell_time = time; initial_sell_lot = vol; }
              }
           }
        }
     }
     
   // --- DASHBOARD DIAGNOSTIK ---
   string dashboard = "=== EA PRO SCALPER M1 ===\n";
   dashboard += "Jarak Dasar: " + DoubleToString(InpGridDistance, 2) + " | TP: " + DoubleToString(InpTakeProfitSingle, 2) + " / " + DoubleToString(InpTakeProfitBEP1, 2) + " / " + DoubleToString(InpTakeProfitBEP2, 2) + "\n";
   dashboard += "==================================\n";
   dashboard += "Balance      : $" + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2) + "\n";
   dashboard += "Equity       : $" + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2) + "\n";
   dashboard += "Margin Level : " + DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN_LEVEL), 2) + "%\n";
   dashboard += "==================================\n\n";
   
   // 2. Eksekusi SELL
   if(sell_count > 0)
     {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID); 
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK); 
      
      double bep_sell = sum_sell_value / sum_sell_volume; 
      double target_price_sell;
      string tp_mode_sell = "";
      
      // Logika Penentuan 3 Level Take Profit SELL
      if(sell_count == 1)
        {
         target_price_sell = bep_sell - InpTakeProfitSingle;
         tp_mode_sell = "Mode Single Posisi";
        }
      else if(sell_count >= InpAktifTPBEP2Posisi)
        {
         target_price_sell = bep_sell - InpTakeProfitBEP2;
         tp_mode_sell = "Mode Averaging (BEP 2 - Rescue)";
        }
      else
        {
         target_price_sell = bep_sell - InpTakeProfitBEP1;
         tp_mode_sell = "Mode Averaging (BEP 1)";
        }
        
      // Hitung Jarak Dinamis
      double current_dynamic_distance = InpGridDistance * MathPow(InpGridMultiplier, sell_count - 1);
      double next_sell_price = last_sell_price + current_dynamic_distance;
      double current_distance = bid - last_sell_price;
      
      // Hitung Periode SnR Dinamis
      int current_snr_period = InpSnRPeriod * sell_count;
      
      // Hitung Resistance untuk Filter SnR
      double current_resistance = GetHighestHigh(_Symbol, PERIOD_CURRENT, current_snr_period, oldest_sell_time);
      bool is_near_resistance = (bid >= (current_resistance - InpSnRTolerance));
      
      dashboard += "--- STATUS SELL ---\n";
      dashboard += "Total Posisi: " + IntegerToString(sell_count) + " / " + IntegerToString(InpMaxPositions) + " (" + tp_mode_sell + ")\n";
      dashboard += "Total Lot: " + DoubleToString(sum_sell_volume, 2) + " | Floating: $" + DoubleToString(floating_sell, 2) + "\n";
      dashboard += "Waktu Trade Awal: " + TimeToString(oldest_sell_time, TIME_DATE|TIME_MINUTES) + "\n";
      dashboard += "Harga Open Terakhir: " + DoubleToString(last_sell_price, 3) + "\n";
      dashboard += "Syarat Jarak Buka Berikutnya: " + DoubleToString(next_sell_price, 3) + "\n";
      dashboard += "Resistance (SnR " + IntegerToString(current_snr_period) + " Candle): " + DoubleToString(current_resistance, 3) + (is_near_resistance ? " [TERCAPAI]" : "") + "\n";
      dashboard += "Harga Market Saat Ini: " + DoubleToString(bid, 3) + "\n";
      dashboard += "Jarak Floating Saat Ini: " + DoubleToString(current_distance, 3) + "\n";
      dashboard += "Harga BEP Rata-rata: " + DoubleToString(bep_sell, 3) + "\n";
      dashboard += "Target Close (TP) di Harga: " + DoubleToString(target_price_sell, 3) + "\n";
      
      // Buka Posisi Martingale Baru 
      if(sell_count < InpMaxPositions && bid >= next_sell_price && is_near_resistance)
        {
         // Rumus: Lot Awal * (Multiplier ^ Jumlah Posisi Saat Ini)
         double exact_calculated_lot = initial_sell_lot * MathPow(InpLotMultiplier, sell_count);
         double new_lot = CalculateLot(exact_calculated_lot);
         trade.Sell(new_lot, _Symbol, bid, 0, 0, "Auto Averaging Sell");
        }
        
      // Tutup Semua Posisi Saat Harga Turun ke Target
      if(ask <= target_price_sell)
        {
         CloseAll(POSITION_TYPE_SELL);
         sell_count = 0; 
        }
     }
     
   // 3. Eksekusi BUY
   if(buy_count > 0)
     {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID); 
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK); 
      
      double bep_buy = sum_buy_value / sum_buy_volume; 
      double target_price_buy;
      string tp_mode_buy = "";
      
      // Logika Penentuan 3 Level Take Profit BUY
      if(buy_count == 1)
        {
         target_price_buy = bep_buy + InpTakeProfitSingle;
         tp_mode_buy = "Mode Single Posisi";
        }
      else if(buy_count >= InpAktifTPBEP2Posisi)
        {
         target_price_buy = bep_buy + InpTakeProfitBEP2;
         tp_mode_buy = "Mode Averaging (BEP 2 - Rescue)";
        }
      else
        {
         target_price_buy = bep_buy + InpTakeProfitBEP1;
         tp_mode_buy = "Mode Averaging (BEP 1)";
        }
        
      // Hitung Jarak Dinamis
      double current_dynamic_distance = InpGridDistance * MathPow(InpGridMultiplier, buy_count - 1);
      double next_buy_price = last_buy_price - current_dynamic_distance;
      double current_distance = last_buy_price - ask;
      
      // Hitung Periode SnR Dinamis
      int current_snr_period = InpSnRPeriod * buy_count;
      
      // Hitung Support untuk Filter SnR
      double current_support = GetLowestLow(_Symbol, PERIOD_CURRENT, current_snr_period, oldest_buy_time);
      bool is_near_support = (ask <= (current_support + InpSnRTolerance));
      
      dashboard += "--- STATUS BUY ---\n";
      dashboard += "Total Posisi: " + IntegerToString(buy_count) + " / " + IntegerToString(InpMaxPositions) + " (" + tp_mode_buy + ")\n";
      dashboard += "Total Lot: " + DoubleToString(sum_buy_volume, 2) + " | Floating: $" + DoubleToString(floating_buy, 2) + "\n";
      dashboard += "Waktu Trade Awal: " + TimeToString(oldest_buy_time, TIME_DATE|TIME_MINUTES) + "\n";
      dashboard += "Harga Open Terakhir: " + DoubleToString(last_buy_price, 3) + "\n";
      dashboard += "Syarat Jarak Buka Berikutnya: " + DoubleToString(next_buy_price, 3) + "\n";
      dashboard += "Support (SnR " + IntegerToString(current_snr_period) + " Candle): " + DoubleToString(current_support, 3) + (is_near_support ? " [TERCAPAI]" : "") + "\n";
      dashboard += "Harga Market Saat Ini: " + DoubleToString(ask, 3) + "\n";
      dashboard += "Jarak Floating Saat Ini: " + DoubleToString(current_distance, 3) + "\n";
      dashboard += "Harga BEP Rata-rata: " + DoubleToString(bep_buy, 3) + "\n";
      dashboard += "Target Close (TP) di Harga: " + DoubleToString(target_price_buy, 3) + "\n";
      
      // Buka Posisi Martingale Baru 
      if(buy_count < InpMaxPositions && ask <= next_buy_price && is_near_support)
        {
         // Rumus: Lot Awal * (Multiplier ^ Jumlah Posisi Saat Ini)
         double exact_calculated_lot = initial_buy_lot * MathPow(InpLotMultiplier, buy_count);
         double new_lot = CalculateLot(exact_calculated_lot);
         trade.Buy(new_lot, _Symbol, ask, 0, 0, "Auto Averaging Buy");
        }
        
      // Tutup Semua Posisi Saat Harga Naik ke Target
      if(bid >= target_price_buy)
        {
         CloseAll(POSITION_TYPE_BUY);
         buy_count = 0; 
        }
     }
     
   Comment(dashboard);
  }

void CloseAll(long pos_type)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionGetString(POSITION_SYMBOL) == _Symbol)
        {
         ulong magic = PositionGetInteger(POSITION_MAGIC);
         if(magic == 0 || magic == InpMagicNumber)
           {
            if(PositionGetInteger(POSITION_TYPE) == pos_type) { trade.PositionClose(ticket); }
           }
        }
     }
  }

double CalculateLot(double calculated_lot)
  {
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double final_lot = MathRound(calculated_lot / step) * step;
   if(final_lot < min_lot) final_lot = min_lot;
   if(final_lot > max_lot) final_lot = max_lot;
   return final_lot;
  }

//+------------------------------------------------------------------+
//| Fungsi Bantuan: Mendapatkan Harga Tertinggi (Resistance)         |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| Fungsi Bantuan: Mendapatkan Harga Terendah (Support)             |
//+------------------------------------------------------------------+
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

