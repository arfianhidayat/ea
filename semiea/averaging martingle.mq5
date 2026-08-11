//+------------------------------------------------------------------+
//|                                     SemiAuto_Martingale_Grid.mq5 |
//|                                  Dibuat untuk Strategi Trading   |
//+------------------------------------------------------------------+
#property copyright "Strategi Trading"
#property link      "https://www.mql5.com"
#property version   "1.20"

#include <Trade\Trade.mqh>

//--- Input Parameters ---
input double   InpGridDistance   = 100;      // Jarak Grid (Input 100 = Jarak Harga 10.00)
input double   InpTargetPoints   = 100;      // Target Profit (Input 100 = Jarak Harga 10.00)
input double   InpPriceMultiplier= 0.1;      // Faktor Pengali Jarak (100 x 0.1 = 10.00)
input double   InpLotMultiplier  = 2.0;      // Multiplier Martingale (cth: 2.0)
input ulong    InpMagicNumber    = 88888;    // Magic Number EA

CTrade trade;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(InpMagicNumber);
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   int buy_count = 0;
   int sell_count = 0;
   
   double sum_buy_volume = 0;
   double sum_buy_value = 0;
   
   double sum_sell_volume = 0;
   double sum_sell_value = 0;
   
   double last_buy_price = 0;
   double last_sell_price = 0;
   
   double last_buy_lot = 0;
   double last_sell_lot = 0;
   
   datetime latest_buy_time = 0;
   datetime latest_sell_time = 0;
   
   // 1. Membaca Seluruh Posisi Terbuka (Manual & EA)
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionGetString(POSITION_SYMBOL) == _Symbol)
        {
         ulong magic = PositionGetInteger(POSITION_MAGIC);
         
         // Memproses order manual (Magic=0) ATAU order buatan EA ini
         if(magic == 0 || magic == InpMagicNumber)
           {
            long type = PositionGetInteger(POSITION_TYPE);
            double price = PositionGetDouble(POSITION_PRICE_OPEN);
            double vol = PositionGetDouble(POSITION_VOLUME);
            datetime time = (datetime)PositionGetInteger(POSITION_TIME);
            
            if(type == POSITION_TYPE_BUY)
              {
               buy_count++;
               sum_buy_volume += vol;
               sum_buy_value += (price * vol); 
               
               if(time > latest_buy_time)
                 {
                  latest_buy_time = time;
                  last_buy_price = price;
                  last_buy_lot = vol;
                 }
              }
            else if(type == POSITION_TYPE_SELL)
              {
               sell_count++;
               sum_sell_volume += vol;
               sum_sell_value += (price * vol); 
               
               if(time > latest_sell_time)
                 {
                  latest_sell_time = time;
                  last_sell_price = price;
                  last_sell_lot = vol;
                 }
              }
           }
        }
     }
     
   // --- PERHITUNGAN JARAK ABSOLUT (Sesuai Skenario Anda) ---
   // Jika InpTargetPoints = 100 dan Multiplier = 0.1, maka jarak_riil = 10.00
   double target_distance_real = InpTargetPoints * InpPriceMultiplier; 
   double grid_distance_real   = InpGridDistance * InpPriceMultiplier;
     
   // 2. Eksekusi Take Profit (Basket Close)
   // LOGIKA BUY
   if(buy_count > 0)
     {
      double bep_buy = sum_buy_value / sum_buy_volume; 
      double target_price_buy = bep_buy + target_distance_real; 
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID); 
      
      if(bid >= target_price_buy)
        {
         CloseAll(POSITION_TYPE_BUY);
         buy_count = 0; 
        }
     }
     
   // LOGIKA SELL
   if(sell_count > 0)
     {
      double bep_sell = sum_sell_value / sum_sell_volume; 
      double target_price_sell = bep_sell - target_distance_real; 
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK); 
      
      if(ask <= target_price_sell)
        {
         CloseAll(POSITION_TYPE_SELL);
         sell_count = 0; 
        }
     }
     
   // 3. Eksekusi Pembukaan Posisi Baru (Martingale Grid)
   // BUY MARTINGALE
   if(buy_count > 0)
     {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      // Jika harga turun melampaui grid_distance_real (misal 10.00 poin) dari buy terakhir
      if(ask <= last_buy_price - grid_distance_real)
        {
         double new_lot = CalculateLot(last_buy_lot * InpLotMultiplier);
         trade.Buy(new_lot, _Symbol, ask, 0, 0, "Auto Averaging Buy");
        }
     }
     
   // SELL MARTINGALE
   if(sell_count > 0)
     {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      // Jika harga naik melampaui grid_distance_real (misal 10.00 poin) dari sell terakhir
      if(bid >= last_sell_price + grid_distance_real)
        {
         double new_lot = CalculateLot(last_sell_lot * InpLotMultiplier);
         trade.Sell(new_lot, _Symbol, bid, 0, 0, "Auto Averaging Sell");
        }
     }
  }

//+------------------------------------------------------------------+
//| Fungsi Penutupan Order Massal                                    |
//+------------------------------------------------------------------+
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
               trade.PositionClose(ticket);
              }
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Fungsi Kalkulasi Lot                                             |
//+------------------------------------------------------------------+
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
