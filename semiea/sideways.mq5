//+------------------------------------------------------------------+
//|                                                     Sideways.mq5 |
//|                                        Copyright 2026, Antigravity |
//|                                       https://www.google.com     |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Antigravity"
#property link      "https://www.google.com"
#property version   "1.00"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>


input group "--- General Settings ---"
input ulong    InpMagicNumber          = 123456;     // Magic Number (0 for manual trades)
input double   InpMaxSpreadPips        = 5.0;        // Max Spread (pips)

input group "--- Averaging & Martingale ---"
input double   InpAveragingPips        = 10.0;       // Jarak Minimal Averaging (pips)
input double   InpMartingaleMultiplier = 2.0;          // Pengali Lot (Martingale)
input int      InpMaxOpenPositions     = 999;         // Maksimal Posisi Terbuka (Layer)

input group "--- Target Profit (BEP) ---"
input double   InpTP_Normal_Pips       = 10.0;       // TP jika Posisi < Start BEP 1 (pips)
input int      InpLayerBEP1_Start      = 2;          // Mulai Level BEP 1 (Posisi ke-)
input double   InpTP_BEP1_Pips         = 5.0;       // Target Profit BEP 1 (pips)
input int      InpLayerBEP2_Start      = 5;          // Mulai Level BEP 2 (Posisi ke-)
input double   InpTP_BEP2_Pips         = 3.0;        // Target Profit BEP 2 (pips)

CTrade         m_trade;
CSymbolInfo    m_symbol;
CPositionInfo  m_position;


//+------------------------------------------------------------------+
//| Helper function to safely normalize lot size                     |
//+------------------------------------------------------------------+
double NormalizeVolume(double vol)
  {
   double step = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
   double minVol = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
   double maxVol = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
   
   if(step <= 0) step = 0.01;
   
   int stepDigits = 0;
   if(step < 0.1) stepDigits = 2;
   else if(step < 1.0) stepDigits = 1;
   
   double normVol = MathRound(vol / step) * step;
   normVol = NormalizeDouble(normVol, stepDigits);
   
   if(normVol < minVol) normVol = minVol;
   if(normVol > maxVol) normVol = maxVol;
   return normVol;
  }

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   if(!m_symbol.Name(Symbol()))
      return(INIT_FAILED);
   
   m_trade.SetExpertMagicNumber(InpMagicNumber);
   m_trade.SetDeviationInPoints(10);
   
   // Auto-detect supported order filling type
   uint filling = (uint)SymbolInfoInteger(Symbol(), SYMBOL_FILLING_MODE);
   if((filling & SYMBOL_FILLING_FOK) != 0)
      m_trade.SetTypeFilling(ORDER_FILLING_FOK);
   else if((filling & SYMBOL_FILLING_IOC) != 0)
      m_trade.SetTypeFilling(ORDER_FILLING_IOC);
   else
      m_trade.SetTypeFilling(ORDER_FILLING_RETURN);
   
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   m_symbol.RefreshRates();
   
   // Variables to store positions info
   int countBuy = 0, countSell = 0;
   double totalBuyLot = 0, totalSellLot = 0;
   double avgBuyPrice = 0, avgSellPrice = 0;
   double lastBuyPrice = 0, lastSellPrice = 0;
   double lastBuyLot = 0, lastSellLot = 0;
   double totalBuyProfit = 0, totalSellProfit = 0;
   
   double sumBuyPriceLot = 0;
   double sumSellPriceLot = 0;

   // Analyze open positions
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(m_position.SelectByIndex(i))
        {
         // Allow Magic 0 if InpMagicNumber == 0 or exact magic match
         if(m_position.Symbol() == Symbol() && (InpMagicNumber == 0 || m_position.Magic() == InpMagicNumber))
           {
            double price = m_position.PriceOpen();
            double volume = m_position.Volume();
            double profit = m_position.Profit() + m_position.Swap() + m_position.Commission();
            
            if(m_position.PositionType() == POSITION_TYPE_BUY)
              {
               countBuy++;
               totalBuyLot += volume;
               sumBuyPriceLot += price * volume;
               totalBuyProfit += profit;
               
               // Find lowest price for buy averaging
               if(lastBuyPrice == 0 || price <= lastBuyPrice)
                 {
                  lastBuyPrice = price;
                  lastBuyLot = volume;
                 }
              }
            else if(m_position.PositionType() == POSITION_TYPE_SELL)
              {
               countSell++;
               totalSellLot += volume;
               sumSellPriceLot += price * volume;
               totalSellProfit += profit;
               
               // Find highest price for sell averaging
               if(lastSellPrice == 0 || price >= lastSellPrice)
                 {
                  lastSellPrice = price;
                  lastSellLot = volume;
                 }
              }
           }
        }
     }
     
   if(countBuy > 0)
      avgBuyPrice = sumBuyPriceLot / totalBuyLot;
   if(countSell > 0)
      avgSellPrice = sumSellPriceLot / totalSellLot;
      
   double pipSize = m_symbol.Point();
   if(m_symbol.Digits() == 3 || m_symbol.Digits() == 5)
      pipSize *= 10.0;
       
   // Process Close based on Target Profit
   ManageClose(countBuy, countSell, avgBuyPrice, avgSellPrice, pipSize);
   
   // Process Averaging
   double spreadPips = (m_symbol.Ask() - m_symbol.Bid()) / pipSize;
   if(spreadPips <= InpMaxSpreadPips)
     {
      if(countBuy > 0)
         ProcessAveraging(POSITION_TYPE_BUY, lastBuyPrice, lastBuyLot, pipSize, countBuy);
      if(countSell > 0)
         ProcessAveraging(POSITION_TYPE_SELL, lastSellPrice, lastSellLot, pipSize, countSell);
     }
   else
     {
      static datetime lastSpreadWarn = 0;
      if(TimeCurrent() - lastSpreadWarn >= 60)
        {
         PrintFormat("Peringatan: Spread saat ini (%.1f pips) melebihi InpMaxSpreadPips (%.1f pips). Averaging ditunda.", spreadPips, InpMaxSpreadPips);
         lastSpreadWarn = TimeCurrent();
        }
     }
  }

//+------------------------------------------------------------------+
//| Manage closing positions based on dynamic BEP Target             |
//+------------------------------------------------------------------+
void ManageClose(int countBuy, int countSell, double avgBuyPrice, double avgSellPrice, double pipSize)
  {
   // Check BUY
   if(countBuy > 0)
     {
      double currentPrice = m_symbol.Bid();
      double targetPrice = 0;
      
      if(countBuy >= InpLayerBEP2_Start)
         targetPrice = avgBuyPrice + (InpTP_BEP2_Pips * pipSize);
      else if(countBuy >= InpLayerBEP1_Start)
         targetPrice = avgBuyPrice + (InpTP_BEP1_Pips * pipSize);
      else
         targetPrice = avgBuyPrice + (InpTP_Normal_Pips * pipSize);
         
      if(currentPrice >= targetPrice)
         CloseAll(POSITION_TYPE_BUY);
     }
     
   // Check SELL
   if(countSell > 0)
     {
      double currentPrice = m_symbol.Ask();
      double targetPrice = 0;
      
      if(countSell >= InpLayerBEP2_Start)
         targetPrice = avgSellPrice - (InpTP_BEP2_Pips * pipSize);
      else if(countSell >= InpLayerBEP1_Start)
         targetPrice = avgSellPrice - (InpTP_BEP1_Pips * pipSize);
      else
         targetPrice = avgSellPrice - (InpTP_Normal_Pips * pipSize);
         
      if(currentPrice <= targetPrice && targetPrice > 0)
         CloseAll(POSITION_TYPE_SELL);
     }
  }

//+------------------------------------------------------------------+
//| Process Averaging logic                                          |
//+------------------------------------------------------------------+
void ProcessAveraging(ENUM_POSITION_TYPE type, double lastPrice, double lastLot, double pipSize, int currentCount)
  {
   if(currentCount >= InpMaxOpenPositions)
      return;
      
   double currentPrice = (type == POSITION_TYPE_BUY) ? m_symbol.Ask() : m_symbol.Bid();
   
   // Check Distance
   double distance = 0;
   if(type == POSITION_TYPE_BUY)
      distance = (lastPrice - currentPrice) / pipSize;
   else
      distance = (currentPrice - lastPrice) / pipSize;
      
   if(distance >= InpAveragingPips)
     {
      // Calculate normalized volume
      double newLot = NormalizeVolume(lastLot * InpMartingaleMultiplier);
      
      string comment = StringFormat("Averaging %s #%d", (type == POSITION_TYPE_BUY ? "Buy" : "Sell"), currentCount + 1);
      
      bool res = false;
      if(type == POSITION_TYPE_BUY)
         res = m_trade.Buy(newLot, Symbol(), 0, 0, 0, comment);
      else
         res = m_trade.Sell(newLot, Symbol(), 0, 0, 0, comment);
         
      if(res)
        {
         PrintFormat("Berhasil membuka %s! Lot: %.2f | Distance: %.1f pips | Price: %s", 
                     comment, newLot, distance, DoubleToString(currentPrice, m_symbol.Digits()));
        }
      else
        {
         PrintFormat("GAGAL membuka %s! Lot: %.2f | Retcode: %d | Desc: %s",
                     comment, newLot, m_trade.ResultRetcode(), m_trade.ResultRetcodeDescription());
        }
     }
  }


//+------------------------------------------------------------------+
//| Close all positions of a specific type                           |
//+------------------------------------------------------------------+
void CloseAll(ENUM_POSITION_TYPE type)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(m_position.SelectByIndex(i))
        {
         if(m_position.Symbol() == Symbol() && (InpMagicNumber == 0 || m_position.Magic() == InpMagicNumber))
           {
            if(m_position.PositionType() == type)
              {
               if(!m_trade.PositionClose(m_position.Ticket()))
                 {
                  PrintFormat("Gagal menutup posisi ticket #%s! Error: %d - %s",
                              (string)m_position.Ticket(), m_trade.ResultRetcode(), m_trade.ResultRetcodeDescription());
                 }
              }
           }
        }
     }
  }
//+------------------------------------------------------------------+
