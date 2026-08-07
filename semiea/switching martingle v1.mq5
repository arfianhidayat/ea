//+------------------------------------------------------------------+
//|                                         switching martingle.mq5  |
//|                                      Copyright 2026, Antigravity |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Antigravity"
#property link      ""
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

//--- Input Parameters
input double InpLossPoints = 500.0;        // Loss Distance to Switch (Points)
input double InpTargetPoints = 500.0;      // Total Profit Target (Points)
input double InpLotMultiplier = 2.0;        // Lot Multiplier for Martingale
input int InpMaxPositions = 5;              // Batas Maksimal Posisi Terbuka
input int InpSnRPeriod = 50;                // Periode Candle Support & Resistance
input ulong InpMagic = 99999;               // EA Magic Number untuk Martingale

//--- Global Variables
double point_value;

// Struct untuk menyimpan dan mengurutkan data posisi
struct PosData {
    ulong ticket;
    datetime time;
    double profit; 
    double volume;
    long type;
    double openPrice;
};

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   // MENGGUNAKAN POINT MURNI (Fix untuk Kripto/BTCUSD)
   point_value = _Point;
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   Comment(""); // Bersihkan Comment jika ada
   ObjectsDeleteAll(0, "lbl_"); // Bersihkan dashboard UI
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   int total_positions = PositionsTotal();
   int total_orders = OrdersTotal();
   
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   
   int myPositions = 0;
   int manualOrders = 0;
   int eaOrders = 0;
   
   double totalProfitMoney = 0;
   PosData posArr[]; // Array dinamis untuk menyimpan posisi
   
   // Alokasi awal memori array untuk mencegah memory overhead
   ArrayResize(posArr, total_positions);
   
   // 1. Kumpulkan data posisi aktif di pair saat ini
   for(int i = total_positions - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionGetString(POSITION_SYMBOL) == _Symbol)
        {
         double profit = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
         totalProfitMoney += profit;
         
         posArr[myPositions].ticket = ticket;
         posArr[myPositions].time = (datetime)PositionGetInteger(POSITION_TIME);
         posArr[myPositions].profit = profit;
         posArr[myPositions].volume = PositionGetDouble(POSITION_VOLUME);
         posArr[myPositions].type = PositionGetInteger(POSITION_TYPE);
         posArr[myPositions].openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         
         myPositions++;
        }
     }
   ArrayResize(posArr, myPositions); // Trim array ke ukuran sesungguhnya
     
   // Urutkan posisi berdasarkan waktu Buka (dari terlama ke terbaru)
   if(myPositions > 1)
     {
      for(int i = 0; i < myPositions - 1; i++)
        {
         for(int j = 0; j < myPositions - i - 1; j++)
           {
            if(posArr[j].time > posArr[j+1].time)
              {
               PosData temp = posArr[j];
               posArr[j] = posArr[j+1];
               posArr[j+1] = temp;
              }
           }
        }
     }
     
   // 2. Kumpulkan data pending order di pair saat ini
   for(int i = total_orders - 1; i >= 0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(OrderGetString(ORDER_SYMBOL) == _Symbol)
        {
         ulong magic = OrderGetInteger(ORDER_MAGIC);
         if(magic == InpMagic)
            eaOrders++;
         else
            manualOrders++;
        }
     }
     
   static int lastTickPositions = -1;
   static int lastTickEaOrders = -1;
   static datetime delayUntil = 0;
   
   if(lastTickPositions != -1 && lastTickEaOrders != -1)
     {
      // Deteksi penutupan posisi atau penghapusan order EA.
      // Tunda 3 detik untuk mencegah open pending order saat proses "Close All" manual
      if(myPositions < lastTickPositions || (eaOrders < lastTickEaOrders && myPositions <= lastTickPositions))
        {
         delayUntil = TimeCurrent() + InpMaxPositions + 3;
        }
     }
   lastTickPositions = myPositions;
   lastTickEaOrders = eaOrders;
      
   // --- LOGIKA UTAMA ---
   
   // A. Bersihkan Pending Order Manual sisa jika ada posisi aktif
   if(myPositions > 0 && manualOrders > 0)
     {
      for(int i = OrdersTotal() - 1; i >= 0; i--)
        {
         ulong ticket = OrderGetTicket(i);
         if(OrderGetString(ORDER_SYMBOL) == _Symbol && OrderGetInteger(ORDER_MAGIC) != InpMagic)
           {
            trade.OrderDelete(ticket);
           }
        }
     }
     
   // B. Bersihkan Pending Order EA yang tertinggal saat semua posisi ditutup manual
   if(myPositions == 0 && eaOrders > 0)
     {
      for(int i = OrdersTotal() - 1; i >= 0; i--)
        {
         ulong ticket = OrderGetTicket(i);
         if(OrderGetString(ORDER_SYMBOL) == _Symbol && OrderGetInteger(ORDER_MAGIC) == InpMagic)
           {
            trade.OrderDelete(ticket);
           }
        }
     }
     
   // C. Manajemen Posisi Aktif (Partial Close / Overlapping & Pending Martingale)
   if(myPositions > 0)
     {
      // Target $ = Target Points * (TickValue / TickSize) * InitialLot
      double initialLot = posArr[0].volume;
      double targetMoney = 0;
      if(tickSize > 0)
         targetMoney = (InpTargetPoints * point_value / tickSize) * tickValue * initialLot;
      
      PosData lastPos = posArr[myPositions - 1];
      bool justClosed = false;
      
      // C.1. Logika Partial Close / Overlapping
      bool hitTarget = false;
      bool isSingle = false;
      PosData prevPos = {}; // Inisialisasi struct kosong untuk menghilangkan warning compiler
      
      if(myPositions == 1)
        {
         // Jika hanya ada 1 posisi, cek target (sama dengan Global TP)
         if(InpTargetPoints > 0 && targetMoney > 0 && lastPos.profit >= targetMoney)
           {
            hitTarget = true;
            isSingle = true;
           }
        }
      else if(myPositions > 1)
        {
         // Jika > 1 posisi, gabungkan profit Posisi Terakhir dan Posisi Sebelumnya
         prevPos = posArr[myPositions - 2];
         if(InpTargetPoints > 0 && targetMoney > 0 && (lastPos.profit + prevPos.profit) >= targetMoney)
           {
            hitTarget = true;
            isSingle = false;
           }
        }
        
      // Eksekusi penutupan jika target tercapai
      if(hitTarget)
        {
         // 1. BATALKAN PENDING ORDER TERLEBIH DAHULU (Mencegah order ter-trigger saat proses close)
         for(int i = OrdersTotal() - 1; i >= 0; i--)
           {
            ulong ticket = OrderGetTicket(i);
            if(OrderGetString(ORDER_SYMBOL) == _Symbol && OrderGetInteger(ORDER_MAGIC) == InpMagic)
              {
               trade.OrderDelete(ticket);
              }
           }
           
         // 2. KEMUDIAN TUTUP POSISI
         if(isSingle)
           {
            trade.PositionClose(lastPos.ticket);
            Print("Target profit tercapai! Posisi awal ditutup.");
           }
         else
           {
            trade.PositionClose(lastPos.ticket);
            trade.PositionClose(prevPos.ticket);
            Print("Target Partial Close berpasangan tercapai! Posisi terakhir & sebelumnya ditutup.");
           }
           
         return; // Selesai siklus tick ini, reset state
        }
        
      // C.2. Pasang Pending Order Martingale (Lawan Arah) jika belum ada
      if(eaOrders == 0 && myPositions < InpMaxPositions && PositionSelectByTicket(lastPos.ticket))
        {
         if(TimeCurrent() >= delayUntil)
           {
            double newLot = NormalizeDouble(lastPos.volume * InpLotMultiplier, 2);
            double switchPrice = 0;
            
            trade.SetExpertMagicNumber(InpMagic); // Gunakan identitas EA
            
            if(lastPos.type == POSITION_TYPE_BUY)
              {
               switchPrice = lastPos.openPrice - (InpLossPoints * point_value);
               switchPrice = NormalizeDouble(switchPrice, _Digits);
               
               if(trade.SellStop(newLot, switchPrice, _Symbol, 0, 0, 0, 0, "Switching SellStop"))
                  Print("Berhasil memasang jaring SELL STOP di harga ", switchPrice);
               else
                  Print("Gagal memasang Sell Stop: Error ", trade.ResultRetcode());
              }
            else if(lastPos.type == POSITION_TYPE_SELL)
              {
               switchPrice = lastPos.openPrice + (InpLossPoints * point_value);
               switchPrice = NormalizeDouble(switchPrice, _Digits);
               
               if(trade.BuyStop(newLot, switchPrice, _Symbol, 0, 0, 0, 0, "Switching BuyStop"))
                  Print("Berhasil memasang jaring BUY STOP di harga ", switchPrice);
               else
                  Print("Gagal memasang Buy Stop: Error ", trade.ResultRetcode());
              }
              
            trade.SetExpertMagicNumber(0); // Kembalikan ke 0 demi keamanan
           }
        }
     }
     
     // D. Kalkulasi dan Gambar Support & Resistance
     double highest = 0;
     double lowest = 0;
     
     int highestIdx = iHighest(_Symbol, _Period, MODE_HIGH, InpSnRPeriod, 1);
     int lowestIdx = iLowest(_Symbol, _Period, MODE_LOW, InpSnRPeriod, 1);
     
     if(highestIdx >= 0 && lowestIdx >= 0)
       {
        highest = iHigh(_Symbol, _Period, highestIdx);
        lowest = iLow(_Symbol, _Period, lowestIdx);
        
        if(ObjectFind(0, "ResistanceLine") < 0)
          {
           ObjectCreate(0, "ResistanceLine", OBJ_HLINE, 0, 0, highest);
           ObjectSetInteger(0, "ResistanceLine", OBJPROP_COLOR, clrRed);
           ObjectSetInteger(0, "ResistanceLine", OBJPROP_STYLE, STYLE_DASH);
           ObjectSetInteger(0, "ResistanceLine", OBJPROP_WIDTH, 1);
           ObjectSetString(0, "ResistanceLine", OBJPROP_TEXT, "Resistance");
          }
        else
          {
           // Hanya update jika harga berubah untuk menghindari render berlebihan
           if(ObjectGetDouble(0, "ResistanceLine", OBJPROP_PRICE) != highest)
              ObjectSetDouble(0, "ResistanceLine", OBJPROP_PRICE, highest);
          }
          
        if(ObjectFind(0, "SupportLine") < 0)
          {
           ObjectCreate(0, "SupportLine", OBJ_HLINE, 0, 0, lowest);
           ObjectSetInteger(0, "SupportLine", OBJPROP_COLOR, clrLime);
           ObjectSetInteger(0, "SupportLine", OBJPROP_STYLE, STYLE_DASH);
           ObjectSetInteger(0, "SupportLine", OBJPROP_WIDTH, 1);
           ObjectSetString(0, "SupportLine", OBJPROP_TEXT, "Support");
          }
        else
          {
           if(ObjectGetDouble(0, "SupportLine", OBJPROP_PRICE) != lowest)
              ObjectSetDouble(0, "SupportLine", OBJPROP_PRICE, lowest);
          }
       }
       
     // E. Tampilkan Info di Layar (Dashboard Mini)
     double currentTarget = 0;
     double initialLotForDisplay = (myPositions > 0) ? posArr[0].volume : 0;
     if(myPositions > 0 && tickSize > 0)
        currentTarget = (InpTargetPoints * point_value / tickSize) * tickValue * initialLotForDisplay;
     
     string tpStatus = "N/A";
     if(myPositions == 1) tpStatus = "Target Global";
     else if(myPositions > 1) tpStatus = "Partial Close (Pos " + IntegerToString(myPositions) + " & " + IntegerToString(myPositions-1) + ")";
     
     // Tampilkan info di layar menggunakan Comment bawaan
     string commentText = "\n== PENDING SWITCH MARTINGALE ==\n\n" +
                          "Status Robot   : " + (myPositions > 0 ? "RUNNING (Manage Positions)" : "STANDBY (Waiting for Manual)") + "\n" +
                          "Posisi Aktif   : " + IntegerToString(myPositions) + " (Max " + IntegerToString(InpMaxPositions) + ")\n" +
                          "EA Jaring Order: " + IntegerToString(eaOrders) + "\n" +
                          "Manual Order   : " + IntegerToString(manualOrders) + "\n" +
                          "TP Mode        : " + tpStatus + "\n\n" +
                          "Total Profit   : $" + DoubleToString(totalProfitMoney, 2) + "\n" +
                          "Pair Target TP : $" + DoubleToString(currentTarget, 2);
     
     Comment(commentText);
     
  }
//+------------------------------------------------------------------+
