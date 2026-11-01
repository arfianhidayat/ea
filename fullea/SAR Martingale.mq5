//==============================================
// SAR_Martingale_XAUUSD.mq5
// Hak Cipta 2026 - Trader Saham & Forex
//==============================================
// RINGKASAN STRATEGI
// - Satu posisi saja, TP = SL (1000 pips).
// - Kena TP (WIN): lot kembali ke awal,
//   arah sama, langsung entry lagi.
// - Kena SL (LOSS): arah dibalik (SAR)
//   dan lot dikali LotMultiplier.
// - Entry pertama butuh UT Bot + ADX.
//==============================================
// STRUKTUR FILE
// 1. Input
// 2. Variabel global
// 3. OnInit / OnDeinit / OnTradeTransaction
// 4. OnTick (alur utama)
// 5. Helper: hold, halt, risiko, posisi
// 6. Filter waktu & sesi
// 7. UT Bot
// 8. Recovery, statistik, log, notifikasi
// 9. Panel chart
// 10. Histori deal & normalisasi lot
//==============================================
// CATATAN PERUBAHAN
// v1.37 Lebar baris maks 50 karakter,
//       indentasi 2 spasi, komentar polos.
// v1.35 Setelah WIN langsung entry tanpa
//       sinyal (EntryAfterWinNoSignal).
// v1.30 Plafon lot, equity stop, rugi
//       harian, recovery riil, umur posisi,
//       cek margin, warm-up UT Bot, filter
//       waktu, backoff, log CSV, push.
//==============================================
#property copyright "Trader Saham & Forex"
#property version   "1.37"

// Library standar MQL5 untuk kirim order
#include <Trade\Trade.mqh>

//==============================================
// 1. INPUT
//==============================================

//---------- DASAR -----------------------------
input group "=== DASAR ==="

// Lot pertama tiap siklus.
// Akun cent: 0.05 = 0.0005 lot standar.
input double InitialLot = 0.05;    // Lot awal

// Ukuran 1 pip dalam harga.
// Exness XAUUSD: 0.01. 0 = otomatis.
input double PipSize = 0.01;       // Ukuran pip

// Pengali lot tiap kena SL.
input double LotMultiplier = 2.0;  // Pengali lot

// Target profit (pips). 1000 x 0.01 = $10.
input int TakeProfit_Pips = 1000;  // TP pips

// Stop loss (pips). Samakan dengan TP.
input int StopLoss_Pips = 1000;    // SL pips

// Slippage maksimal (pips).
input double Slippage_Pips = 30.0; // Slippage

// Penanda order milik EA ini.
input ulong MagicNumber = 12345;   // Magic

// Setelah N loss beruntun, entry berikut
// menunggu sinyal lagi. 0 = tanpa batas.
input int MaxMartingaleStep = 2;   // Batas step

// Tidak entry jika spread > nilai ini.
// 0 = abaikan.
input double MaxSpread_Pips = 25.0; // Spread maks

//---------- MANAJEMEN RISIKO ------------------
input group "=== MANAJEMEN RISIKO ==="

// Plafon lot. 0 = ikut maksimal broker.
input double MaxLot = 1.6;         // Plafon lot

// Henti EA jika equity turun % ini dari
// balance awal sesi. 0 = nonaktif.
input double MaxDrawdownPct = 30.0; // Equity stop

// Tutup posisi saat equity stop.
input bool CloseOnEquityStop = true; // Tutup

// Batas rugi harian (mata uang akun).
// Akun cent: 1500 = $15. 0 = nonaktif.
input double DailyLossLimit = 1500; // Rugi harian

// Lot recovery dari rugi riil, bukan x2.
input bool UseLossBasedRecovery = false; // Riil

// Target profit siklus (pips x lot awal)
// untuk mode recovery riil.
input double RecoveryTargetPips = 200; // Target

// Tutup posisi jika umur > N hari. 0 = off.
input int MaxPositionDays = 1;     // Umur maks

// true sekali untuk reset sesi, lalu false.
input bool ResetSession = false;   // Reset sesi

//---------- SINYAL UT BOT ---------------------
input group "=== SINYAL UT BOT ==="

// Arah entry awal ikut sinyal UT Bot.
input bool UseUTBotSignal = true;  // Pakai UT Bot

// Setelah WIN langsung entry lot awal
// searah tanpa tunggu sinyal.
input bool EntryAfterWinNoSignal = true; // Pasca WIN

// Pengali ATR jarak trailing stop.
// Kecil = sinyal sering, besar = jarang.
input double UTBot_KeyValue = 2.0; // Key value

// Periode ATR UT Bot.
input int UTBot_ATR_Period = 10;   // Periode ATR

// Timeframe sinyal UT Bot.
input ENUM_TIMEFRAMES UTBot_Timeframe = PERIOD_M5;

// Sinyal berlaku N bar (antre saat ada posisi).
input int SignalValidBars = 3;     // Berlaku bar

// Bar untuk hitung ulang TS saat dipasang.
input int WarmupBars = 300;        // Bar warm-up

// Tunda switching jika trend UT Bot
// masih berlawanan.
input bool CheckSwitchConflict = true; // Cek konflik

//---------- FILTER ADX ------------------------
input group "=== KONFIRMASI ADX ==="

// Entry awal butuh ADX di atas ambang.
input bool UseADXFilter = true;    // Pakai ADX

// Timeframe ADX (samakan dengan UT Bot).
input ENUM_TIMEFRAMES ADX_Timeframe = PERIOD_M5;

// Periode ADX.
input int ADX_Period = 14;         // Periode ADX

// Minimal ADX agar dianggap trending.
input double ADX_Threshold = 25.0; // Ambang ADX

//---------- FILTER WAKTU ----------------------
input group "=== FILTER WAKTU (server) ==="

// Aktifkan filter waktu.
input bool UseTimeFilter = true;   // Filter waktu

// Jam rollover server (Exness: 0).
input int RolloverHour = 0;        // Jam rollover

// Tidak entry +/- N menit rollover.
input int RolloverBufferMin = 30;  // Buffer rollover

// Tidak entry N menit setelah sesi buka.
input int SessionOpenBufferMin = 15; // Buffer sesi

// Jumat: tidak entry mulai jam ini. 0 = off.
input int FridayStopHour = 20;     // Stop Jumat

// Jam mulai boleh entry.
input int TradeStartHour = 0;      // Jam mulai

// Jam akhir boleh entry (24 = tengah malam).
input int TradeEndHour = 24;       // Jam akhir

//---------- TEKNIS ----------------------------
input group "=== TEKNIS ==="

// Jeda detik setelah order gagal.
input int OrderRetrySec = 30;      // Jeda retry

// Henti EA setelah N gagal beruntun.
input int MaxOrderFailures = 5;    // Maks gagal

// Push notif mulai step ini. 0 = off.
input int NotifyStep = 3;          // Notif step

// Kirim push (perlu MetaQuotes ID).
input bool UsePushNotify = true;   // Push notif

// Catat deal & siklus ke CSV.
input bool LogToCSV = true;        // Log CSV

// Baca histori N hari saat pertama dipasang.
input int HistoryLookbackDays = 30; // Histori hari

//==============================================
// 2. VARIABEL GLOBAL
//==============================================

CTrade trade;             // pengirim order
double pipsToPoints;      // 1 pip dalam harga
long   slippagePoints;    // slippage (points)

int    adxHandle    = INVALID_HANDLE;
double lastADXValue = 0;
bool   needHistoryScan = true; // ada deal baru

//--- State UT Bot
int      utbotAtrHandle      = INVALID_HANDLE;
double   utbotTS             = 0; // trailing stop
int      utbotSignalDir      = 0; // 1 BUY -1 SELL
int      utbotSignalBarsLeft = 0; // sisa bar
datetime utbotLastBar        = 0;
int      utbotTrendDir       = 0; // close vs TS
bool     utbotWarmed         = false;

//--- Status EA
string eaStatus        = "Inisialisasi...";
int    nextDirection   = ORDER_TYPE_BUY;
double nextLot         = 0;
int    lossStreak      = 0;     // loss beruntun
double cumLossSinceWin = 0;     // rugi sejak win
bool   waitTrendSignal = true;  // tunggu sinyal?
bool   lastWasWin      = false; // trade akhir WIN
bool   eaHalted        = false; // henti permanen
string haltReason      = "";
datetime dailyPauseDay = 0;     // hari pause

//--- Backoff order gagal
datetime lastOrderFail  = 0;
int      orderFailCount = 0;

//--- Persistensi (global variable terminal)
string   gvPrefix;
double   startBalance = 0; // balance awal sesi
datetime historyFrom  = 0; // awal baca histori

//--- Statistik
int    statTotalTrades = 0;
int    statWins        = 0;
int    statLosses      = 0;
int    statTradesToday = 0;
double statTotalProfit = 0;
double statProfitToday = 0;
string statLastTrade   = "-";
ulong  lastLoggedDeal  = 0; // deal terakhir di-log
int    prevLossStreak  = 0;
double cycleMaxLot     = 0; // lot tertinggi siklus
double cycleWorstLoss  = 0; // rugi terdalam siklus

//--- Throttle notifikasi & log
datetime lastNotifyTime = 0;
datetime lastFilterLog  = 0;

//==============================================
// 3. INIT / DEINIT / TRANSACTION
//==============================================

//----------------------------------------------
// OnInit: sekali saat EA dipasang.
//----------------------------------------------
int OnInit() {
  trade.SetExpertMagicNumber(MagicNumber);

  // Ukuran pip: eksplisit atau otomatis
  if(PipSize > 0)
    pipsToPoints = PipSize;
  else if(_Digits == 5 || _Digits == 3)
    pipsToPoints = _Point * 10;
  else
    pipsToPoints = _Point;

  // Slippage pips -> points broker
  double slipPts = Slippage_Pips * pipsToPoints;
  slippagePoints = (long)MathRound(slipPts / _Point);
  trade.SetDeviationInPoints((ulong)slippagePoints);

  string pipTxt = DoubleToString(pipsToPoints,
                                 _Digits);
  PrintFormat("Setup %s: 1 pip = %s | TP %d | SL %d"
              + " | slippage %d pts",
              _Symbol, pipTxt, TakeProfit_Pips,
              StopLoss_Pips, (int)slippagePoints);

  // Estimasi risiko 1 unit & eskalasi
  double pv = PipValuePerLot();
  if(pv > 0) {
    double unit = StopLoss_Pips * pv * InitialLot;
    PrintFormat("Risiko 1 unit = %.2f %s | step3"
                + " %.2f, step5 %.2f, step6 %.2f",
                unit,
                AccountInfoString(ACCOUNT_CURRENCY),
                unit * 7, unit * 31, unit * 63);
  }

  // Prefix global variable (unik magic+simbol)
  gvPrefix = "SARM_"
             + IntegerToString((int)MagicNumber)
             + "_" + _Symbol + "_";

  // Peringatan stops level broker
  long stopsLevel = SymbolInfoInteger(_Symbol,
                      SYMBOL_TRADE_STOPS_LEVEL);
  double minPips = MathMin(TakeProfit_Pips,
                           StopLoss_Pips);
  double minPts = minPips * pipsToPoints / _Point;
  if(stopsLevel > 0 && minPts < stopsLevel)
    PrintFormat("PERINGATAN: SL/TP %.0f pts <"
                + " batas broker %d pts.",
                minPts, stopsLevel);

  // Info swap
  PrintFormat("Swap %s: long %.2f | short %.2f",
              _Symbol,
              SymbolInfoDouble(_Symbol,
                               SYMBOL_SWAP_LONG),
              SymbolInfoDouble(_Symbol,
                               SYMBOL_SWAP_SHORT));

  // Handle indikator
  if(UseADXFilter) {
    adxHandle = iADX(_Symbol, ADX_Timeframe,
                     ADX_Period);
    if(adxHandle == INVALID_HANDLE) {
      Print("Gagal handle ADX: ", GetLastError());
      return(INIT_FAILED);
    }
  }
  if(UseUTBotSignal) {
    utbotAtrHandle = iATR(_Symbol, UTBot_Timeframe,
                          UTBot_ATR_Period);
    if(utbotAtrHandle == INVALID_HANDLE) {
      Print("Gagal handle ATR: ", GetLastError());
      return(INIT_FAILED);
    }
  }

  // Reset sesi jika diminta
  string gvBal  = gvPrefix + "StartBalance";
  string gvHist = gvPrefix + "HistoryFrom";
  if(ResetSession) {
    GlobalVariableDel(gvBal);
    GlobalVariableDel(gvHist);
    Print("Sesi di-reset.");
  }

  // Balance awal sesi (persisten)
  if(GlobalVariableCheck(gvBal))
    startBalance = GlobalVariableGet(gvBal);
  else {
    startBalance =
        AccountInfoDouble(ACCOUNT_BALANCE);
    GlobalVariableSet(gvBal, startBalance);
  }

  // Titik awal histori (persisten)
  if(GlobalVariableCheck(gvHist))
    historyFrom =
        (datetime)GlobalVariableGet(gvHist);
  else {
    long back = HistoryLookbackDays * 86400;
    historyFrom = TimeCurrent() - (datetime)back;
    GlobalVariableSet(gvHist, (double)historyFrom);
  }

  // Warm-up UT Bot agar TS tidak mulai dari 0
  if(UseUTBotSignal)
    WarmupUTBot();

  needHistoryScan = true;
  eaHalted = false;
  return(INIT_SUCCEEDED);
}

//----------------------------------------------
// OnDeinit: lepas handle & bersihkan panel.
//----------------------------------------------
void OnDeinit(const int reason) {
  if(adxHandle != INVALID_HANDLE)
    IndicatorRelease(adxHandle);
  if(utbotAtrHandle != INVALID_HANDLE)
    IndicatorRelease(utbotAtrHandle);
  Comment("");
}

//----------------------------------------------
// OnTradeTransaction: tandai histori perlu
// dibaca ulang setiap ada deal baru.
//----------------------------------------------
void OnTradeTransaction(
    const MqlTradeTransaction &trans,
    const MqlTradeRequest &request,
    const MqlTradeResult &result) {
  if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
    needHistoryScan = true;
}

//==============================================
// 4. ONTICK - ALUR UTAMA
//==============================================
void OnTick() {
  // Perbarui sinyal UT Bot (per bar baru)
  UpdateUTBotSignal();

  //--- 1. EA dihentikan permanen
  if(eaHalted) {
    eaStatus = "HENTI: " + haltReason
               + " (pasang ulang EA)";
    UpdateChartComment();
    return;
  }

  //--- 2. Baca histori saat ada deal baru
  if(needHistoryScan) {
    nextDirection   = ORDER_TYPE_BUY;
    nextLot         = InitialLot;
    lossStreak      = 0;
    cumLossSinceWin = 0;
    bool hasHistory = GetLastTradeInfo(
        nextDirection, nextLot,
        lossStreak, cumLossSinceWin);
    UpdateTradeStats();

    // Recovery riil: lot dari rugi + target
    if(UseLossBasedRecovery && lossStreak > 0)
      nextLot = CalcRecoveryLot(cumLossSinceWin);

    // Trade akhir WIN -> entry tanpa sinyal
    lastWasWin = (hasHistory && lossStreak == 0);
    bool skipSignal = EntryAfterWinNoSignal
                      && lastWasWin;
    waitTrendSignal = (lossStreak == 0)
                      && !skipSignal;
    if(skipSignal)
      PrintFormat("Trade akhir WIN: entry %s"
                  + " %.2f lot tanpa sinyal.",
                  DirText(nextDirection), nextLot);

    // Batas step martingale -> tunggu sinyal
    if(MaxMartingaleStep > 0
       && lossStreak >= MaxMartingaleStep) {
      PrintFormat("Batas %d step (loss %d)."
                  + " Lot %.2f tunggu sinyal.",
                  MaxMartingaleStep, lossStreak,
                  nextLot);
      waitTrendSignal = true;
    }

    // Notifikasi step tinggi (sekali/step)
    if(NotifyStep > 0 && lossStreak >= NotifyStep
       && lossStreak != prevLossStreak)
      Notify(StringFormat("%s: step %d, rugi %.2f"
                          + ", lot berikut %.2f",
                          _Symbol, lossStreak,
                          cumLossSinceWin, nextLot));
    prevLossStreak  = lossStreak;
    needHistoryScan = false;
  }

  //--- 3. Cek risiko akun
  if(!RiskChecks()) {
    UpdateChartComment();
    return;
  }

  //--- 4. Ada posisi: kelola umur, tunggu
  if(CountOpenPositions() > 0) {
    ManageOpenPosition();
    eaStatus = "POSISI TERBUKA - tunggu TP/SL";
    UpdateChartComment();
    return;
  }

  //--- 5. Backoff setelah order gagal
  if(lastOrderFail > 0
     && TimeCurrent() - lastOrderFail
        < OrderRetrySec) {
    int lewat = (int)(TimeCurrent() - lastOrderFail);
    int sisa  = OrderRetrySec - lewat;
    eaStatus = StringFormat("Jeda %d dtk (%d/%d)",
                            sisa, orderFailCount,
                            MaxOrderFailures);
    UpdateChartComment();
    return;
  }

  double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
  double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
  bool canLog =
      (TimeCurrent() - lastFilterLog >= 60);
  string why = "";

  //--- 6. Filter pasar & akun
  long tmode = SymbolInfoInteger(_Symbol,
                                 SYMBOL_TRADE_MODE);
  if(tmode != SYMBOL_TRADE_MODE_FULL) {
    Hold("pasar tutup / simbol dibatasi", canLog);
    return;
  }

  if(IsNettingAccount()
     && ForeignPositionOnSymbol()) {
    Hold("akun netting: ada posisi lain", canLog);
    return;
  }

  double spreadPips = (ask - bid) / pipsToPoints;
  if(MaxSpread_Pips > 0
     && spreadPips > MaxSpread_Pips) {
    Hold(StringFormat("spread %.1f > %.1f pips",
                      spreadPips, MaxSpread_Pips),
         canLog);
    return;
  }

  if(UseTimeFilter && TimeFilterBlocks(why)) {
    Hold("filter waktu: " + why, canLog);
    return;
  }

  //--- 7. Logika sinyal
  if(waitTrendSignal) {
    // Entry awal / setelah batas step
    if(UseUTBotSignal) {
      if(utbotSignalDir == 0) {
        eaStatus = "MENUNGGU sinyal UT Bot (TS "
                   + DoubleToString(utbotTS,
                                    _Digits) + ")";
        UpdateChartComment();
        return;
      }
      nextDirection = SigToDir(utbotSignalDir);
    }
    if(UseADXFilter && !IsTrending()) {
      Hold(StringFormat("sideway (ADX %.1f < %.1f)",
                        lastADXValue, ADX_Threshold),
           canLog);
      return;
    }
  }
  else if(lossStreak > 0 && UseUTBotSignal
          && CheckSwitchConflict) {
    // Entry lanjutan: jika SL kena karena spike
    // tapi trend UT Bot belum berbalik, tunda
    // switching sampai trend sejalan atau ada
    // sinyal baru (sinyal baru menentukan arah).
    if(utbotSignalDir != 0)
      nextDirection = SigToDir(utbotSignalDir);
    else {
      int switchDir = 1;
      if(nextDirection != ORDER_TYPE_BUY)
        switchDir = -1;
      if(utbotTrendDir != 0
         && utbotTrendDir != switchDir) {
        string sw = switchDir > 0 ? "BUY" : "SELL";
        string tr = utbotTrendDir > 0
                    ? "BUY" : "SELL";
        Hold(StringFormat("switch %s ditunda,"
                          + " trend %s", sw, tr),
             canLog);
        return;
      }
    }
  }
  // else: trade akhir WIN -> langsung entry

  //--- 8. Kalkulasi lot + validasi broker
  double lot = NormalizeLot(nextLot);
  double volLimit = SymbolInfoDouble(_Symbol,
                      SYMBOL_VOLUME_LIMIT);
  if(volLimit > 0 && lot > volLimit) {
    PrintFormat("Lot %.2f > limit %.2f, dipotong.",
                lot, volLimit);
    lot = volLimit;
  }

  double price = (nextDirection == ORDER_TYPE_BUY)
                 ? ask : bid;
  double marginNeed = 0;
  if(!OrderCalcMargin((ENUM_ORDER_TYPE)nextDirection,
                      _Symbol, lot, price,
                      marginNeed)) {
    Hold("gagal hitung margin: "
         + IntegerToString(GetLastError()), canLog);
    return;
  }
  double freeMargin = AccountInfoDouble(
                        ACCOUNT_MARGIN_FREE);
  if(marginNeed > freeMargin) {
    Hold(StringFormat("margin kurang (butuh %.2f,"
                      + " free %.2f)",
                      marginNeed, freeMargin),
         canLog);
    if(canLog)
      Notify(StringFormat("%s: margin kurang %.2f",
                          _Symbol, lot));
    return;
  }

  //--- 9. Eksekusi order
  double slDist = StopLoss_Pips * pipsToPoints;
  double tpDist = TakeProfit_Pips * pipsToPoints;
  double sl = 0, tp = 0;
  bool sent = false;
  if(nextDirection == ORDER_TYPE_BUY) {
    sl = NormalizeDouble(ask - slDist, _Digits);
    tp = NormalizeDouble(ask + tpDist, _Digits);
    sent = trade.Buy(lot, _Symbol, ask, sl, tp,
                     "SAR Martingale Buy");
  }
  else {
    sl = NormalizeDouble(bid + slDist, _Digits);
    tp = NormalizeDouble(bid - tpDist, _Digits);
    sent = trade.Sell(lot, _Symbol, bid, sl, tp,
                      "SAR Martingale Sell");
  }

  uint rc = trade.ResultRetcode();
  if(!sent || rc != TRADE_RETCODE_DONE) {
    // Order gagal: catat, backoff, halt
    lastOrderFail = TimeCurrent();
    orderFailCount++;
    string rcs = trade.ResultRetcodeDescription();
    PrintFormat("Order gagal (%d/%d): %d %s %.2f",
                orderFailCount, MaxOrderFailures,
                rc, rcs, lot);
    eaStatus = StringFormat("ORDER GAGAL: %s (%d)",
                            rcs, rc);
    if(MaxOrderFailures > 0
       && orderFailCount >= MaxOrderFailures)
      HaltEA(StringFormat("%d order gagal (%s)",
                          orderFailCount, rcs));
  }
  else {
    // Order sukses: reset backoff, sinyal pakai
    eaStatus = "Order terkirim";
    orderFailCount      = 0;
    lastOrderFail       = 0;
    utbotSignalDir      = 0;
    utbotSignalBarsLeft = 0;
    if(lot > cycleMaxLot) cycleMaxLot = lot;
  }
  UpdateChartComment();
}

//==============================================
// 5. HELPER: HOLD, HALT, RISIKO, POSISI
//==============================================

//----------------------------------------------
// DirText: ORDER_TYPE -> "BUY"/"SELL".
//----------------------------------------------
string DirText(int dir) {
  return (dir == ORDER_TYPE_BUY) ? "BUY" : "SELL";
}

//----------------------------------------------
// SigToDir: sinyal 1/-1 -> ORDER_TYPE.
//----------------------------------------------
int SigToDir(int sig) {
  if(sig > 0) return ORDER_TYPE_BUY;
  return ORDER_TYPE_SELL;
}

//----------------------------------------------
// Hold: status "ditahan" + log maks 1x/menit.
//----------------------------------------------
void Hold(string reason, bool canLog) {
  if(canLog) {
    Print("Entry ditahan: ", reason);
    lastFilterLog = TimeCurrent();
  }
  eaStatus = "DITAHAN: " + reason;
  UpdateChartComment();
}

//----------------------------------------------
// HaltEA: henti permanen sampai dipasang ulang.
//----------------------------------------------
void HaltEA(string reason) {
  eaHalted   = true;
  haltReason = reason;
  Print("EA DIHENTIKAN: ", reason);
  Notify(_Symbol + ": EA DIHENTIKAN - " + reason);
  LogCSV("HALT", 0, 0, 0, reason);
}

//----------------------------------------------
// RiskChecks: equity stop & rugi harian.
// Return false jika EA tidak boleh entry.
//----------------------------------------------
bool RiskChecks() {
  double equity = AccountInfoDouble(ACCOUNT_EQUITY);

  // Equity stop terhadap balance awal sesi
  if(MaxDrawdownPct > 0 && startBalance > 0) {
    double floor = startBalance
                   * (1.0 - MaxDrawdownPct / 100.0);
    if(equity <= floor) {
      if(CloseOnEquityStop) CloseAllOwnPositions();
      HaltEA(StringFormat("equity %.2f <= %.2f"
                          + " (DD %.1f%%)",
                          equity, floor,
                          MaxDrawdownPct));
      eaStatus = "HENTI: " + haltReason;
      return false;
    }
  }

  // Batas rugi harian (realized + floating)
  if(DailyLossLimit > 0) {
    datetime todayStart = TodayStart();
    if(dailyPauseDay == todayStart) {
      eaStatus = StringFormat("PAUSE HARIAN: %.2f",
                              DailyLossLimit);
      return false;
    }
    double floating = OwnFloatingProfit();
    double today = statProfitToday + floating;
    if(today <= -DailyLossLimit) {
      dailyPauseDay = todayStart;
      PrintFormat("Batas rugi harian: real %.2f"
                  + " + float %.2f. Pause.",
                  statProfitToday, floating);
      Notify(StringFormat("%s: batas rugi harian",
                          _Symbol));
      eaStatus = "PAUSE HARIAN: batas tercapai";
      return false;
    }
  }
  return true;
}

//----------------------------------------------
// TodayStart: datetime awal hari ini (server).
//----------------------------------------------
datetime TodayStart() {
  string d = TimeToString(TimeCurrent(), TIME_DATE);
  return StringToTime(d);
}

//----------------------------------------------
// ManageOpenPosition: tutup posisi terlalu tua.
//----------------------------------------------
void ManageOpenPosition() {
  if(MaxPositionDays <= 0) return;
  for(int i = PositionsTotal() - 1; i >= 0; i--) {
    ulong ticket = PositionGetTicket(i);
    if(ticket == 0) continue;
    if(!IsOwnPosition()) continue;
    datetime opened = (datetime)
        PositionGetInteger(POSITION_TIME);
    long maxAge = MaxPositionDays * 86400;
    if(TimeCurrent() - opened >= maxAge) {
      PrintFormat("Posisi #%I64u > %d hari, tutup.",
                  ticket, MaxPositionDays);
      if(!trade.PositionClose(ticket))
        PrintFormat("Gagal tutup #%I64u: %s", ticket,
                  trade.ResultRetcodeDescription());
    }
  }
}

//----------------------------------------------
// IsOwnPosition: posisi terpilih milik EA ini?
// (panggil setelah PositionGetTicket)
//----------------------------------------------
bool IsOwnPosition() {
  if(PositionGetString(POSITION_SYMBOL) != _Symbol)
    return false;
  long magic = PositionGetInteger(POSITION_MAGIC);
  return (magic == (long)MagicNumber);
}

//----------------------------------------------
// CloseAllOwnPositions: tutup semua posisi EA.
//----------------------------------------------
void CloseAllOwnPositions() {
  for(int i = PositionsTotal() - 1; i >= 0; i--) {
    ulong ticket = PositionGetTicket(i);
    if(ticket == 0) continue;
    if(IsOwnPosition())
      trade.PositionClose(ticket);
  }
}

//----------------------------------------------
// OwnFloatingProfit: floating P/L posisi EA.
//----------------------------------------------
double OwnFloatingProfit() {
  double p = 0;
  for(int i = PositionsTotal() - 1; i >= 0; i--) {
    ulong ticket = PositionGetTicket(i);
    if(ticket == 0) continue;
    if(IsOwnPosition())
      p += PositionGetDouble(POSITION_PROFIT)
           + PositionGetDouble(POSITION_SWAP);
  }
  return p;
}

//----------------------------------------------
// CountOpenPositions: jumlah posisi EA ini.
//----------------------------------------------
int CountOpenPositions() {
  int count = 0;
  for(int i = PositionsTotal() - 1; i >= 0; i--) {
    ulong ticket = PositionGetTicket(i);
    if(ticket == 0) continue;
    if(IsOwnPosition()) count++;
  }
  return count;
}

//----------------------------------------------
// IsNettingAccount: akun netting?
//----------------------------------------------
bool IsNettingAccount() {
  long mode =
      AccountInfoInteger(ACCOUNT_MARGIN_MODE);
  return (mode == ACCOUNT_MARGIN_MODE_RETAIL_NETTING
          || mode == ACCOUNT_MARGIN_MODE_EXCHANGE);
}

//----------------------------------------------
// ForeignPositionOnSymbol: ada posisi lain
// (manual / EA lain) di simbol ini?
//----------------------------------------------
bool ForeignPositionOnSymbol() {
  for(int i = PositionsTotal() - 1; i >= 0; i--) {
    ulong ticket = PositionGetTicket(i);
    if(ticket == 0) continue;
    if(PositionGetString(POSITION_SYMBOL) != _Symbol)
      continue;
    long magic = PositionGetInteger(POSITION_MAGIC);
    if(magic != (long)MagicNumber) return true;
  }
  return false;
}

//==============================================
// 6. FILTER WAKTU & SESI
//==============================================

//----------------------------------------------
// TimeFilterBlocks: true jika waktu sekarang
// dilarang entry. Alasan lewat 'why'.
//----------------------------------------------
bool TimeFilterBlocks(string &why) {
  MqlDateTime dt;
  TimeToStruct(TimeCurrent(), dt);
  int minuteOfDay = dt.hour * 60 + dt.min;

  // Jarak ke rollover (lintas tengah malam)
  int rolloverMin = RolloverHour * 60;
  int diff = MathAbs(minuteOfDay - rolloverMin);
  diff = MathMin(diff, 1440 - diff);
  if(RolloverBufferMin > 0
     && diff <= RolloverBufferMin) {
    why = StringFormat("rollover +/-%d mnt",
                       RolloverBufferMin);
    return true;
  }

  // Jumat sore
  if(FridayStopHour > 0 && dt.day_of_week == 5
     && dt.hour >= FridayStopHour) {
    why = StringFormat("Jumat >= %02d:00",
                       FridayStopHour);
    return true;
  }

  // Akhir pekan
  if(dt.day_of_week == 0 || dt.day_of_week == 6) {
    why = "akhir pekan";
    return true;
  }

  // Sesi trading simbol (gold ada jeda)
  if(!InTradeSession(why))
    return true;

  // Jam trading user
  if(dt.hour < TradeStartHour
     || dt.hour >= TradeEndHour) {
    why = StringFormat("di luar jam %02d-%02d",
                       TradeStartHour, TradeEndHour);
    return true;
  }

  return false;
}

//----------------------------------------------
// InTradeSession: di dalam sesi trading simbol?
// Plus buffer setelah sesi dibuka.
//----------------------------------------------
bool InTradeSession(string &why) {
  MqlDateTime dt;
  TimeToStruct(TimeCurrent(), dt);
  long secOfDay = dt.hour * 3600 + dt.min * 60
                  + dt.sec;
  ENUM_DAY_OF_WEEK dow =
      (ENUM_DAY_OF_WEEK)dt.day_of_week;
  datetime from = 0, to = 0;
  int sessions = 0;
  for(int i = 0; i < 10; i++) {
    if(!SymbolInfoSessionTrade(_Symbol, dow, i,
                               from, to))
      break;
    sessions++;
    long f = (long)from, t = (long)to;
    if(secOfDay >= f && secOfDay < t) {
      long buf = SessionOpenBufferMin * 60;
      if(SessionOpenBufferMin > 0
         && secOfDay - f < buf) {
        why = StringFormat("%d mnt pertama sesi",
                           SessionOpenBufferMin);
        return false;
      }
      return true;
    }
  }
  // Broker tidak memberi info sesi: anggap buka
  if(sessions == 0) return true;
  why = "di luar sesi simbol";
  return false;
}

//==============================================
// 7. UT BOT
//==============================================

//----------------------------------------------
// UTBotStep: satu langkah trailing stop.
// Return 1 = BUY, -1 = SELL, 0 = tidak ada.
//----------------------------------------------
int UTBotStep(double src, double src_prev,
              double atr) {
  double nLoss = UTBot_KeyValue * atr;
  double ts;
  if(src > utbotTS && src_prev > utbotTS)
    ts = MathMax(utbotTS, src - nLoss); // naik
  else if(src < utbotTS && src_prev < utbotTS)
    ts = MathMin(utbotTS, src + nLoss); // turun
  else if(src > utbotTS)
    ts = src - nLoss;                 // balik atas
  else
    ts = src + nLoss;                 // balik bawah

  int sig = 0;
  if(utbotTS > 0) { // abaikan TS awal = 0
    if(src > ts && src_prev <= utbotTS) sig = 1;
    if(src < ts && src_prev >= utbotTS) sig = -1;
  }
  utbotTS = ts;
  utbotTrendDir = (src > ts) ? 1 : -1;
  return sig;
}

//----------------------------------------------
// WarmupUTBot: hitung ulang TS dari N bar
// terakhir saat EA dipasang.
//----------------------------------------------
void WarmupUTBot() {
  double atrBuf[], closes[];
  ArraySetAsSeries(atrBuf, true);
  ArraySetAsSeries(closes, true);
  int nAtr = CopyBuffer(utbotAtrHandle, 0, 1,
                        WarmupBars, atrBuf);
  int nCls = CopyClose(_Symbol, UTBot_Timeframe, 1,
                       WarmupBars + 1, closes);
  if(nAtr < 2 || nCls < 3) {
    Print("Warm-up UT Bot: data belum siap.");
    return;
  }
  utbotWarmed = true;
  int n = MathMin(nAtr, nCls - 1);
  utbotTS = 0;
  int lastSig = 0;
  // Dari bar tertua ke bar 1
  for(int i = n - 1; i >= 0; i--)
    lastSig = UTBotStep(closes[i], closes[i + 1],
                        atrBuf[i]);

  utbotLastBar = iTime(_Symbol, UTBot_Timeframe, 0);
  if(lastSig != 0) {
    utbotSignalDir      = lastSig;
    utbotSignalBarsLeft = SignalValidBars;
  }
  PrintFormat("Warm-up UT Bot %d bar: TS=%s"
              + " trend=%s sinyal=%d", n,
              DoubleToString(utbotTS, _Digits),
              utbotTrendDir > 0 ? "BUY" : "SELL",
              lastSig);
}

//----------------------------------------------
// UpdateUTBotSignal: evaluasi tiap bar baru
// dan kelola masa berlaku sinyal.
//----------------------------------------------
void UpdateUTBotSignal() {
  if(!UseUTBotSignal) return;

  // Ulangi warm-up jika saat OnInit belum siap
  if(!utbotWarmed) {
    WarmupUTBot();
    if(utbotWarmed) return;
  }

  // Hanya proses saat bar baru
  datetime curBar = iTime(_Symbol,
                          UTBot_Timeframe, 0);
  if(curBar == 0 || curBar == utbotLastBar) return;

  double atrBuf[1];
  if(CopyBuffer(utbotAtrHandle, 0, 1, 1, atrBuf) < 1)
    return;

  double src = iClose(_Symbol, UTBot_Timeframe, 1);
  double src_prev = iClose(_Symbol,
                           UTBot_Timeframe, 2);
  int sig = UTBotStep(src, src_prev, atrBuf[0]);

  if(sig != 0) {
    // Sinyal baru
    utbotSignalDir      = sig;
    utbotSignalBarsLeft = SignalValidBars;
    PrintFormat("Sinyal UT Bot: %s (close %s TS %s)",
                sig > 0 ? "BUY" : "SELL",
                DoubleToString(src, _Digits),
                DoubleToString(utbotTS, _Digits));
  }
  else if(utbotSignalDir != 0) {
    // Masa berlaku berkurang hanya saat tidak
    // ada posisi (sinyal antre saat ada posisi)
    if(CountOpenPositions() == 0) {
      utbotSignalBarsLeft--;
      if(utbotSignalBarsLeft <= 0) {
        Print("Sinyal UT Bot hangus.");
        utbotSignalDir = 0;
      }
    }
    // Sinyal berlawanan trend sekarang -> batal
    else if(utbotTrendDir != 0
            && utbotTrendDir != utbotSignalDir)
      utbotSignalDir = 0;
  }
  utbotLastBar = curBar;
}

//==============================================
// 8. RECOVERY, STATISTIK, LOG, NOTIFIKASI
//==============================================

//----------------------------------------------
// PipValuePerLot: nilai 1 pip untuk 1 lot.
//----------------------------------------------
double PipValuePerLot() {
  double tickVal = SymbolInfoDouble(_Symbol,
                     SYMBOL_TRADE_TICK_VALUE);
  double tickSize = SymbolInfoDouble(_Symbol,
                      SYMBOL_TRADE_TICK_SIZE);
  if(tickSize <= 0) return 0;
  return tickVal / tickSize * pipsToPoints;
}

//----------------------------------------------
// CalcRecoveryLot: lot agar TP menutup
// rugi akumulasi + target.
//----------------------------------------------
double CalcRecoveryLot(double cumLoss) {
  double pv = PipValuePerLot();
  if(pv <= 0 || TakeProfit_Pips <= 0)
    return nextLot; // fallback martingale biasa
  double target = RecoveryTargetPips * pv
                  * InitialLot;
  double lot = (cumLoss + target)
               / (TakeProfit_Pips * pv);
  PrintFormat("Recovery riil: rugi %.2f + target"
              + " %.2f -> lot %.3f (x%.1f=%.3f)",
              cumLoss, target, lot,
              LotMultiplier, nextLot);
  return lot;
}

//----------------------------------------------
// UpdateTradeStats: statistik dari histori
// sejak historyFrom + log CSV deal baru.
//----------------------------------------------
void UpdateTradeStats() {
  statTotalTrades = 0; statWins = 0;
  statLosses = 0; statTotalProfit = 0;
  statTradesToday = 0; statProfitToday = 0;
  statLastTrade = "-";
  datetime todayStart = TodayStart();

  HistorySelect(historyFrom, TimeCurrent());
  int totalDeals = HistoryDealsTotal();
  for(int i = 0; i < totalDeals; i++) {
    ulong d = HistoryDealGetTicket(i);
    if(d == 0) continue;
    if(!IsOwnExitDeal(d)) continue;

    double net  = DealNet(d);
    long reason = HistoryDealGetInteger(d,
                                        DEAL_REASON);
    datetime t  = (datetime)
        HistoryDealGetInteger(d, DEAL_TIME);
    bool isWin  = DealIsWin(reason, net);

    statTotalTrades++;
    statTotalProfit += net;
    if(isWin) statWins++; else statLosses++;
    if(t >= todayStart) {
      statTradesToday++;
      statProfitToday += net;
    }

    // Deal SELL keluar = posisi BUY ditutup
    string dirText = DealPosDir(d);
    double vol = HistoryDealGetDouble(d,
                                      DEAL_VOLUME);
    statLastTrade = StringFormat(
        "%s %.2f lot, %s %.2f (%s)",
        dirText, vol, isWin ? "WIN" : "LOSS", net,
        TimeToString(t, TIME_DATE|TIME_MINUTES));

    // Log CSV untuk deal yang belum dicatat
    if(d > lastLoggedDeal) {
      string reasonTxt =
          (reason == DEAL_REASON_TP) ? "TP" :
          (reason == DEAL_REASON_SL) ? "SL" :
          "CLOSE";
      LogCSV(isWin ? "WIN" : "LOSS", vol, net,
             lossStreak, dirText + " " + reasonTxt);
      if(!isWin && net < cycleWorstLoss)
        cycleWorstLoss = net;
      if(isWin && prevLossStreak > 0) {
        LogCSV("CYCLE_END", cycleMaxLot, net,
               prevLossStreak + 1,
               StringFormat("rugi terdalam %.2f",
                            cycleWorstLoss));
        cycleMaxLot = 0; cycleWorstLoss = 0;
      }
      lastLoggedDeal = d;
    }
  }
}

//----------------------------------------------
// IsOwnExitDeal: deal keluar milik EA ini?
//----------------------------------------------
bool IsOwnExitDeal(ulong d) {
  if(HistoryDealGetString(d, DEAL_SYMBOL) != _Symbol)
    return false;
  if(HistoryDealGetInteger(d, DEAL_MAGIC)
     != (long)MagicNumber)
    return false;
  return HistoryDealGetInteger(d, DEAL_ENTRY)
         == DEAL_ENTRY_OUT;
}

//----------------------------------------------
// DealPosDir: arah posisi dari deal keluar.
//----------------------------------------------
string DealPosDir(ulong d) {
  long dealType = HistoryDealGetInteger(d,
                                        DEAL_TYPE);
  if(dealType == DEAL_TYPE_SELL) return "BUY";
  return "SELL";
}

//----------------------------------------------
// DealNet: profit bersih (profit+swap+komisi).
//----------------------------------------------
double DealNet(ulong d) {
  return HistoryDealGetDouble(d, DEAL_PROFIT)
         + HistoryDealGetDouble(d, DEAL_SWAP)
         + HistoryDealGetDouble(d, DEAL_COMMISSION);
}

//----------------------------------------------
// DealIsWin: TP = win, SL = loss, lain = net.
//----------------------------------------------
bool DealIsWin(long reason, double net) {
  if(reason == DEAL_REASON_TP) return true;
  if(reason == DEAL_REASON_SL) return false;
  return (net > 0);
}

//----------------------------------------------
// LogCSV: tulis ke MQL5\Files\SARM_*.csv
//----------------------------------------------
void LogCSV(string evt, double lot, double net,
            int step, string note) {
  if(!LogToCSV) return;
  string fname = "SARM_" + _Symbol + "_"
                 + IntegerToString((int)MagicNumber)
                 + ".csv";
  bool isNew = !FileIsExist(fname);
  int h = FileOpen(fname, FILE_READ|FILE_WRITE
                          |FILE_TXT|FILE_ANSI);
  if(h == INVALID_HANDLE) {
    Print("Gagal buka log: ", GetLastError());
    return;
  }
  FileSeek(h, 0, SEEK_END);
  if(isNew)
    FileWrite(h, "waktu;event;lot;net;step;"
                 + "balance;equity;catatan");
  string now = TimeToString(TimeCurrent(),
                            TIME_DATE|TIME_SECONDS);
  FileWrite(h, StringFormat(
      "%s;%s;%.3f;%.2f;%d;%.2f;%.2f;%s",
      now, evt, lot, net, step,
      AccountInfoDouble(ACCOUNT_BALANCE),
      AccountInfoDouble(ACCOUNT_EQUITY), note));
  FileClose(h);
}

//----------------------------------------------
// Notify: push notification, maks 1x/60 detik.
//----------------------------------------------
void Notify(string msg) {
  if(!UsePushNotify) return;
  if(TimeCurrent() - lastNotifyTime < 60) return;
  if(!SendNotification(msg))
    Print("Notifikasi gagal (cek MetaQuotes ID): ",
          GetLastError());
  lastNotifyTime = TimeCurrent();
}

//==============================================
// 9. PANEL CHART
//==============================================

//----------------------------------------------
// UpdateChartComment: tampilkan status.
//----------------------------------------------
void UpdateChartComment() {
  double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
  double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
  double spreadPips = (ask - bid) / pipsToPoints;
  string cur = AccountInfoString(ACCOUNT_CURRENCY);

  // Info posisi terbuka milik EA
  int posCount = 0;
  double posProfit = 0, posSL = 0, posTP = 0;
  string posInfo = "-";
  datetime posTime = 0;
  for(int i = PositionsTotal() - 1; i >= 0; i--) {
    ulong ticket = PositionGetTicket(i);
    if(ticket == 0) continue;
    if(!IsOwnPosition()) continue;
    posCount++;
    posProfit += PositionGetDouble(POSITION_PROFIT)
                 + PositionGetDouble(POSITION_SWAP);
    long ptype = PositionGetInteger(POSITION_TYPE);
    double openP = PositionGetDouble(
                     POSITION_PRICE_OPEN);
    posInfo = StringFormat("%s %.2f lot @ %s",
        (ptype == POSITION_TYPE_BUY)
            ? "BUY" : "SELL",
        PositionGetDouble(POSITION_VOLUME),
        DoubleToString(openP, _Digits));
    posSL = PositionGetDouble(POSITION_SL);
    posTP = PositionGetDouble(POSITION_TP);
    posTime = (datetime)
        PositionGetInteger(POSITION_TIME);
  }

  // Info ADX
  string adxInfo = "OFF";
  if(UseADXFilter)
    adxInfo = StringFormat("%.1f (ambang %.1f)",
                           lastADXValue,
                           ADX_Threshold);

  // Info UT Bot
  string utbotInfo = "OFF";
  if(UseUTBotSignal) {
    string trend = (utbotTrendDir > 0) ? "BUY" :
                   (utbotTrendDir < 0) ? "SELL" :
                   "warm-up";
    if(utbotSignalDir != 0)
      utbotInfo = StringFormat(
          "SINYAL %s (%d bar) | trend %s",
          utbotSignalDir > 0 ? "BUY" : "SELL",
          utbotSignalBarsLeft, trend);
    else
      utbotInfo = StringFormat(
          "menunggu (TS %s) | trend %s",
          DoubleToString(utbotTS, _Digits), trend);
  }

  // Status autotrading
  bool termTrade = (bool)TerminalInfoInteger(
                     TERMINAL_TRADE_ALLOWED);
  bool eaTrade = (bool)MQLInfoInteger(
                   MQL_TRADE_ALLOWED);
  string tradeAllowed = "AKTIF";
  if(!termTrade)
    tradeAllowed = "NONAKTIF (AutoTrading OFF)";
  else if(!eaTrade)
    tradeAllowed = "NONAKTIF (Algo Trading EA OFF)";

  double winRate = 0;
  if(statTotalTrades > 0)
    winRate = 100.0 * statWins / statTotalTrades;
  double equity = AccountInfoDouble(ACCOUNT_EQUITY);
  double sessionPL = equity - startBalance;
  double ddFloor = 0;
  if(MaxDrawdownPct > 0)
    ddFloor = startBalance
              * (1.0 - MaxDrawdownPct / 100.0);

  // Susun teks panel
  string t = "\n";
  t += "=== SAR MARTINGALE v1.37 XAUUSD ===\n";
  t += StringFormat("%s chart %s | sinyal %s\n",
                    _Symbol, EnumToString(_Period),
                    EnumToString(UTBot_Timeframe));
  t += "Server      : "
       + TimeToString(TimeCurrent(),
                      TIME_DATE|TIME_SECONDS) + "\n";
  t += "AutoTrading : " + tradeAllowed + "\n";
  t += "Status      : " + eaStatus + "\n";
  t += "-----------------------------------\n";
  t += StringFormat("Bid/Ask     : %s / %s\n",
                    DoubleToString(bid, _Digits),
                    DoubleToString(ask, _Digits));
  t += StringFormat("Spread      : %.1f / %.1f\n",
                    spreadPips, MaxSpread_Pips);
  t += "UT Bot      : " + utbotInfo + "\n";
  t += "ADX         : " + adxInfo + "\n";
  t += "-----------------------------------\n";
  if(posCount > 0) {
    t += "Posisi      : " + posInfo + "\n";
    t += StringFormat("SL / TP     : %s / %s\n",
                      DoubleToString(posSL, _Digits),
                      DoubleToString(posTP,
                                     _Digits));
    double umur = (TimeCurrent() - posTime)
                  / 86400.0;
    string maks = "";
    if(MaxPositionDays > 0)
      maks = StringFormat(" (maks %d)",
                          MaxPositionDays);
    t += StringFormat("Floating    : %.2f %s\n",
                      posProfit, cur);
    t += StringFormat("Umur posisi : %.1f hari%s\n",
                      umur, maks);
  }
  else {
    string dirText;
    if(waitTrendSignal && UseUTBotSignal)
      dirText = "ikut sinyal UT Bot";
    else {
      dirText = DirText(nextDirection);
      if(EntryAfterWinNoSignal && lastWasWin)
        dirText += " (lanjut pasca WIN)";
    }
    t += StringFormat("Entry next  : %s, %.2f lot\n",
                      dirText, nextLot);
    string mode = StringFormat("x%.1f",
                               LotMultiplier);
    if(UseLossBasedRecovery) mode = "recovery riil";
    double cap = MaxLot;
    if(cap <= 0)
      cap = SymbolInfoDouble(_Symbol,
                             SYMBOL_VOLUME_MAX);
    t += StringFormat("Mode lot    : %s, max %.2f\n",
                      mode, cap);
  }
  string stepMax = "tanpa batas";
  string stepNote = "";
  if(MaxMartingaleStep > 0) {
    stepMax = IntegerToString(MaxMartingaleStep);
    if(lossStreak >= MaxMartingaleStep)
      stepNote = " (tunggu sinyal)";
  }
  t += StringFormat("Step        : %d dari %s%s\n",
                    lossStreak, stepMax, stepNote);
  t += StringFormat("Rugi akum.  : %.2f %s\n",
                    cumLossSinceWin, cur);
  t += "Trade akhir : " + statLastTrade + "\n";
  t += "-----------------------------------\n";
  string lim = "";
  if(DailyLossLimit > 0)
    lim = StringFormat(" (batas -%.2f)",
                       DailyLossLimit);
  t += StringFormat("Hari ini    : %d | %.2f%s\n",
                    statTradesToday,
                    statProfitToday, lim);
  t += StringFormat("Total       : %d trade\n",
                    statTotalTrades);
  t += StringFormat("Win/Loss    : %d/%d (%.1f%%)\n",
                    statWins, statLosses, winRate);
  t += StringFormat("Total P/L   : %.2f | %+.2f\n",
                    statTotalProfit, sessionPL);
  t += "-----------------------------------\n";
  t += StringFormat("Balance     : %.2f\n",
         AccountInfoDouble(ACCOUNT_BALANCE));
  t += StringFormat("Equity      : %.2f\n", equity);
  if(ddFloor > 0)
    t += StringFormat("Equity stop : %.2f\n",
                      ddFloor);
  t += StringFormat("Free margin : %.2f\n",
         AccountInfoDouble(ACCOUNT_MARGIN_FREE));
  t += StringFormat("Margin lvl  : %.0f%%\n",
         AccountInfoDouble(ACCOUNT_MARGIN_LEVEL));
  Comment(t);
}

//----------------------------------------------
// IsTrending: ADX bar terakhir >= ambang?
//----------------------------------------------
bool IsTrending() {
  double adx[1];
  int n = CopyBuffer(adxHandle, MAIN_LINE,
                     1, 1, adx);
  if(n < 1) {
    lastADXValue = 0;
    return false;
  }
  lastADXValue = adx[0];
  return (adx[0] >= ADX_Threshold);
}

//==============================================
// 10. HISTORI DEAL & NORMALISASI LOT
//==============================================

//----------------------------------------------
// GetLastTradeInfo: baca histori dari deal
// terbaru. Mengisi arah & lot berikut, loss
// beruntun, dan rugi akumulasi sejak win.
// Return true jika ada deal keluar.
//----------------------------------------------
bool GetLastTradeInfo(int &next_dir,
                      double &next_lot,
                      int &loss_streak,
                      double &cum_loss) {
  HistorySelect(historyFrom, TimeCurrent());
  int totalDeals = HistoryDealsTotal();
  bool foundLast = false;
  loss_streak = 0;
  cum_loss = 0;

  // Loop dari deal terbaru ke terlama
  for(int i = totalDeals - 1; i >= 0; i--) {
    ulong d = HistoryDealGetTicket(i);
    if(d == 0) continue;
    if(!IsOwnExitDeal(d)) continue;

    long reason = HistoryDealGetInteger(d,
                                        DEAL_REASON);
    double net  = DealNet(d);
    bool isWin  = DealIsWin(reason, net);

    if(!foundLast) {
      // Deal terbaru menentukan arah & lot
      double lastLot = HistoryDealGetDouble(
                         d, DEAL_VOLUME);
      int lastPosType = (DealPosDir(d) == "BUY")
                        ? ORDER_TYPE_BUY
                        : ORDER_TYPE_SELL;
      if(isWin) {
        // WIN: arah sama, lot awal
        next_dir    = lastPosType;
        next_lot    = InitialLot;
        loss_streak = 0;
        return true;
      }
      // LOSS: balik arah, lot dikali
      next_dir = (lastPosType == ORDER_TYPE_BUY)
                 ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
      next_lot    = lastLot * LotMultiplier;
      loss_streak = 1;
      cum_loss    = -net;
      foundLast   = true;
    }
    else {
      // Hitung mundur loss beruntun sampai win
      if(isWin) break;
      loss_streak++;
      cum_loss += -net;
    }
  }
  return foundLast;
}

//----------------------------------------------
// NormalizeLot: sesuaikan step/min/max broker
// dan plafon MaxLot.
//----------------------------------------------
double NormalizeLot(double lot) {
  double minLot = SymbolInfoDouble(_Symbol,
                    SYMBOL_VOLUME_MIN);
  double maxLot = SymbolInfoDouble(_Symbol,
                    SYMBOL_VOLUME_MAX);
  double stepLot = SymbolInfoDouble(_Symbol,
                     SYMBOL_VOLUME_STEP);
  double cap = maxLot;
  if(MaxLot > 0) cap = MathMin(MaxLot, maxLot);

  if(lot > cap) {
    PrintFormat("PERINGATAN: lot %.2f dipotong ke"
                + " %.2f. Recovery tak penuh.",
                lot, cap);
    lot = cap;
  }
  if(lot < minLot) lot = minLot;
  if(stepLot > 0)
    lot = MathFloor(lot / stepLot + 1e-9) * stepLot;
  return NormalizeDouble(lot, 2);
}
//==============================================