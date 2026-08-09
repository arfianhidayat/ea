//+------------------------------------------------------------------+
//|                                         switching martingle.mq5  |
//|                                           Copyright 2026, Arfian |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Arfian"
#property link      ""
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

//--- Input Parameters
input double InpLossPoints = 500.0;        // Jarak Loss Switch/Martingale (Points)
input double InpTargetPoints = 500.0;      // Target Profit Posisi 1/Awal (Points)
input double InpTargetBEPPoints = 300.0;   // Target Profit setelah BEP 1 (Points)
input double InpTargetBEP2Points = 150.0;  // Target Profit setelah BEP 2 (Points)
input int InpBEP2ActivationPos = 5;        // Aktifkan BEP 2 mulai posisi ke-
input double InpLotMultiplier = 2.0;       // Pengali Lot Martingale
input int InpMaxPositions = 8;             // Batas Maksimal Posisi Terbuka
input int InpSnRPeriod = 50;               // Periode Candle Support & Resistance
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
//| Asynchronous Helper Functions                                    |
//+------------------------------------------------------------------+
void ClosePositionAsync(ulong ticket)
  {
   if(!PositionSelectByTicket(ticket)) return;
   
   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);
   ZeroMemory(result);
   
   request.action    = TRADE_ACTION_DEAL;
   request.position  = ticket;
   request.symbol    = PositionGetString(POSITION_SYMBOL);
   request.volume    = PositionGetDouble(POSITION_VOLUME);
   request.deviation = 50;
   
   if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
     {
      request.price = SymbolInfoDouble(request.symbol, SYMBOL_BID);
      request.type  = ORDER_TYPE_SELL;
     }
   else
     {
      request.price = SymbolInfoDouble(request.symbol, SYMBOL_ASK);
      request.type  = ORDER_TYPE_BUY;
     }
     
   if(!OrderSendAsync(request, result))
      Print("Async close error: ", GetLastError());
  }

void DeleteOrderAsync(ulong ticket)
  {
   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);
   ZeroMemory(result);
   
   request.action = TRADE_ACTION_REMOVE;
   request.order  = ticket;
   
   if(!OrderSendAsync(request, result))
      Print("Async delete error: ", GetLastError());
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
   ObjectsDeleteAll(0, "lbl_"); 
   ObjectDelete(0, "ResistanceLine");
   ObjectDelete(0, "SupportLine");
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   // --- Cek status Karantina (Sapu Bersih Paksa) ---
   if(isClosingAll)
     {
      int sisaOrder = 0;
      int sisaPosisi = 0;
      
      for(int i = OrdersTotal() - 1; i >= 0; i--)
        {
         ulong ticket = OrderGetTicket(i);
         if(OrderGetString(ORDER_SYMBOL) == _Symbol && OrderGetInteger(ORDER_MAGIC) == InpMagic)
           {
            sisaOrder++;
            DeleteOrderAsync(ticket);
           }
        }
        
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong ticket = PositionGetTicket(i);
         if(PositionGetString(POSITION_SYMBOL) == _Symbol)
           {
            sisaPosisi++;
            ClosePositionAsync(ticket);
           }
        }
        
      if(sisaOrder == 0 && sisaPosisi == 0)
        {
         isClosingAll = false;
         Print("Karantina Close All selesai 100%. Robot kembali Standby.");
        }
      else
        {
         // JANGAN lanjut menjalankan strategi ke bawah jika belum bersih 100%
         return; 
        }
     }
     
   int total_positions = PositionsTotal();
   int total_orders = OrdersTotal();
   
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   
   int myPositions = 0;
   int manualOrders = 0;
   int eaOrders = 0;
   
   double totalProfitMoney = 0;
   double totalBuyLot = 0;  // Untuk menghitung total volume Buy
   double totalSellLot = 0; // Untuk menghitung total volume Sell
   
   PosData posArr[];
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
         
         // Akumulasi Volume berdasarkan arah untuk perhitungan Net Lot BEP
         if(posArr[myPositions].type == POSITION_TYPE_BUY)
            totalBuyLot += posArr[myPositions].volume;
         else if(posArr[myPositions].type == POSITION_TYPE_SELL)
            totalSellLot += posArr[myPositions].volume;
            
         myPositions++;
        }
     }
   ArrayResize(posArr, myPositions);
     
   // Urutkan posisi berdasarkan waktu Buka (lama ke terbaru)
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
     
   // 2. Kumpulkan data pending order
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
     
   // Cek deteksi manual close
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
      
   // --- LOGIKA UTAMA ---
   
   // A. Bersihkan Manual Order yang nyangkut jika ada posisi
   if(myPositions > 0 && manualOrders > 0)
     {
      for(int i = OrdersTotal() - 1; i >= 0; i--)
        {
         ulong ticket = OrderGetTicket(i);
         if(OrderGetString(ORDER_SYMBOL) == _Symbol && OrderGetInteger(ORDER_MAGIC) != InpMagic)
           {
            if(!trade.OrderDelete(ticket))
               Print("Error delete manual order: ", GetLastError());
           }
        }
     }
     
   // B. Bersihkan Pending Order EA jika posisi bersih
   if(myPositions == 0 && eaOrders > 0)
     {
      for(int i = OrdersTotal() - 1; i >= 0; i--)
        {
         ulong ticket = OrderGetTicket(i);
         if(OrderGetString(ORDER_SYMBOL) == _Symbol && OrderGetInteger(ORDER_MAGIC) == InpMagic)
           {
            if(!trade.OrderDelete(ticket))
               Print("Error delete EA order: ", GetLastError());
           }
        }
     }
     
   // C. Manajemen Posisi Aktif & Switching
   if(myPositions > 0)
     {
      PosData lastPos = posArr[myPositions - 1];
      
      // Kalkulasi Target Uang untuk posisi Single (Posisi Pertama)
      double targetMoneyGlobal = 0;
      if(tickSize > 0) targetMoneyGlobal = (InpTargetPoints * point_value / tickSize) * tickValue * posArr[0].volume;
      
      // Kalkulasi Target Uang BEP (Break Even + Points) untuk posisi > 1
      double targetMoneyBEP = 0;
      double netLot = MathAbs(totalBuyLot - totalSellLot); // Cari selisih murni (volume dominan)
      double currentBEPPoints = (myPositions >= InpBEP2ActivationPos) ? InpTargetBEP2Points : InpTargetBEPPoints;
      if(tickSize > 0) targetMoneyBEP = (currentBEPPoints * point_value / tickSize) * tickValue * netLot;
      
      bool hitTarget = false;
      
      // Logika Penentuan Target (Single vs BEP Point)
      if(myPositions == 1)
        {
         if(InpTargetPoints > 0 && targetMoneyGlobal > 0 && lastPos.profit >= targetMoneyGlobal)
            hitTarget = true;
        }
      else if(myPositions > 1)
        {
         // Jika profit terapung melebihi target BEP Money, eksekusi sapu bersih
         if(totalProfitMoney >= targetMoneyBEP)
            hitTarget = true;
        }
        
      // Eksekusi Sapu Bersih (Close All) jika target tercapai
      if(hitTarget)
        {
         Print("Target profit (", myPositions == 1 ? "Global" : "BEP Points", ") tercapai! Menjalankan Auto Close All...");
         
         delayUntil = TimeCurrent() + InpMaxPositions + 5; 
         isClosingAll = true; // Aktifkan mode karantina paksa
         
         // Batal jaring pending secara Asinkron
         for(int i = OrdersTotal() - 1; i >= 0; i--)
           {
            ulong ticket = OrderGetTicket(i);
             if(OrderGetString(ORDER_SYMBOL) == _Symbol && OrderGetInteger(ORDER_MAGIC) == InpMagic)
               {
                DeleteOrderAsync(ticket);
               }
           }
           
         // Tutup posisi aktif secara Asinkron
         for(int i = PositionsTotal() - 1; i >= 0; i--)
           {
            ulong ticket = PositionGetTicket(i);
             if(PositionGetString(POSITION_SYMBOL) == _Symbol)
               {
                ClosePositionAsync(ticket);
               }
           }
           
         return; 
        }
        
      // Pasang Jaring Martingale (Switching)
      if(eaOrders == 0 && myPositions < InpMaxPositions && PositionSelectByTicket(lastPos.ticket))
        {
         if(TimeCurrent() >= delayUntil)
           {
             double newLot = NormalizeVolume(lastPos.volume * InpLotMultiplier);
             double switchPrice = 0;
             
             // Pastikan jarak aman Stop Level
             double stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * point_value;
             double lossDistance = InpLossPoints * point_value;
             if(lossDistance < stopsLevel)
                lossDistance = stopsLevel;
             
             trade.SetExpertMagicNumber(InpMagic);
             
             if(lastPos.type == POSITION_TYPE_BUY)
               {
                switchPrice = NormalizeDouble(lastPos.openPrice - lossDistance, _Digits);
                if(trade.SellStop(newLot, switchPrice, _Symbol, 0, 0, 0, 0, "Switching SellStop"))
                   Print("Berhasil memasang jaring SELL STOP di ", switchPrice);
                else
                   Print("Gagal SellStop: ", GetLastError());
               }
             else if(lastPos.type == POSITION_TYPE_SELL)
               {
                switchPrice = NormalizeDouble(lastPos.openPrice + lossDistance, _Digits);
                if(trade.BuyStop(newLot, switchPrice, _Symbol, 0, 0, 0, 0, "Switching BuyStop"))
                   Print("Berhasil memasang jaring BUY STOP di ", switchPrice);
                else
                   Print("Gagal BuyStop: ", GetLastError());
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
     
     string commentText = "\n== PENDING SWITCH MARTINGALE ==\n\n" +
                          "Status Robot   : " + (myPositions > 0 ? "RUNNING (Manage Positions)" : "STANDBY (Waiting Manual)") + "\n" +
                          "Posisi Aktif   : " + IntegerToString(myPositions) + " / " + IntegerToString(InpMaxPositions) + "\n" +
                          "TP Mode        : " + tpStatus + "\n\n" +
                          "Total Profit   : $" + DoubleToString(totalProfitMoney, 2) + "\n" +
                          "Harus Capai TP : $" + DoubleToString(targetDisplayMoney, 2);
     
     Comment(commentText);
  }
//+------------------------------------------------------------------+