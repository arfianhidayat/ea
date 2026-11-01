//+------------------------------------------------------------------+
//|                                               ZoneRecoveryEA.mq5 |
//|   Zone Recovery Hedging EA (dirancang untuk XAUUSD, akun hedging)|
//|   PERINGATAN: TANPA STOP LOSS & TANPA CUT-LOSS PER SIKLUS.        |
//+------------------------------------------------------------------+
//
//  ALUR KERJA EA (ringkasan)
//  --------------------------------------------------------------
//  1. MENUNGGU   : Tidak ada posisi/pending EA. Jika jam WIB masuk jendela,
//                  spread OK, dan ATR OK, pasang Buy Stop (+JarakPendingAwal)
//                  dan Sell Stop (-JarakPendingAwal) dengan LotAwal, komentar
//                  "ZR L0". Jika 60 menit tidak tersentuh, keduanya dihapus.
//
//  2. ZONA       : Salah satu stop tereksekusi di harga P -> siklus dimulai.
//                  SELL pertama : batas bawah = P, batas atas = P + LebarZona
//                  BUY  pertama : batas atas  = P, batas bawah = P - LebarZona
//                  TP atas = batas atas + JarakTP, TP bawah = batas bawah - JarakTP.
//                  Pending awal yang tersisa dihapus. Batas disimpan ke
//                  Global Variable agar tahan restart terminal.
//
//  3. RECOVERY   : Posisi terakhir BUY  -> pasang Sell Stop di batas bawah.
//                  Posisi terakhir SELL -> pasang Buy Stop di batas atas.
//                  Lot = DeretLot[level berikutnya]. Setiap pending
//                  tereksekusi, level naik dan pending baru dipasang di sisi
//                  seberang. Posisi lama TIDAK pernah ditutup satu per satu.
//                  Berhenti menambah jika MaxLevel tercapai / deret lot habis.
//
//  4. TARGET     : Tiap tick cek Bid >= TP atas atau Ask <= TP bawah.
//                  Jika ya: hapus semua pending + tutup semua posisi dari kode
//                  (close-all serentak), reset siklus, kembali ke langkah 1.
//
//  5. PEMULIHAN  : Saat EA di-restart, posisi tertua dianggap posisi pertama,
//                  zona/TP/level dihitung ulang dari posisi yang ada dan
//                  Global Variable.
//
//  6. TAMPILAN   : Comment() di pojok kiri atas (level, zona, TP, lot,
//                  floating P/L, ekuitas, status) + garis horizontal zona
//                  (oranye) dan TP (hijau) di chart.
//
//  TIDAK ADA STOP LOSS. Satu siklus hanya berakhir dengan TP, berhenti di
//  MaxLevel/deret habis (menggantung), atau margin call.
//  --------------------------------------------------------------

#property copyright "Zone Recovery EA"                       // info hak cipta di tab properti EA
#property version   "1.01"                                   // versi EA
#property description "Zone Recovery hedging: Buy Stop/Sell Stop awal, pending stop bergantian di batas zona"   // deskripsi baris 1
#property description "dengan deret lot, close-all di TP atas/bawah. TANPA STOP LOSS. Risiko margin call tinggi." // deskripsi baris 2

#include <Trade\Trade.mqh>                                   // library CTrade: kirim order (buy/sell/stop/delete/close)
#include <Trade\PositionInfo.mqh>                            // library CPositionInfo: baca data posisi terbuka
#include <Trade\OrderInfo.mqh>                               // library COrderInfo: baca data pending order

//================================ INPUT =============================
input group "--- Identitas & Lot ---"                        // judul grup parameter di dialog input
input long     MagicNumber          = 20261006;              // nomor unik penanda order milik EA ini
input double   LotAwal              = 0.10;                  // lot untuk pending awal (level 0)
input string   DeretLot             = "0.10,0.30,0.75,1.50,3.00,6.00,12.00"; // lot per level, dipisah koma, index 0 = level 0

input group "--- Zona & Target ---"                          // judul grup
input double   LebarZona            = 3.1;                   // jarak batas atas-bawah zona, dalam harga (USD)
input double   JarakTP              = 5.0;                   // jarak TP di luar batas zona, dalam harga
input int      MaxLevel             = 0;                     // level maksimum; 0 = tanpa batas

input group "--- Jendela Waktu (WIB = UTC+7) ---"            // judul grup
input string   JamMulai             = "19:30";               // jam mulai boleh entry awal (WIB); kosong = 24 jam
input string   JamSelesai           = "20:30";               // jam selesai boleh entry awal (WIB); kosong = 24 jam
input int      OffsetServerGMT_Tester = 2;                   // offset jam server broker ke GMT; hanya dipakai di Strategy Tester

input group "--- Pending Awal ---"                           // judul grup
input double   JarakPendingAwal     = 2.0;                   // jarak Buy Stop/Sell Stop awal dari harga saat ini (harga)
input int      ExpirasiPendingAwal  = 60;                    // masa berlaku pending awal (menit); 0 = tidak expire

input group "--- Filter ATR ---"                             // judul grup
input bool     GunakanFilterATR     = false;                 // true = entry awal hanya jika ATR >= ATRMinimum
input int      ATRPeriode           = 14;                    // periode indikator ATR
input ENUM_TIMEFRAMES ATRTimeframe  = PERIOD_M15;            // timeframe indikator ATR
input double   ATRMinimum           = 2.0;                   // nilai ATR minimum (harga) agar boleh entry

input group "--- Zona Berbasis ATR ---"                      // judul grup
input bool     ZonaBerbasisATR      = false;                 // true = LebarZona & JarakTP dihitung dari ATR saat posisi pertama
input double   PengaliZonaATR       = 1.0;                   // LebarZona = ATR x pengali ini
input double   PengaliTPATR         = 1.5;                   // JarakTP   = ATR x pengali ini

input group "--- Eksekusi ---"                               // judul grup
input int      MaxSpreadPoint       = 50;                    // spread maksimum (point) agar entry awal diizinkan
input int      Slippage             = 30;                    // deviasi harga yang ditoleransi untuk market order (point)

input group "--- Tampilan ---"                               // judul grup
input bool     GambarGaris          = true;                  // gambar garis zona & TP di chart

//================================ GLOBAL ============================
CTrade         trade;                                        // objek pengirim order
CPositionInfo  pos;                                          // objek pembaca posisi
COrderInfo     ord;                                          // objek pembaca pending order

double   g_lots[];                                           // array lot hasil parse DeretLot
int      g_startMin = -1;                                    // jam mulai dalam menit sejak 00:00 WIB (-1 = tidak dipakai)
int      g_endMin   = -1;                                    // jam selesai dalam menit sejak 00:00 WIB
bool     g_useWindow = false;                                // true jika jendela waktu aktif
int      g_atrHandle = INVALID_HANDLE;                       // handle indikator ATR

bool     g_cycleActive = false;                              // true jika siklus zona sedang berjalan
int      g_level       = -1;                                 // level saat ini (-1 = tidak ada posisi, 0 = posisi pertama)
double   g_zoneUpper   = 0.0;                                // batas atas zona
double   g_zoneLower   = 0.0;                                // batas bawah zona
double   g_tpUpper     = 0.0;                                // harga TP atas (close-all)
double   g_tpLower     = 0.0;                                // harga TP bawah (close-all)
double   g_zoneWidth   = 0.0;                                // lebar zona yang dipakai siklus ini
double   g_tpDist      = 0.0;                                // jarak TP yang dipakai siklus ini
bool     g_closing     = false;                              // true saat sedang proses close-all
datetime g_lastTryTime = 0;                                  // waktu terakhir mencoba kirim order (throttle)
datetime g_lastCommentTime = 0;                              // waktu terakhir Comment() diperbarui
string   g_gvZW = "";                                        // nama Global Variable penyimpan lebar zona
string   g_gvTP = "";                                        // nama Global Variable penyimpan jarak TP
string   g_lastMsg = "";                                     // pesan status terakhir untuk ditampilkan di chart
string   g_objPrefix = "";                                   // prefix nama objek garis di chart

//================================ UTIL ==============================
//--- normalisasi harga ke jumlah digit simbol
double NormPrice(double p) { return NormalizeDouble(p, _Digits); }   // bulatkan harga sesuai digit simbol

//--- normalisasi lot sesuai step/min/max broker
double NormalizeLot(double lot)
{
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);      // kelipatan lot yang diizinkan (mis. 0.01)
   double mn   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);       // lot minimum
   double mx   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);       // lot maksimum
   if(step > 0) lot = MathFloor(lot / step + 1e-8) * step;           // bulatkan ke bawah ke kelipatan step
   if(lot < mn) lot = mn;                                            // paksa minimal lot min
   if(lot > mx) lot = mx;                                            // paksa maksimal lot max
   int d = 0; double s = step;                                       // hitung jumlah desimal dari step
   while(s < 1.0 && d < 8) { s *= 10.0; d++; }                       // 0.01 -> 2 desimal, 0.1 -> 1 desimal
   return NormalizeDouble(lot, d);                                   // kembalikan lot yang sudah rapi
}

//--- parse string "a,b,c" menjadi array lot
bool ParseLots(string s)
{
   string parts[];                                                   // penampung potongan string
   int n = StringSplit(s, ',', parts);                               // pecah berdasarkan koma
   ArrayResize(g_lots, 0);                                           // kosongkan array lot
   for(int i = 0; i < n; i++)                                        // loop tiap potongan
   {
      string p = parts[i];                                           // ambil potongan
      StringTrimLeft(p); StringTrimRight(p);                         // buang spasi kiri-kanan
      if(p == "") continue;                                          // lewati jika kosong
      double v = StringToDouble(p);                                  // ubah ke angka
      if(v <= 0) continue;                                           // lewati jika tidak valid
      int k = ArraySize(g_lots);                                     // ukuran array sekarang
      ArrayResize(g_lots, k + 1);                                    // tambah satu slot
      g_lots[k] = v;                                                 // simpan lot
   }
   return (ArraySize(g_lots) > 0);                                   // sukses jika minimal ada satu lot
}

//--- parse "HH:MM" menjadi menit sejak 00:00, -1 jika tidak valid
int ParseHHMM(string s)
{
   StringTrimLeft(s); StringTrimRight(s);                            // buang spasi
   if(s == "") return -1;                                            // kosong = tidak dipakai
   string p[];                                                       // penampung HH dan MM
   if(StringSplit(s, ':', p) < 2) return -1;                         // harus ada titik dua
   int h = (int)StringToInteger(p[0]);                               // jam
   int m = (int)StringToInteger(p[1]);                               // menit
   if(h < 0 || h > 23 || m < 0 || m > 59) return -1;                 // validasi rentang
   return h * 60 + m;                                                // konversi ke menit
}

//--- waktu WIB (UTC+7) saat ini, dikonversi otomatis dari waktu server
datetime WIBNow()
{
   datetime gmt;                                                     // waktu GMT
   if(MQLInfoInteger(MQL_TESTER))                                    // jika berjalan di Strategy Tester
      gmt = TimeCurrent() - (datetime)(OffsetServerGMT_Tester * 3600); // tester tidak tahu offset -> pakai input
   else                                                              // jika live/demo
      gmt = TimeGMT();                                               // terminal tahu GMT sebenarnya
   return gmt + 7 * 3600;                                            // GMT + 7 jam = WIB
}

//--- cek apakah waktu sekarang di dalam jendela entry
bool InTimeWindow()
{
   if(!g_useWindow) return true;                                     // jendela tidak dipakai = selalu boleh
   MqlDateTime dt;                                                   // struktur tanggal-waktu
   TimeToStruct(WIBNow(), dt);                                       // pecah waktu WIB ke jam/menit
   int cur = dt.hour * 60 + dt.min;                                  // menit sekarang sejak 00:00
   if(g_startMin <= g_endMin) return (cur >= g_startMin && cur <= g_endMin); // jendela normal, mis. 19:30-20:30
   return (cur >= g_startMin || cur <= g_endMin);                    // jendela lewat tengah malam, mis. 23:00-02:00
}

//--- nilai ATR bar terakhir yang sudah tutup (dalam harga)
double GetATR()
{
   if(g_atrHandle == INVALID_HANDLE) return 0.0;                     // ATR tidak dibuat
   double b[];                                                       // buffer nilai
   if(CopyBuffer(g_atrHandle, 0, 1, 1, b) < 1) return 0.0;           // ambil 1 nilai dari bar index 1 (sudah tutup)
   return b[0];                                                      // kembalikan ATR
}

//--- apakah broker mendukung expiration dengan waktu tertentu
bool ExpirationSupported()
{
   long mode = SymbolInfoInteger(_Symbol, SYMBOL_EXPIRATION_MODE);   // ambil flag mode expiration simbol
   return ((mode & SYMBOL_EXPIRATION_SPECIFIED) != 0);               // cek bit ORDER_TIME_SPECIFIED
}

//--- cek apakah free margin cukup untuk order
bool CheckMargin(ENUM_ORDER_TYPE type, double lot, double price)
{
   double margin = 0.0;                                              // margin yang dibutuhkan
   if(!OrderCalcMargin(type, _Symbol, lot, price, margin))           // hitung margin
   {
      PrintFormat("OrderCalcMargin gagal, err=%d", GetLastError());  // log kegagalan hitung
      return false;                                                  // anggap tidak cukup
   }
   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);       // free margin akun
   if(margin > freeMargin)                                           // tidak cukup
   {
      PrintFormat("MARGIN TIDAK CUKUP: butuh %.2f, free margin %.2f (lot %.2f, tipe %s)",
                  margin, freeMargin, lot, EnumToString(type));      // log ke Journal/Experts
      g_lastMsg = StringFormat("Margin tidak cukup utk lot %.2f (butuh %.2f, free %.2f)", lot, margin, freeMargin); // tampilkan di chart
      return false;                                                  // tolak order
   }
   return true;                                                      // margin cukup
}

//--- lot untuk level tertentu; -1 jika deret sudah habis
double LotForLevel(int level)
{
   if(level == 0) return LotAwal;                                    // level 0 memakai LotAwal
   if(level < ArraySize(g_lots)) return g_lots[level];               // level n memakai DeretLot[n]
   return -1.0;                                                      // deret habis
}

//================================ SCAN ==============================
//--- hitung jumlah posisi terbuka milik EA
int CountPositions()
{
   int c = 0;                                                        // penghitung
   for(int i = PositionsTotal() - 1; i >= 0; i--)                    // loop semua posisi di akun
      if(pos.SelectByIndex(i) && pos.Magic() == MagicNumber && pos.Symbol() == _Symbol) c++; // cocok magic & simbol
   return c;                                                         // kembalikan jumlah
}

//--- hitung jumlah pending order milik EA
int CountPendings()
{
   int c = 0;                                                        // penghitung
   for(int i = OrdersTotal() - 1; i >= 0; i--)                       // loop semua pending di akun
      if(ord.SelectByIndex(i) && ord.Magic() == MagicNumber && ord.Symbol() == _Symbol) c++; // cocok magic & simbol
   return c;                                                         // kembalikan jumlah
}

//--- cari tiket posisi tertua (pertama) dan terbaru (terakhir) milik EA
bool GetFirstLastPosition(ulong &firstTicket, ulong &lastTicket)
{
   firstTicket = 0; lastTicket = 0;                                  // reset hasil
   long tFirst = 0, tLast = 0;                                       // waktu buka tertua & terbaru (ms)
   for(int i = PositionsTotal() - 1; i >= 0; i--)                    // loop semua posisi
   {
      if(!pos.SelectByIndex(i)) continue;                            // gagal pilih -> lewati
      if(pos.Magic() != MagicNumber || pos.Symbol() != _Symbol) continue; // bukan milik EA -> lewati
      long t = pos.TimeMsc();                                        // waktu buka dalam milidetik
      ulong tk = pos.Ticket();                                       // tiket posisi
      if(firstTicket == 0 || t < tFirst || (t == tFirst && tk < firstTicket)) { tFirst = t; firstTicket = tk; } // lebih tua
      if(lastTicket  == 0 || t > tLast  || (t == tLast  && tk > lastTicket))  { tLast  = t; lastTicket  = tk; } // lebih baru
   }
   return (firstTicket != 0);                                        // true jika ada posisi
}

//--- total lot, floating P/L, dan net lot posisi EA
void GetBasketStats(double &totalLot, double &floatPL, double &netLot)
{
   totalLot = 0; floatPL = 0; netLot = 0;                            // reset
   for(int i = PositionsTotal() - 1; i >= 0; i--)                    // loop semua posisi
   {
      if(!pos.SelectByIndex(i)) continue;                            // gagal pilih -> lewati
      if(pos.Magic() != MagicNumber || pos.Symbol() != _Symbol) continue; // bukan milik EA
      totalLot += pos.Volume();                                      // jumlahkan lot
      netLot   += (pos.PositionType() == POSITION_TYPE_BUY ? pos.Volume() : -pos.Volume()); // buy positif, sell negatif
      floatPL  += pos.Profit() + pos.Swap() + pos.Commission();      // P/L termasuk swap & komisi
   }
}

//================================ ORDER =============================
//--- hapus semua pending order milik EA
void DeleteAllPendings()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)                       // loop dari belakang (aman saat menghapus)
   {
      if(!ord.SelectByIndex(i)) continue;                            // gagal pilih -> lewati
      if(ord.Magic() != MagicNumber || ord.Symbol() != _Symbol) continue; // bukan milik EA
      if(!trade.OrderDelete(ord.Ticket()))                           // kirim perintah hapus
         PrintFormat("Gagal hapus pending #%I64u retcode=%d", ord.Ticket(), trade.ResultRetcode()); // log jika gagal
   }
}

//--- tutup semua posisi milik EA
void CloseAllPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)                    // loop dari belakang
   {
      if(!pos.SelectByIndex(i)) continue;                            // gagal pilih -> lewati
      if(pos.Magic() != MagicNumber || pos.Symbol() != _Symbol) continue; // bukan milik EA
      if(!trade.PositionClose(pos.Ticket()))                         // tutup posisi di harga pasar
         PrintFormat("Gagal close posisi #%I64u retcode=%d", pos.Ticket(), trade.ResultRetcode()); // log jika gagal
   }
}

//--- hapus pending lalu tutup posisi
void CloseAllAndDelete()
{
   DeleteAllPendings();                                              // pending dulu agar tidak tereksekusi saat closing
   CloseAllPositions();                                              // lalu tutup semua posisi
}

//--- pasang pending stop; jika harga sudah terlewati dan allowMarket=true, pakai market order
bool PlaceStop(ENUM_ORDER_TYPE type, double lot, double price, string cmt, int expMin, bool allowMarket)
{
   lot   = NormalizeLot(lot);                                        // rapikan lot
   price = NormPrice(price);                                         // rapikan harga
   double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);             // harga ask sekarang
   double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);             // harga bid sekarang
   double stops = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point; // jarak minimum stop dari harga

   ENUM_ORDER_TYPE_TIME tt = ORDER_TIME_GTC;                         // default: berlaku sampai dibatalkan
   datetime exp = 0;                                                 // waktu expire
   if(expMin > 0 && ExpirationSupported())                           // jika minta expire dan broker mendukung
   {
      tt  = ORDER_TIME_SPECIFIED;                                    // tipe waktu: sampai waktu tertentu
      exp = TimeCurrent() + (datetime)(expMin * 60);                 // waktu expire = sekarang + menit
   }

   bool ok = false;                                                  // hasil pengiriman
   if(type == ORDER_TYPE_BUY_STOP)                                   // ---- BUY STOP ----
   {
      if(price <= ask + stops)                                       // harga stop terlalu dekat/sudah terlewati
      {
         if(!allowMarket) price = NormPrice(ask + stops + _Point);   // pending awal: geser harga agar valid
         else                                                        // recovery: langsung market buy
         {
            if(!CheckMargin(ORDER_TYPE_BUY, lot, ask)) return false; // cek margin
            ok = trade.Buy(lot, _Symbol, 0.0, 0.0, 0.0, cmt);        // market buy tanpa SL/TP
            PrintFormat("%s BUY MARKET (harga stop %.2f sudah terlewati) lot %.2f retcode=%d",
                        cmt, price, lot, trade.ResultRetcode());     // log
            return ok;                                               // selesai
         }
      }
      if(!CheckMargin(ORDER_TYPE_BUY_STOP, lot, price)) return false; // cek margin
      ok = trade.BuyStop(lot, price, _Symbol, 0.0, 0.0, tt, exp, cmt); // kirim Buy Stop tanpa SL/TP
      PrintFormat("%s BUY STOP @%.2f lot %.2f -> %s (retcode=%d)", cmt, price, lot, ok ? "OK" : "GAGAL", trade.ResultRetcode()); // log
   }
   else if(type == ORDER_TYPE_SELL_STOP)                             // ---- SELL STOP ----
   {
      if(price >= bid - stops)                                       // harga stop terlalu dekat/sudah terlewati
      {
         if(!allowMarket) price = NormPrice(bid - stops - _Point);   // pending awal: geser harga agar valid
         else                                                        // recovery: langsung market sell
         {
            if(!CheckMargin(ORDER_TYPE_SELL, lot, bid)) return false; // cek margin
            ok = trade.Sell(lot, _Symbol, 0.0, 0.0, 0.0, cmt);       // market sell tanpa SL/TP
            PrintFormat("%s SELL MARKET (harga stop %.2f sudah terlewati) lot %.2f retcode=%d",
                        cmt, price, lot, trade.ResultRetcode());     // log
            return ok;                                               // selesai
         }
      }
      if(!CheckMargin(ORDER_TYPE_SELL_STOP, lot, price)) return false; // cek margin
      ok = trade.SellStop(lot, price, _Symbol, 0.0, 0.0, tt, exp, cmt); // kirim Sell Stop tanpa SL/TP
      PrintFormat("%s SELL STOP @%.2f lot %.2f -> %s (retcode=%d)", cmt, price, lot, ok ? "OK" : "GAGAL", trade.ResultRetcode()); // log
   }
   return ok;                                                        // kembalikan hasil
}

//================================ TAMPILAN GARIS ====================
//--- buat/perbarui satu garis horizontal
void DrawHLine(string name, double price, color clr, int style, string text)
{
   if(ObjectFind(0, name) < 0)                                       // jika objek belum ada
   {
      ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);                 // buat garis horizontal
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);          // tidak bisa diklik/digeser
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);               // sembunyikan dari daftar objek
   }
   ObjectSetDouble (0, name, OBJPROP_PRICE, price);                  // set harga garis
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);                    // warna
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);                  // gaya garis (solid/dash)
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);                      // tebal garis
   ObjectSetString (0, name, OBJPROP_TEXT, text);                    // tooltip/label
}

//--- gambar garis zona dan TP
void DrawLevels()
{
   if(!GambarGaris) return;                                          // fitur dimatikan
   if(!g_cycleActive) { DeleteLevels(); return; }                    // tidak ada siklus -> bersihkan
   DrawHLine(g_objPrefix + "ZoneUp",  g_zoneUpper, clrOrange,     STYLE_DASH,  "Batas atas zona");  // batas atas
   DrawHLine(g_objPrefix + "ZoneLow", g_zoneLower, clrOrange,     STYLE_DASH,  "Batas bawah zona"); // batas bawah
   DrawHLine(g_objPrefix + "TPUp",    g_tpUpper,   clrLimeGreen,  STYLE_SOLID, "TP atas (close all)");  // TP atas
   DrawHLine(g_objPrefix + "TPLow",   g_tpLower,   clrLimeGreen,  STYLE_SOLID, "TP bawah (close all)"); // TP bawah
}

//--- hapus semua garis milik EA
void DeleteLevels()
{
   ObjectsDeleteAll(0, g_objPrefix);                                 // hapus objek yang namanya berawalan prefix EA
}

//================================ SIKLUS ============================
//--- tetapkan batas zona & TP dari posisi pertama
void SetZone(long firstType, double P, double zw, double tpd)
{
   g_zoneWidth = zw;                                                 // simpan lebar zona
   g_tpDist    = tpd;                                                // simpan jarak TP
   if(firstType == POSITION_TYPE_SELL)                               // posisi pertama SELL
   {
      g_zoneLower = NormPrice(P);                                    // batas bawah = harga sell
      g_zoneUpper = NormPrice(P + zw);                               // batas atas = harga sell + lebar
   }
   else                                                              // posisi pertama BUY
   {
      g_zoneUpper = NormPrice(P);                                    // batas atas = harga buy
      g_zoneLower = NormPrice(P - zw);                               // batas bawah = harga buy - lebar
   }
   g_tpUpper = NormPrice(g_zoneUpper + tpd);                         // TP atas di luar zona
   g_tpLower = NormPrice(g_zoneLower - tpd);                         // TP bawah di luar zona
   g_cycleActive = true;                                             // tandai siklus aktif
   GlobalVariableSet(g_gvZW, zw);                                    // simpan lebar zona (tahan restart)
   GlobalVariableSet(g_gvTP, tpd);                                   // simpan jarak TP (tahan restart)
   DrawLevels();                                                     // gambar garis di chart
}

//--- reset semua state siklus
void ResetCycle()
{
   g_cycleActive = false;                                            // siklus tidak aktif
   g_level = -1;                                                     // tidak ada level
   g_zoneUpper = g_zoneLower = g_tpUpper = g_tpLower = 0.0;          // kosongkan harga
   g_zoneWidth = g_tpDist = 0.0;                                     // kosongkan lebar/jarak
   g_closing = false;                                                // tidak sedang closing
   if(GlobalVariableCheck(g_gvZW)) GlobalVariableDel(g_gvZW);        // hapus GV lebar zona
   if(GlobalVariableCheck(g_gvTP)) GlobalVariableDel(g_gvTP);        // hapus GV jarak TP
   DeleteLevels();                                                   // hapus garis di chart
}

//--- mulai siklus baru saat posisi pertama terdeteksi
void StartCycle()
{
   ulong ft, lt;                                                     // tiket pertama & terakhir
   if(!GetFirstLastPosition(ft, lt)) return;                         // tidak ada posisi -> keluar
   if(!PositionSelectByTicket(ft)) return;                           // pilih posisi pertama
   double P     = PositionGetDouble(POSITION_PRICE_OPEN);            // harga buka posisi pertama
   long   type  = PositionGetInteger(POSITION_TYPE);                 // arah posisi pertama
   double zw = LebarZona, tpd = JarakTP;                             // default dari input
   if(ZonaBerbasisATR)                                               // jika zona berbasis ATR
   {
      double a = GetATR();                                           // ambil ATR
      if(a > 0) { zw = a * PengaliZonaATR; tpd = a * PengaliTPATR; } // hitung zona & TP dari ATR
      else Print("ATR tidak tersedia, memakai LebarZona/JarakTP input"); // fallback
   }
   SetZone(type, P, zw, tpd);                                        // tetapkan zona
   g_level = 0;                                                      // level 0
   PrintFormat("SIKLUS BARU: posisi pertama %s @%.2f | Zona %.2f - %.2f | TP atas %.2f / bawah %.2f",
               type == POSITION_TYPE_BUY ? "BUY" : "SELL", P, g_zoneLower, g_zoneUpper, g_tpUpper, g_tpLower); // log
}

//--- pulihkan state setelah restart dari posisi/pending yang ada
void RebuildState()
{
   int n = CountPositions();                                         // jumlah posisi EA
   if(n == 0)                                                        // tidak ada posisi
   {
      g_cycleActive = false;                                         // siklus tidak aktif
      g_level = -1;                                                  // tidak ada level
      PrintFormat("Restore: tidak ada posisi EA, pending EA = %d", CountPendings()); // log
      return;                                                        // selesai
   }
   ulong ft, lt;                                                     // tiket pertama & terakhir
   GetFirstLastPosition(ft, lt);                                     // cari
   PositionSelectByTicket(ft);                                       // pilih posisi pertama
   double P    = PositionGetDouble(POSITION_PRICE_OPEN);             // harga buka
   long   type = PositionGetInteger(POSITION_TYPE);                  // arah
   double zw = LebarZona, tpd = JarakTP;                             // default dari input
   if(GlobalVariableCheck(g_gvZW) && GlobalVariableCheck(g_gvTP))    // jika GV tersimpan
   {
      zw  = GlobalVariableGet(g_gvZW);                               // baca lebar zona asli
      tpd = GlobalVariableGet(g_gvTP);                               // baca jarak TP asli
      Print("Restore: lebar zona/TP dibaca dari global variable");   // log
   }
   else if(ZonaBerbasisATR)                                          // GV hilang tapi mode ATR
   {
      double a = GetATR();                                           // ATR sekarang
      if(a > 0) { zw = a * PengaliZonaATR; tpd = a * PengaliTPATR; } // hitung ulang (perkiraan)
      Print("Restore: zona ATR dihitung ulang dari ATR saat ini (nilai asli hilang)"); // log
   }
   SetZone(type, P, zw, tpd);                                        // bangun zona
   g_level = n - 1;                                                  // level = jumlah posisi - 1
   PrintFormat("Restore: %d posisi, level %d, posisi pertama %s @%.2f, Zona %.2f-%.2f, TP %.2f/%.2f",
               n, g_level, type == POSITION_TYPE_BUY ? "BUY" : "SELL", P, g_zoneLower, g_zoneUpper, g_tpUpper, g_tpLower); // log
}

//--- hapus pending awal yang kedaluwarsa (cadangan manual, juga bekerja di tester)
void CheckInitialExpiry()
{
   if(ExpirasiPendingAwal <= 0) return;                              // expire tidak dipakai
   datetime now = TimeCurrent();                                     // waktu server sekarang
   for(int i = OrdersTotal() - 1; i >= 0; i--)                       // loop pending
   {
      if(!ord.SelectByIndex(i)) continue;                            // gagal pilih
      if(ord.Magic() != MagicNumber || ord.Symbol() != _Symbol) continue; // bukan milik EA
      if(now - ord.TimeSetup() >= ExpirasiPendingAwal * 60)          // umur pending >= batas
      {
         PrintFormat("Pending awal #%I64u kedaluwarsa, dihapus", ord.Ticket()); // log
         trade.OrderDelete(ord.Ticket());                            // hapus
      }
   }
}

//--- entry awal: pasang Buy Stop + Sell Stop
void TryInitialEntry()
{
   if(!InTimeWindow()) { g_lastMsg = "Di luar jendela waktu"; return; } // cek jam
   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);          // spread sekarang (point)
   if(spread > MaxSpreadPoint) { g_lastMsg = StringFormat("Spread %d > max %d, entry ditolak", spread, MaxSpreadPoint); return; } // cek spread
   if(GunakanFilterATR)                                              // cek filter ATR
   {
      double a = GetATR();                                           // ATR sekarang
      if(a < ATRMinimum) { g_lastMsg = StringFormat("ATR %.2f < min %.2f, entry ditolak", a, ATRMinimum); return; } // ATR terlalu kecil
   }
   if(TimeCurrent() - g_lastTryTime < 10) return;                    // jangan coba lagi dalam 10 detik (hindari spam)
   g_lastTryTime = TimeCurrent();                                    // catat waktu percobaan

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);               // ask
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);               // bid
   double lot = NormalizeLot(LotAwal);                               // lot awal rapi

   bool okBuy  = PlaceStop(ORDER_TYPE_BUY_STOP,  lot, ask + JarakPendingAwal, "ZR L0", ExpirasiPendingAwal, false); // Buy Stop di atas
   bool okSell = PlaceStop(ORDER_TYPE_SELL_STOP, lot, bid - JarakPendingAwal, "ZR L0", ExpirasiPendingAwal, false); // Sell Stop di bawah
   if(okBuy != okSell)                                               // hanya satu yang berhasil
   {
      Print("Hanya satu pending awal berhasil, keduanya dihapus agar simetris"); // log
      DeleteAllPendings();                                           // hapus supaya tidak berat sebelah
   }
   else if(okBuy) g_lastMsg = "Pending awal terpasang";              // keduanya sukses
}

//--- pastikan pending recovery level berikutnya ada di batas seberang
void MaintainRecoveryPending()
{
   ulong ft, lt;                                                     // tiket pertama & terakhir
   if(!GetFirstLastPosition(ft, lt)) return;                         // tidak ada posisi
   if(!PositionSelectByTicket(lt)) return;                           // pilih posisi terakhir
   long lastType = PositionGetInteger(POSITION_TYPE);                // arah posisi terakhir

   int nextLevel = g_level + 1;                                      // level berikutnya
   ENUM_ORDER_TYPE wantType  = (lastType == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL_STOP : ORDER_TYPE_BUY_STOP; // arah berlawanan
   double          wantPrice = (wantType == ORDER_TYPE_BUY_STOP) ? g_zoneUpper : g_zoneLower; // di batas seberang
   string          wantCmt   = "ZR L" + IntegerToString(nextLevel);  // komentar "ZR L<level>"
   double          tol       = 2.0 * _Point;                         // toleransi pembandingan harga

   bool allowed = true;                                              // boleh pasang pending?
   if(MaxLevel > 0 && nextLevel > MaxLevel) { allowed = false; g_lastMsg = StringFormat("MaxLevel %d tercapai, tidak tambah level", MaxLevel); } // batas level
   double lot = LotForLevel(nextLevel);                              // lot level berikutnya
   if(lot <= 0) { allowed = false; g_lastMsg = StringFormat("Deret lot habis di level %d, tidak tambah level", nextLevel); } // deret habis

   bool exists = false;                                              // pending yang diinginkan sudah ada?
   for(int i = OrdersTotal() - 1; i >= 0; i--)                       // loop pending
   {
      if(!ord.SelectByIndex(i)) continue;                            // gagal pilih
      if(ord.Magic() != MagicNumber || ord.Symbol() != _Symbol) continue; // bukan milik EA
      bool match = allowed && ord.OrderType() == wantType && MathAbs(ord.PriceOpen() - wantPrice) <= tol; // cocok tipe & harga
      if(match && !exists) exists = true;                            // pertama yang cocok dipertahankan
      else                                                           // tidak cocok (sisa pending awal / duplikat)
      {
         PrintFormat("Hapus pending #%I64u %s @%.2f (tidak sesuai level %d)", ord.Ticket(), EnumToString(ord.OrderType()), ord.PriceOpen(), nextLevel); // log
         trade.OrderDelete(ord.Ticket());                            // hapus
      }
   }
   if(!allowed || exists) return;                                    // tidak perlu pasang

   if(TimeCurrent() - g_lastTryTime < 10) return;                    // throttle jika sebelumnya gagal
   g_lastTryTime = TimeCurrent();                                    // catat waktu percobaan
   if(PlaceStop(wantType, lot, wantPrice, wantCmt, 0, true))         // pasang pending (atau market jika terlewati)
      g_lastMsg = StringFormat("Pending level %d terpasang @%.2f", nextLevel, wantPrice); // status
}

//--- mesin utama: dipanggil tiap tick dan setelah deal baru
void ManageCycle()
{
   int nPos  = CountPositions();                                     // jumlah posisi EA
   int nPend = CountPendings();                                      // jumlah pending EA
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);               // bid
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);               // ask

   if(g_closing)                                                     // sedang close-all
   {
      if(nPos > 0 || nPend > 0) { CloseAllAndDelete(); return; }     // masih ada sisa -> ulangi close
      PrintFormat("Siklus selesai. Ekuitas %.2f", AccountInfoDouble(ACCOUNT_EQUITY)); // log
      ResetCycle();                                                  // bersih -> reset
      g_lastMsg = "Siklus selesai, menunggu entry baru";             // status
      nPos = 0; nPend = 0;                                           // sinkronkan variabel lokal
   }

   if(nPos == 0)                                                     // tidak ada posisi
   {
      if(g_cycleActive)                                              // tapi siklus masih dianggap aktif
      {
         Print("Semua posisi hilang (ditutup manual?) -> reset siklus & hapus pending"); // log
         ResetCycle();                                               // reset
         DeleteAllPendings();                                        // bersihkan pending
         return;                                                     // selesai tick ini
      }
      if(nPend > 0) { CheckInitialExpiry(); g_lastMsg = "Menunggu pending awal tereksekusi"; return; } // pending awal menunggu
      TryInitialEntry();                                             // tidak ada apa-apa -> coba entry awal
      return;                                                        // selesai
   }

   if(!g_cycleActive) StartCycle();                                  // posisi pertama baru muncul -> mulai siklus
   g_level = nPos - 1;                                               // level = jumlah posisi - 1

   if(bid >= g_tpUpper || ask <= g_tpLower)                          // target tercapai?
   {
      PrintFormat("TARGET TERCAPAI (Bid %.2f / Ask %.2f, TP atas %.2f / bawah %.2f) -> close all", bid, ask, g_tpUpper, g_tpLower); // log
      g_closing = true;                                              // masuk mode closing
      CloseAllAndDelete();                                           // tutup semua
      return;                                                        // selesai
   }

   MaintainRecoveryPending();                                        // jaga pending recovery
}

//================================ COMMENT ===========================
//--- tampilkan panel informasi di pojok kiri atas chart
void UpdateComment()
{
   datetime now = TimeCurrent();                                     // waktu sekarang
   if(now == g_lastCommentTime && !MQLInfoInteger(MQL_VISUAL_MODE)) return; // maksimal 1x per detik (kecuali visual tester)
   g_lastCommentTime = now;                                          // catat

   double totalLot, floatPL, netLot;                                 // statistik keranjang
   GetBasketStats(totalLot, floatPL, netLot);                        // hitung
   MqlDateTime wib; TimeToStruct(WIBNow(), wib);                     // waktu WIB

   string s = "=== ZONE RECOVERY EA | " + _Symbol + " | Magic " + IntegerToString(MagicNumber) + " ===\n"; // judul
   s += "!!! PERINGATAN: TANPA STOP LOSS & TANPA CUT-LOSS PER SIKLUS. RISIKO MARGIN CALL TINGGI !!!\n";     // peringatan
   s += StringFormat("WIB: %02d:%02d | Jendela: %s | Spread: %d pt\n", wib.hour, wib.min,
                     g_useWindow ? (JamMulai + "-" + JamSelesai + (InTimeWindow() ? " (AKTIF)" : " (TUTUP)")) : "24 jam",
                     (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD)); // jam, jendela, spread
   if(g_cycleActive)                                                 // siklus aktif
   {
      s += StringFormat("Level: %d (lot berikut: %s) | Posisi: %d | Pending: %d\n", g_level,
                        LotForLevel(g_level + 1) > 0 ? DoubleToString(LotForLevel(g_level + 1), 2) : "-",
                        CountPositions(), CountPendings());          // level, lot berikut, jumlah posisi/pending
      s += StringFormat("Zona: %.2f - %.2f (lebar %.2f)\n", g_zoneLower, g_zoneUpper, g_zoneWidth); // batas zona
      s += StringFormat("TP atas: %.2f | TP bawah: %.2f (jarak %.2f)\n", g_tpUpper, g_tpLower, g_tpDist); // TP
   }
   else                                                              // siklus belum aktif
      s += StringFormat("Level: - | Siklus belum aktif | Pending: %d\n", CountPendings()); // info pending awal
   s += StringFormat("Total lot: %.2f (net %+.2f) | Floating P/L: %.2f\n", totalLot, netLot, floatPL); // lot & P/L
   s += StringFormat("Balance: %.2f | Ekuitas: %.2f | Free margin: %.2f\n",
                     AccountInfoDouble(ACCOUNT_BALANCE), AccountInfoDouble(ACCOUNT_EQUITY), AccountInfoDouble(ACCOUNT_MARGIN_FREE)); // akun
   s += "Status: " + g_lastMsg;                                      // pesan status terakhir
   Comment(s);                                                       // tampilkan di chart
}

//================================ EVENTS ============================
//--- dipanggil sekali saat EA dipasang / parameter diubah
int OnInit()
{
   if((ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING) // cek tipe akun
   {
      Alert("EA ini memerlukan akun bertipe HEDGING. Mode akun saat ini bukan hedging."); // peringatan popup
      return INIT_FAILED;                                            // EA tidak jalan
   }
   if(!ParseLots(DeretLot))                                          // parse deret lot
   {
      Alert("DeretLot tidak valid: ", DeretLot);                     // popup
      return INIT_PARAMETERS_INCORRECT;                              // gagal
   }
   if(LotAwal <= 0 || LebarZona <= 0 || JarakTP < 0 || JarakPendingAwal <= 0) // validasi angka
   {
      Alert("Parameter lot/zona/TP/jarak pending tidak valid");      // popup
      return INIT_PARAMETERS_INCORRECT;                              // gagal
   }

   g_startMin = ParseHHMM(JamMulai);                                 // parse jam mulai
   g_endMin   = ParseHHMM(JamSelesai);                               // parse jam selesai
   g_useWindow = (g_startMin >= 0 && g_endMin >= 0);                 // jendela aktif jika keduanya valid
   if(!g_useWindow && (JamMulai != "" || JamSelesai != ""))          // salah satu diisi tapi tidak valid
      Print("Jendela waktu tidak valid/tidak lengkap -> EA aktif 24 jam"); // log

   if(GunakanFilterATR || ZonaBerbasisATR)                           // butuh ATR?
   {
      g_atrHandle = iATR(_Symbol, ATRTimeframe, ATRPeriode);         // buat indikator ATR
      if(g_atrHandle == INVALID_HANDLE)                              // gagal
      {
         Alert("Gagal membuat handle ATR");                          // popup
         return INIT_FAILED;                                         // gagal
      }
   }

   trade.SetExpertMagicNumber((ulong)MagicNumber);                   // semua order pakai magic ini
   trade.SetDeviationInPoints((ulong)Slippage);                      // toleransi slippage
   trade.SetTypeFillingBySymbol(_Symbol);                            // mode filling sesuai broker
   trade.SetAsyncMode(false);                                        // tunggu jawaban server (sinkron)
   trade.LogLevel(LOG_LEVEL_ERRORS);                                 // hanya log error dari CTrade

   g_gvZW = "ZR_" + _Symbol + "_" + IntegerToString(MagicNumber) + "_ZW"; // nama GV lebar zona
   g_gvTP = "ZR_" + _Symbol + "_" + IntegerToString(MagicNumber) + "_TP"; // nama GV jarak TP
   g_objPrefix = "ZR_" + IntegerToString(MagicNumber) + "_";         // prefix nama objek chart

   g_lastMsg = "Inisialisasi";                                       // status awal
   RebuildState();                                                   // pulihkan state jika ada posisi

   PrintFormat("ZoneRecoveryEA siap. Lot: %d level, zona %.2f, TP %.2f, MaxLevel %d, expiration broker %s",
               ArraySize(g_lots), LebarZona, JarakTP, MaxLevel, ExpirationSupported() ? "didukung" : "manual"); // log ringkasan
   return INIT_SUCCEEDED;                                            // sukses
}

//--- dipanggil saat EA dilepas / terminal ditutup
void OnDeinit(const int reason)
{
   if(g_atrHandle != INVALID_HANDLE) IndicatorRelease(g_atrHandle);  // lepaskan indikator ATR
   DeleteLevels();                                                   // hapus garis
   Comment("");                                                      // bersihkan panel teks
}

//--- dipanggil setiap tick harga baru
void OnTick()
{
   ManageCycle();                                                    // jalankan logika utama
   UpdateComment();                                                  // perbarui panel
}

//--- dipanggil setiap ada transaksi (order/deal) di akun: deteksi eksekusi pending secara andal
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;              // hanya tangani deal baru
   if(!HistoryDealSelect(trans.deal)) return;                        // ambil deal dari history
   if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != MagicNumber) return; // bukan milik EA
   if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol) return;     // bukan simbol ini

   ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY); // masuk atau keluar?
   if(entry == DEAL_ENTRY_IN)                                        // deal pembukaan posisi (pending tereksekusi)
   {
      PrintFormat("Deal IN #%I64u %s lot %.2f @%.2f (%s)", trans.deal,
                  HistoryDealGetInteger(trans.deal, DEAL_TYPE) == DEAL_TYPE_BUY ? "BUY" : "SELL",
                  HistoryDealGetDouble(trans.deal, DEAL_VOLUME),
                  HistoryDealGetDouble(trans.deal, DEAL_PRICE),
                  HistoryDealGetString(trans.deal, DEAL_COMMENT));   // log detail deal
      g_lastTryTime = 0;                                             // hapus throttle agar pending berikut langsung dipasang
      ManageCycle();                                                 // proses segera: hapus pending lawan, pasang level berikut
      UpdateComment();                                               // perbarui panel
   }
}
//+------------------------------------------------------------------+