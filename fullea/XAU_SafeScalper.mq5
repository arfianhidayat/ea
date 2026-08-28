//+------------------------------------------------------------------+
//|                                             XAU_SafeScalper.mq5  |
//|                            Scalping XAUUSD - Safety First Design |
//|                                        Copyright 2026, Antigravity |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Antigravity"
#property link      "https://www.google.com"
#property version   "1.00"
#property description "EA scalping XAUUSD tanpa martingale / tanpa averaging."
#property description "Setiap posisi WAJIB punya Stop Loss. Risiko per trade dibatasi % equity."
#property description "Dilengkapi guard: max loss harian, max DD, max loss beruntun, filter spread & sesi."

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>

//+------------------------------------------------------------------+
//| INPUTS                                                           |
//+------------------------------------------------------------------+
input group "=== 1. Umum ==="
input ulong    InpMagic              = 20260828;  // Magic Number
input string   InpComment            = "SafeScalp"; // Komentar Order
input ENUM_TIMEFRAMES InpTF          = PERIOD_M5;  // Timeframe kerja

input group "=== 2. Manajemen Risiko (INTI KEAMANAN) ==="
input bool     InpUseRiskPercent     = true;       // Sizing otomatis berbasis % equity
input double   InpRiskPercent        = 0.5;        // Risiko per trade (% equity)
input double   InpFixedLot           = 0.01;       // Lot tetap (jika sizing otomatis = false)
input double   InpMaxLot             = 0.50;       // Batas keras lot maksimum
input int      InpMaxPositions       = 1;          // Maksimal posisi bersamaan (disarankan 1)

input group "=== 3. Circuit Breaker (Proteksi Akun) ==="
input double   InpMaxDailyLossPct    = 2.0;        // Stop trading jika loss harian >= % equity
input double   InpMaxDailyProfitPct  = 3.0;        // Stop trading jika profit harian >= % (0=off)
input double   InpMaxDrawdownPct     = 10.0;       // Stop TOTAL jika DD dari puncak >= %
input int      InpMaxConsecLosses    = 3;          // Stop harian setelah N loss beruntun
input int      InpMaxTradesPerDay    = 6;          // Maksimal entry per hari (0=unlimited)
input double   InpMinEquityStop      = 0.0;        // Stop TOTAL jika equity <= nilai ini (0=off)

input group "=== 4. Stop Loss / Take Profit (berbasis ATR) ==="
input int      InpATRPeriod          = 14;         // Periode ATR
input double   InpSL_ATR             = 1.5;        // SL = ATR x
input double   InpTP_ATR             = 1.5;        // TP = ATR x (RR 1:1 pada default)
input double   InpMinSL_Points       = 300;        // SL minimum (points) - hindari SL terlalu rapat
input double   InpMaxSL_Points       = 3000;       // SL maksimum (points) - hindari risiko melar

input group "=== 5. Proteksi Posisi Berjalan ==="
input bool     InpUseBreakEven       = true;       // Aktifkan Break Even
input double   InpBE_TriggerATR      = 0.8;        // BE aktif setelah profit = ATR x
input double   InpBE_LockPoints      = 50;         // Kunci profit (points) saat BE
input bool     InpUseTrailing        = true;       // Aktifkan Trailing Stop
input double   InpTrailStartATR      = 1.0;        // Trailing mulai setelah profit = ATR x
input double   InpTrailATR           = 1.0;        // Jarak trailing = ATR x
input int      InpMaxPositionMinutes = 120;        // Tutup paksa posisi > N menit (0=off)

input group "=== 6. Filter Entry ==="
input int      InpEMAFast            = 21;         // EMA cepat (arah)
input int      InpEMASlow            = 50;         // EMA lambat (arah)
input int      InpEMATrendTF_Period  = 200;        // EMA filter tren H1
input int      InpRSIPeriod          = 14;         // Periode RSI
input double   InpRSI_BuyMax         = 65.0;       // Jangan BUY jika RSI di atas ini (anti kejar harga)
input double   InpRSI_BuyMin         = 45.0;       // BUY hanya jika RSI di atas ini
input double   InpRSI_SellMin        = 35.0;       // Jangan SELL jika RSI di bawah ini
input double   InpRSI_SellMax        = 55.0;       // SELL hanya jika RSI di bawah ini
input double   InpMinATR_Points      = 100;        // ATR minimum (points) - hindari pasar mati
input double   InpMaxATR_Points      = 2500;       // ATR maksimum (points) - hindari pasar liar

input group "=== 7. Filter Spread & Waktu ==="
input int      InpMaxSpreadPoints    = 35;         // Spread maksimum (points) untuk entry
input bool     InpUseSessionFilter   = true;       // Aktifkan filter jam (waktu server)
input int      InpStartHour          = 8;          // Jam mulai trading
input int      InpEndHour            = 20;         // Jam berhenti trading
input bool     InpAvoidRollover      = true;       // Hindari jam rollover (23:00-01:00 server)
input bool     InpFridayCloseEarly   = true;       // Jumat: stop entry & tutup posisi sore
input int      InpFridayStopHour     = 19;         // Jam stop di hari Jumat
input int      InpSlippagePoints     = 20;         // Deviasi harga maksimum (points)
input int      InpCooldownMinutes    = 5;          // Jeda minimal antar entry (menit)

input group "=== 8. Filter News (Kalender Ekonomi MT5) ==="
input bool     InpUseNewsFilter      = true;       // Aktifkan filter news
input int      InpNewsMinutesBefore  = 30;         // Stop entry N menit SEBELUM news
input int      InpNewsMinutesAfter   = 30;         // Stop entry N menit SESUDAH news
input bool     InpNewsHighOnly       = true;       // Hanya news berdampak TINGGI (false = tinggi+sedang)
input bool     InpNewsCloseOpen      = false;      // Tutup posisi terbuka menjelang news
input string   InpNewsCurrencies     = "USD";      // Mata uang dipantau (pisah koma, mis. "USD,EUR")
input bool     InpNewsFailSafe       = true;       // Jika kalender tidak tersedia -> tetap trading (false = stop)
input string   InpManualNewsTimes    = "";         // Cadangan manual: "2026.09.05 12:30,2026.09.11 12:30" (waktu server)

//+------------------------------------------------------------------+
//| GLOBALS                                                          |
//+------------------------------------------------------------------+
CTrade        m_trade;
CSymbolInfo   m_symbol;
CPositionInfo m_position;

int      h_atr = INVALID_HANDLE;
int      h_emaFast = INVALID_HANDLE;
int      h_emaSlow = INVALID_HANDLE;
int      h_emaTrend = INVALID_HANDLE;
int      h_rsi = INVALID_HANDLE;

datetime g_lastBarTime   = 0;
datetime g_lastEntryTime = 0;
datetime g_currentDay    = 0;

double   g_dayStartEquity = 0.0;
double   g_peakEquity     = 0.0;
int      g_consecLosses   = 0;
int      g_tradesToday    = 0;
bool     g_haltPermanent  = false;   // dimatikan total (DD / equity floor)
bool     g_haltToday      = false;   // dimatikan sampai hari berikutnya

// --- News filter state ---
datetime g_newsCache[];               // waktu event yang lolos filter (sudah dalam waktu server)
datetime g_newsCacheTime  = 0;        // kapan cache terakhir diisi
string   g_newsNextName   = "";       // nama event terdekat (untuk panel)
datetime g_newsNextTime   = 0;
bool     g_calendarOK     = true;     // false jika kalender tidak bisa dibaca
datetime g_manualNews[];              // hasil parse InpManualNewsTimes

// --- Forward declarations ---
void   CloseAllPositions(string reason);
void   ShowPanel(double atr);
bool   IsTradingTime();
int    CountMyPositions();
bool   IsNewsTime(string &reason);
void   RefreshNewsCache();
void   ParseManualNews();

//+------------------------------------------------------------------+
//| Normalisasi volume sesuai spesifikasi broker                     |
//+------------------------------------------------------------------+
double NormalizeVolume(double vol)
  {
   double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   if(step <= 0.0) step = 0.01;

   int stepDigits = 0;
   double s = step;
   while(s < 1.0 && stepDigits < 8) { s *= 10.0; stepDigits++; }

   double norm = MathFloor(vol / step) * step;          // selalu bulatkan KE BAWAH (konservatif)
   norm = NormalizeDouble(norm, stepDigits);

   if(norm > maxVol) norm = maxVol;
   if(InpMaxLot > 0.0 && norm > InpMaxLot) norm = NormalizeDouble(MathFloor(InpMaxLot/step)*step, stepDigits);
   if(norm < minVol) norm = 0.0;                        // terlalu kecil -> jangan paksa entry
   return norm;
  }

//+------------------------------------------------------------------+
//| Hitung lot dari risiko % equity dan jarak SL (dalam harga)       |
//+------------------------------------------------------------------+
double CalcLot(double slDistancePrice)
  {
   if(!InpUseRiskPercent)
      return NormalizeVolume(InpFixedLot);

   if(slDistancePrice <= 0.0) return 0.0;

   double equity    = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskMoney = equity * InpRiskPercent / 100.0;

   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
   if(tickValue <= 0.0) tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tickSize <= 0.0 || tickValue <= 0.0) return 0.0;

   double lossPerLot = (slDistancePrice / tickSize) * tickValue;
   if(lossPerLot <= 0.0) return 0.0;

   double lot = NormalizeVolume(riskMoney / lossPerLot);
   if(lot <= 0.0) return 0.0;

   // Verifikasi margin tersedia sebelum kirim order
   double margin = 0.0;
   double price  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, lot, price, margin))
     {
      double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      if(margin > freeMargin * 0.3)   // pakai maksimal 30% free margin
        {
         PrintFormat("Lot %.2f butuh margin %.2f (free %.2f) - entry dibatalkan.", lot, margin, freeMargin);
         return 0.0;
        }
     }
   return lot;
  }

//+------------------------------------------------------------------+
//| Baca 1 nilai indikator pada shift tertentu                       |
//+------------------------------------------------------------------+
bool GetVal(int handle, int shift, double &out)
  {
   double buf[];
   if(CopyBuffer(handle, 0, shift, 1, buf) != 1) return false;
   out = buf[0];
   return true;
  }

//+------------------------------------------------------------------+
//| Reset counter harian                                             |
//+------------------------------------------------------------------+
void CheckNewDay()
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   datetime today = StringToTime(StringFormat("%04d.%02d.%02d", dt.year, dt.mon, dt.day));

   if(today != g_currentDay)
     {
      g_currentDay      = today;
      g_dayStartEquity  = AccountInfoDouble(ACCOUNT_EQUITY);
      g_consecLosses    = 0;
      g_tradesToday     = 0;
      g_haltToday       = false;
      PrintFormat("=== Hari baru. Equity awal: %.2f ===", g_dayStartEquity);
     }
  }

//+------------------------------------------------------------------+
//| Circuit breaker: cek semua batas proteksi akun                   |
//+------------------------------------------------------------------+
void CheckRiskGuards()
  {
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity > g_peakEquity) g_peakEquity = equity;

   // --- Proteksi permanen ---
   if(InpMinEquityStop > 0.0 && equity <= InpMinEquityStop && !g_haltPermanent)
     {
      g_haltPermanent = true;
      Print("!!! HALT PERMANEN: equity <= batas minimum. Tutup semua posisi.");
      CloseAllPositions("equity floor");
      return;
     }

   if(InpMaxDrawdownPct > 0.0 && g_peakEquity > 0.0 && !g_haltPermanent)
     {
      double dd = (g_peakEquity - equity) / g_peakEquity * 100.0;
      if(dd >= InpMaxDrawdownPct)
        {
         g_haltPermanent = true;
         PrintFormat("!!! HALT PERMANEN: drawdown %.2f%% >= %.2f%%. Tutup semua posisi.", dd, InpMaxDrawdownPct);
         CloseAllPositions("max drawdown");
         return;
        }
     }

   if(g_haltToday || g_dayStartEquity <= 0.0) return;

   // --- Proteksi harian ---
   double dayPL = (equity - g_dayStartEquity) / g_dayStartEquity * 100.0;

   if(InpMaxDailyLossPct > 0.0 && dayPL <= -InpMaxDailyLossPct)
     {
      g_haltToday = true;
      PrintFormat("*** STOP HARI INI: loss harian %.2f%%. Tutup semua posisi.", dayPL);
      CloseAllPositions("daily loss limit");
      return;
     }

   if(InpMaxDailyProfitPct > 0.0 && dayPL >= InpMaxDailyProfitPct)
     {
      g_haltToday = true;
      PrintFormat("*** STOP HARI INI: target profit harian %.2f%% tercapai.", dayPL);
      CloseAllPositions("daily profit target");
      return;
     }

   if(InpMaxConsecLosses > 0 && g_consecLosses >= InpMaxConsecLosses)
     {
      g_haltToday = true;
      PrintFormat("*** STOP HARI INI: %d loss beruntun.", g_consecLosses);
     }
  }

//+------------------------------------------------------------------+
//| Filter waktu trading                                             |
//+------------------------------------------------------------------+
bool IsTradingTime()
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);

   if(dt.day_of_week == 0 || dt.day_of_week == 6) return false;      // weekend

   if(InpAvoidRollover && (dt.hour >= 23 || dt.hour < 1)) return false;

   if(InpFridayCloseEarly && dt.day_of_week == 5 && dt.hour >= InpFridayStopHour) return false;

   if(!InpUseSessionFilter) return true;

   if(InpStartHour <= InpEndHour)
      return (dt.hour >= InpStartHour && dt.hour < InpEndHour);
   return (dt.hour >= InpStartHour || dt.hour < InpEndHour);         // sesi lewat tengah malam
  }

//+------------------------------------------------------------------+
//| Parse daftar waktu news manual (waktu server)                    |
//+------------------------------------------------------------------+
void ParseManualNews()
  {
   ArrayResize(g_manualNews, 0);
   if(StringLen(InpManualNewsTimes) == 0) return;

   string parts[];
   int n = StringSplit(InpManualNewsTimes, ',', parts);
   for(int i = 0; i < n; i++)
     {
      string s = parts[i];
      StringTrimLeft(s); StringTrimRight(s);
      if(StringLen(s) == 0) continue;
      datetime t = StringToTime(s);
      if(t <= 0) { Print("Format waktu news manual tidak valid: ", s); continue; }
      int sz = ArraySize(g_manualNews);
      ArrayResize(g_manualNews, sz + 1);
      g_manualNews[sz] = t;
     }
   if(ArraySize(g_manualNews) > 0)
      PrintFormat("Filter news manual: %d jadwal dimuat.", ArraySize(g_manualNews));
  }

//+------------------------------------------------------------------+
//| Cek apakah currency event termasuk yang dipantau                 |
//+------------------------------------------------------------------+
bool IsWatchedCurrency(string cur)
  {
   string list = InpNewsCurrencies;
   StringToUpper(list);
   StringToUpper(cur);
   string parts[];
   int n = StringSplit(list, ',', parts);
   for(int i = 0; i < n; i++)
     {
      string p = parts[i];
      StringTrimLeft(p); StringTrimRight(p);
      if(p == cur) return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Muat ulang cache event dari kalender ekonomi MT5 (tiap 30 menit) |
//+------------------------------------------------------------------+
void RefreshNewsCache()
  {
   datetime now = TimeCurrent();
   if(g_newsCacheTime > 0 && (now - g_newsCacheTime) < 1800) return;
   g_newsCacheTime = now;

   ArrayResize(g_newsCache, 0);

   // Ambil event dari 1 hari lalu s/d 2 hari ke depan
   datetime from = now - 86400;
   datetime to   = now + 2 * 86400;

   MqlCalendarValue values[];
   int total = CalendarValueHistory(values, from, to);
   if(total < 0)
     {
      g_calendarOK = false;
      static bool warned = false;
      if(!warned)
        {
         PrintFormat("Kalender ekonomi tidak tersedia (err %d). %s", GetLastError(),
                     InpNewsFailSafe ? "Filter news memakai daftar manual saja." : "Trading DIHENTIKAN (fail-safe off).");
         warned = true;
        }
      return;
     }
   g_calendarOK = true;

   // Selisih waktu server vs GMT: kalender MT5 sudah mengembalikan waktu server,
   // jadi tidak perlu konversi.
   for(int i = 0; i < total; i++)
     {
      MqlCalendarEvent ev;
      if(!CalendarEventById(values[i].event_id, ev)) continue;

      if(ev.importance == CALENDAR_IMPORTANCE_NONE) continue;
      if(ev.importance == CALENDAR_IMPORTANCE_LOW)  continue;
      if(InpNewsHighOnly && ev.importance != CALENDAR_IMPORTANCE_HIGH) continue;

      MqlCalendarCountry country;
      if(!CalendarCountryById(ev.country_id, country)) continue;
      if(!IsWatchedCurrency(country.currency)) continue;

      int sz = ArraySize(g_newsCache);
      ArrayResize(g_newsCache, sz + 1);
      g_newsCache[sz] = values[i].time;

      // simpan event terdekat di depan untuk panel
      if(values[i].time >= now && (g_newsNextTime == 0 || values[i].time < g_newsNextTime || g_newsNextTime < now))
        {
         g_newsNextTime = values[i].time;
         g_newsNextName = country.currency + " " + ev.name;
        }
     }
  }

//+------------------------------------------------------------------+
//| True jika sekarang berada dalam jendela blackout news            |
//+------------------------------------------------------------------+
bool IsNewsTime(string &reason)
  {
   reason = "";
   if(!InpUseNewsFilter) return false;

   datetime now    = TimeCurrent();
   int      before = InpNewsMinutesBefore * 60;
   int      after  = InpNewsMinutesAfter  * 60;

   RefreshNewsCache();

   if(!g_calendarOK && !InpNewsFailSafe && ArraySize(g_manualNews) == 0)
     {
      reason = "kalender tidak tersedia";
      return true;
     }

   for(int i = 0; i < ArraySize(g_newsCache); i++)
     {
      if(now >= g_newsCache[i] - before && now <= g_newsCache[i] + after)
        {
         reason = "news kalender " + TimeToString(g_newsCache[i], TIME_DATE|TIME_MINUTES);
         return true;
        }
     }

   for(int i = 0; i < ArraySize(g_manualNews); i++)
     {
      if(now >= g_manualNews[i] - before && now <= g_manualNews[i] + after)
        {
         reason = "news manual " + TimeToString(g_manualNews[i], TIME_DATE|TIME_MINUTES);
         return true;
        }
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Hitung posisi milik EA ini                                       |
//+------------------------------------------------------------------+
int CountMyPositions()
  {
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
      if(m_position.SelectByIndex(i))
         if(m_position.Symbol() == _Symbol && m_position.Magic() == InpMagic)
            count++;
   return count;
  }

//+------------------------------------------------------------------+
//| Tutup semua posisi milik EA                                      |
//+------------------------------------------------------------------+
void CloseAllPositions(string reason)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!m_position.SelectByIndex(i)) continue;
      if(m_position.Symbol() != _Symbol || m_position.Magic() != InpMagic) continue;

      if(!m_trade.PositionClose(m_position.Ticket(), InpSlippagePoints))
         PrintFormat("Gagal menutup #%I64u (%s): %d %s",
                     m_position.Ticket(), reason, m_trade.ResultRetcode(), m_trade.ResultRetcodeDescription());
     }
  }

//+------------------------------------------------------------------+
//| Break even + trailing + time stop                                |
//+------------------------------------------------------------------+
void ManagePositions(double atr)
  {
   if(atr <= 0.0) return;

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   long   stopLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minDist = stopLevel * point;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!m_position.SelectByIndex(i)) continue;
      if(m_position.Symbol() != _Symbol || m_position.Magic() != InpMagic) continue;

      ulong  ticket  = m_position.Ticket();
      double open    = m_position.PriceOpen();
      double curSL   = m_position.StopLoss();
      double curTP   = m_position.TakeProfit();
      bool   isBuy   = (m_position.PositionType() == POSITION_TYPE_BUY);
      double bid     = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask     = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double cur     = isBuy ? bid : ask;
      double profitDist = isBuy ? (cur - open) : (open - cur);

      // --- Jaring pengaman: posisi tanpa SL wajib diberi SL ---
      if(curSL <= 0.0)
        {
         double sl = isBuy ? open - InpSL_ATR * atr : open + InpSL_ATR * atr;
         sl = NormalizeDouble(sl, digits);
         if(m_trade.PositionModify(ticket, sl, curTP))
            Print("SL darurat dipasang pada #", ticket);
         continue;
        }

      // --- Time stop ---
      if(InpMaxPositionMinutes > 0)
        {
         long ageMin = (long)(TimeCurrent() - m_position.Time()) / 60;
         if(ageMin >= InpMaxPositionMinutes)
           {
            PrintFormat("Time stop: tutup #%I64u setelah %d menit.", ticket, (int)ageMin);
            m_trade.PositionClose(ticket, InpSlippagePoints);
            continue;
           }
        }

      double newSL = 0.0;

      // --- Trailing stop (prioritas lebih tinggi dari BE) ---
      if(InpUseTrailing && profitDist >= InpTrailStartATR * atr)
        {
         newSL = isBuy ? cur - InpTrailATR * atr : cur + InpTrailATR * atr;
        }
      // --- Break even ---
      else if(InpUseBreakEven && profitDist >= InpBE_TriggerATR * atr)
        {
         newSL = isBuy ? open + InpBE_LockPoints * point : open - InpBE_LockPoints * point;
        }

      if(newSL <= 0.0) continue;
      newSL = NormalizeDouble(newSL, digits);

      // Hanya geser ke arah yang mengunci profit, dan hormati stop level broker
      if(isBuy)
        {
         if(newSL <= curSL + point * 0.5) continue;
         if(bid - newSL < minDist) continue;
        }
      else
        {
         if(newSL >= curSL - point * 0.5) continue;
         if(newSL - ask < minDist) continue;
        }

      if(!m_trade.PositionModify(ticket, newSL, curTP))
         PrintFormat("PositionModify #%I64u gagal: %d %s",
                     ticket, m_trade.ResultRetcode(), m_trade.ResultRetcodeDescription());
     }
  }

//+------------------------------------------------------------------+
//| Sinyal entry: 0 = tidak ada, 1 = buy, -1 = sell                  |
//+------------------------------------------------------------------+
int GetSignal(double atr)
  {
   double emaF1, emaS1, emaF2, emaS2, emaTrend, rsi;
   if(!GetVal(h_emaFast, 1, emaF1))   return 0;
   if(!GetVal(h_emaSlow, 1, emaS1))   return 0;
   if(!GetVal(h_emaFast, 2, emaF2))   return 0;
   if(!GetVal(h_emaSlow, 2, emaS2))   return 0;
   if(!GetVal(h_emaTrend, 1, emaTrend)) return 0;
   if(!GetVal(h_rsi, 1, rsi))         return 0;

   double close1 = iClose(_Symbol, InpTF, 1);
   double low1   = iLow(_Symbol, InpTF, 1);
   double high1  = iHigh(_Symbol, InpTF, 1);
   double open1  = iOpen(_Symbol, InpTF, 1);
   if(close1 <= 0.0) return 0;

   bool upStruct   = (emaF1 > emaS1) && (emaF2 > emaS2) && (close1 > emaTrend);
   bool downStruct = (emaF1 < emaS1) && (emaF2 < emaS2) && (close1 < emaTrend);

   // BUY: tren naik, harga pullback menyentuh EMA cepat lalu ditutup bullish di atasnya
   if(upStruct && low1 <= emaF1 && close1 > emaF1 && close1 > open1)
      if(rsi > InpRSI_BuyMin && rsi < InpRSI_BuyMax)
         return 1;

   // SELL: tren turun, harga pullback menyentuh EMA cepat lalu ditutup bearish di bawahnya
   if(downStruct && high1 >= emaF1 && close1 < emaF1 && close1 < open1)
      if(rsi < InpRSI_SellMax && rsi > InpRSI_SellMin)
         return -1;

   return 0;
  }

//+------------------------------------------------------------------+
//| Buka posisi dengan SL & TP wajib                                 |
//+------------------------------------------------------------------+
void OpenTrade(int dir, double atr)
  {
   double point   = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int    digits  = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   long   stopLvl = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minDist = stopLvl * point;

   double slDist = InpSL_ATR * atr;
   double tpDist = InpTP_ATR * atr;

   // Batasi jarak SL di rentang yang wajar
   double minSL = InpMinSL_Points * point;
   double maxSL = InpMaxSL_Points * point;
   if(slDist < minSL) { tpDist *= minSL / slDist; slDist = minSL; }
   if(slDist > maxSL) { PrintFormat("SL %.1f points melebihi batas - entry dilewati.", slDist/point); return; }
   if(slDist < minDist) slDist = minDist + point;
   if(tpDist < minDist) tpDist = minDist + point;

   double lot = CalcLot(slDist);
   if(lot <= 0.0) { Print("Lot hasil perhitungan 0 - entry dilewati."); return; }

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   double price, sl, tp;
   if(dir > 0)
     {
      price = ask;
      sl = NormalizeDouble(price - slDist, digits);
      tp = NormalizeDouble(price + tpDist, digits);
     }
   else
     {
      price = bid;
      sl = NormalizeDouble(price + slDist, digits);
      tp = NormalizeDouble(price - tpDist, digits);
     }

   m_trade.SetDeviationInPoints(InpSlippagePoints);

   bool ok = (dir > 0)
             ? m_trade.Buy(lot, _Symbol, price, sl, tp, InpComment)
             : m_trade.Sell(lot, _Symbol, price, sl, tp, InpComment);

   if(ok)
     {
      g_lastEntryTime = TimeCurrent();
      g_tradesToday++;
      PrintFormat("%s %.2f lot @ %.*f | SL %.*f | TP %.*f | risiko %.2f%% | trade ke-%d hari ini",
                  (dir > 0 ? "BUY" : "SELL"), lot, digits, price, digits, sl, digits, tp,
                  InpRiskPercent, g_tradesToday);
     }
   else
     {
      PrintFormat("Order gagal: %d %s", m_trade.ResultRetcode(), m_trade.ResultRetcodeDescription());
     }
  }

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
  {
   if(!m_symbol.Name(_Symbol))
     {
      Print("Gagal inisialisasi simbol.");
      return INIT_FAILED;
     }

   // Validasi input yang berbahaya jika salah isi
   if(InpRiskPercent <= 0.0 || InpRiskPercent > 5.0)
     {
      Print("InpRiskPercent harus di rentang 0.01 - 5.0 (disarankan <= 1.0).");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpSL_ATR <= 0.0 || InpTP_ATR <= 0.0)
     {
      Print("SL/TP ATR multiplier harus > 0.");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpMaxPositions < 1)
     {
      Print("InpMaxPositions minimal 1.");
      return INIT_PARAMETERS_INCORRECT;
     }

   h_atr      = iATR(_Symbol, InpTF, InpATRPeriod);
   h_emaFast  = iMA(_Symbol, InpTF, InpEMAFast, 0, MODE_EMA, PRICE_CLOSE);
   h_emaSlow  = iMA(_Symbol, InpTF, InpEMASlow, 0, MODE_EMA, PRICE_CLOSE);
   h_emaTrend = iMA(_Symbol, PERIOD_H1, InpEMATrendTF_Period, 0, MODE_EMA, PRICE_CLOSE);
   h_rsi      = iRSI(_Symbol, InpTF, InpRSIPeriod, PRICE_CLOSE);

   if(h_atr == INVALID_HANDLE || h_emaFast == INVALID_HANDLE || h_emaSlow == INVALID_HANDLE ||
      h_emaTrend == INVALID_HANDLE || h_rsi == INVALID_HANDLE)
     {
      Print("Gagal membuat handle indikator.");
      return INIT_FAILED;
     }

   m_trade.SetExpertMagicNumber(InpMagic);
   m_trade.SetDeviationInPoints(InpSlippagePoints);
   m_trade.SetTypeFillingBySymbol(_Symbol);
   m_trade.LogLevel(LOG_LEVEL_ERRORS);

   g_dayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   g_peakEquity     = AccountInfoDouble(ACCOUNT_EQUITY);
   CheckNewDay();

   ParseManualNews();
   if(InpUseNewsFilter)
     {
      g_newsCacheTime = 0;
      RefreshNewsCache();
      PrintFormat("Filter news aktif: %d event kalender dimuat (%s, %s).",
                  ArraySize(g_newsCache), InpNewsCurrencies,
                  InpNewsHighOnly ? "dampak tinggi" : "dampak tinggi+sedang");
     }

   PrintFormat("XAU_SafeScalper aktif di %s %s | equity %.2f | risiko %.2f%%/trade",
               _Symbol, EnumToString(InpTF), g_dayStartEquity, InpRiskPercent);

   if(StringFind(_Symbol, "XAU") < 0)
      Print("PERINGATAN: EA ini dirancang untuk XAUUSD. Simbol saat ini: ", _Symbol);

   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(h_atr      != INVALID_HANDLE) IndicatorRelease(h_atr);
   if(h_emaFast  != INVALID_HANDLE) IndicatorRelease(h_emaFast);
   if(h_emaSlow  != INVALID_HANDLE) IndicatorRelease(h_emaSlow);
   if(h_emaTrend != INVALID_HANDLE) IndicatorRelease(h_emaTrend);
   if(h_rsi      != INVALID_HANDLE) IndicatorRelease(h_rsi);
   Comment("");
  }

//+------------------------------------------------------------------+
//| OnTick                                                           |
//+------------------------------------------------------------------+
void OnTick()
  {
   CheckNewDay();
   CheckRiskGuards();

   double atr = 0.0;
   if(!GetVal(h_atr, 1, atr) || atr <= 0.0) return;

   // Manajemen posisi berjalan tetap aktif walaupun trading dihentikan
   ManagePositions(atr);

   // --- Filter news: tutup posisi terbuka menjelang news (opsional) ---
   string newsReason = "";
   bool   newsNow = IsNewsTime(newsReason);
   if(newsNow && InpNewsCloseOpen && CountMyPositions() > 0)
     {
      Print("Menutup posisi karena ", newsReason);
      CloseAllPositions(newsReason);
     }

   ShowPanel(atr);

   if(g_haltPermanent || g_haltToday) return;
   if(newsNow) return;

   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)) return;
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))           return;
   if(!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))   return;

   // --- Entry hanya sekali per bar baru ---
   datetime barTime = iTime(_Symbol, InpTF, 0);
   if(barTime == g_lastBarTime) return;
   g_lastBarTime = barTime;

   if(CountMyPositions() >= InpMaxPositions) return;
   if(!IsTradingTime()) return;
   if(InpMaxTradesPerDay > 0 && g_tradesToday >= InpMaxTradesPerDay) return;

   if(InpCooldownMinutes > 0 && g_lastEntryTime > 0 &&
      (TimeCurrent() - g_lastEntryTime) < InpCooldownMinutes * 60) return;

   // --- Filter spread ---
   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(InpMaxSpreadPoints > 0 && spread > InpMaxSpreadPoints) return;

   // --- Filter volatilitas ---
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double atrPoints = atr / point;
   if(InpMinATR_Points > 0 && atrPoints < InpMinATR_Points) return;
   if(InpMaxATR_Points > 0 && atrPoints > InpMaxATR_Points) return;

   int sig = GetSignal(atr);
   if(sig != 0) OpenTrade(sig, atr);
  }

//+------------------------------------------------------------------+
//| OnTradeTransaction - lacak hasil deal untuk loss beruntun        |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal)) return;

   if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != (long)InpMagic) return;
   if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol) return;
   if(HistoryDealGetInteger(trans.deal, DEAL_ENTRY) != DEAL_ENTRY_OUT) return;

   double pl = HistoryDealGetDouble(trans.deal, DEAL_PROFIT)
             + HistoryDealGetDouble(trans.deal, DEAL_SWAP)
             + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);

   if(pl < 0.0)
     {
      g_consecLosses++;
      PrintFormat("Deal rugi %.2f | loss beruntun: %d/%d", pl, g_consecLosses, InpMaxConsecLosses);
     }
   else
     {
      if(g_consecLosses > 0) Print("Deal profit ", DoubleToString(pl, 2), " - reset hitungan loss beruntun.");
      g_consecLosses = 0;
     }
  }

//+------------------------------------------------------------------+
//| Panel info di chart                                              |
//+------------------------------------------------------------------+
void ShowPanel(double atr)
  {
   static datetime lastUpdate = 0;
   if(TimeCurrent() == lastUpdate) return;
   lastUpdate = TimeCurrent();

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double dayPL  = (g_dayStartEquity > 0.0) ? (equity - g_dayStartEquity) / g_dayStartEquity * 100.0 : 0.0;
   double dd     = (g_peakEquity > 0.0) ? (g_peakEquity - equity) / g_peakEquity * 100.0 : 0.0;
   double point  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   string newsReason = "";
   bool   newsNow = IsNewsTime(newsReason);

   string status = "AKTIF";
   if(g_haltPermanent)   status = "HALT PERMANEN";
   else if(g_haltToday)  status = "STOP HARI INI";
   else if(newsNow)      status = "BLACKOUT NEWS (" + newsReason + ")";
   else if(!IsTradingTime()) status = "DI LUAR JAM TRADING";

   string newsLine;
   if(!InpUseNewsFilter)       newsLine = "nonaktif";
   else if(!g_calendarOK)      newsLine = "kalender N/A" + (ArraySize(g_manualNews) > 0 ? " (manual aktif)" : "");
   else if(g_newsNextTime > TimeCurrent())
     {
      long mins = (long)(g_newsNextTime - TimeCurrent()) / 60;
      newsLine = StringFormat("%s dalam %d mnt", g_newsNextName, (int)mins);
     }
   else newsLine = "tidak ada event 48 jam ke depan";

   string txt = StringFormat(
      "=== XAU Safe Scalper ===\n"
      "Status        : %s\n"
      "Equity        : %.2f  (P/L hari ini: %+.2f%%)\n"
      "Drawdown      : %.2f%% / %.2f%%\n"
      "Posisi        : %d / %d\n"
      "Trade hari ini: %d / %d\n"
      "Loss beruntun : %d / %d\n"
      "ATR           : %.0f points\n"
      "Spread        : %d points (maks %d)\n"
      "News berikut  : %s",
      status, equity, dayPL, dd, InpMaxDrawdownPct,
      CountMyPositions(), InpMaxPositions,
      g_tradesToday, InpMaxTradesPerDay,
      g_consecLosses, InpMaxConsecLosses,
      (point > 0 ? atr / point : 0),
      (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD), InpMaxSpreadPoints,
      newsLine);

   Comment(txt);
  }
//+------------------------------------------------------------------+
