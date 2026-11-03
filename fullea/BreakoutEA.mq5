//+------------------------------------------------------------------+
//|                                                   BreakoutEA.mq5 |
//|  EA Breakout sesi harian: hitung range high/low pada jam sesi,   |
//|  entry saat harga menembus range (opsional hanya setelah candle  |
//|  close), satu trade per arah per hari, SL/TP dalam point.         |
//+------------------------------------------------------------------+
#property copyright "Breakout EA"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\PositionInfo.mqh>
#include "PriceRange.mqh"

//--- input
input group "=== Sesi Range (waktu server) ==="
input int      InpRangeStartHour   = 0;      // Jam mulai range
input int      InpRangeStartMin    = 0;      // Menit mulai range
input int      InpRangeEndHour     = 8;      // Jam akhir range
input int      InpRangeEndMin      = 0;      // Menit akhir range
input int      InpTradeEndHour     = 20;     // Jam terakhir boleh entry

input group "=== Entry ==="
input bool     InpCloseCandleOnly  = true;   // Entry hanya setelah candle close
input bool     InpOneTradePerDay   = true;   // Maks 1 trade per hari
input bool     InpAllowBuy         = true;   // Izinkan Buy
input bool     InpAllowSell        = true;   // Izinkan Sell
input int      InpBufferPoints     = 0;      // Buffer di atas/bawah range (point)

input group "=== Money Management ==="
input double   InpLots             = 0.10;   // Lot
input int      InpSLPoints         = 300;    // Stop Loss (point), 0 = pakai sisi range lawan
input int      InpTPPoints         = 600;    // Take Profit (point), 0 = tanpa TP
input bool     InpCloseAtDayEnd    = false;  // Tutup posisi saat ganti hari

input group "=== Lainnya ==="
input ulong    InpMagic            = 20260101;
input int      InpSlippage         = 20;     // Deviation (point)
input bool     InpDrawRange        = true;   // Gambar garis range di chart

//--- objek
CTrade         trade;
CSymbolInfo    symbolInfo;
CPositionInfo  posInfo;
CPriceRange    priceRange;

//--- state
datetime       g_last_bar_time = 0;
datetime       g_trade_day     = 0;     // hari terakhir trade dibuka
bool           g_buy_done      = false;
bool           g_sell_done     = false;

//+------------------------------------------------------------------+
int OnInit()
  {
   if(!symbolInfo.Name(_Symbol))
     {
      Print("Gagal inisialisasi CSymbolInfo");
      return(INIT_FAILED);
     }
   symbolInfo.RefreshRates();

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippage);
   trade.SetTypeFillingBySymbol(_Symbol);

   priceRange.Init(_Symbol, _Period,
                   InpRangeStartHour, InpRangeStartMin,
                   InpRangeEndHour,   InpRangeEndMin);

   if(InpRangeEndHour * 60 + InpRangeEndMin <= InpRangeStartHour * 60 + InpRangeStartMin)
     {
      Print("Jam akhir range harus lebih besar dari jam mulai.");
      return(INIT_PARAMETERS_INCORRECT);
     }

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   ObjectsDeleteAll(0, "BRK_");
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   if(!symbolInfo.RefreshRates())
      return;

   datetime now = TimeCurrent();
   datetime day = now - (now % 86400);

   //--- reset state saat ganti hari
   if(day != g_trade_day)
     {
      if(InpCloseAtDayEnd)
         CloseAllByMagic();
      g_trade_day = day;
      g_buy_done  = false;
      g_sell_done = false;
     }

   //--- hitung range hari ini (sekali setelah sesi selesai)
   if(!priceRange.IsValid() || priceRange.GetCalcDay() != day)
     {
      if(!priceRange.CalculateToday())
         return;                      // sesi belum selesai / data belum ada
      if(InpDrawRange)
         DrawRange();
     }

   //--- hanya trading setelah range terbentuk & sebelum jam batas
   if(!priceRange.IsAfterRange(now))
      return;
   MqlDateTime dt;
   TimeToStruct(now, dt);
   if(dt.hour >= InpTradeEndHour)
      return;

   //--- sudah ada posisi dari EA ini?
   if(CountPositions() > 0)
      return;
   if(InpOneTradePerDay && (g_buy_done || g_sell_done))
      return;

   double buffer = InpBufferPoints * _Point;
   bool   breakUp = false, breakDown = false;

   if(InpCloseCandleOnly)
     {
      //--- cek hanya saat candle baru terbentuk, pakai candle yang baru close (index 1)
      datetime bar_time = iTime(_Symbol, _Period, 0);
      if(bar_time == g_last_bar_time)
         return;
      g_last_bar_time = bar_time;

      // candle index 1 harus setelah sesi range
      if(iTime(_Symbol, _Period, 1) < priceRange.GetRangeEnd())
         return;

      double o = iOpen(_Symbol, _Period, 1);
      double c = iClose(_Symbol, _Period, 1);
      breakUp   = priceRange.BreakUp(o, c)   && c > priceRange.GetHigh() + buffer;
      breakDown = priceRange.BreakDown(o, c) && c < priceRange.GetLow()  - buffer;
     }
   else
     {
      //--- cek real-time dengan Bid/Ask
      breakUp   = priceRange.BreakUp(symbolInfo.Ask()   - buffer);
      breakDown = priceRange.BreakDown(symbolInfo.Bid() + buffer);
     }

   if(breakUp && InpAllowBuy && !g_buy_done)
     {
      if(OpenPosition(ORDER_TYPE_BUY))
         g_buy_done = true;
     }
   else if(breakDown && InpAllowSell && !g_sell_done)
     {
      if(OpenPosition(ORDER_TYPE_SELL))
         g_sell_done = true;
     }
  }

//+------------------------------------------------------------------+
//| Buka posisi dengan SL/TP                                         |
//+------------------------------------------------------------------+
bool OpenPosition(const ENUM_ORDER_TYPE type)
  {
   symbolInfo.RefreshRates();
   int    digits = symbolInfo.Digits();
   double point  = symbolInfo.Point();
   double price, sl = 0.0, tp = 0.0;

   if(type == ORDER_TYPE_BUY)
     {
      price = symbolInfo.Ask();
      sl = (InpSLPoints > 0) ? price - InpSLPoints * point : priceRange.GetLow();
      if(InpTPPoints > 0) tp = price + InpTPPoints * point;
     }
   else
     {
      price = symbolInfo.Bid();
      sl = (InpSLPoints > 0) ? price + InpSLPoints * point : priceRange.GetHigh();
      if(InpTPPoints > 0) tp = price - InpTPPoints * point;
     }

   sl = NormalizeDouble(sl, digits);
   tp = NormalizeDouble(tp, digits);

   //--- validasi jarak stop level
   double stops = symbolInfo.StopsLevel() * point;
   if(type == ORDER_TYPE_BUY)
     {
      if(sl > 0 && price - sl < stops) sl = NormalizeDouble(price - stops, digits);
      if(tp > 0 && tp - price < stops) tp = NormalizeDouble(price + stops, digits);
     }
   else
     {
      if(sl > 0 && sl - price < stops) sl = NormalizeDouble(price + stops, digits);
      if(tp > 0 && price - tp < stops) tp = NormalizeDouble(price - stops, digits);
     }

   double lots = NormalizeLots(InpLots);
   bool ok = (type == ORDER_TYPE_BUY)
             ? trade.Buy(lots, _Symbol, price, sl, tp, "Breakout Buy")
             : trade.Sell(lots, _Symbol, price, sl, tp, "Breakout Sell");

   if(!ok || trade.ResultRetcode() != TRADE_RETCODE_DONE)
     {
      PrintFormat("Order gagal: %d - %s", trade.ResultRetcode(), trade.ResultRetcodeDescription());
      return(false);
     }

   PrintFormat("%s dibuka @ %.5f SL %.5f TP %.5f | Range H=%.5f L=%.5f",
               (type == ORDER_TYPE_BUY ? "BUY" : "SELL"), price, sl, tp,
               priceRange.GetHigh(), priceRange.GetLow());
   return(true);
  }

//+------------------------------------------------------------------+
double NormalizeLots(double lots)
  {
   double minLot  = symbolInfo.LotsMin();
   double maxLot  = symbolInfo.LotsMax();
   double stepLot = symbolInfo.LotsStep();
   lots = MathMax(minLot, MathMin(maxLot, lots));
   lots = MathFloor(lots / stepLot) * stepLot;
   return(NormalizeDouble(lots, 2));
  }

//+------------------------------------------------------------------+
int CountPositions()
  {
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(posInfo.SelectByIndex(i) &&
         posInfo.Symbol() == _Symbol &&
         posInfo.Magic()  == InpMagic)
         count++;
     }
   return(count);
  }

//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| Gambar garis high/low range di chart                             |
//+------------------------------------------------------------------+
void DrawRange()
  {
   string tag  = TimeToString(priceRange.GetCalcDay(), TIME_DATE);
   string hiN  = "BRK_H_" + tag;
   string loN  = "BRK_L_" + tag;
   datetime t1 = priceRange.GetRangeStart();
   datetime t2 = priceRange.GetCalcDay() + 86400 - 1;

   if(ObjectFind(0, hiN) < 0)
      ObjectCreate(0, hiN, OBJ_TREND, 0, t1, priceRange.GetHigh(), t2, priceRange.GetHigh());
   if(ObjectFind(0, loN) < 0)
      ObjectCreate(0, loN, OBJ_TREND, 0, t1, priceRange.GetLow(), t2, priceRange.GetLow());

   ObjectSetInteger(0, hiN, OBJPROP_COLOR, clrDodgerBlue);
   ObjectSetInteger(0, loN, OBJPROP_COLOR, clrOrangeRed);
   ObjectSetInteger(0, hiN, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, loN, OBJPROP_RAY_RIGHT, false);
  }
//+------------------------------------------------------------------+