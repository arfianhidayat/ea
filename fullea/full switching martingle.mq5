//+------------------------------------------------------------------+
//|                                         switching martingle.mq5  |
//|                                           Copyright 2026, Arfian |
//|                                      Modified with Auto Breakout |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Arfian"
#property link      ""
#property version   "1.10"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

//--- Input Parameters
input group "=== Auto Breakout Settings ==="
input bool   InpAutoBreakout     = true;       // Aktifkan Auto Breakout Entry
input int    InpBreakoutPeriod   = 10;         // Periode Candle Breakout
input double InpBreakoutBuffer   = 15.0;       // Jarak Buffer Pips Breakout
input double InpInitialLot       = 0.01;       // Lot Awal Posisi Pertama

input group "=== Martingale & Target Settings ==="
input double InpLossPoints = 400.0;        // Jarak Loss Switch/Martingale (Points)
input double InpTargetPoints = 500.0;      // Target Profit Posisi 1/Awal (Points)
input double InpTargetBEPPoints = 300.0;   // Target Profit setelah BEP 1 (Points)
input double InpTargetBEP2Points = 150.0;  // Target Profit setelah BEP 2 (Points)
input int InpBEP2ActivationPos = 5;        // Aktifkan BEP 2 mulai posisi ke-
input double InpLotMultiplier = 2.0;       // Pengali Lot Martingale
input int InpMaxPositions = 8;             // Batas Maksimal Posisi Terbuka
input int InpSnRPeriod = 50;               // Periode Candle Support & Resistance Visual
input ulong InpMagic = 99999;              // EA Magic Number

//--- Global Variables
double point_value;
datetime delayUntil = 0; // Variabel keamanan anti-bentrok
bool isClosingAll = false; // Flag mode karantina sapu bersih

// Struct untuk menyimpan dan mengurutkan data posisi
struct PosData {
    ulong ticket;
    datetime time;
    double profit; 
    double volume;
    long type;
    double openPrice;
};

// Struct untuk Data Level Breakout
struct BreakoutLevels
  {
   double            highestHigh;
   double            lowestLow;
   bool              isValid;
  };

// Helper function for Lot Step
double NormalizeVolume(double vol) {
    double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    double minVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double normVol = MathRound(vol / step) * step;
    if (normVol < minVol) normVol = minVol;
    if (normVol > maxVol) normVol = maxVol;
    return normVol;
}

//+------------------------------------------------------------------+
//| Fungsi Pendeteksi Level Breakout                                 |
//+------------------------------------------------------------------+
BreakoutLevels GetBreakoutLevels(string symbol, ENUM_TIMEFRAMES timeframe, int lookback_period)
  {
   BreakoutLevels levels;
   levels.isValid = false;
   levels.highestHigh = 0;
   levels.lowestLow = 0;
   
   double high[], low[];
   ArraySetAsSeries(high, true); 
   ArraySetAsSeries(low, true);
   
   if(CopyHigh(symbol, timeframe, 1, lookback_period, high) <= 0 || 
      CopyLow(symbol, timeframe, 1, lookback_period, low) <= 0)
     {
      return levels;
     }
     
   int highestIndex = ArrayMaximum(high, 0, lookback_period);
   int lowestIndex = ArrayMinimum(low, 0, lookback_period);
   
   levels.highestHigh = high[highestIndex];
   levels.lowestLow = low[lowestIndex];
   levels.isValid = true;
   
   return levels;
  }

//+------------------------------------------------------------------+
//| CloseBy Helper Function (Tutup Saling Silang)                    |
//+------------------------------------------------------------------+
void CloseAllPositions()
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(OrderGetString(ORDER_SYMBOL) == _Symbol && OrderGetInteger(ORDER_MAGIC) == InpMagic)
        {
         trade.OrderDelete(ticket);
        }
     }
     
   while(true)
     {
      ulong buyTicket = 0;
      ulong sellTicket = 0;
      
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong ticket = PositionGetTicket(i);
         if(PositionGetString(POSITION_SYMBOL) == _Symbol)
           {
            long type = PositionGetInteger(POSITION_TYPE);
            if(type == POSITION_TYPE_BUY) buyTicket = ticket;
            else if(type == POSITION_TYPE_SELL) sellTicket = ticket;
           }
        }
        
      if(buyTicket > 0 && sellTicket > 0)
        {
         if(!trade.PositionCloseBy(buyTicket, sellTicket)) break; 
        }
      else
        {
         break; 
        }
     }
     
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionGetString(POSITION_SYMBOL) == _Symbol)
        {
         trade.PositionClose(ticket);
        }
     }
  }

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   point_value = _Point;
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   Comment(""); 
   ObjectDelete(0, "ResistanceLine");
   ObjectDelete(0, "SupportLine");
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   if(isClosingAll)
     {
      CloseAllPositions();
      int sisa = 0;
      for(int i = OrdersTotal() - 1; i >= 0; i--)
         if(OrderGetString(ORDER_SYMBOL) == _Symbol && OrderGetInteger(ORDER_MAGIC) == InpMagic) sisa++;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
         if(PositionGetString(POSITION_SYMBOL) == _Symbol) sisa++;
         
      if(sisa == 0)
        {
         isClosingAll = false;
         Print("Karantina Close All selesai 100%. Robot kembali Standby.");
        }
      else return; 
     }
     
   int total_positions = PositionsTotal();
   int total_orders = OrdersTotal();
   
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   
   int myPositions = 0;
   int manualOrders = 0;
   int eaOrders = 0;
   
   double totalProfitMoney = 0;
   double totalBuyLot = 0;  
   double totalSellLot = 0; 
   
   PosData posArr[];
   ArrayResize(posArr, total_positions);
   
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
         
         if(posArr[myPositions].type == POSITION_TYPE_BUY) totalBuyLot += posArr[myPositions].volume;
         else if(posArr[myPositions].type == POSITION_TYPE_SELL) totalSellLot += posArr[myPositions].volume;
            
         myPositions++;
        }
     }
   ArrayResize(posArr, myPositions);
     
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
     
   for(int i = total_orders - 1; i >= 0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(OrderGetString(ORDER_SYMBOL) == _Symbol)
        {
         ulong magic = OrderGetInteger(ORDER_MAGIC);
         if(magic == InpMagic) eaOrders++;
         else manualOrders++;
        }
     }
     
   static int lastTickPositions = -1;
   static int lastTickEaOrders = -1;
   
   if(lastTickPositions != -1 && lastTickEaOrders != -1)
     {
      if(myPositions < lastTickPositions || (eaOrders < lastTickEaOrders && myPositions <= lastTickPositions))
        {
         delayUntil = TimeCurrent() + InpMaxPositions + 3;
        }
     }
   lastTickPositions = myPositions;
   lastTickEaOrders = eaOrders;
      
   // A. Bersihkan Manual Order yang nyangkut jika ada posisi
   if(myPositions > 0 && manualOrders > 0)
     {
      for(int i = OrdersTotal() - 1; i >= 0; i--)
        {
         ulong ticket = OrderGetTicket(i);
         if(OrderGetString(ORDER_SYMBOL) == _Symbol && OrderGetInteger(ORDER_MAGIC) != InpMagic)
            trade.OrderDelete(ticket);
        }
     }
     
   // B. Manajemen Initial Entry (Auto Breakout / Manual)
   if(myPositions == 0)
     {
      if(!InpAutoBreakout)
        {
         if(eaOrders > 0)
           {
            for(int i = OrdersTotal() - 1; i >= 0; i--)
              {
               ulong ticket = OrderGetTicket(i);
               if(OrderGetString(ORDER_SYMBOL) == _Symbol && OrderGetInteger(ORDER_MAGIC) == InpMagic)
                  trade.OrderDelete(ticket);
              }
           }
        }
      else
        {
         // Hitung Level Breakout
         BreakoutLevels levels = GetBreakoutLevels(_Symbol, _Period, InpBreakoutPeriod);
         
         if(levels.isValid)
           {
            double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
            int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
            double buffer_points = (digits == 3 || digits == 5) ? InpBreakoutBuffer * 10 * point : InpBreakoutBuffer * point;
            
            double expectedBuyStop = NormalizeDouble(levels.highestHigh + buffer_points, digits);
            double expectedSellStop = NormalizeDouble(levels.lowestLow - buffer_points, digits);
            
            bool buyStopExists = false;
            bool sellStopExists = false;
            
            // Evaluasi pending order yang ada, hapus jika harganya sudah usang
            for(int i = OrdersTotal() - 1; i >= 0; i--)
              {
               ulong ticket = OrderGetTicket(i);
               if(OrderGetString(ORDER_SYMBOL) == _Symbol && OrderGetInteger(ORDER_MAGIC) == InpMagic)
                 {
                  long type = OrderGetInteger(ORDER_TYPE);
                  double price = OrderGetDouble(ORDER_PRICE_OPEN);
                  
                  if(type == ORDER_TYPE_BUY_STOP)
                    {
                     if(MathAbs(price - expectedBuyStop) > (point * 0.5)) trade.OrderDelete(ticket);
                     else buyStopExists = true;
                    }
                  else if(type == ORDER_TYPE_SELL_STOP)
                    {
                     if(MathAbs(price - expectedSellStop) > (point * 0.5)) trade.OrderDelete(ticket);
                     else sellStopExists = true;
                    }
                 }
              }
              
            // Pasang pending order baru jika area tersebut kosong
            trade.SetExpertMagicNumber(InpMagic);
            if(!buyStopExists) trade.BuyStop(InpInitialLot, expectedBuyStop, _Symbol, 0, 0, 0, 0, "Breakout BuyStop");
            if(!sellStopExists) trade.SellStop(InpInitialLot, expectedSellStop, _Symbol, 0, 0, 0, 0, "Breakout SellStop");
            trade.SetExpertMagicNumber(0);
           }
        }
     }
     
   // C. Manajemen Posisi Aktif & Switching Martingale
   if(myPositions > 0)
     {
      PosData lastPos = posArr[myPositions - 1];
      
      double targetMoneyGlobal = 0;
      if(tickSize > 0) targetMoneyGlobal = (InpTargetPoints * point_value / tickSize) * tickValue * posArr[0].volume;
      
      double targetMoneyBEP = 0;
      double netLot = MathAbs(totalBuyLot - totalSellLot); 
      double currentBEPPoints = (myPositions >= InpBEP2ActivationPos) ? InpTargetBEP2Points : InpTargetBEPPoints;
      if(tickSize > 0) targetMoneyBEP = (currentBEPPoints * point_value / tickSize) * tickValue * netLot;
      
      bool hitTarget = false;
      
      if(myPositions == 1)
        {
         if(InpTargetPoints > 0 && targetMoneyGlobal > 0 && lastPos.profit >= targetMoneyGlobal) hitTarget = true;
        }
      else if(myPositions > 1)
        {
         if(totalProfitMoney >= targetMoneyBEP) hitTarget = true;
        }
        
      if(hitTarget)
        {
         Print("Target profit (", myPositions == 1 ? "Global" : "BEP Points", ") tercapai! Menjalankan Auto Close All...");
         delayUntil = TimeCurrent() + InpMaxPositions + 5; 
         isClosingAll = true; 
         CloseAllPositions();
         return; 
        }
        
      // Bersihkan Pending Order Sisa Breakout / Tidak Valid sebelum Switching
      double stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * point_value;
      double lossDistance = InpLossPoints * point_value;
      if(lossDistance < stopsLevel) lossDistance = stopsLevel;
      
      double expectedSwitchPrice = 0;
      long expectedSwitchType = -1;
      
      if(lastPos.type == POSITION_TYPE_BUY)
        {
         expectedSwitchPrice = NormalizeDouble(lastPos.openPrice - lossDistance, _Digits);
         expectedSwitchType = ORDER_TYPE_SELL_STOP;
        }
      else if(lastPos.type == POSITION_TYPE_SELL)
        {
         expectedSwitchPrice = NormalizeDouble(lastPos.openPrice + lossDistance, _Digits);
         expectedSwitchType = ORDER_TYPE_BUY_STOP;
        }
        
      int validSwitchingOrders = 0;
      for(int i = OrdersTotal() - 1; i >= 0; i--)
        {
         ulong ticket = OrderGetTicket(i);
         if(OrderGetString(ORDER_SYMBOL) == _Symbol && OrderGetInteger(ORDER_MAGIC) == InpMagic)
           {
            long type = OrderGetInteger(ORDER_TYPE);
            double price = OrderGetDouble(ORDER_PRICE_OPEN);
            
            // Jika tipe atau harganya meleset dari perhitungan martingale, buang! (Termasuk sisa breakout)
            if(type == expectedSwitchType && MathAbs(price - expectedSwitchPrice) < point_value) validSwitchingOrders++;
            else trade.OrderDelete(ticket);
           }
        }
      eaOrders = validSwitchingOrders; // Update jumlah order EA murni

      // Pasang Jaring Martingale (Switching)
      if(eaOrders == 0 && myPositions < InpMaxPositions && PositionSelectByTicket(lastPos.ticket))
        {
         if(TimeCurrent() >= delayUntil)
           {
             double newLot = NormalizeVolume(lastPos.volume * InpLotMultiplier);
             trade.SetExpertMagicNumber(InpMagic);
             
             if(expectedSwitchType == ORDER_TYPE_SELL_STOP)
               {
                if(trade.SellStop(newLot, expectedSwitchPrice, _Symbol, 0, 0, 0, 0, "Switching SellStop"))
                   Print("Berhasil memasang jaring SELL STOP di ", expectedSwitchPrice);
               }
             else if(expectedSwitchType == ORDER_TYPE_BUY_STOP)
               {
                if(trade.BuyStop(newLot, expectedSwitchPrice, _Symbol, 0, 0, 0, 0, "Switching BuyStop"))
                   Print("Berhasil memasang jaring BUY STOP di ", expectedSwitchPrice);
               }
               
             trade.SetExpertMagicNumber(0);
           }
        }
     }
     
     // D. Kalkulasi Support & Resistance Visual
     double highest = 0;
     double lowest = 0;
     
     double highArr[], lowArr[];
     ArraySetAsSeries(highArr, true);
     ArraySetAsSeries(lowArr, true);
     
     if(CopyHigh(_Symbol, _Period, 1, InpSnRPeriod, highArr) == InpSnRPeriod &&
        CopyLow(_Symbol, _Period, 1, InpSnRPeriod, lowArr) == InpSnRPeriod)
       {
        int highestIdx = ArrayMaximum(highArr);
        int lowestIdx = ArrayMinimum(lowArr);
        
        if(highestIdx >= 0 && lowestIdx >= 0)
          {
           highest = highArr[highestIdx];
           lowest = lowArr[lowestIdx];
           
           if(ObjectFind(0, "ResistanceLine") < 0)
             {
              ObjectCreate(0, "ResistanceLine", OBJ_HLINE, 0, 0, highest);
              ObjectSetInteger(0, "ResistanceLine", OBJPROP_COLOR, clrRed);
              ObjectSetInteger(0, "ResistanceLine", OBJPROP_STYLE, STYLE_DASH);
              ObjectSetInteger(0, "ResistanceLine", OBJPROP_WIDTH, 1);
             }
           else ObjectSetDouble(0, "ResistanceLine", OBJPROP_PRICE, highest);
             
           if(ObjectFind(0, "SupportLine") < 0)
             {
              ObjectCreate(0, "SupportLine", OBJ_HLINE, 0, 0, lowest);
              ObjectSetInteger(0, "SupportLine", OBJPROP_COLOR, clrLime);
              ObjectSetInteger(0, "SupportLine", OBJPROP_STYLE, STYLE_DASH);
              ObjectSetInteger(0, "SupportLine", OBJPROP_WIDTH, 1);
             }
           else ObjectSetDouble(0, "SupportLine", OBJPROP_PRICE, lowest);
          }
       }
       
     // E. Dashboard Visual
     string tpStatus = "N/A";
     double targetDisplayMoney = 0;
     
     if(myPositions == 1) 
       {
        tpStatus = "Target Awal (" + DoubleToString(InpTargetPoints, 0) + " Points)";
        if(tickSize > 0) targetDisplayMoney = (InpTargetPoints * point_value / tickSize) * tickValue * posArr[0].volume;
       }
     else if(myPositions > 1) 
       {
        double currentBEPPoints = (myPositions >= InpBEP2ActivationPos) ? InpTargetBEP2Points : InpTargetBEPPoints;
        string bepLabel = (myPositions >= InpBEP2ActivationPos) ? "BEP 2 Close All (" : "BEP 1 Close All (";
        tpStatus = bepLabel + DoubleToString(currentBEPPoints, 0) + " Points)";
        
        double netLot = MathAbs(totalBuyLot - totalSellLot);
        if(tickSize > 0) targetDisplayMoney = (currentBEPPoints * point_value / tickSize) * tickValue * netLot;
       }
     
     string modeText = InpAutoBreakout ? "AUTO BREAKOUT" : "MANUAL OPEN";
     string runStatus = (myPositions > 0) ? "RUNNING (Manage Positions)" : (InpAutoBreakout ? "STANDBY (Waiting Breakout)" : "STANDBY (Waiting Manual)");
     
     string commentText = "\n== PENDING SWITCH MARTINGALE ==\n\n" +
                          "Mode Entry     : " + modeText + "\n" +
                          "Status Robot   : " + runStatus + "\n" +
                          "Posisi Aktif   : " + IntegerToString(myPositions) + " / " + IntegerToString(InpMaxPositions) + "\n" +
                          "TP Mode        : " + tpStatus + "\n\n" +
                          "Total Profit   : $" + DoubleToString(totalProfitMoney, 2) + "\n" +
                          "Harus Capai TP : $" + DoubleToString(targetDisplayMoney, 2);
     
     Comment(commentText);
  }
//+------------------------------------------------------------------+
