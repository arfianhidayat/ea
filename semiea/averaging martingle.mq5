//+------------------------------------------------------------------+
//|                                          SemiAuto_Grid_Flat.mq5  |
//|                                     Versi 2.4 (Grid Flat Lot)    |
//+------------------------------------------------------------------+
//| CARA KERJA EA (SEMI-OTOMATIS):                                   |
//| 1. Posisi Pertama (Initial Trade): Dibuka secara manual oleh     |
//|    user (magic 0) atau oleh EA ini. EA mengelola semua posisi    |
//|    di simbol ini yang ber-magic 0 atau InpMagicNumber.           |
//| 2. Jarak Averaging Dinamis: jarak level ke-N =                   |
//|    InpGridDistance x InpGridMultiplier^(N-1), makin melebar.     |
//| 3. Lot Averaging FLAT: setiap posisi tambahan memakai lot yang   |
//|    sama dengan posisi pertama (tanpa martingale).                |
//| 4. Multi-Level Take Profit: TP mengecil secara bertahap (Single, |
//|    Averaging, dan Rescue) agar cepat lolos dari market.          |
//| 5. Semua order dicek hasilnya; jika gagal dicetak ke log Expert. |
//+------------------------------------------------------------------+
#property copyright "Strategi Trading"
#property link      "https://www.mql5.com"
#property version   "2.40"

#include <Trade\Trade.mqh>

//--- Input Parameters ---
input double   InpGridDistance       = 2.0;      // Jarak Averaging Dasar (satuan harga)
input double   InpGridMultiplier     = 1.2;      // Pengali Jarak per level (melebar)
input int      InpMaxPositions       = 99;       // Maksimal Posisi per arah
input double   InpTakeProfitSingle   = 1.0;      // TP jika hanya 1 posisi
input double   InpTakeProfitBEP1     = 0.8;      // TP dari BEP saat averaging (BEP 1)
input int      InpAktifTPBEP2Posisi  = 4;        // Aktif TP Rescue mulai posisi ke-
input double   InpTakeProfitBEP2     = 0.6;      // TP dari BEP mode Rescue (BEP 2)
input ulong    InpMagicNumber        = 88888;    // Magic Number EA

CTrade trade;

int OnInit()
  {
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(50); // Toleransi slippage
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   Comment("");
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
   string dashboard = "=== EA SEMI-AUTO GRID (FLAT LOT) v2.4 ===\n";
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

      dashboard += "--- STATUS SELL ---\n";
      dashboard += "Total Posisi: " + IntegerToString(sell_count) + " / " + IntegerToString(InpMaxPositions) + " (" + tp_mode_sell + ")\n";
      dashboard += "Total Lot: " + DoubleToString(sum_sell_volume, 2) + " | Floating: $" + DoubleToString(floating_sell, 2) + "\n";
      dashboard += "Waktu Trade Awal: " + TimeToString(oldest_sell_time, TIME_DATE|TIME_MINUTES) + "\n";
      dashboard += "Harga Open Terakhir: " + DoubleToString(last_sell_price, _Digits) + "\n";
      dashboard += "Syarat Jarak Buka Berikutnya: " + DoubleToString(next_sell_price, _Digits) + "\n";
      dashboard += "Harga Market Saat Ini: " + DoubleToString(bid, _Digits) + "\n";
      dashboard += "Jarak Floating Saat Ini: " + DoubleToString(current_distance, _Digits) + "\n";
      dashboard += "Harga BEP Rata-rata: " + DoubleToString(bep_sell, _Digits) + "\n";
      dashboard += "Target Close (TP) di Harga: " + DoubleToString(target_price_sell, _Digits) + "\n";

      // Buka Posisi Averaging Baru
      if(sell_count < InpMaxPositions && bid >= next_sell_price)
        {
         // Lot averaging sama dengan lot posisi pertama
         double new_lot = CalculateLot(initial_sell_lot);
         if(!trade.Sell(new_lot, _Symbol, bid, 0, 0, "Auto Averaging Sell"))
            Print("Gagal Averaging Sell: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
        }

      // Tutup Semua Posisi Saat Harga Turun ke Target
      if(ask <= target_price_sell)
        {
         CloseAll(POSITION_TYPE_SELL);
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

      dashboard += "--- STATUS BUY ---\n";
      dashboard += "Total Posisi: " + IntegerToString(buy_count) + " / " + IntegerToString(InpMaxPositions) + " (" + tp_mode_buy + ")\n";
      dashboard += "Total Lot: " + DoubleToString(sum_buy_volume, 2) + " | Floating: $" + DoubleToString(floating_buy, 2) + "\n";
      dashboard += "Waktu Trade Awal: " + TimeToString(oldest_buy_time, TIME_DATE|TIME_MINUTES) + "\n";
      dashboard += "Harga Open Terakhir: " + DoubleToString(last_buy_price, _Digits) + "\n";
      dashboard += "Syarat Jarak Buka Berikutnya: " + DoubleToString(next_buy_price, _Digits) + "\n";
      dashboard += "Harga Market Saat Ini: " + DoubleToString(ask, _Digits) + "\n";
      dashboard += "Jarak Floating Saat Ini: " + DoubleToString(current_distance, _Digits) + "\n";
      dashboard += "Harga BEP Rata-rata: " + DoubleToString(bep_buy, _Digits) + "\n";
      dashboard += "Target Close (TP) di Harga: " + DoubleToString(target_price_buy, _Digits) + "\n";

      // Buka Posisi Averaging Baru
      if(buy_count < InpMaxPositions && ask <= next_buy_price)
        {
         // Lot averaging sama dengan lot posisi pertama
         double new_lot = CalculateLot(initial_buy_lot);
         if(!trade.Buy(new_lot, _Symbol, ask, 0, 0, "Auto Averaging Buy"))
            Print("Gagal Averaging Buy: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
        }

      // Tutup Semua Posisi Saat Harga Naik ke Target
      if(bid >= target_price_buy)
        {
         CloseAll(POSITION_TYPE_BUY);
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
            if(PositionGetInteger(POSITION_TYPE) == pos_type)
              {
               if(!trade.PositionClose(ticket))
                  Print("Gagal close ticket ", ticket, ": ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
              }
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

