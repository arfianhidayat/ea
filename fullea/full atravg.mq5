//+------------------------------------------------------------------+
//|                                     UT_Bot_Martingale_Grid.mq5   |
//|                                     Versi Integrasi Penuh & Aman |
//+------------------------------------------------------------------+
#property copyright "Trading Strategy Converter"
#property version   "4.00"

#include <Trade\Trade.mqh>
CTrade trade;

//--- 1. Inputs UT Bot (Pemicu Entry Awal)
input double   InpKeyValue           = 1.0;      // Key Value (Sensitivity)
input int      InpATRPeriod          = 10;       // ATR Period
input double   InpLotSize            = 0.01;     // Ukuran Lot Awal

//--- 2. Inputs Martingale & Grid (Sistem Close/Averaging)
input double   InpGridDistance       = 5.0;      // Jarak Averaging
input double   InpTakeProfitSingle   = 5.0;      // TP jika HANYA 1 Posisi
input double   InpTakeProfitBEP1     = 2.0;      // TP BEP 1 (Averaging Awal)
input int      InpAktifTPBEP2Posisi  = 5;        // Aktif TP BEP 2 pada Posisi ke-
input double   InpTakeProfitBEP2     = 1.0;      // TP BEP 2 (Averaging Lanjut)
input double   InpLotMultiplier      = 1.3;      // Multiplier Martingale
input ulong    InpMagicNumber        = 88888;    // Magic Number EA

//--- Global Variables (Memory)
int atrHandle;
double atrBuffer[];
double ts_prev = 0.0;
int pos_prev = 0;
datetime last_time = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(50); // Maksimal slippage 50 poin
   
   atrHandle = iATR(_Symbol, _Period, InpATRPeriod);
   
   if(atrHandle == INVALID_HANDLE) 
     {
      Print("Gagal memuat indikator ATR.");
      return INIT_FAILED;
     }
     
   ArraySetAsSeries(atrBuffer, true);
   
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   int buy_count = 0;
   int sell_count = 0;
   
   double sum_buy_val = 0, sum_buy_vol = 0;
   double sum_sell_val = 0, sum_sell_vol = 0;
   
   double last_buy_price = 0, last_sell_price = 0;
   double initial_buy_lot = 0, initial_sell_lot = 0;
   
   datetime latest_buy_time = 0, latest_sell_time = 0;
   datetime oldest_buy_time = 0, oldest_sell_time = 0;

   // 1. Memindai Status Posisi Terbuka Saat Ini
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
        {
         long type = PositionGetInteger(POSITION_TYPE);
         double price = PositionGetDouble(POSITION_PRICE_OPEN);
         double vol = PositionGetDouble(POSITION_VOLUME);
         datetime time = (datetime)PositionGetInteger(POSITION_TIME);

         if(type == POSITION_TYPE_BUY)
           {
            buy_count++; 
            sum_buy_vol += vol; 
            sum_buy_val += (price * vol);
            
            if(time >= latest_buy_time) 
              { 
               latest_buy_time = time; 
               last_buy_price = price; 
              }
              
            if(oldest_buy_time == 0 || time < oldest_buy_time) 
              { 
               oldest_buy_time = time; 
               initial_buy_lot = vol; 
              }
           }
         else if(type == POSITION_TYPE_SELL)
           {
            sell_count++; 
            sum_sell_vol += vol; 
            sum_sell_val += (price * vol);
            
            if(time >= latest_sell_time) 
              { 
               latest_sell_time = time; 
               last_sell_price = price; 
              }
              
            if(oldest_sell_time == 0 || time < oldest_sell_time) 
              { 
               oldest_sell_time = time; 
               initial_sell_lot = vol; 
              }
           }
        }
     }

   string dashboard = "=== UT BOT + MARTINGALE EA ===\n";
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   // 2. LOGIKA MARTINGALE (Manajemen Posisi Terbuka)
   
   // --- Logika Untuk Posisi SELL ---
   if(sell_count > 0)
     {
      double bep_sell = sum_sell_val / sum_sell_vol;
      double target_price_sell;
      string tp_mode_sell = "";
      
      if(sell_count == 1) 
        { 
         target_price_sell = bep_sell - InpTakeProfitSingle; 
         tp_mode_sell = "Single Posisi"; 
        }
      else if(sell_count >= InpAktifTPBEP2Posisi) 
        { 
         target_price_sell = bep_sell - InpTakeProfitBEP2; 
         tp_mode_sell = "Averaging (BEP 2)"; 
        }
      else 
        { 
         target_price_sell = bep_sell - InpTakeProfitBEP1; 
         tp_mode_sell = "Averaging (BEP 1)"; 
        }
      
      double next_sell_price = last_sell_price + InpGridDistance;
      
      dashboard += "--- STATUS SELL (Martingale) ---\n";
      dashboard += "Jumlah Posisi : " + IntegerToString(sell_count) + " (" + tp_mode_sell + ")\n";
      dashboard += "Target Close (TP) : " + DoubleToString(target_price_sell, 3) + "\n";
      dashboard += "Harga Grid Lanjut : " + DoubleToString(next_sell_price, 3) + "\n";

      // Buka Posisi Averaging Baru
      if(bid >= next_sell_price)
        {
         double exact_lot = initial_sell_lot * MathPow(InpLotMultiplier, sell_count);
         trade.Sell(CalculateLot(exact_lot), _Symbol, bid, 0, 0, "Averaging Sell");
        }
        
      // Tutup Semua Posisi Sell jika mencapai TP
      if(ask <= target_price_sell) 
        { 
         CloseAll(POSITION_TYPE_SELL); 
        }
     }

   // --- Logika Untuk Posisi BUY ---
   if(buy_count > 0)
     {
      double bep_buy = sum_buy_val / sum_buy_vol;
      double target_price_buy;
      string tp_mode_buy = "";
      
      if(buy_count == 1) 
        { 
         target_price_buy = bep_buy + InpTakeProfitSingle; 
         tp_mode_buy = "Single Posisi"; 
        }
      else if(buy_count >= InpAktifTPBEP2Posisi) 
        { 
         target_price_buy = bep_buy + InpTakeProfitBEP2; 
         tp_mode_buy = "Averaging (BEP 2)"; 
        }
      else 
        { 
         target_price_buy = bep_buy + InpTakeProfitBEP1; 
         tp_mode_buy = "Averaging (BEP 1)"; 
        }
      
      double next_buy_price = last_buy_price - InpGridDistance;
      
      dashboard += "--- STATUS BUY (Martingale) ---\n";
      dashboard += "Jumlah Posisi : " + IntegerToString(buy_count) + " (" + tp_mode_buy + ")\n";
      dashboard += "Target Close (TP) : " + DoubleToString(target_price_buy, 3) + "\n";
      dashboard += "Harga Grid Lanjut : " + DoubleToString(next_buy_price, 3) + "\n";

      // Buka Posisi Averaging Baru
      if(ask <= next_buy_price)
        {
         double exact_lot = initial_buy_lot * MathPow(InpLotMultiplier, buy_count);
         trade.Buy(CalculateLot(exact_lot), _Symbol, ask, 0, 0, "Averaging Buy");
        }
        
      // Tutup Semua Posisi Buy jika mencapai TP
      if(bid >= target_price_buy) 
        { 
         CloseAll(POSITION_TYPE_BUY); 
        }
     }

   // 3. LOGIKA UT BOT (Mencari Sinyal Awal di Pergantian Candlestick)
   datetime time[];
   CopyTime(_Symbol, _Period, 0, 1, time);
   
   if(time[0] == last_time) 
     {
      Comment(dashboard);
      return; 
     }

   double close[];
   ArraySetAsSeries(close, true);
   CopyClose(_Symbol, _Period, 0, 3, close);
   
   if(CopyBuffer(atrHandle, 0, 0, 2, atrBuffer) <= 0) 
     {
      return;
     }

   double xATR = atrBuffer[1]; 
   double nLoss = InpKeyValue * xATR;
   double src = close[1];
   double src_prev = close[2];
   double ts = ts_prev;

   // Kalkulasi Trailing Stop Dinamis
   if(src > ts_prev && src_prev > ts_prev) 
     {
      ts = MathMax(ts_prev, src - nLoss);
     }
   else if(src < ts_prev && src_prev < ts_prev) 
     {
      ts = MathMin(ts_prev, src + nLoss);
     }
   else if(src > ts_prev) 
     {
      ts = src - nLoss;
     }
   else 
     {
      ts = src + nLoss;
     }

   int pos = pos_prev;
   
   if(src_prev < ts_prev && src > ts_prev) 
     {
      pos = 1; 
     }
   else if(src_prev > ts_prev && src < ts_prev) 
     {
      pos = -1;
     }

   bool buy_signal = (src > ts) && (src_prev <= ts_prev); 
   bool sell_signal = (src < ts) && (src_prev >= ts_prev); 

   // --- FILTER ANTI-DOUBLE ENTRY ---
   
   // Hanya entry BUY jika ada sinyal DAN belum ada posisi BUY
   if(buy_signal && buy_count == 0) 
     {
      trade.Buy(InpLotSize, _Symbol, 0, 0, 0, "UT Bot Buy Pertama");
     }
   
   // Hanya entry SELL jika ada sinyal DAN belum ada posisi SELL
   if(sell_signal && sell_count == 0) 
     {
      trade.Sell(InpLotSize, _Symbol, 0, 0, 0, "UT Bot Sell Pertama");
     }

   // Tampilkan Info UT Bot ke Dashboard jika sedang tidak ada posisi aktif
   if(buy_count == 0 && sell_count == 0)
     {
      dashboard += "\n--- STATUS UT BOT ---\n";
      dashboard += "Batas Trailing Stop : " + DoubleToString(ts, _Digits) + "\n";
      dashboard += "Menunggu Sinyal Valid Berikutnya...\n";
     }
     
   Comment(dashboard);

   // Update Memori untuk pembacaan berikutnya
   ts_prev = ts;
   pos_prev = pos;
   last_time = time[0];
  }

//+------------------------------------------------------------------+
//| Helper Functions                                                 |
//+------------------------------------------------------------------+
void CloseAll(long pos_type)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
        {
         if(PositionGetInteger(POSITION_TYPE) == pos_type) 
           { 
            trade.PositionClose(ticket); 
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
   
   if(final_lot < min_lot) 
     {
      final_lot = min_lot;
     }
   if(final_lot > max_lot) 
     {
      final_lot = max_lot;
     }
     
   return final_lot;
  }
//+------------------------------------------------------------------+
