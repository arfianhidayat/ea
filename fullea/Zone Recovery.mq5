//+--------------------------------------------------+
//| ZoneRecoveryEA.mq5                               |
//| Zone Recovery Hedging EA untuk XAUUSD            |
//| Akun harus bertipe HEDGING                       |
//| PERINGATAN: TANPA STOP LOSS,                     |
//| TANPA CUT-LOSS PER SIKLUS                        |
//+--------------------------------------------------+
//
// ALUR KERJA EA
// ----------------------------------------------------
// 1. MENUNGGU
//    Tidak ada posisi/pending EA.
//    Jika jam WIB masuk jendela, spread OK, ATR OK:
//    pasang Buy Stop di Ask + JarakPendingAwal dan
//    Sell Stop di Bid - JarakPendingAwal, lot LotAwal,
//    komentar "ZR L0".
//    Jika 60 menit tidak tersentuh, keduanya dihapus.
//
// 2. ZONA
//    Salah satu stop tereksekusi di harga P.
//    SELL pertama: bawah = P, atas = P + LebarZona
//    BUY  pertama: atas  = P, bawah = P - LebarZona
//    TP atas  = atas  + JarakTP
//    TP bawah = bawah - JarakTP
//    Pending awal yang tersisa dihapus.
//    Batas disimpan ke Global Variable (tahan restart).
//
// 3. RECOVERY
//    Posisi terakhir BUY  -> Sell Stop di batas bawah.
//    Posisi terakhir SELL -> Buy Stop  di batas atas.
//    Lot = DeretLot[level berikutnya].
//    Tiap pending tereksekusi: level naik, pending
//    baru dipasang di sisi seberang.
//    Posisi lama tidak pernah ditutup satu per satu.
//    Berhenti jika MaxLevel tercapai / deret habis.
//
// 4. TARGET
//    Tiap tick: Bid >= TP atas atau Ask <= TP bawah
//    -> hapus semua pending, tutup semua posisi
//    (close-all dari kode), reset, kembali ke 1.
//
// 5. PEMULIHAN
//    Saat restart: posisi tertua = posisi pertama,
//    zona/TP/level dihitung ulang dari posisi yang
//    ada dan Global Variable.
//
// 6. TAMPILAN
//    Panel Comment() di kiri atas chart dan garis
//    horizontal: zona (oranye), TP (hijau).
//
// TIDAK ADA STOP LOSS. Siklus berakhir hanya dengan
// TP, berhenti di MaxLevel (menggantung), atau
// margin call.
// ------------------------------------------------------

#property copyright "Zone Recovery EA"
#property version   "1.01"
#property description "Zone Recovery hedging XAUUSD."
#property description "TANPA STOP LOSS. Risiko tinggi."

// Library standar untuk order, posisi, pending
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>

//======================= INPUT =========================

input group "--- Identitas & Lot ---"
// Nomor unik penanda order milik EA ini
input long MagicNumber = 20261006; // Magic Number
// Lot pending awal (level 0)
input double LotAwal = 0.10; // Lot awal
// Lot per level, pisah koma, index 0 = level 0
input string DeretLot = "0.10,0.30,0.75,1.50,3.00,6.00,12.00"; // Deret lot

input group "--- Zona & Target ---"
// Jarak batas atas-bawah zona (harga/USD)
input double LebarZona = 3.1; // Lebar zona
// Jarak TP di luar batas zona (harga)
input double JarakTP = 5.0; // Jarak TP
// Level maksimum, 0 = tanpa batas
input int MaxLevel = 0; // Max level

input group "--- Jendela Waktu (WIB) ---"
// Jam mulai entry awal, WIB. Kosong = 24 jam
input string JamMulai = "19:30"; // Jam mulai WIB
// Jam selesai entry awal, WIB. Kosong = 24 jam
input string JamSelesai = "20:30"; // Jam selesai WIB
// Offset jam server ke GMT, hanya untuk Tester
input int OffsetServerGMT_Tester = 2; // Offset GMT tester

input group "--- Pending Awal ---"
// Jarak Buy/Sell Stop awal dari harga (harga)
input double JarakPendingAwal = 2.0; // Jarak pending awal
// Masa berlaku pending awal (menit), 0 = tanpa
input int ExpirasiPendingAwal = 60; // Expirasi (menit)

input group "--- Filter ATR ---"
// true = entry awal hanya jika ATR >= ATRMinimum
input bool GunakanFilterATR = false; // Filter ATR
// Periode ATR
input int ATRPeriode = 14; // Periode ATR
// Timeframe ATR
input ENUM_TIMEFRAMES ATRTimeframe = PERIOD_M15; // TF ATR
// ATR minimum (harga) agar boleh entry
input double ATRMinimum = 2.0; // ATR minimum

input group "--- Zona Berbasis ATR ---"
// true = LebarZona & JarakTP dari ATR
input bool ZonaBerbasisATR = false; // Zona dari ATR
// LebarZona = ATR x pengali
input double PengaliZonaATR = 1.0; // Pengali zona
// JarakTP = ATR x pengali
input double PengaliTPATR = 1.5; // Pengali TP

input group "--- Eksekusi ---"
// Spread maksimum (point) untuk entry awal
input int MaxSpreadPoint = 50; // Max spread (point)
// Deviasi harga market order (point)
input int Slippage = 30; // Slippage (point)

input group "--- Tampilan ---"
// Gambar garis zona & TP di chart
input bool GambarGaris = true; // Gambar garis

//======================= GLOBAL ========================

// Objek pengirim order
CTrade trade;
// Objek pembaca posisi
CPositionInfo pos;
// Objek pembaca pending
COrderInfo ord;

// Array lot hasil parse DeretLot
double g_lots[];
// Jam mulai/selesai dalam menit sejak 00:00 WIB
int g_startMin = -1;
int g_endMin = -1;
// true jika jendela waktu dipakai
bool g_useWindow = false;
// Handle indikator ATR
int g_atrHandle = INVALID_HANDLE;

// true jika siklus zona sedang berjalan
bool g_cycleActive = false;
// Level saat ini: -1 tidak ada, 0 posisi pertama
int g_level = -1;
// Batas zona dan TP
double g_zoneUpper = 0.0;
double g_zoneLower = 0.0;
double g_tpUpper = 0.0;
double g_tpLower = 0.0;
// Lebar zona dan jarak TP siklus ini
double g_zoneWidth = 0.0;
double g_tpDist = 0.0;
// true saat sedang close-all
bool g_closing = false;
// Waktu percobaan order terakhir (throttle)
datetime g_lastTryTime = 0;
// Waktu Comment() terakhir diperbarui
datetime g_lastCommentTime = 0;
// Nama Global Variable penyimpan zona/TP
string g_gvZW = "";
string g_gvTP = "";
// Pesan status untuk panel chart
string g_lastMsg = "";
// Prefix nama objek garis di chart
string g_objPrefix = "";

//======================= UTIL ==========================

// Bulatkan harga sesuai digit simbol
double NormPrice(double p)
{
   return NormalizeDouble(p, _Digits);
}

// Rapikan lot sesuai step/min/max broker
double NormalizeLot(double lot)
{
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double mn = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double mx = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   // Bulatkan ke bawah ke kelipatan step
   if(step > 0)
      lot = MathFloor(lot / step + 1e-8) * step;
   // Batasi ke rentang min-max
   if(lot < mn) lot = mn;
   if(lot > mx) lot = mx;
   // Hitung jumlah desimal dari step
   int d = 0;
   double s = step;
   while(s < 1.0 && d < 8)
   {
      s *= 10.0;
      d++;
   }
   return NormalizeDouble(lot, d);
}

// Pecah "a,b,c" menjadi array lot
bool ParseLots(string s)
{
   string parts[];
   int n = StringSplit(s, ',', parts);
   ArrayResize(g_lots, 0);
   for(int i = 0; i < n; i++)
   {
      string p = parts[i];
      StringTrimLeft(p);
      StringTrimRight(p);
      // Lewati kosong atau tidak valid
      if(p == "") continue;
      double v = StringToDouble(p);
      if(v <= 0) continue;
      // Tambah ke array
      int k = ArraySize(g_lots);
      ArrayResize(g_lots, k + 1);
      g_lots[k] = v;
   }
   return (ArraySize(g_lots) > 0);
}

// "HH:MM" -> menit sejak 00:00, -1 jika tidak valid
int ParseHHMM(string s)
{
   StringTrimLeft(s);
   StringTrimRight(s);
   if(s == "") return -1;
   string p[];
   if(StringSplit(s, ':', p) < 2) return -1;
   int h = (int)StringToInteger(p[0]);
   int m = (int)StringToInteger(p[1]);
   if(h < 0 || h > 23 || m < 0 || m > 59) return -1;
   return h * 60 + m;
}

// Waktu WIB (UTC+7) sekarang
datetime WIBNow()
{
   datetime gmt;
   // Tester tidak tahu offset GMT -> pakai input
   if(MQLInfoInteger(MQL_TESTER))
      gmt = TimeCurrent()
            - (datetime)(OffsetServerGMT_Tester * 3600);
   else
      gmt = TimeGMT();
   return gmt + 7 * 3600;
}

// Apakah sekarang di dalam jendela entry
bool InTimeWindow()
{
   if(!g_useWindow) return true;
   MqlDateTime dt;
   TimeToStruct(WIBNow(), dt);
   int cur = dt.hour * 60 + dt.min;
   // Jendela normal, mis. 19:30-20:30
   if(g_startMin <= g_endMin)
      return (cur >= g_startMin && cur <= g_endMin);
   // Jendela lewat tengah malam, mis. 23:00-02:00
   return (cur >= g_startMin || cur <= g_endMin);
}

// ATR bar terakhir yang sudah tutup (harga)
double GetATR()
{
   if(g_atrHandle == INVALID_HANDLE) return 0.0;
   double b[];
   if(CopyBuffer(g_atrHandle, 0, 1, 1, b) < 1)
      return 0.0;
   return b[0];
}

// Apakah broker mendukung expiration waktu tertentu
bool ExpirationSupported()
{
   long mode = SymbolInfoInteger(_Symbol,
                                 SYMBOL_EXPIRATION_MODE);
   return ((mode & SYMBOL_EXPIRATION_SPECIFIED) != 0);
}

// Cek free margin cukup untuk order
bool CheckMargin(ENUM_ORDER_TYPE type,
                 double lot, double price)
{
   double margin = 0.0;
   if(!OrderCalcMargin(type, _Symbol, lot, price, margin))
   {
      PrintFormat("OrderCalcMargin gagal, err=%d",
                  GetLastError());
      return false;
   }
   double freeMargin =
      AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   if(margin > freeMargin)
   {
      PrintFormat("MARGIN TIDAK CUKUP: butuh %.2f, "
                  "free %.2f (lot %.2f, %s)",
                  margin, freeMargin, lot,
                  EnumToString(type));
      g_lastMsg = StringFormat(
         "Margin tidak cukup lot %.2f (butuh %.2f)",
         lot, margin);
      return false;
   }
   return true;
}

// Lot untuk level tertentu, -1 jika deret habis
double LotForLevel(int level)
{
   if(level == 0) return LotAwal;
   if(level < ArraySize(g_lots)) return g_lots[level];
   return -1.0;
}

//======================= SCAN ==========================

// Jumlah posisi terbuka milik EA
int CountPositions()
{
   int c = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!pos.SelectByIndex(i)) continue;
      if(pos.Magic() != MagicNumber) continue;
      if(pos.Symbol() != _Symbol) continue;
      c++;
   }
   return c;
}

// Jumlah pending order milik EA
int CountPendings()
{
   int c = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!ord.SelectByIndex(i)) continue;
      if(ord.Magic() != MagicNumber) continue;
      if(ord.Symbol() != _Symbol) continue;
      c++;
   }
   return c;
}

// Tiket posisi tertua (pertama) dan terbaru (terakhir)
bool GetFirstLastPosition(ulong &firstTicket,
                          ulong &lastTicket)
{
   firstTicket = 0;
   lastTicket = 0;
   long tFirst = 0;
   long tLast = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!pos.SelectByIndex(i)) continue;
      if(pos.Magic() != MagicNumber) continue;
      if(pos.Symbol() != _Symbol) continue;
      long t = pos.TimeMsc();
      ulong tk = pos.Ticket();
      // Lebih tua -> jadi posisi pertama
      if(firstTicket == 0 || t < tFirst
         || (t == tFirst && tk < firstTicket))
      {
         tFirst = t;
         firstTicket = tk;
      }
      // Lebih baru -> jadi posisi terakhir
      if(lastTicket == 0 || t > tLast
         || (t == tLast && tk > lastTicket))
      {
         tLast = t;
         lastTicket = tk;
      }
   }
   return (firstTicket != 0);
}

// Total lot, floating P/L, net lot posisi EA
void GetBasketStats(double &totalLot,
                    double &floatPL,
                    double &netLot)
{
   totalLot = 0;
   floatPL = 0;
   netLot = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!pos.SelectByIndex(i)) continue;
      if(pos.Magic() != MagicNumber) continue;
      if(pos.Symbol() != _Symbol) continue;
      totalLot += pos.Volume();
      // Buy positif, sell negatif
      if(pos.PositionType() == POSITION_TYPE_BUY)
         netLot += pos.Volume();
      else
         netLot -= pos.Volume();
      // P/L termasuk swap dan komisi
      floatPL += pos.Profit() + pos.Swap()
                 + pos.Commission();
   }
}

//======================= ORDER =========================

// Hapus semua pending milik EA
void DeleteAllPendings()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!ord.SelectByIndex(i)) continue;
      if(ord.Magic() != MagicNumber) continue;
      if(ord.Symbol() != _Symbol) continue;
      if(!trade.OrderDelete(ord.Ticket()))
         PrintFormat("Gagal hapus pending #%I64u rc=%d",
                     ord.Ticket(), trade.ResultRetcode());
   }
}

// Tutup semua posisi milik EA
void CloseAllPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!pos.SelectByIndex(i)) continue;
      if(pos.Magic() != MagicNumber) continue;
      if(pos.Symbol() != _Symbol) continue;
      if(!trade.PositionClose(pos.Ticket()))
         PrintFormat("Gagal close posisi #%I64u rc=%d",
                     pos.Ticket(), trade.ResultRetcode());
   }
}

// Hapus pending dulu, lalu tutup posisi
void CloseAllAndDelete()
{
   DeleteAllPendings();
   CloseAllPositions();
}

// Pasang pending stop.
// Jika harga sudah terlewati dan allowMarket=true,
// langsung market order.
bool PlaceStop(ENUM_ORDER_TYPE type, double lot,
               double price, string cmt,
               int expMin, bool allowMarket)
{
   lot = NormalizeLot(lot);
   price = NormPrice(price);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   // Jarak minimum stop dari harga (point -> harga)
   double stops = (double)SymbolInfoInteger(
                     _Symbol, SYMBOL_TRADE_STOPS_LEVEL)
                  * _Point;

   // Default: berlaku sampai dibatalkan
   ENUM_ORDER_TYPE_TIME tt = ORDER_TIME_GTC;
   datetime exp = 0;
   if(expMin > 0 && ExpirationSupported())
   {
      tt = ORDER_TIME_SPECIFIED;
      exp = TimeCurrent() + (datetime)(expMin * 60);
   }

   bool ok = false;

   if(type == ORDER_TYPE_BUY_STOP)
   {
      // Harga stop terlalu dekat / sudah terlewati
      if(price <= ask + stops)
      {
         if(!allowMarket)
         {
            // Pending awal: geser agar valid
            price = NormPrice(ask + stops + _Point);
         }
         else
         {
            // Recovery: market buy
            if(!CheckMargin(ORDER_TYPE_BUY, lot, ask))
               return false;
            ok = trade.Buy(lot, _Symbol, 0.0, 0.0, 0.0, cmt);
            PrintFormat("%s BUY MARKET lot %.2f rc=%d",
                        cmt, lot, trade.ResultRetcode());
            return ok;
         }
      }
      if(!CheckMargin(ORDER_TYPE_BUY_STOP, lot, price))
         return false;
      ok = trade.BuyStop(lot, price, _Symbol,
                         0.0, 0.0, tt, exp, cmt);
      PrintFormat("%s BUY STOP @%.2f lot %.2f -> %s rc=%d",
                  cmt, price, lot, ok ? "OK" : "GAGAL",
                  trade.ResultRetcode());
   }
   else if(type == ORDER_TYPE_SELL_STOP)
   {
      // Harga stop terlalu dekat / sudah terlewati
      if(price >= bid - stops)
      {
         if(!allowMarket)
         {
            // Pending awal: geser agar valid
            price = NormPrice(bid - stops - _Point);
         }
         else
         {
            // Recovery: market sell
            if(!CheckMargin(ORDER_TYPE_SELL, lot, bid))
               return false;
            ok = trade.Sell(lot, _Symbol, 0.0, 0.0, 0.0, cmt);
            PrintFormat("%s SELL MARKET lot %.2f rc=%d",
                        cmt, lot, trade.ResultRetcode());
            return ok;
         }
      }
      if(!CheckMargin(ORDER_TYPE_SELL_STOP, lot, price))
         return false;
      ok = trade.SellStop(lot, price, _Symbol,
                          0.0, 0.0, tt, exp, cmt);
      PrintFormat("%s SELL STOP @%.2f lot %.2f -> %s rc=%d",
                  cmt, price, lot, ok ? "OK" : "GAGAL",
                  trade.ResultRetcode());
   }
   return ok;
}

//======================= GARIS CHART ===================

// Buat atau perbarui satu garis horizontal
void DrawHLine(string name, double price,
               color clr, int style, string text)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   }
   ObjectSetDouble(0, name, OBJPROP_PRICE, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
}

// Gambar garis zona (oranye) dan TP (hijau)
void DrawLevels()
{
   if(!GambarGaris) return;
   if(!g_cycleActive)
   {
      DeleteLevels();
      return;
   }
   DrawHLine(g_objPrefix + "ZoneUp", g_zoneUpper,
             clrOrange, STYLE_DASH, "Batas atas zona");
   DrawHLine(g_objPrefix + "ZoneLow", g_zoneLower,
             clrOrange, STYLE_DASH, "Batas bawah zona");
   DrawHLine(g_objPrefix + "TPUp", g_tpUpper,
             clrLimeGreen, STYLE_SOLID, "TP atas");
   DrawHLine(g_objPrefix + "TPLow", g_tpLower,
             clrLimeGreen, STYLE_SOLID, "TP bawah");
}

// Hapus semua garis milik EA
void DeleteLevels()
{
   ObjectsDeleteAll(0, g_objPrefix);
}

//======================= SIKLUS ========================

// Tetapkan batas zona dan TP dari posisi pertama
void SetZone(long firstType, double P,
             double zw, double tpd)
{
   g_zoneWidth = zw;
   g_tpDist = tpd;
   if(firstType == POSITION_TYPE_SELL)
   {
      // SELL pertama: bawah = P, atas = P + lebar
      g_zoneLower = NormPrice(P);
      g_zoneUpper = NormPrice(P + zw);
   }
   else
   {
      // BUY pertama: atas = P, bawah = P - lebar
      g_zoneUpper = NormPrice(P);
      g_zoneLower = NormPrice(P - zw);
   }
   g_tpUpper = NormPrice(g_zoneUpper + tpd);
   g_tpLower = NormPrice(g_zoneLower - tpd);
   g_cycleActive = true;
   // Simpan agar tahan restart
   GlobalVariableSet(g_gvZW, zw);
   GlobalVariableSet(g_gvTP, tpd);
   DrawLevels();
}

// Reset semua state siklus
void ResetCycle()
{
   g_cycleActive = false;
   g_level = -1;
   g_zoneUpper = 0.0;
   g_zoneLower = 0.0;
   g_tpUpper = 0.0;
   g_tpLower = 0.0;
   g_zoneWidth = 0.0;
   g_tpDist = 0.0;
   g_closing = false;
   if(GlobalVariableCheck(g_gvZW))
      GlobalVariableDel(g_gvZW);
   if(GlobalVariableCheck(g_gvTP))
      GlobalVariableDel(g_gvTP);
   DeleteLevels();
}

// Mulai siklus saat posisi pertama terdeteksi
void StartCycle()
{
   ulong ft, lt;
   if(!GetFirstLastPosition(ft, lt)) return;
   if(!PositionSelectByTicket(ft)) return;
   double P = PositionGetDouble(POSITION_PRICE_OPEN);
   long type = PositionGetInteger(POSITION_TYPE);
   double zw = LebarZona;
   double tpd = JarakTP;
   // Hitung zona dari ATR jika diminta
   if(ZonaBerbasisATR)
   {
      double a = GetATR();
      if(a > 0)
      {
         zw = a * PengaliZonaATR;
         tpd = a * PengaliTPATR;
      }
      else
         Print("ATR tidak tersedia, pakai input");
   }
   SetZone(type, P, zw, tpd);
   g_level = 0;
   PrintFormat("SIKLUS BARU: %s @%.2f | Zona %.2f-%.2f "
               "| TP %.2f / %.2f",
               type == POSITION_TYPE_BUY ? "BUY" : "SELL",
               P, g_zoneLower, g_zoneUpper,
               g_tpUpper, g_tpLower);
}

// Pulihkan state setelah restart
void RebuildState()
{
   int n = CountPositions();
   if(n == 0)
   {
      g_cycleActive = false;
      g_level = -1;
      PrintFormat("Restore: tidak ada posisi, pending=%d",
                  CountPendings());
      return;
   }
   ulong ft, lt;
   GetFirstLastPosition(ft, lt);
   PositionSelectByTicket(ft);
   double P = PositionGetDouble(POSITION_PRICE_OPEN);
   long type = PositionGetInteger(POSITION_TYPE);
   double zw = LebarZona;
   double tpd = JarakTP;
   // Prioritas: Global Variable (nilai asli siklus)
   if(GlobalVariableCheck(g_gvZW)
      && GlobalVariableCheck(g_gvTP))
   {
      zw = GlobalVariableGet(g_gvZW);
      tpd = GlobalVariableGet(g_gvTP);
      Print("Restore: zona/TP dari global variable");
   }
   else if(ZonaBerbasisATR)
   {
      // GV hilang -> hitung ulang dari ATR (perkiraan)
      double a = GetATR();
      if(a > 0)
      {
         zw = a * PengaliZonaATR;
         tpd = a * PengaliTPATR;
      }
      Print("Restore: zona ATR dihitung ulang");
   }
   SetZone(type, P, zw, tpd);
   g_level = n - 1;
   PrintFormat("Restore: %d posisi, level %d, "
               "Zona %.2f-%.2f, TP %.2f/%.2f",
               n, g_level, g_zoneLower, g_zoneUpper,
               g_tpUpper, g_tpLower);
}

// Hapus pending awal yang kedaluwarsa
// (cadangan manual, juga jalan di tester)
void CheckInitialExpiry()
{
   if(ExpirasiPendingAwal <= 0) return;
   datetime now = TimeCurrent();
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!ord.SelectByIndex(i)) continue;
      if(ord.Magic() != MagicNumber) continue;
      if(ord.Symbol() != _Symbol) continue;
      if(now - ord.TimeSetup() >= ExpirasiPendingAwal * 60)
      {
         PrintFormat("Pending awal #%I64u kedaluwarsa",
                     ord.Ticket());
         trade.OrderDelete(ord.Ticket());
      }
   }
}

// Entry awal: Buy Stop + Sell Stop
void TryInitialEntry()
{
   // Filter jam
   if(!InTimeWindow())
   {
      g_lastMsg = "Di luar jendela waktu";
      return;
   }
   // Filter spread
   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spread > MaxSpreadPoint)
   {
      g_lastMsg = StringFormat("Spread %d > %d, tolak",
                               spread, MaxSpreadPoint);
      return;
   }
   // Filter ATR
   if(GunakanFilterATR)
   {
      double a = GetATR();
      if(a < ATRMinimum)
      {
         g_lastMsg = StringFormat("ATR %.2f < %.2f, tolak",
                                  a, ATRMinimum);
         return;
      }
   }
   // Jangan coba lagi dalam 10 detik
   if(TimeCurrent() - g_lastTryTime < 10) return;
   g_lastTryTime = TimeCurrent();

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double lot = NormalizeLot(LotAwal);

   bool okBuy = PlaceStop(ORDER_TYPE_BUY_STOP, lot,
                          ask + JarakPendingAwal,
                          "ZR L0", ExpirasiPendingAwal,
                          false);
   bool okSell = PlaceStop(ORDER_TYPE_SELL_STOP, lot,
                           bid - JarakPendingAwal,
                           "ZR L0", ExpirasiPendingAwal,
                           false);
   // Hanya satu yang sukses -> hapus agar simetris
   if(okBuy != okSell)
   {
      Print("Hanya satu pending awal sukses, dihapus");
      DeleteAllPendings();
   }
   else if(okBuy)
      g_lastMsg = "Pending awal terpasang";
}

// Pastikan pending recovery level berikutnya ada
void MaintainRecoveryPending()
{
   ulong ft, lt;
   if(!GetFirstLastPosition(ft, lt)) return;
   if(!PositionSelectByTicket(lt)) return;
   long lastType = PositionGetInteger(POSITION_TYPE);

   int nextLevel = g_level + 1;
   // Arah berlawanan dengan posisi terakhir
   ENUM_ORDER_TYPE wantType;
   if(lastType == POSITION_TYPE_BUY)
      wantType = ORDER_TYPE_SELL_STOP;
   else
      wantType = ORDER_TYPE_BUY_STOP;
   // Di batas seberang
   double wantPrice;
   if(wantType == ORDER_TYPE_BUY_STOP)
      wantPrice = g_zoneUpper;
   else
      wantPrice = g_zoneLower;
   string wantCmt = "ZR L" + IntegerToString(nextLevel);
   double tol = 2.0 * _Point;

   // Boleh tambah level?
   bool allowed = true;
   if(MaxLevel > 0 && nextLevel > MaxLevel)
   {
      allowed = false;
      g_lastMsg = StringFormat("MaxLevel %d tercapai",
                               MaxLevel);
   }
   double lot = LotForLevel(nextLevel);
   if(lot <= 0)
   {
      allowed = false;
      g_lastMsg = StringFormat("Deret lot habis di L%d",
                               nextLevel);
   }

   // Hapus pending yang tidak sesuai,
   // cek apakah pending yang diinginkan sudah ada
   bool exists = false;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!ord.SelectByIndex(i)) continue;
      if(ord.Magic() != MagicNumber) continue;
      if(ord.Symbol() != _Symbol) continue;
      bool match = allowed
                   && ord.OrderType() == wantType
                   && MathAbs(ord.PriceOpen() - wantPrice)
                      <= tol;
      if(match && !exists)
      {
         exists = true;
      }
      else
      {
         PrintFormat("Hapus pending #%I64u (bukan L%d)",
                     ord.Ticket(), nextLevel);
         trade.OrderDelete(ord.Ticket());
      }
   }
   if(!allowed || exists) return;

   // Throttle jika sebelumnya gagal
   if(TimeCurrent() - g_lastTryTime < 10) return;
   g_lastTryTime = TimeCurrent();
   if(PlaceStop(wantType, lot, wantPrice,
                wantCmt, 0, true))
      g_lastMsg = StringFormat("Pending L%d @%.2f",
                               nextLevel, wantPrice);
}

// Mesin utama: tiap tick dan setelah deal baru
void ManageCycle()
{
   int nPos = CountPositions();
   int nPend = CountPendings();
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   // Sedang close-all: ulangi sampai bersih
   if(g_closing)
   {
      if(nPos > 0 || nPend > 0)
      {
         CloseAllAndDelete();
         return;
      }
      PrintFormat("Siklus selesai. Ekuitas %.2f",
                  AccountInfoDouble(ACCOUNT_EQUITY));
      ResetCycle();
      g_lastMsg = "Siklus selesai, menunggu entry";
      nPos = 0;
      nPend = 0;
   }

   // Tidak ada posisi
   if(nPos == 0)
   {
      // Siklus masih dianggap aktif -> ditutup manual
      if(g_cycleActive)
      {
         Print("Posisi hilang -> reset & hapus pending");
         ResetCycle();
         DeleteAllPendings();
         return;
      }
      // Pending awal masih menunggu
      if(nPend > 0)
      {
         CheckInitialExpiry();
         g_lastMsg = "Menunggu pending awal";
         return;
      }
      // Kosong total -> coba entry awal
      TryInitialEntry();
      return;
   }

   // Ada posisi: mulai siklus jika belum
   if(!g_cycleActive) StartCycle();
   g_level = nPos - 1;

   // Cek target -> close-all dari kode
   if(bid >= g_tpUpper || ask <= g_tpLower)
   {
      PrintFormat("TARGET: Bid %.2f Ask %.2f -> close all",
                  bid, ask);
      g_closing = true;
      CloseAllAndDelete();
      return;
   }

   MaintainRecoveryPending();
}

//======================= PANEL CHART ===================

// Panel informasi di kiri atas chart
void UpdateComment()
{
   datetime now = TimeCurrent();
   // Maksimal 1x per detik (kecuali visual tester)
   if(now == g_lastCommentTime
      && !MQLInfoInteger(MQL_VISUAL_MODE))
      return;
   g_lastCommentTime = now;

   double totalLot, floatPL, netLot;
   GetBasketStats(totalLot, floatPL, netLot);
   MqlDateTime wib;
   TimeToStruct(WIBNow(), wib);

   string win;
   if(g_useWindow)
   {
      win = JamMulai + "-" + JamSelesai;
      win += InTimeWindow() ? " (AKTIF)" : " (TUTUP)";
   }
   else
      win = "24 jam";

   string s = "=== ZONE RECOVERY EA | " + _Symbol
              + " | Magic " + IntegerToString(MagicNumber)
              + " ===\n";
   s += "!!! TANPA STOP LOSS & TANPA CUT-LOSS. "
        "RISIKO MARGIN CALL TINGGI !!!\n";
   s += StringFormat("WIB: %02d:%02d | Jendela: %s "
                     "| Spread: %d pt\n",
                     wib.hour, wib.min, win,
                     (int)SymbolInfoInteger(_Symbol,
                                            SYMBOL_SPREAD));
   if(g_cycleActive)
   {
      double nl = LotForLevel(g_level + 1);
      string nlStr = nl > 0 ? DoubleToString(nl, 2) : "-";
      s += StringFormat("Level: %d (lot berikut: %s) "
                        "| Posisi: %d | Pending: %d\n",
                        g_level, nlStr,
                        CountPositions(), CountPendings());
      s += StringFormat("Zona: %.2f - %.2f (lebar %.2f)\n",
                        g_zoneLower, g_zoneUpper,
                        g_zoneWidth);
      s += StringFormat("TP atas: %.2f | TP bawah: %.2f "
                        "(jarak %.2f)\n",
                        g_tpUpper, g_tpLower, g_tpDist);
   }
   else
   {
      s += StringFormat("Level: - | Siklus belum aktif "
                        "| Pending: %d\n",
                        CountPendings());
   }
   s += StringFormat("Total lot: %.2f (net %+.2f) "
                     "| Floating P/L: %.2f\n",
                     totalLot, netLot, floatPL);
   s += StringFormat("Balance: %.2f | Ekuitas: %.2f "
                     "| Free margin: %.2f\n",
                     AccountInfoDouble(ACCOUNT_BALANCE),
                     AccountInfoDouble(ACCOUNT_EQUITY),
                     AccountInfoDouble(ACCOUNT_MARGIN_FREE));
   s += "Status: " + g_lastMsg;
   Comment(s);
}

//======================= EVENTS ========================

// Dipanggil sekali saat EA dipasang
int OnInit()
{
   // Akun harus hedging
   long mm = AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   if(mm != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
   {
      Alert("EA ini memerlukan akun HEDGING.");
      return INIT_FAILED;
   }
   // Parse deret lot
   if(!ParseLots(DeretLot))
   {
      Alert("DeretLot tidak valid: ", DeretLot);
      return INIT_PARAMETERS_INCORRECT;
   }
   // Validasi angka
   if(LotAwal <= 0 || LebarZona <= 0
      || JarakTP < 0 || JarakPendingAwal <= 0)
   {
      Alert("Parameter lot/zona/TP/jarak tidak valid");
      return INIT_PARAMETERS_INCORRECT;
   }

   // Jendela waktu
   g_startMin = ParseHHMM(JamMulai);
   g_endMin = ParseHHMM(JamSelesai);
   g_useWindow = (g_startMin >= 0 && g_endMin >= 0);
   if(!g_useWindow && (JamMulai != "" || JamSelesai != ""))
      Print("Jendela waktu tidak valid -> 24 jam");

   // Indikator ATR jika dibutuhkan
   if(GunakanFilterATR || ZonaBerbasisATR)
   {
      g_atrHandle = iATR(_Symbol, ATRTimeframe, ATRPeriode);
      if(g_atrHandle == INVALID_HANDLE)
      {
         Alert("Gagal membuat handle ATR");
         return INIT_FAILED;
      }
   }

   // Pengaturan CTrade
   trade.SetExpertMagicNumber((ulong)MagicNumber);
   trade.SetDeviationInPoints((ulong)Slippage);
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetAsyncMode(false);
   trade.LogLevel(LOG_LEVEL_ERRORS);

   // Nama Global Variable dan prefix objek
   string base = "ZR_" + _Symbol + "_"
                 + IntegerToString(MagicNumber);
   g_gvZW = base + "_ZW";
   g_gvTP = base + "_TP";
   g_objPrefix = "ZR_" + IntegerToString(MagicNumber) + "_";

   g_lastMsg = "Inisialisasi";
   // Pulihkan state jika ada posisi
   RebuildState();

   PrintFormat("ZoneRecoveryEA siap. %d level, zona %.2f, "
               "TP %.2f, MaxLevel %d",
               ArraySize(g_lots), LebarZona,
               JarakTP, MaxLevel);
   return INIT_SUCCEEDED;
}

// Dipanggil saat EA dilepas
void OnDeinit(const int reason)
{
   if(g_atrHandle != INVALID_HANDLE)
      IndicatorRelease(g_atrHandle);
   DeleteLevels();
   Comment("");
}

// Dipanggil tiap tick harga
void OnTick()
{
   ManageCycle();
   UpdateComment();
}

// Dipanggil tiap ada transaksi di akun.
// Dipakai untuk mendeteksi pending tereksekusi.
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   // Hanya deal baru
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal)) return;
   if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC)
      != MagicNumber) return;
   if(HistoryDealGetString(trans.deal, DEAL_SYMBOL)
      != _Symbol) return;

   // Deal pembukaan posisi = pending tereksekusi
   long entry = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if(entry == DEAL_ENTRY_IN)
   {
      PrintFormat("Deal IN #%I64u lot %.2f @%.2f (%s)",
                  trans.deal,
                  HistoryDealGetDouble(trans.deal, DEAL_VOLUME),
                  HistoryDealGetDouble(trans.deal, DEAL_PRICE),
                  HistoryDealGetString(trans.deal, DEAL_COMMENT));
      // Buka throttle agar pending berikut segera dipasang
      g_lastTryTime = 0;
      ManageCycle();
      UpdateComment();
   }
}
//+----------------------------------------------------+