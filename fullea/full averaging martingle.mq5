//+------------------------------------------------------------------+
//|                                         Auto_Martingale_Grid.mq5 |
//|                                         Versi 3.0 (Full Auto)    |
//+------------------------------------------------------------------+
#property copyright "Strategi Trading"
#property link      "https://www.mql5.com"
#property version   "3.00"

#include <Trade\Trade.mqh>

//--- Input Parameters ---
input double   InpInitialLot         = 0.01;     // Lot Awal (Posisi Pertama)
input double   InpGridDistance       = 5.0;      // Jarak Buka Posisi Averaging
input double   InpTakeProfitSingle   = 5.0;      // Take Profit jika HANYA 1 Posisi
input double   InpTakeProfitBEP1     = 2.0;      // Take Profit BEP 1 (Averaging Awal)
input int      InpAktifTPBEP2Posisi  = 5;        // Aktif TP BEP 2 pada Posisi ke-
input double   InpTakeProfitBEP2     = 1.0;      // Take Profit BEP 2 (Averaging Lanjut)
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
   
   double initial_buy_lot = 0, initial_sell_lot = 0;
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
     }
     
   // ==========================================
   // 2. LOGIKA FULL OTOMATIS (OPEN POSISI AWAL)
   // ==========================================
   
   // Jika tidak ada posisi SELL, buka SELL baru
   if(sell_count == 0)
     {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double start_lot = CalculateLot(InpInitialLot);
      trade.Sell(start_lot, _Symbol, bid, 0, 0, "First Auto Sell");
      sell_count++; // Update count secara simulasi agar tidak error di blok berikutnya
     }
     
   // Jika tidak ada posisi BUY, buka BUY baru
   if(buy_count == 0)
     {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double start_lot = CalculateLot(InpInitialLot);
      trade.Buy(start_lot, _Symbol, ask, 0, 0, "First Auto Buy");
      buy_count++; // Update count secara simulasi
     }


   // --- DASHBOARD DIAGNOSTIK ---
   string dashboard = "=== EA MARTINGALE (FULL AUTO) ===\n";
   dashboard += "Lot Awal (Start): " + DoubleToString(InpInitialLot, 2) + "\n";
   dashboard += "Jarak Averaging: " + DoubleToString(InpGridDistance, 2) + "\n";
   dashboard += "TP 1 Posisi: " + DoubleToString(InpTakeProfitSingle, 2) + "\n";
   dashboard += "TP BEP 1: " + DoubleToString(InpTakeProfitBEP1, 2) + " | TP BEP 2: " + DoubleToString(InpTakeProfitBEP2, 2) + " (Posisi ke-" + IntegerToString(InpAktifTPBEP2Posisi) + ")\n\n";
   
   // ==========================================
   // 3. LOGIKA AVERAGING & TAKE PROFIT SELL
   // ==========================================
   if(sell_count > 0 && sum_sell_volume > 0) // Pastikan ada volume agar tidak error dibagi 0
     {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID); 
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK); 
      
      double bep_sell = sum_sell_value / sum_sell_volume; 
      double target_price_sell;
      string tp_mode_sell = "";
      
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
        
      double next_sell_price = last_sell_price + InpGridDistance;
      double current_distance = bid - last_sell_price;
      
      dashboard += "--- STATUS SELL ---\n";
      dashboard += "Total Posisi: " + IntegerToString(sell_count) + " (" + tp_mode_sell + ")\n";
      dashboard += "Harga Open Terakhir: " + DoubleToString(last_sell_price, 3) + "\n";
      dashboard += "Harga Buka Selanjutnya: " + DoubleToString(next_sell_price, 3) + "\n";
      dashboard += "Harga BEP Rata-rata: " + DoubleToString(bep_sell, 3) + "\n";
      dashboard += "Target Close (TP): " + DoubleToString(target_price_sell, 3) + "\n";
      
      // Buka Posisi Martingale Baru (Hanya jika last_sell_price sudah terekam)
      if(last_sell_price > 0 && bid >= next_sell_price)
        {
         // Gunakan rumus pangkat agar lot membesar dengan benar
         double exact_calculated_lot = initial_sell_lot * MathPow(InpLotMultiplier, sell_count);
         double new_lot = CalculateLot(exact_calculated_lot);
         trade.Sell(new_lot, _Symbol, bid, 0, 0, "Auto Averaging Sell");
        }
        
      // Tutup Semua Posisi Saat Harga Turun ke Target
      if(ask <= target_price_sell && target_price_sell > 0)
        {
         CloseAll(POSITION_TYPE_SELL);
        }
     }
     
   // ==========================================
   // 4. LOGIKA AVERAGING & TAKE PROFIT BUY
   // ==========================================
   if(buy_count > 0 && sum_buy_volume > 0)
     {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID); 
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK); 
      
      double bep_buy = sum_buy_value / sum_buy_volume; 
      double target_price_buy;
      string tp_mode_buy = "";
      
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
        
      double next_buy_price = last_buy_price - InpGridDistance;
      double current_distance = last_buy_price - ask;
      
      dashboard += "--- STATUS BUY ---\n";
      dashboard += "Total Posisi: " + IntegerToString(buy_count) + " (" + tp_mode_buy + ")\n";
      dashboard += "Harga Open Terakhir: " + DoubleToString(last_buy_price, 3) + "\n";
      dashboard += "Harga Buka Selanjutnya: " + DoubleToString(next_buy_price, 3) + "\n";
      dashboard += "Harga BEP Rata-rata: " + DoubleToString(bep_buy, 3) + "\n";
      dashboard += "Target Close (TP): " + DoubleToString(target_price_buy, 3) + "\n";
      
      // Buka Posisi Martingale Baru (Hanya jika last_buy_price sudah terekam)
      if(last_buy_price > 0 && ask <= next_buy_price)
        {
         double exact_calculated_lot = initial_buy_lot * MathPow(InpLotMultiplier, buy_count);
         double new_lot = CalculateLot(exact_calculated_lot);
         trade.Buy(new_lot, _Symbol, ask, 0, 0, "Auto Averaging Buy");
        }
        
      // Tutup Semua Posisi Saat Harga Naik ke Target
      if(bid >= target_price_buy && target_price_buy > 0)
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
