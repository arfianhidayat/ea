//+------------------------------------------------------------------+
//|                                  Auto_Martingale_Grid_BB_Mod.mq5 |
//|              Versi 4.2 (Sideways + BB Zone + Spread/News Filter) |
//+------------------------------------------------------------------+
//| ALUR PROGRAM (dijalankan setiap tick):                           |
//|                                                                  |
//| 1. BACA POSISI TERBUKA                                           |
//|    Scan semua posisi di simbol ini (magic = InpMagicNumber atau  |
//|    magic = 0 / manual). Untuk Buy dan Sell dihitung terpisah:    |
//|    jumlah posisi, total lot, BEP (rata-rata harga tertimbang),   |
//|    harga open terakhir, lot posisi pertama, waktu posisi pertama.|
//|                                                                  |
//| 2. FILTER SIDEWAYS (3 syarat, SEMUA harus terpenuhi)             |
//|    Dihitung ulang hanya saat candle InpFilterTimeFrame baru,     |
//|    memakai candle yang sudah tertutup. HANYA untuk entry awal.   |
//|    a. BB Width %  = (upper - lower) / middle x 100               |
//|       di InpFilterTimeFrame, harus < InpMaxBBWidthPct            |
//|       -> menolak volatilitas tinggi                              |
//|    b. Efficiency Ratio = |close skrg - close N lalu| /           |
//|       jumlah |close[i] - close[i-1]| selama N candle             |
//|       di InpFilterTimeFrame, harus < InpMaxER                    |
//|       -> menolak harga yang bergerak lurus (tren pelan pun kena) |
//|    c. ADX di InpADXTimeFrame (default H1), harus < InpMaxADX     |
//|       -> menolak tren kuat di timeframe lebih besar              |
//|                                                                  |
//| 3. ENTRY AWAL (dua arah, Buy dan Sell diperiksa terpisah)        |
//|    Buka Sell dgn InpInitialLot jika SEMUA terpenuhi:             |
//|      - belum ada posisi Sell                                     |
//|      - dalam sesi trading (Asia/Eropa/US, jam WIB); jika         |
//|        InpUseSessionFilter = false, syarat ini selalu terpenuhi  |
//|        (EA entry 24 jam)                                         |
//|      - market sideways (3 filter di langkah 2 lolos semua)       |
//|      - spread (ask - bid) <= InpMaxSpread (0 = tidak dicek)      |
//|      - tidak dalam jendela berita (lihat FILTER NEWS di bawah)   |
//|      - bid di dalam zona entry BB (lihat di bawah)               |
//|    Buka Buy dgn InpInitialLot jika SEMUA terpenuhi:              |
//|      - belum ada posisi Buy                                      |
//|      - dalam sesi trading                                        |
//|      - market sideways (3 filter di langkah 2 lolos semua)       |
//|      - spread <= InpMaxSpread                                    |
//|      - tidak dalam jendela berita                                |
//|      - ask di dalam zona entry BB (lihat di bawah)               |
//|    Buy dan Sell BISA terbuka bersamaan (hedging dua arah).       |
//|                                                                  |
//|    FILTER NEWS (InpUseNewsFilter), dua lapis, cukup satu kena:   |
//|    a. Kalender ekonomi MT5: berita mata uang InpNewsCurrencies   |
//|       berdampak HIGH (atau HIGH+MODERATE jika InpNewsHighOnly =  |
//|       false). Entry ditahan dari InpNewsMinutesBefore sebelum    |
//|       sampai InpNewsMinutesAfter sesudah waktu berita. Dicek     |
//|       ulang tiap 60 detik. TIDAK tersedia di strategy tester.    |
//|    b. Blackout manual InpBlackout1..3 ("HH:MM-HH:MM", WIB):      |
//|       jendela tetap yang selalu berlaku, termasuk di tester.     |
//|       Default: 20:15-21:00 (data US) dan 04:00-05:30 (rollover). |
//|                                                                  |
//|    ZONA ENTRY BB: harga harus berjarak minimal InpBBZonePct      |
//|    (% dari lebar band) dari upper DAN lower band, yaitu:         |
//|      lower + zona  <=  harga  <=  upper - zona                   |
//|    Tujuannya mencegah Buy tepat di resistance / Sell tepat di    |
//|    support, dan mencegah re-entry langsung di titik TP grid      |
//|    sebelumnya (yang biasanya berada di tepi band).               |
//|    Band yang dipakai = cache filter (candle tertutup).           |
//|    InpBBZonePct = 0 menonaktifkan zona.                          |
//|    InpDirectionalZone = true (opsional, default false):          |
//|      Sell hanya jika bid >= middle, Buy hanya jika ask <= middle |
//|      -> menghilangkan hedging, entry searah mean-reversion.      |
//|                                                                  |
//| 4. AVERAGING / MARTINGALE (per arah, tiap tick, tanpa filter     |
//|    sideways dan tanpa filter sesi)                               |
//|    Sell baru dibuka jika SEMUA terpenuhi:                        |
//|      - jumlah posisi Sell < InpMaxPositions                      |
//|      - bid >= harga Sell terakhir + InpGridDistance              |
//|    Buy baru dibuka jika SEMUA terpenuhi (kebalikan):             |
//|      - jumlah posisi Buy < InpMaxPositions                       |
//|      - ask <= harga Buy terakhir - InpGridDistance               |
//|    Lot averaging = lot posisi pertama x InpLotMultiplier^N       |
//|    (N = jumlah posisi saat ini), dibulatkan ke step broker.      |
//|                                                                  |
//| 5. TAKE PROFIT (per arah, tutup semua posisi arah tersebut)      |
//|    - 1 posisi   : TP = BEP +/- InpTakeProfitSingle               |
//|    - >= 2 posisi: TP = BEP +/- InpTakeProfitBEP1                 |
//|    Sell ditutup saat ask <= TP, Buy ditutup saat bid >= TP.      |
//|    Setelah tertutup, tick berikutnya kembali ke langkah 3.       |
//|                                                                  |
//| 6. DASHBOARD                                                     |
//|    Comment() di chart: status sesi, bid/ask/spread + status,     |
//|    status news (berita aktif / berikutnya / blackout), nilai &   |
//|    status 3 filter sideways, batas zona entry BB & posisi harga  |
//|    di dalamnya, dan untuk tiap arah: jumlah posisi, total lot,   |
//|    floating, harga averaging berikutnya, BEP, dan target TP.     |
//|                                                                  |
//| CATATAN:                                                         |
//| - Tidak ada Stop Loss. Risiko dibatasi hanya oleh InpMaxPositions|
//| - Semua satuan jarak (grid, TP, spread) dalam satuan HARGA       |
//|   mentah, bukan pips. Lebar BB dalam persen, ER tanpa satuan.    |
//| - Waktu berita dari kalender memakai waktu SERVER broker;        |
//|   sesi dan blackout manual memakai WIB (GMT+7).                  |
//| - EA tidak bergantung pada timeframe chart; semua indikator      |
//|   memakai timeframe eksplisit dari input.                        |
//| - Semua order dicek hasilnya; jika gagal dicetak ke log Expert.  |
//+------------------------------------------------------------------+
#property copyright "Strategi Trading"
#property link      "https://www.mql5.com"
#property version   "4.20"

#include <Trade\Trade.mqh>

//--- Input Parameters --- 
input group "=== SETTING LOT & GRID ==="
input double   InpInitialLot         = 0.01;
input double   InpGridDistance       = 2.0;      // Jarak Averaging
input int      InpMaxPositions       = 99;       // Maksimal Posisi Averaging
input double   InpTakeProfitSingle   = 1.0;
input double   InpTakeProfitBEP1     = 0.7;
input double   InpLotMultiplier      = 1.2;
input ulong    InpMagicNumber        = 88888;

input group "=== FILTER SIDEWAYS (dihitung per candle baru) ==="
input ENUM_TIMEFRAMES InpFilterTimeFrame = PERIOD_M15; // Timeframe BB & Efficiency Ratio
input int      InpBBPeriod           = 20;         // Periode BB
input double   InpBBDeviation        = 2.0;        // Deviasi BB
input double   InpMaxBBWidthPct      = 0.8;        // Maks Lebar BB (% dari harga tengah)
input int      InpERPeriod           = 20;         // Periode Efficiency Ratio
input double   InpMaxER              = 0.3;        // Maks Efficiency Ratio (0=sideways, 1=trending)
input ENUM_TIMEFRAMES InpADXTimeFrame = PERIOD_H1; // Timeframe ADX (konteks tren besar)
input int      InpADXPeriod          = 14;         // Periode ADX
input double   InpMaxADX             = 25.0;       // Maks ADX (di bawah ini = tidak ada tren kuat)

input group "=== ZONA ENTRY BOLLINGER BANDS ==="
input double   InpBBZonePct          = 20.0;       // Jarak minimal dari tepi BB (% lebar band), 0 = nonaktif
input bool     InpDirectionalZone    = false;      // true: Sell hanya di atas middle, Buy hanya di bawah middle

input group "=== AKTIVASI SESI TRADING ==="
input bool     InpUseSessionFilter   = true;     // true: entry hanya di sesi di bawah | false: entry 24 jam
input bool     InpUseAsia            = true;
input bool     InpUseEropa           = false;     
input bool     InpUseUS              = false;     
input string   InpAsiaStart          = "07:00";  
input string   InpAsiaEnd            = "14:00";  
input string   InpEropaStart         = "15:30";  
input string   InpEropaEnd           = "17:30";  
input string   InpUSStart            = "22:30";
input string   InpUSEnd              = "01:30";

input group "=== FILTER SPREAD ==="
input double   InpMaxSpread          = 0.4;      // Maks spread (satuan harga) untuk entry awal, 0 = nonaktif

input group "=== FILTER NEWS (Kalender Ekonomi MT5) ==="
input bool     InpUseNewsFilter      = true;     // Aktifkan filter berita
input string   InpNewsCurrencies     = "USD";    // Mata uang yang dipantau, pisahkan koma (mis. "USD,EUR")
input bool     InpNewsHighOnly       = true;     // true: hanya dampak tinggi | false: tinggi + sedang
input int      InpNewsMinutesBefore  = 30;       // Tahan entry X menit sebelum berita
input int      InpNewsMinutesAfter   = 30;       // Tahan entry X menit sesudah berita
input string   InpBlackout1          = "20:15-21:00"; // Jendela larangan manual WIB (cadangan, aktif juga di tester)
input string   InpBlackout2          = "04:00-05:30"; // Jendela larangan manual WIB
input string   InpBlackout3          = "";       // Jendela larangan manual WIB (kosong = tidak dipakai)

CTrade trade;

int AsiaStartMin, AsiaEndMin, EropaStartMin, EropaEndMin, USStartMin, USEndMin;
int bb_handle, adx_handle;

// Jendela blackout manual (menit WIB), -1 = tidak dipakai
int blackout_start[3] = {-1, -1, -1}, blackout_end[3] = {-1, -1, -1};

// Cache filter news, diperbarui tiap 60 detik
datetime news_last_check = 0;
bool     news_active = false;          // sedang dalam jendela before/after sebuah berita
bool     news_calendar_ok = false;     // kalender berhasil diakses (false di tester / offline)
string   news_active_name = "", news_next_name = "";
datetime news_active_time = 0, news_next_time = 0;

// Cache hasil filter sideways, diperbarui hanya saat candle InpFilterTimeFrame baru
datetime filter_last_bar = 0;
double   filter_bb_width_pct = 0.0, filter_er = 0.0, filter_adx = 0.0;
double   filter_bb_upper = 0.0, filter_bb_middle = 0.0, filter_bb_lower = 0.0;
double   filter_er_net = 0.0, filter_er_total = 0.0;
double   filter_di_plus = 0.0, filter_di_minus = 0.0;
bool     filter_bb_ok = false, filter_er_ok = false, filter_adx_ok = false;

// --- FUNGSI INISIALISASI UTAMA ---
int OnInit()
  {
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(50);
   
   AsiaStartMin = TimeToMinutes(InpAsiaStart); AsiaEndMin = TimeToMinutes(InpAsiaEnd);
   EropaStartMin = TimeToMinutes(InpEropaStart); EropaEndMin = TimeToMinutes(InpEropaEnd);
   USStartMin = TimeToMinutes(InpUSStart); USEndMin = TimeToMinutes(InpUSEnd);

   ParseBlackout(InpBlackout1, 0);
   ParseBlackout(InpBlackout2, 1);
   ParseBlackout(InpBlackout3, 2);

   // Inisialisasi Indikator Filter
   bb_handle = iBands(_Symbol, InpFilterTimeFrame, InpBBPeriod, 0, InpBBDeviation, PRICE_CLOSE);
   if(bb_handle == INVALID_HANDLE) { Print("Gagal memuat indikator BB"); return(INIT_FAILED); }

   adx_handle = iADX(_Symbol, InpADXTimeFrame, InpADXPeriod);
   if(adx_handle == INVALID_HANDLE) { Print("Gagal memuat indikator ADX"); return(INIT_FAILED); }

   return(INIT_SUCCEEDED);
  }

// --- FUNGSI UTAMA (BERJALAN SETIAP TICK HARGA) ---
void OnTick()
  {
   int buy_count = 0, sell_count = 0;
   double sum_buy_volume = 0, sum_buy_value = 0, sum_sell_volume = 0, sum_sell_value = 0;
   double last_buy_price = 0, last_sell_price = 0, initial_buy_lot = 0, initial_sell_lot = 0;
   double floating_buy = 0, floating_sell = 0;
   datetime latest_buy_time = 0, latest_sell_time = 0, oldest_buy_time = 0, oldest_sell_time = 0;
   
   // --- MEMBACA POSISI TERBUKA ---
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && (PositionGetInteger(POSITION_MAGIC) == 0 || PositionGetInteger(POSITION_MAGIC) == InpMagicNumber))
        {
         long type = PositionGetInteger(POSITION_TYPE);
         double price = PositionGetDouble(POSITION_PRICE_OPEN), vol = PositionGetDouble(POSITION_VOLUME);
         datetime time = (datetime)PositionGetInteger(POSITION_TIME);
         
         if(type == POSITION_TYPE_BUY)
           {
            floating_buy += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
            buy_count++; sum_buy_volume += vol; sum_buy_value += (price * vol);
            if(time >= latest_buy_time) { latest_buy_time = time; last_buy_price = price; }
            if(oldest_buy_time == 0 || time < oldest_buy_time) { oldest_buy_time = time; initial_buy_lot = vol; }
           }
         else if(type == POSITION_TYPE_SELL)
           {
            floating_sell += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
            sell_count++; sum_sell_volume += vol; sum_sell_value += (price * vol);
            if(time >= latest_sell_time) { latest_sell_time = time; last_sell_price = price; }
            if(oldest_sell_time == 0 || time < oldest_sell_time) { oldest_sell_time = time; initial_sell_lot = vol; }
           }
        }
     }
     
   // --- FILTER SIDEWAYS (BB Width % + Efficiency Ratio + ADX) ---
   UpdateSidewaysFilter();
   bool is_sideways = (filter_bb_ok && filter_er_ok && filter_adx_ok);
   
   // --- LOGIKA OPEN AWAL (PERTAMA KALI) ---
   bool is_trading_time = IsTradingTime();
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID), ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   // Zona entry: harga harus berjarak minimal InpBBZonePct dari kedua tepi BB
   double bb_width   = filter_bb_upper - filter_bb_lower;
   double zone_upper = filter_bb_upper - bb_width * InpBBZonePct / 100.0;
   double zone_lower = filter_bb_lower + bb_width * InpBBZonePct / 100.0;
   bool   zone_ready = (bb_width > 0);

   bool sell_zone_ok = zone_ready && bid <= zone_upper && bid >= zone_lower;
   bool buy_zone_ok  = zone_ready && ask <= zone_upper && ask >= zone_lower;
   if(InpDirectionalZone)
     {
      sell_zone_ok = sell_zone_ok && bid >= filter_bb_middle;
      buy_zone_ok  = buy_zone_ok  && ask <= filter_bb_middle;
     }

   // Filter spread & news (hanya untuk entry awal)
   double spread = ask - bid;
   bool spread_ok = (InpMaxSpread <= 0 || spread <= InpMaxSpread);

   UpdateNewsFilter();
   bool in_blackout = IsManualBlackout();
   bool news_ok = !InpUseNewsFilter || (!news_active && !in_blackout);

   bool entry_allowed = is_trading_time && is_sideways && spread_ok && news_ok;

   if(sell_count == 0 && entry_allowed && sell_zone_ok)
     {
      if(!trade.Sell(CalculateLot(InpInitialLot), _Symbol, bid, 0, 0, "First Auto Sell"))
         Print("Gagal First Auto Sell: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
     }

   if(buy_count == 0 && entry_allowed && buy_zone_ok)
     {
      if(!trade.Buy(CalculateLot(InpInitialLot), _Symbol, ask, 0, 0, "First Auto Buy"))
         Print("Gagal First Auto Buy: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
     }

   // --- DASHBOARD LAYAR ---
   string tf_filter = EnumToString(InpFilterTimeFrame);
   string tf_adx    = EnumToString(InpADXTimeFrame);

   string dashboard = "=== EA MARTINGALE (SIDEWAYS FILTER) v4.2 ===\n";
   dashboard += "Server: " + TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) + " | Sesi: " + (InpUseSessionFilter ? (string)(is_trading_time ? "ON (WIB)" : "OFF (WIB)") : "24 JAM") + "\n";
   dashboard += "Bid: " + DoubleToString(bid, _Digits) + " | Ask: " + DoubleToString(ask, _Digits) + " | Spread: " + DoubleToString(spread, _Digits);
   dashboard += (InpMaxSpread > 0 ? " (maks " + DoubleToString(InpMaxSpread, _Digits) + ") " + (spread_ok ? "[OK]" : "[X]") : " (filter off)") + "\n\n";

   dashboard += "--- FILTER NEWS ---\n";
   if(!InpUseNewsFilter)
      dashboard += "Nonaktif\n";
   else
     {
      dashboard += "Kalender: " + (news_calendar_ok ? "aktif (" + InpNewsCurrencies + ", " + (InpNewsHighOnly ? "HIGH" : "HIGH+MED") + ")" : "TIDAK TERSEDIA (tester/offline) - hanya blackout manual") + "\n";
      if(news_active)
         dashboard += "SEDANG BERITA: " + news_active_name + " @ " + TimeToString(news_active_time, TIME_MINUTES) + " server  [X]\n";
      else if(news_calendar_ok)
         dashboard += "Berita berikutnya: " + (news_next_time > 0 ? news_next_name + " @ " + TimeToString(news_next_time, TIME_DATE|TIME_MINUTES) + " server" : "tidak ada dalam 24 jam") + "  [OK]\n";
      dashboard += "Blackout manual WIB: " + InpBlackout1 + (InpBlackout2 != "" ? ", " + InpBlackout2 : "") + (InpBlackout3 != "" ? ", " + InpBlackout3 : "") + "  " + (in_blackout ? "[X AKTIF]" : "[OK]") + "\n";
     }
   dashboard += "\n";

   dashboard += "--- FILTER SIDEWAYS (update: " + TimeToString(filter_last_bar, TIME_DATE|TIME_MINUTES) + ") ---\n";
   dashboard += "[1] Bollinger Bands " + tf_filter + " (" + IntegerToString(InpBBPeriod) + ", " + DoubleToString(InpBBDeviation, 1) + ")\n";
   dashboard += "    Upper : " + DoubleToString(filter_bb_upper, _Digits) + "\n";
   dashboard += "    Middle: " + DoubleToString(filter_bb_middle, _Digits) + "\n";
   dashboard += "    Lower : " + DoubleToString(filter_bb_lower, _Digits) + "\n";
   dashboard += "    Lebar : " + DoubleToString(filter_bb_upper - filter_bb_lower, _Digits) + " = " + DoubleToString(filter_bb_width_pct, 3) + "%  (maks " + DoubleToString(InpMaxBBWidthPct, 2) + "%)  " + (filter_bb_ok ? "[OK]" : "[X]") + "\n";
   dashboard += "[2] Efficiency Ratio " + tf_filter + " (" + IntegerToString(InpERPeriod) + " candle)\n";
   dashboard += "    Jarak bersih: " + DoubleToString(filter_er_net, _Digits) + " | Total jalan: " + DoubleToString(filter_er_total, _Digits) + "\n";
   dashboard += "    ER    : " + DoubleToString(filter_er, 3) + "  (maks " + DoubleToString(InpMaxER, 2) + ")  " + (filter_er_ok ? "[OK]" : "[X]") + "\n";
   dashboard += "[3] ADX " + tf_adx + " (" + IntegerToString(InpADXPeriod) + ")\n";
   dashboard += "    +DI: " + DoubleToString(filter_di_plus, 1) + " | -DI: " + DoubleToString(filter_di_minus, 1) + " | Arah: " + (filter_di_plus > filter_di_minus ? "NAIK" : "TURUN") + "\n";
   dashboard += "    ADX   : " + DoubleToString(filter_adx, 1) + "  (maks " + DoubleToString(InpMaxADX, 1) + ")  " + (filter_adx_ok ? "[OK]" : "[X]") + "\n";
   dashboard += ">> STATUS: " + (string)(is_sideways ? "SIDEWAYS - Entry Diizinkan" : "TRENDING - Entry Ditahan") + "\n\n";

   dashboard += "--- ZONA ENTRY BB (" + DoubleToString(InpBBZonePct, 0) + "% dari tepi" + (InpDirectionalZone ? ", arah terpisah" : ", hedging") + ") ---\n";
   dashboard += "Batas Atas : " + DoubleToString(zone_upper, _Digits) + "\n";
   dashboard += "Batas Bawah: " + DoubleToString(zone_lower, _Digits) + "\n";
   dashboard += "Posisi Harga: " + (bb_width > 0 ? DoubleToString((bid - filter_bb_lower) / bb_width * 100.0, 1) + "% dari lower" : "-") + "\n";
   dashboard += "Sell: " + (sell_zone_ok ? "[ZONA OK]" : "[DI LUAR ZONA]") + " | Buy: " + (buy_zone_ok ? "[ZONA OK]" : "[DI LUAR ZONA]") + "\n\n";
   
   // --- AVERAGING & TAKE PROFIT LOGIC (SELL) ---
   if(sell_count > 0 && sum_sell_volume > 0)
     {
      double bep = sum_sell_value / sum_sell_volume;
      double tp;
      string tp_mode_sell = "";

      // Logika Penentuan Take Profit SELL
      if(sell_count == 1)
        {
         tp = bep - InpTakeProfitSingle;
         tp_mode_sell = "Mode Single Posisi";
        }
      else
        {
         tp = bep - InpTakeProfitBEP1;
         tp_mode_sell = "Mode Averaging (BEP)";
        }

      double next_sell_price = last_sell_price + InpGridDistance;

      dashboard += "--- STATUS SELL ---\n";
      dashboard += "Total Posisi: " + IntegerToString(sell_count) + " / " + IntegerToString(InpMaxPositions) + " (" + tp_mode_sell + ")\n";
      dashboard += "Total Lot: " + DoubleToString(sum_sell_volume, 2) + " | Floating: $" + DoubleToString(floating_sell, 2) + "\n";
      dashboard += "Syarat Jarak Buka Berikutnya: " + DoubleToString(next_sell_price, _Digits) + "\n";
      dashboard += "Harga BEP Rata-rata: " + DoubleToString(bep, _Digits) + "\n";
      dashboard += "Target Close (TP) di Harga: " + DoubleToString(tp, _Digits) + "\n\n";

      // Buka Posisi Martingale Baru
      if(sell_count < InpMaxPositions && last_sell_price > 0 && bid >= next_sell_price)
        {
         double new_lot = CalculateLot(initial_sell_lot * MathPow(InpLotMultiplier, sell_count));
         if(!trade.Sell(new_lot, _Symbol, bid, 0, 0, "Auto Averaging Sell"))
            Print("Gagal Averaging Sell: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
        }
      if(ask <= tp && tp > 0)
        {
         CloseAll(POSITION_TYPE_SELL);
        }
     }
     
   // --- AVERAGING & TAKE PROFIT LOGIC (BUY) ---
   if(buy_count > 0 && sum_buy_volume > 0)
     {
      double bep = sum_buy_value / sum_buy_volume;
      double tp;
      string tp_mode_buy = "";

      // Logika Penentuan Take Profit BUY
      if(buy_count == 1)
        {
         tp = bep + InpTakeProfitSingle;
         tp_mode_buy = "Mode Single Posisi";
        }
      else
        {
         tp = bep + InpTakeProfitBEP1;
         tp_mode_buy = "Mode Averaging (BEP)";
        }

      double next_buy_price = last_buy_price - InpGridDistance;

      dashboard += "--- STATUS BUY ---\n";
      dashboard += "Total Posisi: " + IntegerToString(buy_count) + " / " + IntegerToString(InpMaxPositions) + " (" + tp_mode_buy + ")\n";
      dashboard += "Total Lot: " + DoubleToString(sum_buy_volume, 2) + " | Floating: $" + DoubleToString(floating_buy, 2) + "\n";
      dashboard += "Syarat Jarak Buka Berikutnya: " + DoubleToString(next_buy_price, _Digits) + "\n";
      dashboard += "Harga BEP Rata-rata: " + DoubleToString(bep, _Digits) + "\n";
      dashboard += "Target Close (TP) di Harga: " + DoubleToString(tp, _Digits) + "\n\n";

      // Buka Posisi Martingale Baru
      if(buy_count < InpMaxPositions && last_buy_price > 0 && ask <= next_buy_price)
        {
         double new_lot = CalculateLot(initial_buy_lot * MathPow(InpLotMultiplier, buy_count));
         if(!trade.Buy(new_lot, _Symbol, ask, 0, 0, "Auto Averaging Buy"))
            Print("Gagal Averaging Buy: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
        }
      if(bid >= tp && tp > 0)
        {
         CloseAll(POSITION_TYPE_BUY);
        }
     }
     
   Comment(dashboard);
  }

// --- FUNGSI FILTER SIDEWAYS (dihitung ulang hanya saat candle baru) ---
// Semua nilai memakai candle yang sudah tertutup (shift 1) agar stabil.
// Jika data belum siap, cache lama dipertahankan dan dicoba lagi tick berikutnya.
void UpdateSidewaysFilter()
  {
   datetime current_bar = iTime(_Symbol, InpFilterTimeFrame, 0);
   if(current_bar == 0 || current_bar == filter_last_bar) return;

   // 1. Lebar Bollinger Bands relatif terhadap harga tengah (%)
   double upper[], middle[], lower[];
   if(CopyBuffer(bb_handle, 0, 1, 1, middle) <= 0 ||
      CopyBuffer(bb_handle, 1, 1, 1, upper)  <= 0 ||
      CopyBuffer(bb_handle, 2, 1, 1, lower)  <= 0 ||
      middle[0] <= 0) return;

   // 2. Kaufman Efficiency Ratio: jarak bersih / total jarak yang ditempuh
   double close[];
   ArraySetAsSeries(close, true);
   if(CopyClose(_Symbol, InpFilterTimeFrame, 1, InpERPeriod + 1, close) < InpERPeriod + 1) return;

   double net_move = MathAbs(close[0] - close[InpERPeriod]);
   double total_move = 0.0;
   for(int i = 0; i < InpERPeriod; i++)
      total_move += MathAbs(close[i] - close[i + 1]);

   // 3. ADX pada timeframe konteks (buffer 0 = ADX, 1 = +DI, 2 = -DI)
   double adx[], di_plus[], di_minus[];
   if(CopyBuffer(adx_handle, 0, 1, 1, adx)      <= 0 ||
      CopyBuffer(adx_handle, 1, 1, 1, di_plus)  <= 0 ||
      CopyBuffer(adx_handle, 2, 1, 1, di_minus) <= 0) return;

   // Semua data berhasil diambil: perbarui cache
   filter_bb_upper     = upper[0];
   filter_bb_middle    = middle[0];
   filter_bb_lower     = lower[0];
   filter_bb_width_pct = (upper[0] - lower[0]) / middle[0] * 100.0;
   filter_er_net       = net_move;
   filter_er_total     = total_move;
   filter_er           = (total_move > 0) ? net_move / total_move : 0.0;
   filter_adx          = adx[0];
   filter_di_plus      = di_plus[0];
   filter_di_minus     = di_minus[0];

   filter_bb_ok  = (filter_bb_width_pct < InpMaxBBWidthPct);
   filter_er_ok  = (filter_er < InpMaxER);
   filter_adx_ok = (filter_adx < InpMaxADX);

   filter_last_bar = current_bar;
  }

// --- FUNGSI FILTER NEWS: cek kalender ekonomi MT5 (refresh tiap 60 detik) ---
// Kalender tidak tersedia di strategy tester; saat itu hanya blackout manual yang bekerja.
void UpdateNewsFilter()
  {
   if(!InpUseNewsFilter) return;

   datetime now = TimeCurrent();
   if(news_last_check > 0 && now - news_last_check < 60) return;
   news_last_check = now;

   news_active = false;
   news_active_name = ""; news_active_time = 0;
   news_next_name = "";   news_next_time = 0;

   if(MQLInfoInteger(MQL_TESTER)) { news_calendar_ok = false; return; }

   string currencies[];
   int n_cur = StringSplit(InpNewsCurrencies, ',', currencies);
   if(n_cur <= 0) { news_calendar_ok = false; return; }

   datetime from = now - InpNewsMinutesAfter * 60;
   datetime to   = now + 24 * 3600;
   bool any_ok = false;

   for(int c = 0; c < n_cur; c++)
     {
      string cur = currencies[c];
      StringTrimLeft(cur); StringTrimRight(cur);
      if(cur == "") continue;

      MqlCalendarValue values[];
      if(!CalendarValueHistory(values, from, to, NULL, cur)) continue;
      any_ok = true;

      for(int i = 0; i < ArraySize(values); i++)
        {
         MqlCalendarEvent ev;
         if(!CalendarEventById(values[i].event_id, ev)) continue;

         bool important = (ev.importance == CALENDAR_IMPORTANCE_HIGH) ||
                          (!InpNewsHighOnly && ev.importance == CALENDAR_IMPORTANCE_MODERATE);
         if(!important) continue;

         datetime t = values[i].time;

         // Sedang dalam jendela larangan sebuah berita
         if(t - InpNewsMinutesBefore * 60 <= now && now <= t + InpNewsMinutesAfter * 60)
           {
            if(!news_active || t < news_active_time)
              { news_active = true; news_active_time = t; news_active_name = cur + " " + ev.name; }
           }
         // Berita berikutnya (untuk dashboard)
         else if(t > now && (news_next_time == 0 || t < news_next_time))
           { news_next_time = t; news_next_name = cur + " " + ev.name; }
        }
     }

   news_calendar_ok = any_ok;
  }

// --- FUNGSI PARSE JENDELA BLACKOUT "HH:MM-HH:MM" ---
void ParseBlackout(string window, int idx)
  {
   blackout_start[idx] = -1; blackout_end[idx] = -1;
   string parts[];
   if(StringSplit(window, '-', parts) != 2) return;
   StringTrimLeft(parts[0]); StringTrimRight(parts[0]);
   StringTrimLeft(parts[1]); StringTrimRight(parts[1]);
   if(parts[0] == "" || parts[1] == "") return;
   blackout_start[idx] = TimeToMinutes(parts[0]);
   blackout_end[idx]   = TimeToMinutes(parts[1]);
  }

// --- FUNGSI CEK BLACKOUT MANUAL (WIB) ---
bool IsManualBlackout()
  {
   int current_min = CurrentMinuteWIB();
   for(int i = 0; i < 3; i++)
     {
      if(blackout_start[i] < 0) continue;
      if(CheckSession(current_min, blackout_start[i], blackout_end[i])) return true;
     }
   return false;
  }

// --- FUNGSI MENIT SAAT INI DALAM WIB (GMT+7) ---
int CurrentMinuteWIB()
  {
   MqlDateTime dt;
   TimeToStruct(TimeGMT() + 25200, dt);
   return dt.hour * 60 + dt.min;
  }

// --- FUNGSI KONVERSI WAKTU ---
int TimeToMinutes(string time_str)
  {
   string arr[];
   if(StringSplit(time_str, ':', arr) == 2)
     {
      return (int)StringToInteger(arr[0]) * 60 + (int)StringToInteger(arr[1]);
     }
   return 0;
  }

// --- FUNGSI CEK SESI TRADING ---
bool CheckSession(int current_min, int start_min, int end_min)
  {
   if(start_min < end_min)
     {
      return (current_min >= start_min && current_min <= end_min);
     }
   else
     {
      return (current_min >= start_min || current_min <= end_min);
     }
  }

// --- FUNGSI VALIDASI WAKTU TRADING ---
bool IsTradingTime()
  {
   if(!InpUseSessionFilter) return true; // Mode 24 jam: semua waktu dianggap sesi aktif

   int current_min = CurrentMinuteWIB();

   if(InpUseAsia && CheckSession(current_min, AsiaStartMin, AsiaEndMin)) return true;
   if(InpUseEropa && CheckSession(current_min, EropaStartMin, EropaEndMin)) return true;
   if(InpUseUS && CheckSession(current_min, USStartMin, USEndMin)) return true;
   
   return false;
  }

// --- FUNGSI TUTUP SEMUA POSISI (TAKE PROFIT) ---
void CloseAll(long pos_type)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionGetString(POSITION_SYMBOL) == _Symbol)
        {
         if((PositionGetInteger(POSITION_MAGIC) == 0 || PositionGetInteger(POSITION_MAGIC) == InpMagicNumber) && PositionGetInteger(POSITION_TYPE) == pos_type)
           {
            trade.PositionClose(ticket);
           }
        }
     }
  }

// --- FUNGSI PERHITUNGAN LOT AMAN ---
double CalculateLot(double calc_lot)
  {
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double final_lot = MathRound(calc_lot / step) * step;
   double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   
   return MathMax(min_lot, MathMin(final_lot, max_lot));
  }
//+------------------------------------------------------------------+
