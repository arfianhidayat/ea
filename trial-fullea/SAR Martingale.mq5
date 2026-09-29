//+------------------------------------------------------------------+
//|                                             SAR_Martingale.mq5   |
//|                                                Hak Cipta 2026    |
//+------------------------------------------------------------------+
#property copyright "Trader Saham & Forex"
#property version   "1.00"

#include <Trade\Trade.mqh>

//--- Variabel Input (Parameter Eksternal)
input double InitialLot      = 0.01;    // Lot Awal
input double LotMultiplier   = 2.0;     // Pengali Lot (Martingale)
input int    TakeProfit_Pips = 5;       // Target Profit (Pips)
input int    StopLoss_Pips   = 5;       // Stop Loss (Pips)
input ulong  Slippage        = 3;       // Slippage Maksimal (Points)
input ulong  MagicNumber     = 12345;   // Magic Number EA

CTrade trade;
double pipsToPoints;

//+------------------------------------------------------------------+
//| Fungsi Inisialisasi EA (Berjalan sekali saat EA dipasang)        |
//+------------------------------------------------------------------+
int OnInit()
  {
   // Mengatur Magic Number dan Slippage untuk eksekusi trade
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(Slippage);
   
   // Penyesuaian otomatis untuk broker 4-digit atau 5-digit
   if(_Digits == 5 || _Digits == 3)
      pipsToPoints = _Point * 10;
   else
      pipsToPoints = _Point;

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Fungsi Tick EA (Berjalan setiap kali ada perubahan harga)        |
//+------------------------------------------------------------------+
void OnTick()
  {
   // Periksa apakah EA sedang memiliki posisi terbuka
   if(CountOpenPositions() > 0) 
      return; // Jika masih ada posisi yang terbuka, tunggu hingga terkena TP atau SL

   // Variabel untuk menentukan arah dan lot posisi baru
   double nextLot = InitialLot;
   int nextDirection = ORDER_TYPE_BUY; // Default entry pertama kali adalah Buy

   // Analisa histori transaksi terakhir untuk menentukan logika SAR Martingale
   if(GetLastTradeInfo(nextDirection, nextLot))
     {
      // Jika ada histori trade sebelumnya, arah dan lot sudah diperbarui oleh fungsi
     }
   else
     {
      // Jika belum ada histori transaksi (EA baru dipasang), gunakan parameter default
      nextDirection = ORDER_TYPE_BUY;
      nextLot = InitialLot;
     }

   // Menormalkan ukuran lot sesuai batasan minimal dan maksimal broker
   nextLot = NormalizeLot(nextLot);

   // Mengambil harga Ask dan Bid saat ini
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   double sl = 0, tp = 0;
   
   // Eksekusi Always-In: Langsung buka posisi baru berdasarkan hasil kalkulasi
   if(nextDirection == ORDER_TYPE_BUY)
     {
      sl = ask - (StopLoss_Pips * pipsToPoints);
      tp = ask + (TakeProfit_Pips * pipsToPoints);
      trade.Buy(nextLot, _Symbol, ask, sl, tp, "SAR Martingale Buy");
     }
   else if(nextDirection == ORDER_TYPE_SELL)
     {
      sl = bid + (StopLoss_Pips * pipsToPoints);
      tp = bid - (TakeProfit_Pips * pipsToPoints);
      trade.Sell(nextLot, _Symbol, bid, sl, tp, "SAR Martingale Sell");
     }
  }

//+------------------------------------------------------------------+
//| Fungsi internal: Menghitung total posisi terbuka milik EA ini    |
//+------------------------------------------------------------------+
int CountOpenPositions()
  {
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
        {
         count++;
        }
     }
   return count;
  }

//+------------------------------------------------------------------+
//| Fungsi internal: Mengekstrak arah dan profit posisi terakhir     |
//+------------------------------------------------------------------+
bool GetLastTradeInfo(int &next_dir, double &next_lot)
  {
   // Memuat seluruh histori transaksi ke dalam memori
   HistorySelect(0, TimeCurrent());
   int totalDeals = HistoryDealsTotal();
   
   // Melakukan perulangan mundur untuk mencari transaksi terakhir
   for(int i = totalDeals - 1; i >= 0; i--)
     {
      ulong dealTicket = HistoryDealGetTicket(i);
      if(dealTicket > 0)
        {
         // Memastikan transaksi tersebut milik EA ini pada pair yang sama
         if(HistoryDealGetString(dealTicket, DEAL_SYMBOL) == _Symbol && 
            HistoryDealGetInteger(dealTicket, DEAL_MAGIC) == MagicNumber)
           {
            // Hanya memproses transaksi penutupan posisi (deal out)
            if(HistoryDealGetInteger(dealTicket, DEAL_ENTRY) == DEAL_ENTRY_OUT)
              {
               double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
               long dealType = HistoryDealGetInteger(dealTicket, DEAL_TYPE);
               double lastLot = HistoryDealGetDouble(dealTicket, DEAL_VOLUME);
               
               // Menentukan posisi sebelumnya (Di MQL5, Deal SELL menutup posisi BUY, dan sebaliknya)
               int lastPositionType = (dealType == DEAL_TYPE_SELL) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
               
               if(profit > 0) // Jika trade terakhir Profit (TP tersentuh)
                 {
                  next_dir = lastPositionType; // Buka posisi searah dengan trade sebelumnya
                  next_lot = InitialLot;       // Kembalikan lot ke Lot Awal
                 }
               else // Jika trade terakhir Loss (SL tersentuh)
                 {
                  next_dir = (lastPositionType == ORDER_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY; // Buka posisi berlawanan (Switching)
                  next_lot = lastLot * LotMultiplier; // Kalikan lot (Martingale)
                 }
               return true; // Berhasil menemukan histori dan menghitung langkah selanjutnya
              }
           }
        }
     }
   return false; // Mengembalikan false jika tidak ada histori transaksi yang relevan
  }

//+------------------------------------------------------------------+
//| Fungsi internal: Memastikan ukuran Lot valid bagi Broker         |
//+------------------------------------------------------------------+
double NormalizeLot(double lot)
  {
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   if(lot < minLot) lot = minLot;
   if(lot > maxLot) lot = maxLot;
   
   lot = MathRound(lot / stepLot) * stepLot;
   return lot;
  }
//+------------------------------------------------------------------+
