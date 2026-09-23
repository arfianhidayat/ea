//+------------------------------------------------------------------+
//|                                                          BEP.mq5 |
//|                                        Copyright 2025, AutoBotFx |
//|                                        https://www.Robotop.my.id |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, AutoBotFx"
#property link      "https://www.Robotop.my.id"
#property version   "1.00"
/*
   Belajar Code MQL: t.me/codeMQL
   Group Free EA : t.me/FreeEA_TradeXpert
   
*/
#include <Trade\Trade.mqh>
CTrade oTrade;

#include <Trade\SymbolInfo.mqh>
CSymbolInfo oSym;

input       int         IN_TrailingStart      = 300;      //Trailing Start

struct sDtPos{
   int total;
   double bep;
   double tLot;
   double tPriceWeight;
   void sDtPos(){
      total = 0;
      tLot = 0.0;
      tPriceWeight = 0.0;
      bep = 0.0;
   }
};

void updateInfoTrade(sDtPos &dtPos[]){
   int tPos = PositionsTotal();
   for (int i=tPos-1; i>=0; i--){
      ulong ticket = PositionGetTicket(i);
      if (ticket > 0){
         int type = (int) PositionGetInteger(POSITION_TYPE);
         dtPos[type].total++; // a = a + 1 =>> a++  >> a += 1;
         dtPos[type].tLot += PositionGetDouble(POSITION_VOLUME);
         dtPos[type].tPriceWeight += PositionGetDouble(POSITION_VOLUME) * PositionGetDouble(POSITION_PRICE_OPEN);
      }
   }
   
   dtPos[0].bep = dtPos[0].tPriceWeight / dtPos[0].tLot;
   dtPos[1].bep = dtPos[1].tPriceWeight / dtPos[1].tLot;
   
}

void SetTrailingStop(){
   string pair = oSym.Name(); // Symbol();
   double Bid = oSym.Bid(); // SymbolInfoDouble(pair, SYMBOL_BID);
   double Ask = oSym.Ask();

   int tPos = PositionsTotal();
   for (int i=tPos-1; i>=0; i--){
      ulong ticket = PositionGetTicket(i);
      if (ticket > 0){
         int type = (int) PositionGetInteger(POSITION_TYPE);
         double newSL = 0.0;
         if (type == POSITION_TYPE_BUY){
            newSL = Bid - IN_TrailingStart * Point();
            if (newSL > PositionGetDouble(POSITION_SL) ){
               if (!oTrade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP) ) ){
                  Print ("gagal set SL ");
               }
            }
         } else if (type == POSITION_TYPE_SELL){
            newSL = Ask + IN_TrailingStart * Point();
            if (newSL < PositionGetDouble(POSITION_SL) || PositionGetDouble(POSITION_SL) == 0 ){
               if (!oTrade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP) ) ){
                  Print ("gagal set SL ");
               }
            }
         }
         
      }
   }
}


int OnInit()
{
   oSym.Name(Symbol() );
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{

   
}

void OnTick()
{
   sDtPos dtPos[2];
   updateInfoTrade(dtPos);
   
//   //informasi untuk BUY:
//   Print ("Total Posisi Buy: ", dtPos[0].total);
//   Print ("Total Lot BUY: ", dtPos[0].tLot);
//   Print ("Harga BEP BUY: ", dtPos[0].bep);
//   
//   //informasi untuk SELL:
//   Print ("Total Posisi SELL: ", dtPos[1].total);
//   Print ("Total Lot SELL: ", dtPos[1].tLot);
//   Print ("Harga BEP SELL: ", dtPos[1].bep);
   
   
}
//+------------------------------------------------------------------+
