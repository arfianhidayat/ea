//+------------------------------------------------------------------+
//|                                                 EASwitchFibo.mq5 |
//|                                        Copyright 2025, AutoBotFx |
//|                                        https://www.Robotop.my.id |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, AutoBotFx"
#property link      "https://www.Robotop.my.id"
#property version   "1.00"

/*
   
   Materi edukasi untuk media YouTube
   Channel : AutoBotFX ( @AutoBotFx88 )
   
   Tujuan :
   untuk edukasi pembuatan EA, dan bukan saran untuk digunakan dalam trading.
   
   Group edukasi codeMQL:
   t.me/codeMQL
   
   Group free EA:
   t.me/freeEA_tradeXpert
   
   NB:
   Jika terdapat kesalahan / bugs pada contoh code ini, 
   silakan tinggalkan pesan di comment agar kami bisa bantu revisi.
   
*/

input    int   inStopLoss     = 100;      //StopLoss
input    int   inTakeProfit   = 100;      //TakeProfit
input    double inMultiply    = 2.0;      //Multiply lotsize

#include <Trade/Trade.mqh>
#include <Trade/SymbolInfo.mqh>

CTrade oTrade;
CSymbolInfo oSymbol;

double P_Point = 0.0;
int P_Digit = 0;

int OnInit()
{
   oSymbol.Name(Symbol());
   oSymbol.Refresh();
   oSymbol.RefreshRates();
   
   P_Digit = (int) SymbolInfoInteger(oSymbol.Name(), SYMBOL_DIGITS);
   P_Point = SymbolInfoDouble(oSymbol.Name(), SYMBOL_POINT);
   if (P_Digit % 2 == 1){
      P_Point *= 10;
   }
   if (StringFind(oSymbol.Name() , "XAUUSD", 0) >= 0){
      P_Point *= 10;
   }
   
   
   return(INIT_SUCCEEDED);
}

void OnTick()
{
   
   transaksi();
   setTPSL();

}

struct sDtPos{
   int total;
   double hargaOP;
   double lot;
   
   void sDtPos(){
      total = 0;
      hargaOP = 0.0;
      lot = 0.0;
   }
};

void getUpdatePos(sDtPos &dtPos[]){
   
   int tPos = PositionsTotal();
   for (int i=tPos-1; i>=0; i--){
      ulong ticket = PositionGetTicket(i);
      if (ticket > 0){
         string pair = PositionGetString(POSITION_SYMBOL);
         if (pair == oSymbol.Name() ){
            int type = (int) PositionGetInteger(POSITION_TYPE);
            dtPos[type].total++;
            dtPos[type].hargaOP = PositionGetDouble(POSITION_PRICE_OPEN);
            dtPos[type].lot     = PositionGetDouble(POSITION_VOLUME);
         }
      }
   }
}

void getUpdateOrders(int &dtArr[]){
   int tOrder = OrdersTotal();
   for (int i=tOrder-1; i>=0; i--){
      ulong ticket = OrderGetTicket(i);
      if (ticket > 0){
         string pair = OrderGetString(ORDER_SYMBOL);
         if (pair == oSymbol.Name() ){
            int type = (int) OrderGetInteger(ORDER_TYPE);
            dtArr[type-2]++;
         }
      }
   }
}

void transaksi(){
   //0: buy
   //1: sell
   //2: buy limit
   //3: sell limit
   //4: buy stop
   //5: sell stop
   
   sDtPos dtPos[2];
   getUpdatePos(dtPos);
   
   int arrOrders[4];
   getUpdateOrders(arrOrders);
   
   //code sementara untuk testing, karena seharusnya open secara manual.
   if (dtPos[0].total == 0 && dtPos[1].total == 0 ){
      oTrade.Buy(0.01, oSymbol.Name(), 0, 0, 0, "");
   }
   //===============
   
   
   static int tOpen = 0;
   static double lotInitial = 0;
   if (tOpen == 0 && (dtPos[0].total == 1 || dtPos[1].total == 1 ) ){
      tOpen = 1;
      if (dtPos[0].total == 1) lotInitial  = dtPos[0].lot;
      else if (dtPos[1].total == 1) lotInitial  = dtPos[1].lot;
   }
   
   if (dtPos[0].total == 0 && dtPos[1].total == 0 ){
      tOpen = 0;
      if (arrOrders[ORDER_TYPE_SELL_STOP-2] > 0){
         //delete pending Order
         fDeletePO(ORDER_TYPE_SELL_STOP);
      }
      if (arrOrders[ORDER_TYPE_BUY_STOP-2] > 0){
         fDeletePO(ORDER_TYPE_BUY_STOP);
      }
   }
   
   
   double lot = 0.0;
   double hargaPO = 0.0, sl = 0.0, tp = 0.0;
   
   if (dtPos[0].total > 0 && arrOrders[ORDER_TYPE_SELL_STOP-2] == 0){
      hargaPO = dtPos[0].hargaOP - getHargaPips(inStopLoss);
      sl    = hargaPO + getHargaPips(inStopLoss);
      tp    = hargaPO - getHargaPips(inTakeProfit);
      
      //lot   = dtPos[0].lot * inMultiply;
      //ubah lot dengan deret fibo
      
      lot   = lotInitial * nilaiFibo(tOpen);
      
      if (!oTrade.SellStop(lot, hargaPO, oSymbol.Name(), sl, tp, 0, 0, "")){
         Print ("Gagal open sell stop");
      }else{
         //berhasil Open Pending Order
         tOpen++;
      }
      
      return;
      
   }
   
   if (dtPos[1].total > 0 && arrOrders[ORDER_TYPE_BUY_STOP-2] == 0){
      hargaPO = dtPos[1].hargaOP + getHargaPips(inStopLoss);
      sl    = hargaPO - getHargaPips(inStopLoss);
      tp    = hargaPO + getHargaPips(inTakeProfit);
      
      //lot   = dtPos[1].lot * inMultiply;
      lot   = lotInitial * nilaiFibo(tOpen);
      
      if (!oTrade.BuyStop(lot, hargaPO, oSymbol.Name(), sl, tp, 0, 0, "")){
         Print ("Gagal open sell stop");
      }else{
         //berhasil Open Pending Order
         tOpen++;
      }
      
      return;
      
   }
   
   
}

void setTPSL(){
   int tPos = PositionsTotal();
   for (int i=tPos-1; i>=0; i--){
      ulong ticket = PositionGetTicket(i);
      if (ticket > 0){
         string pair = PositionGetString(POSITION_SYMBOL);
         if (pair == oSymbol.Name() ){
            int type = (int) PositionGetInteger(POSITION_TYPE);
            double hargaOp = PositionGetDouble(POSITION_PRICE_OPEN);
            double tp = 0.0, sl = 0.0;
            
            if (type == POSITION_TYPE_BUY){
               tp = (inTakeProfit > 0)? hargaOp + getHargaPips(inTakeProfit) : 0.0;
               sl = (inStopLoss > 0)? hargaOp - getHargaPips(inStopLoss) : 0.0;
               
            }else if (type == POSITION_TYPE_SELL){
               tp = (inTakeProfit > 0)? hargaOp - getHargaPips(inTakeProfit) : 0.0;
               sl = (inStopLoss > 0)? hargaOp + getHargaPips(inStopLoss) : 0.0;
            }
            
            tp = NormalizeDouble(tp, oSymbol.Digits() );
            sl = NormalizeDouble(sl, oSymbol.Digits() );
            
            if (tp != PositionGetDouble(POSITION_TP) || sl != PositionGetDouble(POSITION_SL) ){
               if (!oTrade.PositionModify(ticket, sl, tp)){
                  Print ("Gagal set TP/SL");
               }
            }
            
         }
      }
   }
}


void fDeletePO(int typeClose){
   int tOrder = OrdersTotal();
   for (int i=tOrder-1; i>=0; i--){
      ulong ticket = OrderGetTicket(i);
      if (ticket > 0){
         string pair = OrderGetString(ORDER_SYMBOL);
         if (pair == oSymbol.Name() ){
            int type = (int) OrderGetInteger(ORDER_TYPE);
            if (type == typeClose){
               oTrade.OrderDelete(ticket);
            }
         }
      }
   }
}   
   

double getHargaPips(int jarak){
   return (jarak * P_Point);
}

//bool isNewCandle(){
//   static datetime wktCandle = iTime(Symbol(), PERIOD_CURRENT, 0);
//   if (wktCandle < iTime(Symbol(), PERIOD_CURRENT, 0) ){
//      wktCandle = iTime(Symbol(), PERIOD_CURRENT, 0);
//      return (true);
//   }
//   return (false);
//}

int nilaiFibo(int n){
   int fibo[] = {1, 1, 2, 3, 5, 8, 13, 21, 34, 55, 89, 144, 233, 377, 610};
   return (fibo[n]);
   
//   ulong result[];
//   if(n < 1) return 0;
//
//   ArrayResize(result, n);
//
//   result[0] = 0;
//   if(n == 1) return 1;
//
//   result[1] = 1;
//
//   for(int i = 2; i < n; i++)
//      result[i] = result[i-1] + result[i-2];
//
//   return n;
   
}
