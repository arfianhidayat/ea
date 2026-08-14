//+------------------------------------------------------------------+
//|                                     SemiAuto_Martingale_Grid.mq5 |
//|                                     Versi 2.2 (Direct Price)     |
//+------------------------------------------------------------------+
#property copyright "Strategi Trading"
#property link      "https://www.mql5.com"
#property version   "2.20"

#include <Trade\Trade.mqh>

//--- Input Parameters ---
input double   InpGridDistance       = 5.0;      // Jarak Buka Posisi (Contoh: 5.0)
input double   InpTakeProfitSingle   = 5.0;      // Take Profit jika HANYA 1 Posisi
input double   InpTakeProfitBEP1     = 2.0;      // Take Profit BEP 1 (Averaging Awal)
input int      InpAktifTPBEP2Posisi  = 5;        // Aktif TP BEP 2 pada Posisi ke-
input double   InpTakeProfitBEP2     = 1.0;      // Take Profit BEP 2 (Averaging Lanjut)
input double   InpLotMultiplier      = 2.0;      // Multiplier Martingale (Contoh: 2.0)
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
   double last_buy_lot = 0, last_sell_lot = 0;
   
   datetime latest_buy_time = 0, latest_sell_time = 0;
   
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
               if(time >= latest_buy_time) { latest_buy_time = time; last_buy_price = price; last_buy_lot = vol; }
              }
            else if(type == POSITION_TYPE_SELL)
              {
               sell_count++; sum_sell_volume += vol; sum_sell_value += (price * vol); 
               if(time >= latest_sell_time) { latest_sell_time = time; last_sell_price = price; last_sell_lot = vol; }
              }
           }
        }
     }
     
   // --- DASHBOARD DIAGNOSTIK ---
   string dashboard = "=== EA MARTINGALE (DIRECT PRICE) ===\n";
   dashboard += "Jarak Averaging Disetel: " + DoubleToString(InpGridDistance, 2) + "\n";
   dashboard += "TP 1 Posisi: " + DoubleToString(InpTakeProfitSingle, 2) + "\n";
   dashboard += "TP BEP 1: " + DoubleToString(InpTakeProfitBEP1, 2) + " | TP BEP 2: " + DoubleToString(InpTakeProfitBEP2, 2) + " (Mulai Posisi ke-" + IntegerToString(InpAktifTPBEP2Posisi) + ")\n\n";
   
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
        
      double next_sell_price = last_sell_price + InpGridDistance;
      double current_distance = bid - last_sell_price;
      
      dashboard += "--- STATUS SELL ---\n";
      dashboard += "Total Posisi: " + IntegerToString(sell_count) + " (" + tp_mode_sell + ")\n";
      dashboard += "Harga Open Terakhir: " + DoubleToString(last_sell_price, 3) + "\n";
      dashboard += "Harga Buka Selanjutnya: " + DoubleToString(next_sell_price, 3) + "\n";
      dashboard += "Harga Market Saat Ini: " + DoubleToString(bid, 3) + "\n";
      dashboard += "Jarak Floating Saat Ini: " + DoubleToString(current_distance, 3) + "\n";
      dashboard += "Harga BEP Rata-rata: " + DoubleToString(bep_sell, 3) + "\n";
      dashboard += "Target Close (TP) di Harga: " + DoubleToString(target_price_sell, 3) + "\n";
      
      // Buka Posisi Martingale Baru
      if(bid >= next_sell_price)
        {
         double new_lot = CalculateLot(last_sell_lot * InpLotMultiplier);
         trade.Sell(new_lot, _Symbol, bid, 0, 0, "Auto Averaging Sell");
        }
        
      // Tutup Semua Posisi Saat Harga Turun ke Target
      if(ask <= target_price_sell)
        {
         CloseAll(POSITION_TYPE_SELL);
         sell_count = 0; 
        }
     }
     
   // 3. Eksekusi BUY (Kebalikan dari Sell)
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
        
      double next_buy_price = last_buy_price - InpGridDistance;
      double current_distance = last_buy_price - ask;
      
      dashboard += "--- STATUS BUY ---\n";
      dashboard += "Total Posisi: " + IntegerToString(buy_count) + " (" + tp_mode_buy + ")\n";
      dashboard += "Harga Open Terakhir: " + DoubleToString(last_buy_price, 3) + "\n";
      dashboard += "Harga Buka Selanjutnya: " + DoubleToString(next_buy_price, 3) + "\n";
      dashboard += "Harga Market Saat Ini: " + DoubleToString(ask, 3) + "\n";
      dashboard += "Jarak Floating Saat Ini: " + DoubleToString(current_distance, 3) + "\n";
      dashboard += "Harga BEP Rata-rata: " + DoubleToString(bep_buy, 3) + "\n";
      dashboard += "Target Close (TP) di Harga: " + DoubleToString(target_price_buy, 3) + "\n";
      
      // Buka Posisi Martingale Baru
      if(ask <= next_buy_price)
        {
         double new_lot = CalculateLot(last_buy_lot * InpLotMultiplier);
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
