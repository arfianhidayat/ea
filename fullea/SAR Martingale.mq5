//+------------------------------------------------------------------+
//|                                       SAR_Martingale_XAUUSD.mq5  |
//|                                                Hak Cipta 2026    |
//+------------------------------------------------------------------+
//| CATATAN PERUBAHAN v1.30 (dari v1.20)                             |
//|  Risiko : plafon lot, equity stop (drawdown %), batas rugi harian,|
//|           recovery berbasis kerugian riil (opsional), batas umur  |
//|           posisi, cek margin & volume limit sebelum entry.        |
//|  Sinyal : state UT Bot dihitung ulang saat init (warm-up), sinyal |
//|           berlaku N bar & "antre" saat posisi terbuka, cek        |
//|           konflik arah switching martingale vs trend UT Bot.      |
//|  Waktu  : hindari rollover, Jumat sore, jam trading, cek sesi.    |
//|  Teknis : backoff order gagal + henti otomatis, cek akun netting, |
//|           histori dibatasi sejak EA dipasang (global variable),   |
//|           log CSV per deal/siklus, notifikasi push.               |
//+------------------------------------------------------------------+
#property copyright "Trader Saham & Forex"
#property version   "1.34"

#include <Trade\Trade.mqh>

//--- Parameter dasar
input group "=== DASAR ==="
input double InitialLot        = 0.05;    // Lot Awal (akun cent: 0.05 lot cent = 0.0005 lot standar)
input double PipSize           = 0.01;    // Ukuran 1 pip dalam harga (Exness XAUUSD: 0.01 = 1 sen; 0 = deteksi otomatis)
input double LotMultiplier     = 2.0;     // Pengali Lot (Martingale)
input int    TakeProfit_Pips   = 1000;    // Target Profit (Pips) -> 1000 x 0.01 = $10 (500 = $5, tapi spread jadi 4% dari TP)
input int    StopLoss_Pips     = 1000;    // Stop Loss (Pips) -> samakan dengan TP agar matematika martingale utuh
input double Slippage_Pips     = 30.0;    // Slippage Maksimal (pips; 30 = $0.30)
input ulong  MagicNumber       = 12345;   // Magic Number EA
input int    MaxMartingaleStep = 2;       // Batas Step: setelah ini entry tunggu sinyal (M5 whipsaw sering; 0 = tanpa batas)
input double MaxSpread_Pips    = 25.0;    // Spread Maksimal untuk Entry (pips; 25 = $0.25; 0 = abaikan)

//--- Manajemen risiko
input group "=== MANAJEMEN RISIKO ==="
input double MaxLot            = 1.6;     // Plafon lot (1.6 = step 6 dari 0.05; 6.4 = step 8; 0 = ikut maksimal broker)
input double MaxDrawdownPct    = 30.0;    // Equity stop: henti EA jika equity turun % ini dari balance awal sesi (0 = off)
input bool   CloseOnEquityStop = true;    // Tutup posisi saat equity stop tercapai
input double DailyLossLimit    = 1500;    // Batas rugi harian dalam MATA UANG AKUN (akun cent = USC: 1500 = $15; 0 = off)
input bool   UseLossBasedRecovery = false;// Lot recovery dari kerugian riil (termasuk swap/komisi), bukan x2
input double RecoveryTargetPips = 200;    // Target profit siklus (pips x lot awal) untuk mode recovery riil
input int    MaxPositionDays   = 1;       // Tutup posisi jika umur melebihi N hari (target $10 wajarnya selesai < 1 hari; 0 = off)
input bool   ResetSession      = false;   // Reset balance awal sesi & titik awal histori (set true sekali, lalu false)

//--- Sinyal entry UT Bot
input group "=== SINYAL ENTRY UT BOT (Entry Awal) ==="
input bool   UseUTBotSignal    = true;    // Sinyal UT Bot: arah entry awal mengikuti sinyal
input double UTBot_KeyValue    = 2.0;     // Key Value (M5 gold bising; 2.0 mengurangi sinyal palsu)
input int    UTBot_ATR_Period  = 10;      // Periode ATR UT Bot
input ENUM_TIMEFRAMES UTBot_Timeframe = PERIOD_M5; // Timeframe sinyal UT Bot (M5 sepadan dengan target $5-10)
input int    SignalValidBars   = 3;       // Sinyal berlaku N bar (tidak berkurang saat posisi terbuka = antre)
input int    WarmupBars        = 300;     // Jumlah bar untuk hitung ulang trailing saat EA dipasang
input bool   CheckSwitchConflict = true;  // Tunda switching martingale jika trend UT Bot masih berlawanan

//--- Konfirmasi ADX
input group "=== KONFIRMASI ADX (Filter Sideway) ==="
input bool   UseADXFilter      = true;    // Konfirmasi ADX untuk entry awal
input ENUM_TIMEFRAMES ADX_Timeframe = PERIOD_M5; // Timeframe ADX (samakan dengan TF sinyal UT Bot)
input int    ADX_Period        = 14;      // Periode ADX
input double ADX_Threshold     = 25.0;    // Minimal ADX (diturunkan dari 35 agar sejalan dengan crossover UT Bot)

//--- Filter waktu (waktu server)
input group "=== FILTER WAKTU (waktu server) ==="
input bool   UseTimeFilter     = true;    // Aktifkan filter waktu
input int    RolloverHour      = 0;       // Jam rollover server (biasanya 0 = 17:00 New York)
input int    RolloverBufferMin = 30;      // Hindari entry +/- menit sekitar rollover (Exness server GMT+0, rollover 00:00)
input int    SessionOpenBufferMin = 15;   // Hindari entry N menit setelah sesi simbol dibuka (gap/spike pembukaan)
input int    FridayStopHour    = 20;      // Jumat: tidak entry mulai jam ini (0 = off)
input int    TradeStartHour    = 0;       // Jam mulai boleh entry
input int    TradeEndHour      = 24;      // Jam akhir boleh entry (24 = sampai tengah malam)

//--- Teknis
input group "=== TEKNIS ==="
input int    OrderRetrySec     = 30;      // Jeda sebelum mencoba lagi setelah order gagal (detik)
input int    MaxOrderFailures  = 5;       // Henti EA setelah N kegagalan order beruntun
input int    NotifyStep        = 3;       // Kirim notifikasi push mulai step ini (0 = off)
input bool   UsePushNotify     = true;    // Kirim notifikasi push (perlu MetaQuotes ID di terminal)
input bool   LogToCSV          = true;    // Catat deal & siklus ke file CSV (MQL5\Files)
input int    HistoryLookbackDays = 30;    // Titik awal baca histori saat pertama dipasang (hari ke belakang)

//+------------------------------------------------------------------+
//| Variabel global                                                  |
//+------------------------------------------------------------------+
CTrade trade;
double pipsToPoints;   // Ukuran 1 pip dalam harga
long   slippagePoints;
int    adxHandle    = INVALID_HANDLE;
double lastADXValue = 0;
bool   needHistoryScan = true;

// UT Bot
int      utbotAtrHandle    = INVALID_HANDLE;
double   utbotTS           = 0;   // Garis trailing stop
int      utbotSignalDir    = 0;   // 1 = BUY, -1 = SELL, 0 = tidak ada
int      utbotSignalBarsLeft = 0; // Sisa masa berlaku sinyal (bar)
datetime utbotLastBar      = 0;
int      utbotTrendDir     = 0;   // Arah trend menurut UT Bot (close vs TS): 1 BUY, -1 SELL
bool     utbotWarmed       = false; // Warm-up sudah berhasil (data indikator sering belum siap saat OnInit)

// Status EA
string eaStatus        = "Inisialisasi...";
int    nextDirection   = ORDER_TYPE_BUY;
double nextLot         = 0;
int    lossStreak      = 0;
double cumLossSinceWin = 0;   // Akumulasi rugi bersih sejak win terakhir (angka positif)
bool   waitTrendSignal = true;
bool   eaHalted        = false;
string haltReason      = "";
datetime dailyPauseDay = 0;   // Tanggal (awal hari) saat batas rugi harian tercapai

// Backoff order
datetime lastOrderFail  = 0;
int      orderFailCount = 0;

// Persistensi (global variable terminal)
string   gvPrefix;
double   startBalance = 0;
datetime historyFrom  = 0;

// Statistik
int    statTotalTrades = 0, statWins = 0, statLosses = 0, statTradesToday = 0;
double statTotalProfit = 0, statProfitToday = 0;
string statLastTrade   = "-";
ulong  lastLoggedDeal  = 0;
int    prevLossStreak  = 0;
double cycleMaxLot     = 0;
double cycleWorstLoss  = 0;

// Notifikasi (throttle)
datetime lastNotifyTime = 0;
datetime lastFilterLog  = 0;

//+------------------------------------------------------------------+
//| Inisialisasi                                                     |
//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(MagicNumber);

   // Ukuran pip: eksplisit (disarankan untuk gold) atau deteksi otomatis
   if(PipSize > 0) pipsToPoints = PipSize;
   else if(_Digits == 5 || _Digits == 3) pipsToPoints = _Point * 10;
   else pipsToPoints = _Point;
   slippagePoints = (long)MathRound(Slippage_Pips * pipsToPoints / _Point);
   trade.SetDeviationInPoints((ulong)slippagePoints);
   PrintFormat("Setup %s: 1 pip = %s | TP %d pips = %s | SL %d pips = %s | slippage %d pts",
               _Symbol, DoubleToString(pipsToPoints, _Digits),
               TakeProfit_Pips, DoubleToString(TakeProfit_Pips * pipsToPoints, _Digits),
               StopLoss_Pips, DoubleToString(StopLoss_Pips * pipsToPoints, _Digits), (int)slippagePoints);
   // Estimasi risiko per unit & eskalasi martingale
   double pv = PipValuePerLot();
   if(pv > 0)
     {
      double unit = StopLoss_Pips * pv * InitialLot;
      PrintFormat("Risiko 1 unit (lot awal kena SL) = %.2f %s | akumulasi rugi: step3 %.2f, step5 %.2f, step6 %.2f",
                  unit, AccountInfoString(ACCOUNT_CURRENCY), unit*7, unit*31, unit*63);
     }

   gvPrefix = "SARM_" + IntegerToString((int)MagicNumber) + "_" + _Symbol + "_";

   // Peringatan batas minimal stop broker
   long stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minPts = MathMin(TakeProfit_Pips, StopLoss_Pips) * pipsToPoints / _Point;
   if(stopsLevel > 0 && minPts < stopsLevel)
      PrintFormat("PERINGATAN: SL/TP (%.0f points) di bawah batas minimal broker (%d points).", minPts, stopsLevel);

   // Peringatan swap (posisi 1000 pips hampir pasti melewati rollover)
   PrintFormat("Info swap %s: long %.2f | short %.2f (per lot per malam, satuan %s)",
               _Symbol, SymbolInfoDouble(_Symbol, SYMBOL_SWAP_LONG),
               SymbolInfoDouble(_Symbol, SYMBOL_SWAP_SHORT),
               EnumToString((ENUM_SYMBOL_SWAP_MODE)SymbolInfoInteger(_Symbol, SYMBOL_SWAP_MODE)));

   // Handle indikator
   if(UseADXFilter)
     {
      adxHandle = iADX(_Symbol, ADX_Timeframe, ADX_Period);
      if(adxHandle == INVALID_HANDLE) { Print("Gagal membuat handle ADX: ", GetLastError()); return(INIT_FAILED); }
     }
   if(UseUTBotSignal)
     {
      utbotAtrHandle = iATR(_Symbol, UTBot_Timeframe, UTBot_ATR_Period);
      if(utbotAtrHandle == INVALID_HANDLE) { Print("Gagal membuat handle ATR: ", GetLastError()); return(INIT_FAILED); }
     }

   // Persistensi balance awal sesi & titik awal histori
   if(ResetSession)
     {
      GlobalVariableDel(gvPrefix + "StartBalance");
      GlobalVariableDel(gvPrefix + "HistoryFrom");
      Print("Sesi di-reset: balance awal & titik histori dihapus.");
     }
   if(GlobalVariableCheck(gvPrefix + "StartBalance"))
      startBalance = GlobalVariableGet(gvPrefix + "StartBalance");
   else
     {
      startBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      GlobalVariableSet(gvPrefix + "StartBalance", startBalance);
     }
   if(GlobalVariableCheck(gvPrefix + "HistoryFrom"))
      historyFrom = (datetime)GlobalVariableGet(gvPrefix + "HistoryFrom");
   else
     {
      historyFrom = TimeCurrent() - (datetime)(HistoryLookbackDays * 86400);
      GlobalVariableSet(gvPrefix + "HistoryFrom", (double)historyFrom);
     }

   // Warm-up UT Bot agar tidak mulai dari TS = 0
   if(UseUTBotSignal)
      WarmupUTBot();

   needHistoryScan = true;
   eaHalted = false;
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(adxHandle != INVALID_HANDLE)      IndicatorRelease(adxHandle);
   if(utbotAtrHandle != INVALID_HANDLE) IndicatorRelease(utbotAtrHandle);
   Comment("");
  }

//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
      needHistoryScan = true;
  }

//+------------------------------------------------------------------+
//| Tick utama                                                       |
//+------------------------------------------------------------------+
void OnTick()
  {
   UpdateUTBotSignal();

   // 1. EA dihentikan permanen (equity stop / order gagal beruntun) -> hanya tampil status
   if(eaHalted)
     {
      eaStatus = "HENTI: " + haltReason + " (lepas & pasang ulang EA untuk lanjut)";
      UpdateChartComment();
      return;
     }

   // 2. Scan histori hanya saat ada deal baru
   if(needHistoryScan)
     {
      nextDirection   = ORDER_TYPE_BUY;
      nextLot         = InitialLot;
      lossStreak      = 0;
      cumLossSinceWin = 0;
      GetLastTradeInfo(nextDirection, nextLot, lossStreak, cumLossSinceWin);
      UpdateTradeStats();

      // Mode recovery riil: hitung lot dari kerugian yang harus dipulihkan + target
      if(UseLossBasedRecovery && lossStreak > 0)
         nextLot = CalcRecoveryLot(cumLossSinceWin);

      waitTrendSignal = (lossStreak == 0);
      if(MaxMartingaleStep > 0 && lossStreak >= MaxMartingaleStep)
        {
         PrintFormat("Batas martingale %d step tercapai (loss beruntun %d). Entry lot %.2f menunggu sinyal.",
                     MaxMartingaleStep, lossStreak, nextLot);
         waitTrendSignal = true;
        }

      // Notifikasi step tinggi
      if(NotifyStep > 0 && lossStreak >= NotifyStep && lossStreak != prevLossStreak)
         Notify(StringFormat("%s: step martingale %d, rugi akumulasi %.2f, lot berikut %.2f",
                             _Symbol, lossStreak, cumLossSinceWin, nextLot));
      prevLossStreak = lossStreak;
      needHistoryScan = false;
     }

   // 3. Cek risiko akun (equity stop & batas rugi harian)
   if(!RiskChecks())
     {
      UpdateChartComment();
      return;
     }

   // 4. Posisi masih terbuka: kelola umur posisi, lalu tunggu
   if(CountOpenPositions() > 0)
     {
      ManageOpenPosition();
      eaStatus = "POSISI TERBUKA - menunggu TP/SL";
      UpdateChartComment();
      return;
     }

   // 5. Backoff setelah order gagal
   if(lastOrderFail > 0 && TimeCurrent() - lastOrderFail < OrderRetrySec)
     {
      eaStatus = StringFormat("Jeda %d dtk setelah order gagal (%d/%d)",
                              OrderRetrySec - (int)(TimeCurrent() - lastOrderFail), orderFailCount, MaxOrderFailures);
      UpdateChartComment();
      return;
     }

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   bool canLog = (TimeCurrent() - lastFilterLog >= 60);
   string why = "";

   // 6. Filter kondisi pasar/akun
   if(SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE) != SYMBOL_TRADE_MODE_FULL)
     { Hold("pasar tutup / trading simbol dibatasi", canLog); return; }

   if(IsNettingAccount() && ForeignPositionOnSymbol())
     { Hold("akun netting: ada posisi lain di simbol ini (manual/EA lain)", canLog); return; }

   double spreadPips = (ask - bid) / pipsToPoints;
   if(MaxSpread_Pips > 0 && spreadPips > MaxSpread_Pips)
     { Hold(StringFormat("spread %.1f pips > batas %.1f pips", spreadPips, MaxSpread_Pips), canLog); return; }

   if(UseTimeFilter && TimeFilterBlocks(why))
     { Hold("filter waktu: " + why, canLog); return; }

   // 7. Logika sinyal
   if(waitTrendSignal)
     {
      if(UseUTBotSignal)
        {
         if(utbotSignalDir == 0)
           {
            eaStatus = StringFormat("MENUNGGU sinyal UT Bot (TS %s)", DoubleToString(utbotTS, _Digits));
            UpdateChartComment();
            return;
           }
         nextDirection = (utbotSignalDir > 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
        }
      if(UseADXFilter && !IsTrending())
        { Hold(StringFormat("sideway (ADX %.1f < %.1f)", lastADXValue, ADX_Threshold), canLog); return; }
     }
   else if(UseUTBotSignal && CheckSwitchConflict)
     {
      // Entry lanjutan martingale: jika SL kena karena spike tapi trend UT Bot
      // belum berbalik, switching justru salah arah -> tunda sampai trend sejalan
      // atau muncul sinyal baru (sinyal baru menentukan arah).
      if(utbotSignalDir != 0)
         nextDirection = (utbotSignalDir > 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      else
        {
         int switchDir = (nextDirection == ORDER_TYPE_BUY) ? 1 : -1;
         if(utbotTrendDir != 0 && utbotTrendDir != switchDir)
           {
            Hold(StringFormat("switching ke %s ditunda, trend UT Bot masih %s",
                              switchDir > 0 ? "BUY" : "SELL", utbotTrendDir > 0 ? "BUY" : "SELL"), canLog);
            return;
           }
        }
     }

   // 8. Kalkulasi lot + validasi broker
   double lot = NormalizeLot(nextLot);
   double volLimit = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_LIMIT);
   if(volLimit > 0 && lot > volLimit)
     {
      PrintFormat("Lot %.2f melebihi SYMBOL_VOLUME_LIMIT %.2f, dipotong.", lot, volLimit);
      lot = volLimit;
     }

   double price = (nextDirection == ORDER_TYPE_BUY) ? ask : bid;
   double marginNeed = 0;
   if(!OrderCalcMargin((ENUM_ORDER_TYPE)nextDirection, _Symbol, lot, price, marginNeed))
     { Hold("gagal hitung margin: " + IntegerToString(GetLastError()), canLog); return; }
   if(marginNeed > AccountInfoDouble(ACCOUNT_MARGIN_FREE))
     {
      Hold(StringFormat("margin tidak cukup (butuh %.2f, free %.2f)", marginNeed, AccountInfoDouble(ACCOUNT_MARGIN_FREE)), canLog);
      if(canLog) Notify(StringFormat("%s: margin tidak cukup untuk lot %.2f (butuh %.2f)", _Symbol, lot, marginNeed));
      return;
     }

   // 9. Eksekusi
   double sl = 0, tp = 0;
   bool sent = false;
   if(nextDirection == ORDER_TYPE_BUY)
     {
      sl = NormalizeDouble(ask - StopLoss_Pips * pipsToPoints, _Digits);
      tp = NormalizeDouble(ask + TakeProfit_Pips * pipsToPoints, _Digits);
      sent = trade.Buy(lot, _Symbol, ask, sl, tp, "SAR Martingale Buy");
     }
   else
     {
      sl = NormalizeDouble(bid + StopLoss_Pips * pipsToPoints, _Digits);
      tp = NormalizeDouble(bid - TakeProfit_Pips * pipsToPoints, _Digits);
      sent = trade.Sell(lot, _Symbol, bid, sl, tp, "SAR Martingale Sell");
     }

   if(!sent || trade.ResultRetcode() != TRADE_RETCODE_DONE)
     {
      lastOrderFail = TimeCurrent();
      orderFailCount++;
      PrintFormat("Order gagal (%d/%d): retcode=%d (%s), lot=%.2f",
                  orderFailCount, MaxOrderFailures, trade.ResultRetcode(), trade.ResultRetcodeDescription(), lot);
      eaStatus = StringFormat("ORDER GAGAL: %s (retcode %d)", trade.ResultRetcodeDescription(), trade.ResultRetcode());
      if(MaxOrderFailures > 0 && orderFailCount >= MaxOrderFailures)
         HaltEA(StringFormat("%d order gagal beruntun (%s)", orderFailCount, trade.ResultRetcodeDescription()));
     }
   else
     {
      eaStatus = "Order terkirim";
      orderFailCount  = 0;
      lastOrderFail   = 0;
      utbotSignalDir  = 0;   // sinyal terpakai
      utbotSignalBarsLeft = 0;
      if(lot > cycleMaxLot) cycleMaxLot = lot;
     }
   UpdateChartComment();
  }

//+------------------------------------------------------------------+
//| Helper status "ditahan" + log terbatas 1x/menit                  |
//+------------------------------------------------------------------+
void Hold(string reason, bool canLog)
  {
   if(canLog)
     {
      Print("Entry ditahan: ", reason);
      lastFilterLog = TimeCurrent();
     }
   eaStatus = "DITAHAN: " + reason;
   UpdateChartComment();
  }

//+------------------------------------------------------------------+
//| Henti EA permanen (sampai dipasang ulang)                         |
//+------------------------------------------------------------------+
void HaltEA(string reason)
  {
   eaHalted   = true;
   haltReason = reason;
   Print("EA DIHENTIKAN: ", reason);
   Notify(_Symbol + ": EA DIHENTIKAN - " + reason);
   LogCSV("HALT", 0, 0, 0, reason);
  }

//+------------------------------------------------------------------+
//| Cek risiko akun: equity stop & batas rugi harian                  |
//+------------------------------------------------------------------+
bool RiskChecks()
  {
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);

   // Equity stop terhadap balance awal sesi
   if(MaxDrawdownPct > 0 && startBalance > 0)
     {
      double floor = startBalance * (1.0 - MaxDrawdownPct / 100.0);
      if(equity <= floor)
        {
         if(CloseOnEquityStop) CloseAllOwnPositions();
         HaltEA(StringFormat("equity %.2f <= batas %.2f (drawdown %.1f%%)", equity, floor, MaxDrawdownPct));
         eaStatus = "HENTI: " + haltReason;
         return false;
        }
     }

   // Batas rugi harian (realized hari ini + floating)
   if(DailyLossLimit > 0)
     {
      datetime todayStart = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
      if(dailyPauseDay == todayStart)
        {
         eaStatus = StringFormat("PAUSE HARIAN: rugi hari ini mencapai batas %.2f", DailyLossLimit);
         return false;
        }
      double floating = OwnFloatingProfit();
      if(statProfitToday + floating <= -DailyLossLimit)
        {
         dailyPauseDay = todayStart;
         PrintFormat("Batas rugi harian tercapai: realized %.2f + floating %.2f. Tidak entry sampai besok.", statProfitToday, floating);
         Notify(StringFormat("%s: batas rugi harian %.2f tercapai", _Symbol, DailyLossLimit));
         eaStatus = "PAUSE HARIAN: batas rugi tercapai";
         return false;
        }
     }
   return true;
  }

//+------------------------------------------------------------------+
//| Kelola posisi terbuka: batas umur posisi                          |
//+------------------------------------------------------------------+
void ManageOpenPosition()
  {
   if(MaxPositionDays <= 0) return;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol || PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      datetime opened = (datetime)PositionGetInteger(POSITION_TIME);
      if(TimeCurrent() - opened >= MaxPositionDays * 86400)
        {
         PrintFormat("Posisi #%I64u berumur > %d hari, ditutup (hasil dihitung dari profit bersih).", ticket, MaxPositionDays);
         if(!trade.PositionClose(ticket))
            PrintFormat("Gagal tutup posisi #%I64u: %s", ticket, trade.ResultRetcodeDescription());
        }
     }
  }

//+------------------------------------------------------------------+
void CloseAllOwnPositions()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         trade.PositionClose(ticket);
     }
  }

//+------------------------------------------------------------------+
double OwnFloatingProfit()
  {
   double p = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         p += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
     }
   return p;
  }

//+------------------------------------------------------------------+
bool IsNettingAccount()
  {
   long mode = AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   return (mode == ACCOUNT_MARGIN_MODE_RETAIL_NETTING || mode == ACCOUNT_MARGIN_MODE_EXCHANGE);
  }

bool ForeignPositionOnSymbol()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Filter waktu (server): rollover, Jumat sore, jam trading          |
//+------------------------------------------------------------------+
bool TimeFilterBlocks(string &why)
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int minuteOfDay = dt.hour * 60 + dt.min;

   // Jarak ke rollover (menghitung lintas tengah malam)
   int rolloverMin = RolloverHour * 60;
   int diff = MathAbs(minuteOfDay - rolloverMin);
   diff = MathMin(diff, 1440 - diff);
   if(RolloverBufferMin > 0 && diff <= RolloverBufferMin)
     { why = StringFormat("rollover +/-%d mnt", RolloverBufferMin); return true; }

   if(FridayStopHour > 0 && dt.day_of_week == 5 && dt.hour >= FridayStopHour)
     { why = StringFormat("Jumat >= %02d:00", FridayStopHour); return true; }

   if(dt.day_of_week == 0 || dt.day_of_week == 6)
     { why = "akhir pekan"; return true; }

   // Sesi trading simbol (Exness gold ada jeda harian; SYMBOL_TRADE_MODE tidak menangkap ini)
   if(!InTradeSession(why))
      return true;

   if(dt.hour < TradeStartHour || dt.hour >= TradeEndHour)
     { why = StringFormat("di luar jam %02d-%02d", TradeStartHour, TradeEndHour); return true; }

   return false;
  }

//+------------------------------------------------------------------+
//| Cek sesi trading simbol hari ini (+ buffer setelah sesi dibuka)   |
//+------------------------------------------------------------------+
bool InTradeSession(string &why)
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   long secOfDay = dt.hour * 3600 + dt.min * 60 + dt.sec;
   datetime from = 0, to = 0;
   int sessions = 0;
   for(int i = 0; i < 10; i++)
     {
      if(!SymbolInfoSessionTrade(_Symbol, (ENUM_DAY_OF_WEEK)dt.day_of_week, i, from, to))
         break;
      sessions++;
      long f = (long)from, t = (long)to;
      if(secOfDay >= f && secOfDay < t)
        {
         if(SessionOpenBufferMin > 0 && secOfDay - f < SessionOpenBufferMin * 60)
           { why = StringFormat("%d mnt pertama setelah sesi buka", SessionOpenBufferMin); return false; }
         return true;
        }
     }
   if(sessions == 0) return true; // broker tidak memberi info sesi: anggap buka
   why = "di luar sesi trading simbol";
   return false;
  }

//+------------------------------------------------------------------+
//| UT Bot: satu langkah kalkulasi trailing stop, mengembalikan sinyal|
//+------------------------------------------------------------------+
int UTBotStep(double src, double src_prev, double atr)
  {
   double nLoss = UTBot_KeyValue * atr;
   double ts;
   if(src > utbotTS && src_prev > utbotTS)      ts = MathMax(utbotTS, src - nLoss);
   else if(src < utbotTS && src_prev < utbotTS) ts = MathMin(utbotTS, src + nLoss);
   else if(src > utbotTS)                       ts = src - nLoss;
   else                                         ts = src + nLoss;

   int sig = 0;
   if(utbotTS > 0) // abaikan sinyal dari kondisi awal TS = 0
     {
      if(src > ts && src_prev <= utbotTS) sig = 1;
      if(src < ts && src_prev >= utbotTS) sig = -1;
     }
   utbotTS = ts;
   utbotTrendDir = (src > ts) ? 1 : -1;
   return sig;
  }

//+------------------------------------------------------------------+
//| Warm-up: hitung ulang trailing dari N bar terakhir saat init      |
//+------------------------------------------------------------------+
void WarmupUTBot()
  {
   double atrBuf[], closes[];
   ArraySetAsSeries(atrBuf, true);
   ArraySetAsSeries(closes, true);
   int nAtr = CopyBuffer(utbotAtrHandle, 0, 1, WarmupBars, atrBuf);
   int nCls = CopyClose(_Symbol, UTBot_Timeframe, 1, WarmupBars + 1, closes);
   if(nAtr < 2 || nCls < 3)
     {
      Print("Warm-up UT Bot: data belum siap, akan dicoba lagi di tick berikutnya.");
      return;
     }
   utbotWarmed = true;
   int n = MathMin(nAtr, nCls - 1);
   utbotTS = 0;
   int lastSig = 0;
   for(int i = n - 1; i >= 0; i--)          // dari bar tertua ke bar 1
      lastSig = UTBotStep(closes[i], closes[i + 1], atrBuf[i]);

   utbotLastBar = iTime(_Symbol, UTBot_Timeframe, 0);
   if(lastSig != 0)
     {
      utbotSignalDir = lastSig;
      utbotSignalBarsLeft = SignalValidBars;
     }
   PrintFormat("Warm-up UT Bot selesai (%d bar): TS=%s, trend=%s, sinyal=%d",
               n, DoubleToString(utbotTS, _Digits), utbotTrendDir > 0 ? "BUY" : "SELL", lastSig);
  }

//+------------------------------------------------------------------+
//| UT Bot: evaluasi per bar baru + masa berlaku sinyal               |
//+------------------------------------------------------------------+
void UpdateUTBotSignal()
  {
   if(!UseUTBotSignal) return;

   // Ulangi warm-up jika saat OnInit data indikator belum tersedia
   if(!utbotWarmed)
     {
      WarmupUTBot();
      if(utbotWarmed) return;
     }

   datetime curBar = iTime(_Symbol, UTBot_Timeframe, 0);
   if(curBar == 0 || curBar == utbotLastBar) return;

   double atrBuf[1];
   if(CopyBuffer(utbotAtrHandle, 0, 1, 1, atrBuf) < 1) return;

   double src      = iClose(_Symbol, UTBot_Timeframe, 1);
   double src_prev = iClose(_Symbol, UTBot_Timeframe, 2);
   int sig = UTBotStep(src, src_prev, atrBuf[0]);

   if(sig != 0)
     {
      utbotSignalDir = sig;
      utbotSignalBarsLeft = SignalValidBars;
      PrintFormat("Sinyal UT Bot: %s (close %s, TS %s)", sig > 0 ? "BUY" : "SELL",
                  DoubleToString(src, _Digits), DoubleToString(utbotTS, _Digits));
     }
   else if(utbotSignalDir != 0)
     {
      // Masa berlaku berkurang hanya saat tidak ada posisi (sinyal "antre" saat posisi terbuka)
      if(CountOpenPositions() == 0)
        {
         utbotSignalBarsLeft--;
         if(utbotSignalBarsLeft <= 0)
           {
            Print("Sinyal UT Bot hangus (masa berlaku habis).");
            utbotSignalDir = 0;
           }
        }
      // Sinyal yang berlawanan dengan trend sekarang tidak valid lagi
      else if(utbotTrendDir != 0 && utbotTrendDir != utbotSignalDir)
         utbotSignalDir = 0;
     }
   utbotLastBar = curBar;
  }

//+------------------------------------------------------------------+
//| Lot recovery berbasis kerugian riil                               |
//+------------------------------------------------------------------+
double PipValuePerLot()
  {
   double tickVal  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSize <= 0) return 0;
   return tickVal / tickSize * pipsToPoints;
  }

double CalcRecoveryLot(double cumLoss)
  {
   double pv = PipValuePerLot();
   if(pv <= 0 || TakeProfit_Pips <= 0) return nextLot; // fallback ke martingale biasa
   double target = RecoveryTargetPips * pv * InitialLot;        // target profit siklus (uang)
   double lot    = (cumLoss + target) / (TakeProfit_Pips * pv); // lot agar TP menutup rugi + target
   PrintFormat("Recovery riil: rugi %.2f + target %.2f -> lot %.3f (martingale x%.1f = %.3f)",
               cumLoss, target, lot, LotMultiplier, nextLot);
   return lot;
  }

//+------------------------------------------------------------------+
//| Statistik histori (sejak historyFrom)                             |
//+------------------------------------------------------------------+
void UpdateTradeStats()
  {
   statTotalTrades = 0; statWins = 0; statLosses = 0; statTotalProfit = 0;
   statTradesToday = 0; statProfitToday = 0; statLastTrade = "-";
   datetime todayStart = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));

   HistorySelect(historyFrom, TimeCurrent());
   int totalDeals = HistoryDealsTotal();
   for(int i = 0; i < totalDeals; i++)
     {
      ulong d = HistoryDealGetTicket(i);
      if(d == 0) continue;
      if(HistoryDealGetString(d, DEAL_SYMBOL) != _Symbol || HistoryDealGetInteger(d, DEAL_MAGIC) != MagicNumber) continue;
      if(HistoryDealGetInteger(d, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;

      double net = HistoryDealGetDouble(d, DEAL_PROFIT) + HistoryDealGetDouble(d, DEAL_SWAP) + HistoryDealGetDouble(d, DEAL_COMMISSION);
      long reason = HistoryDealGetInteger(d, DEAL_REASON);
      datetime t = (datetime)HistoryDealGetInteger(d, DEAL_TIME);
      bool isWin = (reason == DEAL_REASON_TP) ? true : (reason == DEAL_REASON_SL) ? false : (net > 0);

      statTotalTrades++; statTotalProfit += net;
      if(isWin) statWins++; else statLosses++;
      if(t >= todayStart) { statTradesToday++; statProfitToday += net; }

      long dealType = HistoryDealGetInteger(d, DEAL_TYPE);
      string dirText = (dealType == DEAL_TYPE_SELL) ? "BUY" : "SELL";
      statLastTrade = StringFormat("%s %.2f lot, %s %.2f (%s)", dirText, HistoryDealGetDouble(d, DEAL_VOLUME),
                                   isWin ? "WIN" : "LOSS", net, TimeToString(t, TIME_DATE|TIME_MINUTES));

      // Log CSV untuk deal yang belum dicatat
      if(d > lastLoggedDeal)
        {
         string reasonTxt = (reason == DEAL_REASON_TP) ? "TP" : (reason == DEAL_REASON_SL) ? "SL" : "CLOSE";
         LogCSV(isWin ? "WIN" : "LOSS", HistoryDealGetDouble(d, DEAL_VOLUME), net, lossStreak, dirText + " " + reasonTxt);
         if(!isWin && net < cycleWorstLoss) cycleWorstLoss = net;
         if(isWin && prevLossStreak > 0)
           {
            LogCSV("CYCLE_END", cycleMaxLot, net, prevLossStreak + 1,
                   StringFormat("rugi terdalam %.2f", cycleWorstLoss));
            cycleMaxLot = 0; cycleWorstLoss = 0;
           }
         lastLoggedDeal = d;
        }
     }
  }

//+------------------------------------------------------------------+
//| Log CSV: MQL5\Files\SARM_<simbol>_<magic>.csv                     |
//+------------------------------------------------------------------+
void LogCSV(string evt, double lot, double net, int step, string note)
  {
   if(!LogToCSV) return;
   string fname = "SARM_" + _Symbol + "_" + IntegerToString((int)MagicNumber) + ".csv";
   bool isNew = !FileIsExist(fname);
   int h = FileOpen(fname, FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(h == INVALID_HANDLE) { Print("Gagal buka file log: ", GetLastError()); return; }
   FileSeek(h, 0, SEEK_END);
   if(isNew) FileWrite(h, "waktu;event;lot;net;step;balance;equity;catatan");
   FileWrite(h, StringFormat("%s;%s;%.3f;%.2f;%d;%.2f;%.2f;%s",
                             TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS), evt, lot, net, step,
                             AccountInfoDouble(ACCOUNT_BALANCE), AccountInfoDouble(ACCOUNT_EQUITY), note));
   FileClose(h);
  }

//+------------------------------------------------------------------+
//| Notifikasi push (throttle 60 detik)                               |
//+------------------------------------------------------------------+
void Notify(string msg)
  {
   if(!UsePushNotify) return;
   if(TimeCurrent() - lastNotifyTime < 60) return;
   if(!SendNotification(msg))
      Print("Notifikasi gagal (cek MetaQuotes ID di Tools > Options > Notifications): ", GetLastError());
   lastNotifyTime = TimeCurrent();
  }

//+------------------------------------------------------------------+
//| Tampilan Comment                                                  |
//+------------------------------------------------------------------+
void UpdateChartComment()
  {
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double spreadPoints = (ask - bid) / _Point;
   string currency = AccountInfoString(ACCOUNT_CURRENCY);

   int posCount = 0; double posProfit = 0; string posInfo = "-"; double posSL = 0, posTP = 0; datetime posTime = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
        {
         posCount++;
         posProfit += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
         posInfo = StringFormat("%s %.2f lot @ %s",
                                (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? "BUY" : "SELL",
                                PositionGetDouble(POSITION_VOLUME),
                                DoubleToString(PositionGetDouble(POSITION_PRICE_OPEN), _Digits));
         posSL = PositionGetDouble(POSITION_SL); posTP = PositionGetDouble(POSITION_TP);
         posTime = (datetime)PositionGetInteger(POSITION_TIME);
        }
     }

   string adxInfo = UseADXFilter ? StringFormat("%.1f (ambang %.1f)", lastADXValue, ADX_Threshold) : "OFF";
   string utbotInfo = "OFF";
   if(UseUTBotSignal)
     {
      string trend = (utbotTrendDir > 0) ? "trend BUY" : (utbotTrendDir < 0) ? "trend SELL" : "warm-up";
      if(utbotSignalDir != 0)
         utbotInfo = StringFormat("SINYAL %s (%d bar lagi) | %s", utbotSignalDir > 0 ? "BUY" : "SELL", utbotSignalBarsLeft, trend);
      else
         utbotInfo = StringFormat("menunggu (TS %s) | %s", DoubleToString(utbotTS, _Digits), trend);
     }

   double winRate = (statTotalTrades > 0) ? (100.0 * statWins / statTotalTrades) : 0;
   bool terminalTrade = (bool)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED);
   bool eaTrade = (bool)MQLInfoInteger(MQL_TRADE_ALLOWED);
   string tradeAllowed = (terminalTrade && eaTrade) ? "AKTIF" :
                         (!terminalTrade ? "NONAKTIF (AutoTrading terminal OFF)" : "NONAKTIF (Allow Algo Trading EA OFF)");
   double sessionPL = AccountInfoDouble(ACCOUNT_EQUITY) - startBalance;
   double ddFloor = (MaxDrawdownPct > 0) ? startBalance * (1.0 - MaxDrawdownPct / 100.0) : 0;

   string text = "\n";
   text += "=== SAR MARTINGALE v1.34 XAUUSD Exness Cent ===\n";
   text += StringFormat("%s chart %s | sinyal %s | Server: %s\n", _Symbol, EnumToString(_Period),
                        EnumToString(UTBot_Timeframe), TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS));
   text += "AutoTrading : " + tradeAllowed + "\n";
   text += "Status      : " + eaStatus + "\n";
   text += "---------------------------------------------\n";
   text += StringFormat("Bid/Ask     : %s / %s\n", DoubleToString(bid, _Digits), DoubleToString(ask, _Digits));
   text += StringFormat("Spread      : %.1f pips (maks %.1f) | 1 pip = %s\n", spreadPoints * _Point / pipsToPoints, MaxSpread_Pips, DoubleToString(pipsToPoints, _Digits));
   text += "UT Bot      : " + utbotInfo + "\n";
   text += "ADX         : " + adxInfo + "\n";
   text += "---------------------------------------------\n";
   if(posCount > 0)
     {
      text += "Posisi      : " + posInfo + "\n";
      text += StringFormat("SL / TP     : %s / %s\n", DoubleToString(posSL, _Digits), DoubleToString(posTP, _Digits));
      text += StringFormat("Floating P/L: %.2f %s | umur %.1f hari%s\n", posProfit, currency,
                           (TimeCurrent() - posTime) / 86400.0,
                           (MaxPositionDays > 0) ? StringFormat(" (maks %d)", MaxPositionDays) : "");
     }
   else
     {
      string dirText = (waitTrendSignal && UseUTBotSignal) ? "ikut sinyal UT Bot" : ((nextDirection == ORDER_TYPE_BUY) ? "BUY" : "SELL");
      text += StringFormat("Entry next  : %s, %.2f lot (%s, plafon %.2f)\n", dirText, nextLot,
                           UseLossBasedRecovery ? "recovery riil" : StringFormat("x%.1f", LotMultiplier),
                           (MaxLot > 0) ? MaxLot : SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX));
     }
   text += StringFormat("Step        : %d dari %s%s | rugi akumulasi %.2f\n", lossStreak,
                        (MaxMartingaleStep > 0) ? IntegerToString(MaxMartingaleStep) : "tanpa batas",
                        (MaxMartingaleStep > 0 && lossStreak >= MaxMartingaleStep) ? " (tunggu sinyal)" : "", cumLossSinceWin);
   text += "Trade akhir : " + statLastTrade + "\n";
   text += "---------------------------------------------\n";
   text += StringFormat("Hari ini    : %d trade | P/L %.2f %s%s\n", statTradesToday, statProfitToday, currency,
                        (DailyLossLimit > 0) ? StringFormat(" (batas -%.2f)", DailyLossLimit) : "");
   text += StringFormat("Total       : %d trade (W:%d / L:%d, WR %.1f%%)\n", statTotalTrades, statWins, statLosses, winRate);
   text += StringFormat("Total P/L   : %.2f %s | Sesi: %+.2f %s\n", statTotalProfit, currency, sessionPL, currency);
   text += "---------------------------------------------\n";
   text += StringFormat("Balance     : %.2f | Equity: %.2f%s\n", AccountInfoDouble(ACCOUNT_BALANCE), AccountInfoDouble(ACCOUNT_EQUITY),
                        (ddFloor > 0) ? StringFormat(" | Stop @ %.2f", ddFloor) : "");
   text += StringFormat("Free Margin : %.2f | Margin Lvl: %.0f%%\n", AccountInfoDouble(ACCOUNT_MARGIN_FREE), AccountInfoDouble(ACCOUNT_MARGIN_LEVEL));
   Comment(text);
  }

//+------------------------------------------------------------------+
bool IsTrending()
  {
   double adx[1];
   if(CopyBuffer(adxHandle, MAIN_LINE, 1, 1, adx) < 1) { lastADXValue = 0; return false; }
   lastADXValue = adx[0];
   return (adx[0] >= ADX_Threshold);
  }

//+------------------------------------------------------------------+
int CountOpenPositions()
  {
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == MagicNumber) count++;
     }
   return count;
  }

//+------------------------------------------------------------------+
//| Ekstrak arah, lot, loss beruntun, dan akumulasi rugi sejak win    |
//+------------------------------------------------------------------+
bool GetLastTradeInfo(int &next_dir, double &next_lot, int &loss_streak, double &cum_loss)
  {
   HistorySelect(historyFrom, TimeCurrent());
   int totalDeals = HistoryDealsTotal();
   bool foundLast = false;
   loss_streak = 0; cum_loss = 0;

   for(int i = totalDeals - 1; i >= 0; i--)
     {
      ulong d = HistoryDealGetTicket(i);
      if(d == 0) continue;
      if(HistoryDealGetString(d, DEAL_SYMBOL) != _Symbol || HistoryDealGetInteger(d, DEAL_MAGIC) != MagicNumber) continue;
      if(HistoryDealGetInteger(d, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;

      long reason = HistoryDealGetInteger(d, DEAL_REASON);
      double net = HistoryDealGetDouble(d, DEAL_PROFIT) + HistoryDealGetDouble(d, DEAL_SWAP) + HistoryDealGetDouble(d, DEAL_COMMISSION);
      bool isWin = (reason == DEAL_REASON_TP) ? true : (reason == DEAL_REASON_SL) ? false : (net > 0);

      if(!foundLast)
        {
         long   dealType = HistoryDealGetInteger(d, DEAL_TYPE);
         double lastLot  = HistoryDealGetDouble(d, DEAL_VOLUME);
         int lastPositionType = (dealType == DEAL_TYPE_SELL) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
         if(isWin)
           {
            next_dir = lastPositionType; next_lot = InitialLot; loss_streak = 0;
            return true;
           }
         next_dir = (lastPositionType == ORDER_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
         next_lot = lastLot * LotMultiplier;
         loss_streak = 1; cum_loss = -net; foundLast = true;
        }
      else
        {
         if(isWin) break;
         loss_streak++; cum_loss += -net;
        }
     }
   return foundLast;
  }

//+------------------------------------------------------------------+
//| Normalisasi lot: step broker, min/max broker, plafon MaxLot       |
//+------------------------------------------------------------------+
double NormalizeLot(double lot)
  {
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double cap     = (MaxLot > 0) ? MathMin(MaxLot, maxLot) : maxLot;

   if(lot > cap)
     {
      PrintFormat("PERINGATAN: Lot %.2f dipotong ke plafon %.2f. Recovery martingale tidak lagi penuh.", lot, cap);
      lot = cap;
     }
   if(lot < minLot) lot = minLot;
   if(stepLot > 0) lot = MathFloor(lot / stepLot + 1e-9) * stepLot;
   return NormalizeDouble(lot, 2);
  }
//+------------------------------------------------------------------+