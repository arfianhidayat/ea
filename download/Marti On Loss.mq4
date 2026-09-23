//+------------------------------------------------------------------+
//|                                                Marti On Loss.mq4 |
//|                                        Copyright 2025, AutoBotFX |
//|                                            https://robotop.my.id |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, AutoBotFX"
#property link      "https://robotop.my.id"
#property version   "1.00"
#property strict
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

/*
   https://youtu.be/1JIiXavDm2M
   Kalah Sekali, Balik Dua Kali Lebih Cepat 
   
*/

input    double   inLotSize   = 0.01;  //LotSize
input    double   inMartiLot  = 2.0;   //Multiply LotSize
input    int      inStopLoss  = 100;    //Stop Loss
input    int      inTakeProfit= 100;    //Take Profit

struct sDtOrder{
   int total;
   double tFloating;
   
   void sDtOrder(){
      total = 0;
      tFloating = 0.0;
   }
};



string gPair = "";

int OnInit()
{
   gPair = Symbol();
   return(INIT_SUCCEEDED);
}

struct sDtPrev{
   int total;
   double tFloating, lastLot;
   
   void sDtPrev(){
      total = 0;
      tFloating = 0.0;
      lastLot = 0.0;
   };
};

void OnTick()
{
   bool isNewCS = newCandle();
   int signal = -1;
   if (isNewCS){
      signal = getSignal();
   }
   
   //kumpulkan data total posisi dan floating
   sDtOrder data[2];
   int tOrders = OrdersTotal();
   for (int i=tOrders-1; i>=0; i--){
      if (OrderSelect(i, SELECT_BY_POS, MODE_TRADES) ){
         if (OrderSymbol() == gPair){
            int type = OrderType();
            if (type >= 0 && type <= 1){
               data[type].total++;
               data[type].tFloating += OrderProfit() + OrderCommission() + OrderSwap();
            }
         }
      }
   }
   
   static sDtPrev dataPrev[2];
   
   if (dataPrev[0].total <= data[0].total){
      dataPrev[0].total = data[0].total;
      dataPrev[0].tFloating = data[0].tFloating;
   }
   if (dataPrev[1].total <= data[1].total){
      dataPrev[1].total = data[1].total;
      dataPrev[1].tFloating = data[1].tFloating;
   }
   
   if (signal>= 0 && signal<=1 && data[signal].total == 0){
      double lotSize = 0.0;
      lotSize  = inLotSize;
      
      if (dataPrev[signal].tFloating < 0){
         lotSize = dataPrev[signal].lastLot * inMartiLot;
      }else{
         lotSize = inLotSize;
      }
      
      
      fOpenOrder(signal, lotSize);
      
      dataPrev[signal].total = 0;
      dataPrev[signal].tFloating = 0;
      dataPrev[signal].lastLot = lotSize;
      
   }
   
   
}

int getSignal(){
   int signal = -1;
   
   if (iOpen(gPair, 0, 1) < iClose(gPair, 0, 1) ){
      signal = OP_BUY;
   }else{
      signal = OP_SELL;
   }
   
   return (signal);
}

void fOpenOrder(int type, double lotSize){
   double sl = 0.0, tp = 0.0;
   if (type == 0){
      sl = Ask - (inStopLoss * Point() );
      tp = Ask + (inTakeProfit * Point() );
      if (OrderSend(gPair, OP_BUY, lotSize, Ask, 3, sl, tp, "AutoBotFx", 0, 0, clrBlue) <= 0){
         Print ("Gagal open");
      }
   }else if (type == 1){
      sl = Bid + (inStopLoss * Point() );
      tp = Bid - (inTakeProfit * Point() );
      if (OrderSend(gPair, OP_SELL, lotSize, Bid, 3, sl, tp, "AutoBotFx", 0, 0, clrRed) <= 0){
         Print ("Gagal open");
      }
   }
}

bool newCandle(){
   static datetime wkt = iTime(gPair, 0, 0);
   
   if (wkt < iTime(gPair, 0, 0) ){
      wkt = iTime(gPair, 0, 0);
      return (true);
   }
   return (false);
}


   
   
   
