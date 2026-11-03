// =========================================
// BreakoutEA.mq5
// EA Breakout sesi harian
//
// ALUR EA:
// 1. OnInit
//    siapkan CTrade, CSymbolInfo,
//    CPriceRange; cek parameter
// 2. OnTick (tiap tick)
//    a. refresh harga Bid/Ask
//    b. ganti hari -> reset flag
//    c. hitung range sesi (1x per hari)
//    d. filter waktu
//    e. filter posisi
//    f. cek breakout
//       close only -> candle index 1
//       real time  -> Bid/Ask
//    g. break up -> BUY
//       break down -> SELL
// 3. OpenPosition
//    hitung SL/TP, kirim order
// 4. Fungsi bantu
//    lot, hitung posisi, tutup posisi,
//    gambar garis range
// =========================================
#property copyright "Breakout EA"
#property version   "1.00"
#property strict

// pustaka bawaan MQL5
// kirim order
#include <Trade\Trade.mqh>
// info Bid/Ask
#include <Trade\SymbolInfo.mqh>
// info posisi
#include <Trade\PositionInfo.mqh>
// kelas buatan sendiri (satu folder)
#include "PriceRange.mqh"

// =========================================
// INPUT
// =========================================
input group "=== Sesi Range ==="
// jam & menit mulai range (waktu server)
input int InpRangeStartHour = 0;
input int InpRangeStartMin  = 0;
// jam & menit akhir range
input int InpRangeEndHour   = 8;
input int InpRangeEndMin    = 0;
// jam terakhir boleh entry
input int InpTradeEndHour   = 20;

input group "=== Entry ==="
// entry hanya setelah candle close
input bool InpCloseCandleOnly = true;
// maksimal 1 trade per hari
input bool InpOneTradePerDay  = true;
// izinkan buy / sell
input bool InpAllowBuy        = true;
input bool InpAllowSell       = true;
// buffer di atas/bawah range (point)
input int  InpBufferPoints    = 0;

input group "=== Money Management ==="
// ukuran lot
input double InpLots          = 0.10;
// SL dalam point, 0 = pakai sisi range
input int    InpSLPoints      = 300;
// TP dalam point, 0 = tanpa TP
input int    InpTPPoints      = 600;
// tutup posisi saat ganti hari
input bool   InpCloseAtDayEnd = false;

input group "=== Lainnya ==="
// magic number EA
input ulong InpMagic     = 20260101;
// deviasi / slippage (point)
input int   InpSlippage  = 20;
// gambar garis range di chart
input bool  InpDrawRange = true;

// =========================================
// OBJEK GLOBAL
// =========================================
// eksekusi order
CTrade        trade;
// harga Bid/Ask
CSymbolInfo   symbolInfo;
// baca posisi
CPositionInfo posInfo;
// range sesi
CPriceRange   priceRange;

// =========================================
// STATE (status berjalan)
// =========================================
// untuk deteksi bar baru
datetime g_last_bar_time = 0;
// hari aktif
datetime g_trade_day     = 0;
// sudah buy / sell hari ini?
bool     g_buy_done      = false;
bool     g_sell_done     = false;

// =========================================
// 1. OnInit
// =========================================
int OnInit()
  {
   // hubungkan CSymbolInfo ke simbol chart
   if(!symbolInfo.Name(_Symbol))
     {
      Print("Gagal init CSymbolInfo");
      return(INIT_FAILED);
     }
   symbolInfo.RefreshRates();

   // pengaturan CTrade
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippage);
   trade.SetTypeFillingBySymbol(_Symbol);

   // kirim jam sesi ke kelas range
   priceRange.Init(_Symbol, _Period,
                   InpRangeStartHour,
                   InpRangeStartMin,
                   InpRangeEndHour,
                   InpRangeEndMin);

   // validasi: jam akhir harus > jam mulai
   int startMin = InpRangeStartHour * 60
                + InpRangeStartMin;
   int endMin   = InpRangeEndHour * 60
                + InpRangeEndMin;
   if(endMin <= startMin)
     {
      Print("Jam akhir harus > jam mulai");
      return(INIT_PARAMETERS_INCORRECT);
     }

   return(INIT_SUCCEEDED);
  }

// =========================================
// OnDeinit: hapus garis range dari chart
// =========================================
void OnDeinit(const int reason)
  {
   ObjectsDeleteAll(0, "BRK_");
  }

// =========================================
// 2. OnTick
// =========================================
void OnTick()
  {
   // a. refresh Bid/Ask
   // gagal -> tunggu tick berikutnya
   if(!symbolInfo.RefreshRates())
      return;

   datetime now = TimeCurrent();
   // jam 00:00 hari ini
   datetime day = now - (now % 86400);

   // b. hari berganti -> reset flag
   if(day != g_trade_day)
     {
      // tutup posisi lama bila diminta
      if(InpCloseAtDayEnd)
         CloseAllByMagic();
      g_trade_day = day;
      g_buy_done  = false;
      g_sell_done = false;
     }

   // c. hitung range hari ini (1x saja)
   if(!priceRange.IsValid() ||
      priceRange.GetCalcDay() != day)
     {
      // false = sesi belum selesai
      if(!priceRange.CalculateToday())
         return;
      if(InpDrawRange)
         DrawRange();
     }

   // d. filter waktu
   // harus sudah lewat sesi range
   if(!priceRange.IsAfterRange(now))
      return;
   // belum lewat jam batas entry
   MqlDateTime dt;
   TimeToStruct(now, dt);
   if(dt.hour >= InpTradeEndHour)
      return;

   // e. filter posisi
   // masih ada posisi -> skip
   if(CountPositions() > 0)
      return;
   // jatah hari ini habis -> skip
   if(InpOneTradePerDay &&
      (g_buy_done || g_sell_done))
      return;

   // f. cek breakout
   double buffer    = InpBufferPoints * _Point;
   bool   breakUp   = false;
   bool   breakDown = false;

   if(InpCloseCandleOnly)
     {
      // hanya proses saat bar baru muncul
      datetime bar_time = iTime(_Symbol,
                                _Period, 0);
      // masih bar yang sama -> skip
      if(bar_time == g_last_bar_time)
         return;
      g_last_bar_time = bar_time;

      // candle index 1 = baru saja close
      // harus candle setelah sesi selesai
      datetime t1 = iTime(_Symbol, _Period, 1);
      if(t1 < priceRange.GetRangeEnd())
         return;

      double o = iOpen(_Symbol,  _Period, 1);
      double c = iClose(_Symbol, _Period, 1);
      double hi = priceRange.GetHigh();
      double lo = priceRange.GetLow();

      // versi 2 parameter (body candle)
      breakUp   = priceRange.BreakUp(o, c) &&
                  c > hi + buffer;
      breakDown = priceRange.BreakDown(o, c) &&
                  c < lo - buffer;
     }
   else
     {
      // versi 1 parameter (harga real time)
      double ask = symbolInfo.Ask() - buffer;
      double bid = symbolInfo.Bid() + buffer;
      breakUp   = priceRange.BreakUp(ask);
      breakDown = priceRange.BreakDown(bid);
     }

   // g. eksekusi
   if(breakUp && InpAllowBuy && !g_buy_done)
     {
      // tandai sudah buy bila sukses
      if(OpenPosition(ORDER_TYPE_BUY))
         g_buy_done = true;
     }
   else if(breakDown && InpAllowSell &&
           !g_sell_done)
     {
      // tandai sudah sell bila sukses
      if(OpenPosition(ORDER_TYPE_SELL))
         g_sell_done = true;
     }
  }

// =========================================
// 3. OpenPosition
// Langkah:
//  a. ambil harga entry
//     Ask untuk buy, Bid untuk sell
//  b. hitung SL & TP
//  c. normalisasi digit & cek stop level
//  d. kirim order lewat CTrade
// =========================================
bool OpenPosition(const ENUM_ORDER_TYPE type)
  {
   symbolInfo.RefreshRates();
   int    digits = symbolInfo.Digits();
   double point  = symbolInfo.Point();
   double price  = 0.0;
   double sl     = 0.0;
   double tp     = 0.0;

   if(type == ORDER_TYPE_BUY)
     {
      // a. buy pakai harga Ask
      price = symbolInfo.Ask();
      // b. SL: fixed point / low range
      if(InpSLPoints > 0)
         sl = price - InpSLPoints * point;
      else
         sl = priceRange.GetLow();
      // TP opsional
      if(InpTPPoints > 0)
         tp = price + InpTPPoints * point;
     }
   else
     {
      // a. sell pakai harga Bid
      price = symbolInfo.Bid();
      // b. SL: fixed point / high range
      if(InpSLPoints > 0)
         sl = price + InpSLPoints * point;
      else
         sl = priceRange.GetHigh();
      // TP opsional
      if(InpTPPoints > 0)
         tp = price - InpTPPoints * point;
     }

   // c. normalisasi digit
   sl = NormalizeDouble(sl, digits);
   tp = NormalizeDouble(tp, digits);

   // jarak minimum SL/TP dari broker
   double stops = symbolInfo.StopsLevel()
                * point;
   if(type == ORDER_TYPE_BUY)
     {
      if(sl > 0 && price - sl < stops)
         sl = NormalizeDouble(price - stops,
                              digits);
      if(tp > 0 && tp - price < stops)
         tp = NormalizeDouble(price + stops,
                              digits);
     }
   else
     {
      if(sl > 0 && sl - price < stops)
         sl = NormalizeDouble(price + stops,
                              digits);
      if(tp > 0 && price - tp < stops)
         tp = NormalizeDouble(price - stops,
                              digits);
     }

   // d. kirim order
   double lots = NormalizeLots(InpLots);
   bool   ok   = false;

   if(type == ORDER_TYPE_BUY)
      ok = trade.Buy(lots, _Symbol, price,
                     sl, tp, "Breakout Buy");
   else
      ok = trade.Sell(lots, _Symbol, price,
                      sl, tp, "Breakout Sell");

   // cek hasil order
   if(!ok ||
      trade.ResultRetcode() != TRADE_RETCODE_DONE)
     {
      PrintFormat("Order gagal: %d - %s",
                  trade.ResultRetcode(),
                  trade.ResultRetcodeDescription());
      return(false);
     }

   string arah = "SELL";
   if(type == ORDER_TYPE_BUY)
      arah = "BUY";
   PrintFormat("%s @ %.5f SL %.5f TP %.5f",
               arah, price, sl, tp);
   return(true);
  }

// =========================================
// 4a. NormalizeLots
// sesuaikan lot ke aturan broker
// =========================================
double NormalizeLots(double lots)
  {
   double minLot  = symbolInfo.LotsMin();
   double maxLot  = symbolInfo.LotsMax();
   double stepLot = symbolInfo.LotsStep();

   // batasi antara min dan max
   lots = MathMax(minLot,
                  MathMin(maxLot, lots));
   // bulatkan ke kelipatan step
   lots = MathFloor(lots / stepLot) * stepLot;
   return(NormalizeDouble(lots, 2));
  }

// =========================================
// 4b. CountPositions
// hitung posisi milik EA ini
// =========================================
int CountPositions()
  {
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      // hanya simbol & magic yang sama
      if(posInfo.SelectByIndex(i) &&
         posInfo.Symbol() == _Symbol &&
         posInfo.Magic()  == InpMagic)
         count++;
     }
   return(count);
  }

// =========================================
// 4c. CloseAllByMagic
// tutup semua posisi EA ini
// =========================================
void CloseAllByMagic()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(posInfo.SelectByIndex(i) &&
         posInfo.Symbol() == _Symbol &&
         posInfo.Magic()  == InpMagic)
         trade.PositionClose(posInfo.Ticket());
     }
  }

// =========================================
// 4d. DrawRange
// gambar garis high & low di chart
// =========================================
void DrawRange()
  {
   // nama objek unik per tanggal
   string tag = TimeToString(
                   priceRange.GetCalcDay(),
                   TIME_DATE);
   string hiN = "BRK_H_" + tag;
   string loN = "BRK_L_" + tag;

   datetime t1 = priceRange.GetRangeStart();
   datetime t2 = priceRange.GetCalcDay()
               + 86400 - 1;
   double   hi = priceRange.GetHigh();
   double   lo = priceRange.GetLow();

   // buat garis jika belum ada
   if(ObjectFind(0, hiN) < 0)
      ObjectCreate(0, hiN, OBJ_TREND, 0,
                   t1, hi, t2, hi);
   if(ObjectFind(0, loN) < 0)
      ObjectCreate(0, loN, OBJ_TREND, 0,
                   t1, lo, t2, lo);

   // warna garis
   ObjectSetInteger(0, hiN, OBJPROP_COLOR,
                    clrDodgerBlue);
   ObjectSetInteger(0, loN, OBJPROP_COLOR,
                    clrOrangeRed);
   // jangan diperpanjang ke kanan
   ObjectSetInteger(0, hiN, OBJPROP_RAY_RIGHT,
                    false);
   ObjectSetInteger(0, loN, OBJPROP_RAY_RIGHT,
                    false);
  }