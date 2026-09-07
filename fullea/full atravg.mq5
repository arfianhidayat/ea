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
input double   InpGridDistance       = 3.0;      // Jarak Averaging
input double   InpTakeProfitSingle   = 1.5;      // TP jika HANYA 1 Posisi
input double   InpTakeProfitBEP1     = 0.7;      // TP BEP 1 (Averaging Awal)
input int      InpAktifTPBEP2Posisi  = 5;        // Aktif TP BEP 2 pada Posisi ke-
input double   InpTakeProfitBEP2     = 0.4;      // TP BEP 2 (Averaging Lanjut)
input double   InpLotMultiplier      = 1.3;      // Multiplier Martingale
input ulong    InpMagicNumber        = 88888;    // Magic Number EA

//--- 3. Inputs Filter Sesi Trading (Semua jam dalam WIB / GMT+7)
input group "=== AKTIVASI SESI TRADING (JAM WIB) ==="
input bool     InpUseSessionFilter   = false;     // true: entry hanya di sesi di bawah | false: entry 24 jam
input bool     InpAutoDetectGMT      = true;      // true: offset broker dideteksi otomatis (live) | false: pakai input di bawah
input int      InpBrokerGMTOffset    = 3;         // Offset GMT server broker (dipakai di Strategy Tester / jika auto OFF)
input bool     InpUseAsia            = true;
input bool     InpUseEropa           = true;
input bool     InpUseUS              = true;
input string   InpAsiaStart          = "09:30";
input string   InpAsiaEnd            = "12:30";
input string   InpEropaStart         = "15:30";
input string   InpEropaEnd           = "17:30";
input string   InpUSStart            = "22:30";
input string   InpUSEnd              = "01:30";

//--- 4. Inputs Filter News (Kalender Ekonomi MT5 + Blackout Manual WIB)
input group "=== FILTER NEWS (Kalender Ekonomi MT5) ==="
input bool     InpUseNewsFilter      = true;     // Aktifkan filter berita
input string   InpNewsCurrencies     = "USD";    // Mata uang yang dipantau, pisahkan koma (mis. "USD,EUR")
input bool     InpNewsHighOnly       = true;     // true: hanya dampak tinggi | false: tinggi + sedang
input int      InpNewsMinutesBefore  = 30;       // Tahan entry X menit sebelum berita
input int      InpNewsMinutesAfter   = 30;       // Tahan entry X menit sesudah berita
input string   InpBlackout1          = "20:15-21:00"; // Jendela larangan manual WIB (cadangan, aktif juga di tester)
input string   InpBlackout2          = "04:00-05:30"; // Jendela larangan manual WIB
input string   InpBlackout3          = "";       // Jendela larangan manual WIB (kosong = tidak dipakai)

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

   // --- FILTER SESI TRADING (hanya untuk entry awal UT Bot) ---
   string session_name = "";
   bool session_ok = IsTradingSession(session_name);

   // --- FILTER NEWS (hanya untuk entry awal UT Bot) ---
   string news_reason = "";
   bool news_blocked = IsNewsBlocked(news_reason);

   bool entry_allowed = session_ok && !news_blocked;

   // --- FILTER ANTI-DOUBLE ENTRY ---

   // Hanya entry BUY jika ada sinyal, filter lolos, DAN belum ada posisi BUY
   if(buy_signal && entry_allowed && buy_count == 0)
     {
      trade.Buy(InpLotSize, _Symbol, 0, 0, 0, "UT Bot Buy Pertama");
     }

   // Hanya entry SELL jika ada sinyal, filter lolos, DAN belum ada posisi SELL
   if(sell_signal && entry_allowed && sell_count == 0)
     {
      trade.Sell(InpLotSize, _Symbol, 0, 0, 0, "UT Bot Sell Pertama");
     }

   // Tampilkan Info UT Bot ke Dashboard jika sedang tidak ada posisi aktif
   if(buy_count == 0 && sell_count == 0)
     {
      dashboard += "\n--- STATUS UT BOT ---\n";
      dashboard += "Batas Trailing Stop : " + DoubleToString(ts, _Digits) + "\n";
      dashboard += "Jam WIB : " + TimeToString(GetWIBTime(), TIME_MINUTES) + "\n";
      dashboard += "Sesi Trading : " + session_name + "\n";
      dashboard += "Filter News : " + (InpUseNewsFilter ? (news_blocked ? "BLOKIR (" + news_reason + ")" : "Aman") : "OFF") + "\n";
      if(entry_allowed)
         dashboard += "Menunggu Sinyal Valid Berikutnya...\n";
      else if(!session_ok)
         dashboard += "Di luar sesi, entry awal ditunda.\n";
      else
         dashboard += "Ada berita, entry awal ditunda.\n";
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

//+------------------------------------------------------------------+
//| Konversi string "HH:MM" ke menit sejak tengah malam (-1 jika salah)|
//+------------------------------------------------------------------+
int TimeStringToMinutes(string hhmm)
  {
   string parts[];
   if(StringSplit(hhmm, ':', parts) != 2)
      return -1;

   int hh = (int)StringToInteger(parts[0]);
   int mm = (int)StringToInteger(parts[1]);

   if(hh < 0 || hh > 23 || mm < 0 || mm > 59)
      return -1;

   return hh * 60 + mm;
  }

//+------------------------------------------------------------------+
//| Cek apakah menit saat ini berada dalam rentang start-end.        |
//| Mendukung sesi lewat tengah malam (misal 22:30 - 01:30).         |
//+------------------------------------------------------------------+
bool InTimeRange(int now_min, string start_str, string end_str)
  {
   int start = TimeStringToMinutes(start_str);
   int end   = TimeStringToMinutes(end_str);

   if(start < 0 || end < 0)
     {
      Print("Format jam sesi tidak valid: ", start_str, " - ", end_str, " (gunakan HH:MM)");
      return false;
     }

   if(start == end)
      return true; // rentang penuh 24 jam

   if(start < end)
      return (now_min >= start && now_min < end);

   // Lewat tengah malam
   return (now_min >= start || now_min < end);
  }

//+------------------------------------------------------------------+
//| Mengambil waktu saat ini dalam WIB (GMT+7).                      |
//| Live   : offset server dihitung dari TimeCurrent() - TimeGMT().  |
//| Tester : TimeGMT() tidak valid, jadi pakai InpBrokerGMTOffset.   |
//+------------------------------------------------------------------+
datetime GetWIBTime()
  {
   const int WIB_OFFSET_SEC = 7 * 3600;
   datetime server_time = TimeCurrent();
   int server_offset_sec;

   bool in_tester = (MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_OPTIMIZATION));

   if(InpAutoDetectGMT && !in_tester)
      server_offset_sec = (int)(server_time - TimeGMT());
   else
      server_offset_sec = InpBrokerGMTOffset * 3600;

   datetime gmt_time = server_time - server_offset_sec;
   return gmt_time + WIB_OFFSET_SEC;
  }

//+------------------------------------------------------------------+
//| Cek sesi trading aktif berdasarkan jam WIB.                      |
//| Mengisi active_name dengan nama sesi yang sedang berjalan.       |
//+------------------------------------------------------------------+
bool IsTradingSession(string &active_name)
  {
   if(!InpUseSessionFilter)
     {
      active_name = "24 Jam (Filter OFF)";
      return true;
     }

   MqlDateTime dt;
   TimeToStruct(GetWIBTime(), dt);
   int now_min = dt.hour * 60 + dt.min;

   active_name = "";

   if(InpUseAsia && InTimeRange(now_min, InpAsiaStart, InpAsiaEnd))
      active_name += "Asia ";
   if(InpUseEropa && InTimeRange(now_min, InpEropaStart, InpEropaEnd))
      active_name += "Eropa ";
   if(InpUseUS && InTimeRange(now_min, InpUSStart, InpUSEnd))
      active_name += "US ";

   if(active_name == "")
     {
      active_name = "Tidak Ada (Di Luar Sesi)";
      return false;
     }

   return true;
  }

//+------------------------------------------------------------------+
//| Cek jendela blackout manual "HH:MM-HH:MM" (jam WIB).             |
//+------------------------------------------------------------------+
bool InBlackoutWindow(int now_min_wib, string window, string &label)
  {
   string w = window;
   StringTrimLeft(w);
   StringTrimRight(w);
   if(w == "")
      return false;

   string parts[];
   if(StringSplit(w, '-', parts) != 2)
     {
      Print("Format blackout tidak valid: ", window, " (gunakan HH:MM-HH:MM)");
      return false;
     }

   StringTrimLeft(parts[0]);  StringTrimRight(parts[0]);
   StringTrimLeft(parts[1]);  StringTrimRight(parts[1]);

   if(InTimeRange(now_min_wib, parts[0], parts[1]))
     {
      label = "Blackout " + w + " WIB";
      return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Cek Kalender Ekonomi MT5 untuk berita di sekitar waktu sekarang. |
//| Waktu event kalender = waktu server, sama dengan TimeCurrent().  |
//| Tidak tersedia di Strategy Tester (langsung return false).       |
//+------------------------------------------------------------------+
bool IsCalendarNewsNear(string &label)
  {
   if(MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_OPTIMIZATION))
      return false;

   // Cache hasil 60 detik agar tidak query kalender tiap tick
   static datetime last_check   = 0;
   static bool     last_result  = false;
   static string   last_label   = "";

   datetime now = TimeCurrent();
   if(now - last_check < 60 && last_check != 0)
     {
      label = last_label;
      return last_result;
     }

   last_check  = now;
   last_result = false;
   last_label  = "";

   datetime from = now - (datetime)(InpNewsMinutesAfter  * 60);
   datetime to   = now + (datetime)(InpNewsMinutesBefore * 60);

   string currencies[];
   int n = StringSplit(InpNewsCurrencies, ',', currencies);

   for(int c = 0; c < n && !last_result; c++)
     {
      string cur = currencies[c];
      StringTrimLeft(cur);
      StringTrimRight(cur);
      if(cur == "")
         continue;

      MqlCalendarValue values[];
      if(!CalendarValueHistory(values, from, to, NULL, cur))
        {
         Print("CalendarValueHistory gagal untuk ", cur, ", error ", GetLastError());
         continue;
        }

      for(int i = 0; i < ArraySize(values); i++)
        {
         MqlCalendarEvent ev;
         if(!CalendarEventById(values[i].event_id, ev))
            continue;

         bool impact_ok = (ev.importance == CALENDAR_IMPORTANCE_HIGH) ||
                          (!InpNewsHighOnly && ev.importance == CALENDAR_IMPORTANCE_MODERATE);
         if(!impact_ok)
            continue;

         datetime ev_time = values[i].time;
         if(now >= ev_time - InpNewsMinutesBefore * 60 && now <= ev_time + InpNewsMinutesAfter * 60)
           {
            datetime ev_wib = ev_time - (now - GetWIBTime());
            last_label  = cur + " " + ev.name + " @ " + TimeToString(ev_wib, TIME_MINUTES) + " WIB";
            last_result = true;
            break;
           }
        }
     }

   label = last_label;
   return last_result;
  }

//+------------------------------------------------------------------+
//| Gabungan filter news: kalender MT5 + blackout manual WIB.        |
//| Return true jika entry harus DITAHAN.                            |
//+------------------------------------------------------------------+
bool IsNewsBlocked(string &reason)
  {
   reason = "";
   if(!InpUseNewsFilter)
      return false;

   // 1. Blackout manual (berjalan juga di Strategy Tester)
   MqlDateTime dt;
   TimeToStruct(GetWIBTime(), dt);
   int now_min_wib = dt.hour * 60 + dt.min;

   if(InBlackoutWindow(now_min_wib, InpBlackout1, reason)) return true;
   if(InBlackoutWindow(now_min_wib, InpBlackout2, reason)) return true;
   if(InBlackoutWindow(now_min_wib, InpBlackout3, reason)) return true;

   // 2. Kalender ekonomi MT5 (hanya live)
   if(IsCalendarNewsNear(reason))
      return true;

   return false;
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
