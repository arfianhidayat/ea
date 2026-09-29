//+------------------------------------------------------------------+
//|                                             SAR_Martingale.mq5   |
//|                                                Hak Cipta 2026    |
//+------------------------------------------------------------------+
#property copyright "Trader Saham & Forex"
#property version   "1.10"

#include <Trade\Trade.mqh>

//--- Variabel Input (Parameter Eksternal)
input double InitialLot        = 0.01;    // Lot Awal
input double LotMultiplier     = 2.0;     // Pengali Lot (Martingale)
input int    TakeProfit_Pips   = 1000;    // Target Profit (Pips)
input int    StopLoss_Pips     = 1000;    // Stop Loss (Pips)
input ulong  Slippage          = 40;      // Slippage Maksimal (Points)
input ulong  MagicNumber       = 12345;   // Magic Number EA
input int    MaxMartingaleStep = 5;       // Batas Step Martingale (0 = tanpa batas)
input int    MaxSpread_Points  = 30;      // Spread Maksimal untuk Entry (Points, 0 = abaikan)
input bool   UseADXFilter      = true;    // Filter Sideway (ADX) untuk Entry Awal
input ENUM_TIMEFRAMES ADX_Timeframe = PERIOD_CURRENT; // Timeframe ADX
input int    ADX_Period        = 14;      // Periode ADX
input double ADX_Threshold     = 25.0;    // Minimal ADX (di bawah ini = sideway, tunda entry awal)

CTrade trade;
double pipsToPoints;
int    adxHandle = INVALID_HANDLE;
bool   needHistoryScan = true; // Penanda agar scan histori hanya dilakukan saat ada perubahan

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

   // Peringatan jika jarak SL/TP lebih kecil dari batas minimal broker (order akan ditolak)
   long stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minPips = MathMin(TakeProfit_Pips, StopLoss_Pips) * pipsToPoints / _Point;
   if(stopsLevel > 0 && minPips < stopsLevel)
      PrintFormat("PERINGATAN: SL/TP (%.0f points) di bawah batas minimal broker (%d points). Order bisa ditolak.",
                  minPips, stopsLevel);

   // Membuat handle indikator ADX untuk filter kondisi sideway
   if(UseADXFilter)
     {
      adxHandle = iADX(_Symbol, ADX_Timeframe, ADX_Period);
      if(adxHandle == INVALID_HANDLE)
        {
         Print("Gagal membuat handle ADX, error: ", GetLastError());
         return(INIT_FAILED);
        }
     }

   needHistoryScan = true;
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Fungsi Deinisialisasi EA                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(adxHandle != INVALID_HANDLE)
      IndicatorRelease(adxHandle);
  }

//+------------------------------------------------------------------+
//| Fungsi Transaksi: menandai perlunya scan ulang histori           |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   // Setiap ada deal baru (posisi tertutup/terbuka), histori perlu dibaca ulang
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
      needHistoryScan = true;
  }

//+------------------------------------------------------------------+
//| Fungsi Tick EA (Berjalan setiap kali ada perubahan harga)        |
//+------------------------------------------------------------------+
void OnTick()
  {
   // Periksa apakah EA sedang memiliki posisi terbuka
   if(CountOpenPositions() > 0)
      return; // Jika masih ada posisi yang terbuka, tunggu hingga terkena TP atau SL

   // Variabel untuk menentukan arah, lot, dan step martingale posisi baru
   static int    nextDirection = ORDER_TYPE_BUY;
   static double nextLot       = 0;
   static int    lossStreak    = 0;

   // Scan histori hanya saat ada deal baru (bukan setiap tick) agar ringan
   if(needHistoryScan)
     {
      nextDirection = ORDER_TYPE_BUY;
      nextLot       = InitialLot;
      lossStreak    = 0;
      GetLastTradeInfo(nextDirection, nextLot, lossStreak);

      // Batas step martingale: jika loss beruntun mencapai batas, reset ke lot awal
      if(MaxMartingaleStep > 0 && lossStreak >= MaxMartingaleStep)
        {
         PrintFormat("Batas martingale %d step tercapai (loss beruntun %d). Lot direset ke %.2f.",
                     MaxMartingaleStep, lossStreak, InitialLot);
         nextLot    = InitialLot;
         lossStreak = 0; // Dianggap memulai siklus baru (filter entry awal berlaku)
        }

      needHistoryScan = false;
     }

   // Mengambil harga Ask dan Bid saat ini
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // Filter spread: tunda entry saat spread sedang melebar (news/rollover)
   if(MaxSpread_Points > 0 && (ask - bid) / _Point > MaxSpread_Points)
      return;

   // Filter sideway (ADX) HANYA untuk entry awal siklus (lossStreak == 0).
   // Entry lanjutan martingale (switching setelah loss) tidak difilter agar
   // urutan recovery tidak terputus.
   if(lossStreak == 0 && UseADXFilter && !IsTrending())
      return; // Pasar sideway: tunggu sampai ADX di atas ambang

   // Menormalkan ukuran lot sesuai batasan minimal dan maksimal broker
   double lot = NormalizeLot(nextLot);

   double sl = 0, tp = 0;
   bool sent = false;

   // Eksekusi: buka posisi baru berdasarkan hasil kalkulasi
   if(nextDirection == ORDER_TYPE_BUY)
     {
      sl = ask - (StopLoss_Pips * pipsToPoints);
      tp = ask + (TakeProfit_Pips * pipsToPoints);
      sent = trade.Buy(lot, _Symbol, ask, sl, tp, "SAR Martingale Buy");
     }
   else if(nextDirection == ORDER_TYPE_SELL)
     {
      sl = bid + (StopLoss_Pips * pipsToPoints);
      tp = bid - (TakeProfit_Pips * pipsToPoints);
      sent = trade.Sell(lot, _Symbol, bid, sl, tp, "SAR Martingale Sell");
     }

   // Cek hasil eksekusi order: jangan diam saja jika ditolak broker
   if(!sent || trade.ResultRetcode() != TRADE_RETCODE_DONE)
      PrintFormat("Order gagal: retcode=%d (%s), lot=%.2f",
                  trade.ResultRetcode(), trade.ResultRetcodeDescription(), lot);
  }

//+------------------------------------------------------------------+
//| Fungsi internal: Cek apakah pasar sedang trending (ADX)          |
//+------------------------------------------------------------------+
bool IsTrending()
  {
   double adx[1];
   // Membaca nilai ADX bar terakhir yang sudah selesai (shift 1)
   if(CopyBuffer(adxHandle, MAIN_LINE, 1, 1, adx) < 1)
      return false; // Data belum siap: lebih aman tidak entry dulu

   return (adx[0] >= ADX_Threshold);
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
//| Fungsi internal: Mengekstrak arah, lot, dan loss beruntun        |
//+------------------------------------------------------------------+
bool GetLastTradeInfo(int &next_dir, double &next_lot, int &loss_streak)
  {
   // Memuat seluruh histori transaksi ke dalam memori
   // (hanya dipanggil saat ada deal baru, bukan setiap tick)
   HistorySelect(0, TimeCurrent());
   int totalDeals = HistoryDealsTotal();

   bool foundLast = false;
   loss_streak = 0;

   // Perulangan mundur: deal pertama yang ditemukan = trade terakhir,
   // lalu lanjut menghitung berapa loss beruntun sebelum profit terakhir
   for(int i = totalDeals - 1; i >= 0; i--)
     {
      ulong dealTicket = HistoryDealGetTicket(i);
      if(dealTicket == 0)
         continue;

      // Memastikan transaksi tersebut milik EA ini pada pair yang sama
      if(HistoryDealGetString(dealTicket, DEAL_SYMBOL) != _Symbol ||
         HistoryDealGetInteger(dealTicket, DEAL_MAGIC) != MagicNumber)
         continue;

      // Hanya memproses transaksi penutupan posisi (deal out)
      if(HistoryDealGetInteger(dealTicket, DEAL_ENTRY) != DEAL_ENTRY_OUT)
         continue;

      // Menentukan hasil trade: utamakan alasan penutupan (TP/SL),
      // fallback ke profit bersih (termasuk swap & komisi) untuk close manual
      long   reason = HistoryDealGetInteger(dealTicket, DEAL_REASON);
      double netProfit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT)
                       + HistoryDealGetDouble(dealTicket, DEAL_SWAP)
                       + HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
      bool isWin;
      if(reason == DEAL_REASON_TP)
         isWin = true;
      else if(reason == DEAL_REASON_SL)
         isWin = false;
      else
         isWin = (netProfit > 0);

      if(!foundLast)
        {
         // Deal out pertama dari belakang = trade terakhir: tentukan arah & lot
         long   dealType = HistoryDealGetInteger(dealTicket, DEAL_TYPE);
         double lastLot  = HistoryDealGetDouble(dealTicket, DEAL_VOLUME);

         // Menentukan posisi sebelumnya (Deal SELL menutup posisi BUY, dan sebaliknya)
         int lastPositionType = (dealType == DEAL_TYPE_SELL) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;

         if(isWin) // Jika trade terakhir Profit (TP tersentuh)
           {
            next_dir = lastPositionType; // Buka posisi searah dengan trade sebelumnya
            next_lot = InitialLot;       // Kembalikan lot ke Lot Awal
            loss_streak = 0;
            return true; // Siklus baru, tidak perlu hitung loss beruntun
           }
         else // Jika trade terakhir Loss (SL tersentuh)
           {
            next_dir = (lastPositionType == ORDER_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY; // Switching
            next_lot = lastLot * LotMultiplier; // Kalikan lot (Martingale)
            loss_streak = 1;
            foundLast = true; // Lanjut hitung loss beruntun ke belakang
           }
        }
      else
        {
         // Menghitung loss beruntun untuk batas step martingale
         if(isWin)
            break; // Ketemu profit: streak berhenti di sini
         loss_streak++;
        }
     }

   return foundLast;
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
   if(lot > maxLot)
     {
      // Lot melebihi batas broker: matematika recovery martingale sudah rusak,
      // beri peringatan agar tidak dianggap berjalan normal
      PrintFormat("PERINGATAN: Lot %.2f dipotong ke maksimal broker %.2f. Recovery martingale tidak lagi penuh.", lot, maxLot);
      lot = maxLot;
     }

   lot = MathRound(lot / stepLot) * stepLot;
   return lot;
  }
//+------------------------------------------------------------------+
