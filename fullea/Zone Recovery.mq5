//+------------------------------------------------------------------+
//|                                               ZoneRecoveryEA.mq5 |
//|   Zone Recovery Hedging EA (dirancang untuk XAUUSD, akun hedging)|
//|   PERINGATAN: TANPA STOP LOSS & TANPA CUT-LOSS PER SIKLUS.        |
//+------------------------------------------------------------------+
#property copyright "Zone Recovery EA"
#property version   "1.00"
#property description "Zone Recovery hedging: Buy Stop/Sell Stop awal, pending stop bergantian di batas zona"
#property description "dengan deret lot, close-all di TP atas/bawah. TANPA STOP LOSS. Risiko margin call tinggi."

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>

//================================ INPUT =============================
input group "--- Identitas & Lot ---"
input long     MagicNumber          = 20261006;            // Magic Number
input double   LotAwal              = 0.10;                // Lot awal (level 0)
input string   DeretLot             = "0.10,0.30,0.75,1.50,3.00,6.00,12.00"; // Deret lot per level (index 0 = level 0)

input group "--- Zona & Target ---"
input double   LebarZona            = 3.1;                 // Lebar zona (dalam harga/USD)
input double   JarakTP              = 5.0;                 // Jarak TP di luar batas zona (harga)
input int      MaxLevel             = 0;                   // Max level (0 = tanpa batas)

input group "--- Jendela Waktu (WIB = UTC+7) ---"
input string   JamMulai             = "19:30";             // Jam mulai WIB (kosong = 24 jam)
input string   JamSelesai           = "20:30";             // Jam selesai WIB (kosong = 24 jam)
input int      OffsetServerGMT_Tester = 2;                 // Offset server ke GMT (jam) - HANYA dipakai di Strategy Tester

input group "--- Pending Awal ---"
input double   JarakPendingAwal     = 2.0;                 // Jarak Buy Stop/Sell Stop awal dari harga (harga)
input int      ExpirasiPendingAwal  = 60;                  // Expirasi pending awal (menit, 0 = tidak expire)

input group "--- Filter ATR ---"
input bool     GunakanFilterATR     = false;               // Gunakan filter ATR untuk entry awal
input int      ATRPeriode           = 14;                  // Periode ATR
input ENUM_TIMEFRAMES ATRTimeframe  = PERIOD_M15;          // Timeframe ATR
input double   ATRMinimum           = 2.0;                 // ATR minimum (harga) agar boleh entry

input group "--- Zona Berbasis ATR ---"
input bool     ZonaBerbasisATR      = false;               // Lebar zona & TP dihitung dari ATR
input double   PengaliZonaATR       = 1.0;                 // LebarZona = ATR x pengali
input double   PengaliTPATR         = 1.5;                 // JarakTP = ATR x pengali

input group "--- Eksekusi ---"
input int      MaxSpreadPoint       = 50;                  // Spread maksimum (point) untuk entry awal
input int      Slippage             = 30;                  // Slippage / deviation (point)

//================================ GLOBAL ============================
CTrade         trade;
CPositionInfo  pos;
COrderInfo     ord;

double   g_lots[];                 // deret lot hasil parse
int      g_startMin = -1;          // jendela waktu (menit sejak 00:00 WIB)
int      g_endMin   = -1;
bool     g_useWindow = false;
int      g_atrHandle = INVALID_HANDLE;

bool     g_cycleActive = false;    // siklus zona sedang berjalan
int      g_level       = -1;       // level saat ini (-1 = tidak ada posisi)
double   g_zoneUpper   = 0.0;
double   g_zoneLower   = 0.0;
double   g_tpUpper     = 0.0;
double   g_tpLower     = 0.0;
double   g_zoneWidth   = 0.0;      // lebar zona yang dipakai siklus ini
double   g_tpDist      = 0.0;      // jarak TP yang dipakai siklus ini
bool     g_closing     = false;    // sedang proses close-all
datetime g_lastTryTime = 0;        // throttle percobaan order
datetime g_lastCommentTime = 0;
string   g_gvZW = "";              // nama global variable lebar zona
string   g_gvTP = "";              // nama global variable jarak TP
string   g_lastMsg = "";           // pesan status terakhir untuk Comment

//================================ UTIL ==============================
//--- normalisasi harga
double NormPrice(double p) { return NormalizeDouble(p, _Digits); }

//--- normalisasi lot sesuai step/min/max
double NormalizeLot(double lot)
{
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double mn   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double mx   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(step > 0) lot = MathFloor(lot / step + 1e-8) * step;
   if(lot < mn) lot = mn;
   if(lot > mx) lot = mx;
   int d = 0; double s = step;
   while(s < 1.0 && d < 8) { s *= 10.0; d++; }
   return NormalizeDouble(lot, d);
}

//--- parse deret lot "a,b,c" -> array
bool ParseLots(string s)
{
   string parts[];
   int n = StringSplit(s, ',', parts);
   ArrayResize(g_lots, 0);
   for(int i = 0; i < n; i++)
   {
      string p = parts[i];
      StringTrimLeft(p); StringTrimRight(p);
      if(p == "") continue;
      double v = StringToDouble(p);
      if(v <= 0) continue;
      int k = ArraySize(g_lots);
      ArrayResize(g_lots, k + 1);
      g_lots[k] = v;
   }
   return (ArraySize(g_lots) > 0);
}

//--- parse "HH:MM" -> menit, -1 jika tidak valid
int ParseHHMM(string s)
{
   StringTrimLeft(s); StringTrimRight(s);
   if(s == "") return -1;
   string p[];
   if(StringSplit(s, ':', p) < 2) return -1;
   int h = (int)StringToInteger(p[0]);
   int m = (int)StringToInteger(p[1]);
   if(h < 0 || h > 23 || m < 0 || m > 59) return -1;
   return h * 60 + m;
}

//--- waktu WIB saat ini (UTC+7), dikonversi otomatis dari waktu server
datetime WIBNow()
{
   datetime gmt;
   if(MQLInfoInteger(MQL_TESTER))
      gmt = TimeCurrent() - (datetime)(OffsetServerGMT_Tester * 3600); // tester tidak tahu offset GMT
   else
      gmt = TimeGMT();
   return gmt + 7 * 3600;
}

//--- cek jendela waktu
bool InTimeWindow()
{
   if(!g_useWindow) return true;
   MqlDateTime dt;
   TimeToStruct(WIBNow(), dt);
   int cur = dt.hour * 60 + dt.min;
   if(g_startMin <= g_endMin) return (cur >= g_startMin && cur <= g_endMin);
   return (cur >= g_startMin || cur <= g_endMin); // lewat tengah malam
}

//--- nilai ATR bar terakhir yang sudah tutup (dalam harga)
double GetATR()
{
   if(g_atrHandle == INVALID_HANDLE) return 0.0;
   double b[];
   if(CopyBuffer(g_atrHandle, 0, 1, 1, b) < 1) return 0.0;
   return b[0];
}

//--- apakah broker mendukung expiration ORDER_TIME_SPECIFIED
bool ExpirationSupported()
{
   long mode = SymbolInfoInteger(_Symbol, SYMBOL_EXPIRATION_MODE);
   return ((mode & SYMBOL_EXPIRATION_SPECIFIED) != 0);
}

//--- cek margin cukup
bool CheckMargin(ENUM_ORDER_TYPE type, double lot, double price)
{
   double margin = 0.0;
   if(!OrderCalcMargin(type, _Symbol, lot, price, margin))
   {
      PrintFormat("OrderCalcMargin gagal, err=%d", GetLastError());
      return false;
   }
   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   if(margin > freeMargin)
   {
      PrintFormat("MARGIN TIDAK CUKUP: butuh %.2f, free margin %.2f (lot %.2f, tipe %s)",
                  margin, freeMargin, lot, EnumToString(type));
      g_lastMsg = StringFormat("Margin tidak cukup utk lot %.2f (butuh %.2f, free %.2f)", lot, margin, freeMargin);
      return false;
   }
   return true;
}

//--- lot untuk level tertentu, -1 jika deret habis
double LotForLevel(int level)
{
   if(level == 0) return LotAwal;
   if(level < ArraySize(g_lots)) return g_lots[level];
   return -1.0;
}

//================================ SCAN ==============================
int CountPositions()
{
   int c = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
      if(pos.SelectByIndex(i) && pos.Magic() == MagicNumber && pos.Symbol() == _Symbol) c++;
   return c;
}

int CountPendings()
{
   int c = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
      if(ord.SelectByIndex(i) && ord.Magic() == MagicNumber && ord.Symbol() == _Symbol) c++;
   return c;
}

//--- tiket posisi pertama (tertua) dan terakhir (terbaru) milik EA
bool GetFirstLastPosition(ulong &firstTicket, ulong &lastTicket)
{
   firstTicket = 0; lastTicket = 0;
   long tFirst = 0, tLast = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!pos.SelectByIndex(i)) continue;
      if(pos.Magic() != MagicNumber || pos.Symbol() != _Symbol) continue;
      long t = pos.TimeMsc();
      ulong tk = pos.Ticket();
      if(firstTicket == 0 || t < tFirst || (t == tFirst && tk < firstTicket)) { tFirst = t; firstTicket = tk; }
      if(lastTicket  == 0 || t > tLast  || (t == tLast  && tk > lastTicket))  { tLast  = t; lastTicket  = tk; }
   }
   return (firstTicket != 0);
}

//--- total lot & floating P/L posisi EA
void GetBasketStats(double &totalLot, double &floatPL, double &netLot)
{
   totalLot = 0; floatPL = 0; netLot = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!pos.SelectByIndex(i)) continue;
      if(pos.Magic() != MagicNumber || pos.Symbol() != _Symbol) continue;
      totalLot += pos.Volume();
      netLot   += (pos.PositionType() == POSITION_TYPE_BUY ? pos.Volume() : -pos.Volume());
      floatPL  += pos.Profit() + pos.Swap() + pos.Commission();
   }
}

//================================ ORDER =============================
//--- hapus semua pending EA
void DeleteAllPendings()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!ord.SelectByIndex(i)) continue;
      if(ord.Magic() != MagicNumber || ord.Symbol() != _Symbol) continue;
      if(!trade.OrderDelete(ord.Ticket()))
         PrintFormat("Gagal hapus pending #%I64u retcode=%d", ord.Ticket(), trade.ResultRetcode());
   }
}

//--- tutup semua posisi EA
void CloseAllPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!pos.SelectByIndex(i)) continue;
      if(pos.Magic() != MagicNumber || pos.Symbol() != _Symbol) continue;
      if(!trade.PositionClose(pos.Ticket()))
         PrintFormat("Gagal close posisi #%I64u retcode=%d", pos.Ticket(), trade.ResultRetcode());
   }
}

void CloseAllAndDelete()
{
   DeleteAllPendings();
   CloseAllPositions();
}

//--- pasang pending stop; jika harga sudah terlewati dan allowMarket, pakai market order
bool PlaceStop(ENUM_ORDER_TYPE type, double lot, double price, string cmt, int expMin, bool allowMarket)
{
   lot   = NormalizeLot(lot);
   price = NormPrice(price);
   double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double stops = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;

   ENUM_ORDER_TYPE_TIME tt = ORDER_TIME_GTC;
   datetime exp = 0;
   if(expMin > 0 && ExpirationSupported())
   {
      tt  = ORDER_TIME_SPECIFIED;
      exp = TimeCurrent() + (datetime)(expMin * 60);
   }

   bool ok = false;
   if(type == ORDER_TYPE_BUY_STOP)
   {
      if(price <= ask + stops)
      {
         if(!allowMarket) price = NormPrice(ask + stops + _Point);
         else
         {
            if(!CheckMargin(ORDER_TYPE_BUY, lot, ask)) return false;
            ok = trade.Buy(lot, _Symbol, 0.0, 0.0, 0.0, cmt);
            PrintFormat("%s BUY MARKET (harga stop %.2f sudah terlewati) lot %.2f retcode=%d",
                        cmt, price, lot, trade.ResultRetcode());
            return ok;
         }
      }
      if(!CheckMargin(ORDER_TYPE_BUY_STOP, lot, price)) return false;
      ok = trade.BuyStop(lot, price, _Symbol, 0.0, 0.0, tt, exp, cmt);
      PrintFormat("%s BUY STOP @%.2f lot %.2f -> %s (retcode=%d)", cmt, price, lot, ok ? "OK" : "GAGAL", trade.ResultRetcode());
   }
   else if(type == ORDER_TYPE_SELL_STOP)
   {
      if(price >= bid - stops)
      {
         if(!allowMarket) price = NormPrice(bid - stops - _Point);
         else
         {
            if(!CheckMargin(ORDER_TYPE_SELL, lot, bid)) return false;
            ok = trade.Sell(lot, _Symbol, 0.0, 0.0, 0.0, cmt);
            PrintFormat("%s SELL MARKET (harga stop %.2f sudah terlewati) lot %.2f retcode=%d",
                        cmt, price, lot, trade.ResultRetcode());
            return ok;
         }
      }
      if(!CheckMargin(ORDER_TYPE_SELL_STOP, lot, price)) return false;
      ok = trade.SellStop(lot, price, _Symbol, 0.0, 0.0, tt, exp, cmt);
      PrintFormat("%s SELL STOP @%.2f lot %.2f -> %s (retcode=%d)", cmt, price, lot, ok ? "OK" : "GAGAL", trade.ResultRetcode());
   }
   return ok;
}

//================================ SIKLUS ============================
//--- tetapkan batas zona dari posisi pertama
void SetZone(long firstType, double P, double zw, double tpd)
{
   g_zoneWidth = zw;
   g_tpDist    = tpd;
   if(firstType == POSITION_TYPE_SELL)
   {
      g_zoneLower = NormPrice(P);
      g_zoneUpper = NormPrice(P + zw);
   }
   else
   {
      g_zoneUpper = NormPrice(P);
      g_zoneLower = NormPrice(P - zw);
   }
   g_tpUpper = NormPrice(g_zoneUpper + tpd);
   g_tpLower = NormPrice(g_zoneLower - tpd);
   g_cycleActive = true;
   // simpan agar bisa dipulihkan setelah restart (penting jika zona berbasis ATR)
   GlobalVariableSet(g_gvZW, zw);
   GlobalVariableSet(g_gvTP, tpd);
}

//--- reset state siklus
void ResetCycle()
{
   g_cycleActive = false;
   g_level = -1;
   g_zoneUpper = g_zoneLower = g_tpUpper = g_tpLower = 0.0;
   g_zoneWidth = g_tpDist = 0.0;
   g_closing = false;
   if(GlobalVariableCheck(g_gvZW)) GlobalVariableDel(g_gvZW);
   if(GlobalVariableCheck(g_gvTP)) GlobalVariableDel(g_gvTP);
}

//--- mulai siklus baru saat posisi pertama terdeteksi
void StartCycle()
{
   ulong ft, lt;
   if(!GetFirstLastPosition(ft, lt)) return;
   if(!PositionSelectByTicket(ft)) return;
   double P     = PositionGetDouble(POSITION_PRICE_OPEN);
   long   type  = PositionGetInteger(POSITION_TYPE);
   double zw = LebarZona, tpd = JarakTP;
   if(ZonaBerbasisATR)
   {
      double a = GetATR();
      if(a > 0) { zw = a * PengaliZonaATR; tpd = a * PengaliTPATR; }
      else Print("ATR tidak tersedia, memakai LebarZona/JarakTP input");
   }
   SetZone(type, P, zw, tpd);
   g_level = 0;
   PrintFormat("SIKLUS BARU: posisi pertama %s @%.2f | Zona %.2f - %.2f | TP atas %.2f / bawah %.2f",
               type == POSITION_TYPE_BUY ? "BUY" : "SELL", P, g_zoneLower, g_zoneUpper, g_tpUpper, g_tpLower);
}

//--- pulihkan state setelah restart dari posisi/pending yang ada
void RebuildState()
{
   int n = CountPositions();
   if(n == 0)
   {
      g_cycleActive = false;
      g_level = -1;
      PrintFormat("Restore: tidak ada posisi EA, pending EA = %d", CountPendings());
      return;
   }
   ulong ft, lt;
   GetFirstLastPosition(ft, lt);
   PositionSelectByTicket(ft);
   double P    = PositionGetDouble(POSITION_PRICE_OPEN);
   long   type = PositionGetInteger(POSITION_TYPE);
   double zw = LebarZona, tpd = JarakTP;
   if(GlobalVariableCheck(g_gvZW) && GlobalVariableCheck(g_gvTP))
   {
      zw  = GlobalVariableGet(g_gvZW);
      tpd = GlobalVariableGet(g_gvTP);
      Print("Restore: lebar zona/TP dibaca dari global variable");
   }
   else if(ZonaBerbasisATR)
   {
      double a = GetATR();
      if(a > 0) { zw = a * PengaliZonaATR; tpd = a * PengaliTPATR; }
      Print("Restore: zona ATR dihitung ulang dari ATR saat ini (nilai asli hilang)");
   }
   SetZone(type, P, zw, tpd);
   g_level = n - 1;
   PrintFormat("Restore: %d posisi, level %d, posisi pertama %s @%.2f, Zona %.2f-%.2f, TP %.2f/%.2f",
               n, g_level, type == POSITION_TYPE_BUY ? "BUY" : "SELL", P, g_zoneLower, g_zoneUpper, g_tpUpper, g_tpLower);
}

//--- hapus pending awal yang sudah kedaluwarsa (fallback manual, bekerja juga di tester)
void CheckInitialExpiry()
{
   if(ExpirasiPendingAwal <= 0) return;
   datetime now = TimeCurrent();
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!ord.SelectByIndex(i)) continue;
      if(ord.Magic() != MagicNumber || ord.Symbol() != _Symbol) continue;
      if(now - ord.TimeSetup() >= ExpirasiPendingAwal * 60)
      {
         PrintFormat("Pending awal #%I64u kedaluwarsa, dihapus", ord.Ticket());
         trade.OrderDelete(ord.Ticket());
      }
   }
}

//--- entry awal: Buy Stop + Sell Stop
void TryInitialEntry()
{
   if(!InTimeWindow()) { g_lastMsg = "Di luar jendela waktu"; return; }
   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spread > MaxSpreadPoint) { g_lastMsg = StringFormat("Spread %d > max %d, entry ditolak", spread, MaxSpreadPoint); return; }
   if(GunakanFilterATR)
   {
      double a = GetATR();
      if(a < ATRMinimum) { g_lastMsg = StringFormat("ATR %.2f < min %.2f, entry ditolak", a, ATRMinimum); return; }
   }
   if(TimeCurrent() - g_lastTryTime < 10) return; // throttle percobaan
   g_lastTryTime = TimeCurrent();

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double lot = NormalizeLot(LotAwal);

   bool okBuy  = PlaceStop(ORDER_TYPE_BUY_STOP,  lot, ask + JarakPendingAwal, "ZR L0", ExpirasiPendingAwal, false);
   bool okSell = PlaceStop(ORDER_TYPE_SELL_STOP, lot, bid - JarakPendingAwal, "ZR L0", ExpirasiPendingAwal, false);
   if(okBuy != okSell)
   {
      Print("Hanya satu pending awal berhasil, keduanya dihapus agar simetris");
      DeleteAllPendings();
   }
   else if(okBuy) g_lastMsg = "Pending awal terpasang";
}

//--- pastikan pending recovery level berikutnya ada di batas seberang
void MaintainRecoveryPending()
{
   ulong ft, lt;
   if(!GetFirstLastPosition(ft, lt)) return;
   if(!PositionSelectByTicket(lt)) return;
   long lastType = PositionGetInteger(POSITION_TYPE);

   int nextLevel = g_level + 1;
   ENUM_ORDER_TYPE wantType  = (lastType == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL_STOP : ORDER_TYPE_BUY_STOP;
   double          wantPrice = (wantType == ORDER_TYPE_BUY_STOP) ? g_zoneUpper : g_zoneLower;
   string          wantCmt   = "ZR L" + IntegerToString(nextLevel);
   double          tol       = 2.0 * _Point;

   bool allowed = true;
   if(MaxLevel > 0 && nextLevel > MaxLevel) { allowed = false; g_lastMsg = StringFormat("MaxLevel %d tercapai, tidak tambah level", MaxLevel); }
   double lot = LotForLevel(nextLevel);
   if(lot <= 0) { allowed = false; g_lastMsg = StringFormat("Deret lot habis di level %d, tidak tambah level", nextLevel); }

   // hapus pending yang tidak sesuai (termasuk sisa pending awal), cek apakah pending yang diinginkan sudah ada
   bool exists = false;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!ord.SelectByIndex(i)) continue;
      if(ord.Magic() != MagicNumber || ord.Symbol() != _Symbol) continue;
      bool match = allowed && ord.OrderType() == wantType && MathAbs(ord.PriceOpen() - wantPrice) <= tol;
      if(match && !exists) exists = true;
      else
      {
         PrintFormat("Hapus pending #%I64u %s @%.2f (tidak sesuai level %d)", ord.Ticket(), EnumToString(ord.OrderType()), ord.PriceOpen(), nextLevel);
         trade.OrderDelete(ord.Ticket());
      }
   }
   if(!allowed || exists) return;

   if(TimeCurrent() - g_lastTryTime < 10) return; // throttle jika gagal berulang
   g_lastTryTime = TimeCurrent();
   if(PlaceStop(wantType, lot, wantPrice, wantCmt, 0, true))
      g_lastMsg = StringFormat("Pending level %d terpasang @%.2f", nextLevel, wantPrice);
}

//--- mesin utama, dipanggil tiap tick dan dari OnTradeTransaction
void ManageCycle()
{
   int nPos  = CountPositions();
   int nPend = CountPendings();
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   // sedang close-all: ulangi sampai bersih, lalu reset
   if(g_closing)
   {
      if(nPos > 0 || nPend > 0) { CloseAllAndDelete(); return; }
      PrintFormat("Siklus selesai. Ekuitas %.2f", AccountInfoDouble(ACCOUNT_EQUITY));
      ResetCycle();
      g_lastMsg = "Siklus selesai, menunggu entry baru";
      nPos = 0; nPend = 0;
   }

   if(nPos == 0)
   {
      if(g_cycleActive)
      {
         Print("Semua posisi hilang (ditutup manual?) -> reset siklus & hapus pending");
         ResetCycle();
         DeleteAllPendings();
         return;
      }
      if(nPend > 0) { CheckInitialExpiry(); g_lastMsg = "Menunggu pending awal tereksekusi"; return; }
      TryInitialEntry();
      return;
   }

   // ada posisi
   if(!g_cycleActive) StartCycle();
   g_level = nPos - 1;

   // cek target: close-all serentak dari kode
   if(bid >= g_tpUpper || ask <= g_tpLower)
   {
      PrintFormat("TARGET TERCAPAI (Bid %.2f / Ask %.2f, TP atas %.2f / bawah %.2f) -> close all", bid, ask, g_tpUpper, g_tpLower);
      g_closing = true;
      CloseAllAndDelete();
      return;
   }

   MaintainRecoveryPending();
}

//================================ COMMENT ===========================
void UpdateComment()
{
   datetime now = TimeCurrent();
   if(now == g_lastCommentTime && !MQLInfoInteger(MQL_VISUAL_MODE)) return;
   g_lastCommentTime = now;

   double totalLot, floatPL, netLot;
   GetBasketStats(totalLot, floatPL, netLot);
   MqlDateTime wib; TimeToStruct(WIBNow(), wib);

   string s = "=== ZONE RECOVERY EA | " + _Symbol + " | Magic " + IntegerToString(MagicNumber) + " ===\n";
   s += "!!! PERINGATAN: TANPA STOP LOSS & TANPA CUT-LOSS PER SIKLUS. RISIKO MARGIN CALL TINGGI !!!\n";
   s += StringFormat("WIB: %02d:%02d | Jendela: %s | Spread: %d pt\n", wib.hour, wib.min,
                     g_useWindow ? (JamMulai + "-" + JamSelesai + (InTimeWindow() ? " (AKTIF)" : " (TUTUP)")) : "24 jam",
                     (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD));
   if(g_cycleActive)
   {
      s += StringFormat("Level: %d (lot berikut: %s) | Posisi: %d | Pending: %d\n", g_level,
                        LotForLevel(g_level + 1) > 0 ? DoubleToString(LotForLevel(g_level + 1), 2) : "-",
                        CountPositions(), CountPendings());
      s += StringFormat("Zona: %.2f - %.2f (lebar %.2f)\n", g_zoneLower, g_zoneUpper, g_zoneWidth);
      s += StringFormat("TP atas: %.2f | TP bawah: %.2f (jarak %.2f)\n", g_tpUpper, g_tpLower, g_tpDist);
   }
   else
      s += StringFormat("Level: - | Siklus belum aktif | Pending: %d\n", CountPendings());
   s += StringFormat("Total lot: %.2f (net %+.2f) | Floating P/L: %.2f\n", totalLot, netLot, floatPL);
   s += StringFormat("Balance: %.2f | Ekuitas: %.2f | Free margin: %.2f\n",
                     AccountInfoDouble(ACCOUNT_BALANCE), AccountInfoDouble(ACCOUNT_EQUITY), AccountInfoDouble(ACCOUNT_MARGIN_FREE));
   s += "Status: " + g_lastMsg;
   Comment(s);
}

//================================ EVENTS ============================
int OnInit()
{
   // akun harus hedging
   if((ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
   {
      Alert("EA ini memerlukan akun bertipe HEDGING. Mode akun saat ini bukan hedging.");
      return INIT_FAILED;
   }
   if(!ParseLots(DeretLot))
   {
      Alert("DeretLot tidak valid: ", DeretLot);
      return INIT_PARAMETERS_INCORRECT;
   }
   if(LotAwal <= 0 || LebarZona <= 0 || JarakTP < 0 || JarakPendingAwal <= 0)
   {
      Alert("Parameter lot/zona/TP/jarak pending tidak valid");
      return INIT_PARAMETERS_INCORRECT;
   }

   g_startMin = ParseHHMM(JamMulai);
   g_endMin   = ParseHHMM(JamSelesai);
   g_useWindow = (g_startMin >= 0 && g_endMin >= 0);
   if(!g_useWindow && (JamMulai != "" || JamSelesai != ""))
      Print("Jendela waktu tidak valid/tidak lengkap -> EA aktif 24 jam");

   if(GunakanFilterATR || ZonaBerbasisATR)
   {
      g_atrHandle = iATR(_Symbol, ATRTimeframe, ATRPeriode);
      if(g_atrHandle == INVALID_HANDLE)
      {
         Alert("Gagal membuat handle ATR");
         return INIT_FAILED;
      }
   }

   trade.SetExpertMagicNumber((ulong)MagicNumber);
   trade.SetDeviationInPoints((ulong)Slippage);
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetAsyncMode(false);
   trade.LogLevel(LOG_LEVEL_ERRORS);

   g_gvZW = "ZR_" + _Symbol + "_" + IntegerToString(MagicNumber) + "_ZW";
   g_gvTP = "ZR_" + _Symbol + "_" + IntegerToString(MagicNumber) + "_TP";

   g_lastMsg = "Inisialisasi";
   RebuildState();

   PrintFormat("ZoneRecoveryEA siap. Lot: %d level, zona %.2f, TP %.2f, MaxLevel %d, expiration broker %s",
               ArraySize(g_lots), LebarZona, JarakTP, MaxLevel, ExpirationSupported() ? "didukung" : "manual");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(g_atrHandle != INVALID_HANDLE) IndicatorRelease(g_atrHandle);
   Comment("");
}

void OnTick()
{
   ManageCycle();
   UpdateComment();
}

//--- deteksi eksekusi pending secara andal
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal)) return;
   if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != MagicNumber) return;
   if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol) return;

   ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if(entry == DEAL_ENTRY_IN)
   {
      PrintFormat("Deal IN #%I64u %s lot %.2f @%.2f (%s)", trans.deal,
                  HistoryDealGetInteger(trans.deal, DEAL_TYPE) == DEAL_TYPE_BUY ? "BUY" : "SELL",
                  HistoryDealGetDouble(trans.deal, DEAL_VOLUME),
                  HistoryDealGetDouble(trans.deal, DEAL_PRICE),
                  HistoryDealGetString(trans.deal, DEAL_COMMENT));
      g_lastTryTime = 0;      // izinkan pasang pending segera
      ManageCycle();          // langsung proses: hapus pending lawan, pasang pending level berikut
      UpdateComment();
   }
}
//+------------------------------------------------------------------+