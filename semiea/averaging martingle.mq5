//+------------------------------------------------------------------+
//|                                     SemiAuto_Martingale_Grid.mq5 |
//|                                  Dibuat untuk Strategi Trading   |
//+------------------------------------------------------------------+
#property copyright "Strategi Trading"
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Trade\Trade.mqh>

//--- Input Parameters ---
input double   InpGridDistance   = 250;      // Jarak Grid (Points, cth: 250 = 25 pips)
input double   InpLotMultiplier  = 2.0;      // Multiplier Martingale (cth: 2.0)
input double   InpTargetProfit   = 10.0;     // Target Profit Basket (dalam USD/Currency)
input ulong    InpMagicNumber    = 88888;    // Magic Number EA (untuk order lanjutan)

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
   
   double total_buy_profit = 0;
   double total_sell_profit = 0;
   
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
            // Menghitung profit + swap agar akurat
            double profit = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
            datetime time = (datetime)PositionGetInteger(POSITION_TIME);
            
            if(type == POSITION_TYPE_BUY)
              {
               buy_count++;
               total_buy_profit += profit;
               // Mencari harga dan lot dari posisi Buy TERAKHIR dibuka
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
               total_sell_profit += profit;
               // Mencari harga dan lot dari posisi Sell TERAKHIR dibuka
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
     
   // 2. Eksekusi Take Profit (Basket Close)
   if(buy_count > 0 && total_buy_profit >= InpTargetProfit)
     {
      CloseAll(POSITION_TYPE_BUY);
      buy_count = 0; // Reset setelah ditutup
     }
     
   if(sell_count > 0 && total_sell_profit >= InpTargetProfit)
     {
      CloseAll(POSITION_TYPE_SELL);
      sell_count = 0; // Reset setelah ditutup
     }
     
   // 3. Eksekusi Pembukaan Posisi Baru (Martingale Grid)
   // BUY MARTINGALE
   if(buy_count > 0 && total_buy_profit < InpTargetProfit)
     {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      // Jika harga turun melampaui jarak grid dari buy terakhir
      if(ask <= last_buy_price - (InpGridDistance * _Point))
        {
         double new_lot = CalculateLot(last_buy_lot * InpLotMultiplier);
         trade.Buy(new_lot, _Symbol, ask, 0, 0, "Auto Averaging Buy");
        }
     }
     
   // SELL MARTINGALE
   if(sell_count > 0 && total_sell_profit < InpTargetProfit)
     {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      // Jika harga naik melampaui jarak grid dari sell terakhir
      if(bid >= last_sell_price + (InpGridDistance * _Point))
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
//| Fungsi Kalkulasi Lot (Menyesuaikan aturan broker)                |
//+------------------------------------------------------------------+
double CalculateLot(double calculated_lot)
  {
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   
   // Normalisasi lot agar tidak ditolak broker (misal: 0.165 jadi 0.16)
   double final_lot = MathRound(calculated_lot / step) * step;
   
   if(final_lot < min_lot) final_lot = min_lot;
   if(final_lot > max_lot) final_lot = max_lot;
   
   return final_lot;
  }
