//+------------------------------------------------------------------+
//|                                     SemiAuto_Martingale_Grid.mq5 |
//|                                     Versi 1.30 (Diagnostic)      |
//+------------------------------------------------------------------+
#property copyright "Strategi Trading"
#property link      "https://www.mql5.com"
#property version   "1.30"

#include <Trade\Trade.mqh>

//--- Input Parameters ---
input double   InpGridDistance   = 100;      // Jarak Grid (Input 100 = Jarak 10.00)
input double   InpTargetPoints   = 100;      // Target Profit (Input 100 = Jarak 10.00)
input double   InpPriceMultiplier= 0.1;      // Faktor Pengali (100 x 0.1 = 10.00)
input double   InpLotMultiplier  = 2.0;      // Multiplier Martingale
input ulong    InpMagicNumber    = 88888;    // Magic Number EA

CTrade trade;

int OnInit()
  {
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(50); // Tambahan toleransi slippage agar broker tidak reject
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
     
   double target_distance_real = InpTargetPoints * InpPriceMultiplier; 
   double grid_distance_real   = InpGridDistance * InpPriceMultiplier;
   
   // --- DASHBOARD DIAGNOSTIK UNTUK TRADER ---
   string dashboard = "=== DIAGNOSTIK EA MARTINGALE ===\n";
   dashboard += "Jarak Grid Disetel: " + DoubleToString(grid_distance_real, 2) + "\n";
   dashboard += "Total Posisi Sell: " + IntegerToString(sell_count) + "\n";
   
   // 2. Eksekusi & Update Dashboard Sell
   if(sell_count > 0)
     {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID); 
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK); 
      
      double bep_sell = sum_sell_value / sum_sell_volume; 
      double target_price_sell = bep_sell - target_distance_real; 
      double next_sell_price = last_sell_price + grid_distance_real;
      double current_distance = bid - last_sell_price;
      
      dashboard += "Harga Terakhir Buka (Sell): " + DoubleToString(last_sell_price, 3) + "\n";
      dashboard += "Harga Averaging Berikutnya: " + DoubleToString(next_sell_price, 3) + "\n";
      dashboard += "Harga Market (Bid) Saat Ini: " + DoubleToString(bid, 3) + "\n";
      dashboard += "Jarak Floating Saat Ini: " + DoubleToString(current_distance, 3) + " / " + DoubleToString(grid_distance_real, 2) + "\n";
      dashboard += "Target Basket Close (TP): " + DoubleToString(target_price_sell, 3) + "\n";
      
      // Martingale Eksekusi
      if(bid >= next_sell_price)
        {
         double new_lot = CalculateLot(last_sell_lot * InpLotMultiplier);
         if(!trade.Sell(new_lot, _Symbol, bid, 0, 0, "Auto Averaging Sell"))
           {
            Print("[-] GAGAL BUKA SELL! Error Broker: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
           }
        }
        
      // TP Eksekusi
      if(ask <= target_price_sell)
        {
         CloseAll(POSITION_TYPE_SELL);
         sell_count = 0; 
        }
     }
     
   // Tampilkan di Chart
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
