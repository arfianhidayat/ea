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
input int    MaxSpread_Points  = 50;      // Spread Maksimal untuk Entry (Points, 0 = abaikan)
input bool   UseADXFilter      = true;    // Filter Sideway (ADX) untuk Entry Awal
input ENUM_TIMEFRAMES ADX_Timeframe = PERIOD_CURRENT; // Timeframe ADX
input int    ADX_Period        = 14;      // Periode ADX
input double ADX_Threshold     = 35.0;    // Minimal ADX (di bawah ini = sideway, tunda entry awal)

CTrade trade;
double pipsToPoints;
int    adxHandle = INVALID_HANDLE;
double lastADXValue = 0; // Nilai ADX terakhir yang terbaca (untuk log diagnostik)
bool   needHistoryScan = true; // Penanda agar scan histori hanya dilakukan saat ada perubahan

// Variabel status untuk ditampilkan pada Comment di chart
string eaStatus      = "Inisialisasi...";
int    nextDirection = ORDER_TYPE_BUY;
double nextLot       = 0;
int    lossStreak    = 0;

// Statistik histori trade EA (dihitung ulang hanya saat ada deal baru)
int      statTotalTrades = 0;
int      statWins        = 0;
int      statLosses      = 0;
double   statTotalProfit = 0;
int      statTradesToday = 0;
double   statProfitToday = 0;
string   statLastTrade   = "-";
double   startBalance    = 0; // Balance saat EA dipasang (untuk hitung P/L sesi)

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

   startBalance = AccountInfoDouble(ACCOUNT_BALANCE);
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
   Comment(""); // Bersihkan tampilan comment saat EA dilepas
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
   // Scan histori hanya saat ada deal baru (bukan setiap tick) agar ringan
   if(needHistoryScan)
     {
      nextDirection = ORDER_TYPE_BUY;
      nextLot       = InitialLot;
      lossStreak    = 0;
      GetLastTradeInfo(nextDirection, nextLot, lossStreak);
      UpdateTradeStats(); // Hitung ulang statistik untuk tampilan Comment

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

   // Periksa apakah EA sedang memiliki posisi terbuka
   if(CountOpenPositions() > 0)
     {
      eaStatus = "POSISI TERBUKA - menunggu TP/SL";
      UpdateChartComment();
      return; // Jika masih ada posisi yang terbuka, tunggu hingga terkena TP atau SL
     }

   // Mengambil harga Ask dan Bid saat ini
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // Log diagnostik saat entry tertahan filter, dibatasi maksimal 1x per menit
   static datetime lastFilterLog = 0;
   bool canLog = (TimeCurrent() - lastFilterLog >= 60);

   // Filter spread: tunda entry saat spread sedang melebar (news/rollover)
   double spreadPoints = (ask - bid) / _Point;
   if(MaxSpread_Points > 0 && spreadPoints > MaxSpread_Points)
     {
      if(canLog)
        {
         PrintFormat("Entry ditahan: spread %.0f points > batas %d points.", spreadPoints, MaxSpread_Points);
         lastFilterLog = TimeCurrent();
        }
      eaStatus = StringFormat("DITAHAN: spread %.0f pts > batas %d pts", spreadPoints, MaxSpread_Points);
      UpdateChartComment();
      return;
     }

   // Filter sideway (ADX) HANYA untuk entry awal siklus (lossStreak == 0).
   // Entry lanjutan martingale (switching setelah loss) tidak difilter agar
   // urutan recovery tidak terputus.
   if(lossStreak == 0 && UseADXFilter && !IsTrending())
     {
      if(canLog)
        {
         PrintFormat("Entry ditahan: ADX %.1f di bawah ambang %.1f (sideway).", lastADXValue, ADX_Threshold);
         lastFilterLog = TimeCurrent();
        }
      eaStatus = StringFormat("DITAHAN: sideway (ADX %.1f < %.1f)", lastADXValue, ADX_Threshold);
      UpdateChartComment();
      return; // Pasar sideway: tunggu sampai ADX di atas ambang
     }

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
     {
      PrintFormat("Order gagal: retcode=%d (%s), lot=%.2f",
                  trade.ResultRetcode(), trade.ResultRetcodeDescription(), lot);
      eaStatus = StringFormat("ORDER GAGAL: %s (retcode %d)",
                              trade.ResultRetcodeDescription(), trade.ResultRetcode());
     }
   else
      eaStatus = "Order terkirim";

   UpdateChartComment();
  }

//+------------------------------------------------------------------+
//| Fungsi internal: Menghitung statistik histori trade EA ini       |
//| (dipanggil hanya saat ada deal baru, bukan setiap tick)          |
//+------------------------------------------------------------------+
void UpdateTradeStats()
  {
   statTotalTrades = 0;
   statWins        = 0;
   statLosses      = 0;
   statTotalProfit = 0;
   statTradesToday = 0;
   statProfitToday = 0;
   statLastTrade   = "-";

   // Batas awal hari ini menurut waktu server
   datetime todayStart = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));

   HistorySelect(0, TimeCurrent());
   int totalDeals = HistoryDealsTotal();

   for(int i = 0; i < totalDeals; i++)
     {
      ulong dealTicket = HistoryDealGetTicket(i);
      if(dealTicket == 0)
         continue;

      if(HistoryDealGetString(dealTicket, DEAL_SYMBOL) != _Symbol ||
         HistoryDealGetInteger(dealTicket, DEAL_MAGIC) != MagicNumber)
         continue;

      if(HistoryDealGetInteger(dealTicket, DEAL_ENTRY) != DEAL_ENTRY_OUT)
         continue;

      double netProfit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT)
                       + HistoryDealGetDouble(dealTicket, DEAL_SWAP)
                       + HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
      long   reason   = HistoryDealGetInteger(dealTicket, DEAL_REASON);
      datetime dtTime = (datetime)HistoryDealGetInteger(dealTicket, DEAL_TIME);

      bool isWin;
      if(reason == DEAL_REASON_TP)
         isWin = true;
      else if(reason == DEAL_REASON_SL)
         isWin = false;
      else
         isWin = (netProfit > 0);

      statTotalTrades++;
      statTotalProfit += netProfit;
      if(isWin) statWins++; else statLosses++;

      if(dtTime >= todayStart)
        {
         statTradesToday++;
         statProfitToday += netProfit;
        }

      // Karena loop maju, deal terakhir yang lolos filter = trade terakhir
      long dealType = HistoryDealGetInteger(dealTicket, DEAL_TYPE);
      string dirText = (dealType == DEAL_TYPE_SELL) ? "BUY" : "SELL"; // Deal penutup berlawanan arah posisi
      statLastTrade = StringFormat("%s %.2f lot, %s %.2f (%s)",
                                   dirText,
                                   HistoryDealGetDouble(dealTicket, DEAL_VOLUME),
                                   isWin ? "WIN" : "LOSS",
                                   netProfit,
                                   TimeToString(dtTime, TIME_DATE|TIME_MINUTES));
     }
  }

//+------------------------------------------------------------------+
//| Fungsi internal: Menampilkan informasi EA pada chart (Comment)   |
//+------------------------------------------------------------------+
void UpdateChartComment()
  {
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double spreadPoints = (ask - bid) / _Point;
   string currency = AccountInfoString(ACCOUNT_CURRENCY);

   // Informasi posisi terbuka milik EA ini (jika ada)
   int    posCount  = 0;
   double posProfit = 0;
   string posInfo   = "-";
   double posSL = 0, posTP = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
        {
         posCount++;
         posProfit += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
         posInfo = StringFormat("%s %.2f lot @ %s",
                                (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? "BUY" : "SELL",
                                PositionGetDouble(POSITION_VOLUME),
                                DoubleToString(PositionGetDouble(POSITION_PRICE_OPEN), _Digits));
         posSL = PositionGetDouble(POSITION_SL);
         posTP = PositionGetDouble(POSITION_TP);
        }
     }

   string adxInfo = UseADXFilter
                    ? StringFormat("%.1f (ambang %.1f)", lastADXValue, ADX_Threshold)
                    : "OFF";

   // Win rate keseluruhan
   double winRate = (statTotalTrades > 0) ? (100.0 * statWins / statTotalTrades) : 0;

   // Status izin trading terminal & EA
   bool terminalTrade = (bool)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED);
   bool eaTrade       = (bool)MQLInfoInteger(MQL_TRADE_ALLOWED);
   string tradeAllowed = (terminalTrade && eaTrade) ? "AKTIF" :
                         (!terminalTrade ? "NONAKTIF (AutoTrading terminal OFF)"
                                         : "NONAKTIF (Allow Algo Trading EA OFF)");

   // P/L sesi sejak EA dipasang (realized + floating)
   double sessionPL = AccountInfoDouble(ACCOUNT_EQUITY) - startBalance;

   // Margin level (0 jika tidak ada posisi)
   double marginLevel = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);

   string text = "\n"; // Baris kosong agar tidak tertutup nama EA di pojok chart
   text += "=== SAR MARTINGALE v1.10 ===\n";
   text += StringFormat("%s %s | Server: %s\n", _Symbol, EnumToString(_Period),
                        TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS));
   text += "AutoTrading : " + tradeAllowed + "\n";
   text += "Status      : " + eaStatus + "\n";
   text += "---------------------------------------------\n";
   text += StringFormat("Bid/Ask     : %s / %s\n",
                        DoubleToString(bid, _Digits), DoubleToString(ask, _Digits));
   text += StringFormat("Spread      : %.0f pts (maks %d)\n", spreadPoints, MaxSpread_Points);
   text += "ADX         : " + adxInfo + "\n";
   text += "---------------------------------------------\n";
   if(posCount > 0)
     {
      text += "Posisi      : " + posInfo + "\n";
      text += StringFormat("SL / TP     : %s / %s\n",
                           DoubleToString(posSL, _Digits), DoubleToString(posTP, _Digits));
      text += StringFormat("Floating P/L: %.2f %s\n", posProfit, currency);
     }
   else
     {
      text += StringFormat("Entry next  : %s %.2f lot (multiplier x%.1f)\n",
                           (nextDirection == ORDER_TYPE_BUY) ? "BUY" : "SELL", nextLot, LotMultiplier);
     }
   text += StringFormat("Step        : %d dari %s\n", lossStreak,
                        (MaxMartingaleStep > 0) ? IntegerToString(MaxMartingaleStep) : "tanpa batas");
   text += "Trade akhir : " + statLastTrade + "\n";
   text += "---------------------------------------------\n";
   text += StringFormat("Hari ini    : %d trade | P/L %.2f %s\n",
                        statTradesToday, statProfitToday, currency);
   text += StringFormat("Total       : %d trade (W:%d / L:%d, WR %.1f%%)\n",
                        statTotalTrades, statWins, statLosses, winRate);
   text += StringFormat("Total P/L   : %.2f %s | Sesi: %+.2f %s\n",
                        statTotalProfit, currency, sessionPL, currency);
   text += "---------------------------------------------\n";
   text += StringFormat("Balance     : %.2f | Equity: %.2f\n",
                        AccountInfoDouble(ACCOUNT_BALANCE), AccountInfoDouble(ACCOUNT_EQUITY));
   text += StringFormat("Free Margin : %.2f | Margin Lvl: %.0f%%\n",
                        AccountInfoDouble(ACCOUNT_MARGIN_FREE), marginLevel);

   Comment(text);
  }

//+------------------------------------------------------------------+
//| Fungsi internal: Cek apakah pasar sedang trending (ADX)          |
//+------------------------------------------------------------------+
bool IsTrending()
  {
   double adx[1];
   // Membaca nilai ADX bar terakhir yang sudah selesai (shift 1)
   if(CopyBuffer(adxHandle, MAIN_LINE, 1, 1, adx) < 1)
     {
      lastADXValue = 0;
      return false; // Data belum siap: lebih aman tidak entry dulu
     }

   lastADXValue = adx[0];
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
