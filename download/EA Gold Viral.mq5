//+------------------------------------------------------------------+
//|                                                EA Gold Viral.mq5 |
//|                                            Copyright 2026, Trexa |
//|                                                 https://Trexa.id |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Trexa"
#property link      "https://Trexa.id"
#property version   "1.00"

#include <Trade/Trade.mqh>
#include <Trade/AccountInfo.mqh>
#include <Trade/SymbolInfo.mqh>

CTrade oTrade;
CAccountInfo oAcc;
CSymbolInfo oSym;

input    int   IN_MagicNumber = 123;      //Magic Number
input    double IN_LotSize    = 0.01;     //Lot Size
input    double IN_Multiplier = 1.2;      //Multiplier
input    int    IN_MaxOrder   = 100;      //Max Order
input    int    IN_JarakLayer = 20;       //Jarak Layer

input    int   IN_TakeProfit1 = 100;      //TP 1
input    int   IN_TakeProfit2 = 200;      //TP 2
input    int   IN_TakeProfit3 = 500;      //TP 3

input    bool  IN_IsTrailingStop = true;     //Trailing Stop
input    int   IN_TrailingStart  = 200;      //Trailing Start
input    int   IN_TrailingStep   = 50;       //Trailing Step

struct sData{
   int totalPos;
   double hargaTerAtas, hargaTerBawah;
   double tLot, tWeightPrice, hargaBEP;
   
   void sData(){
      totalPos = 0;
      hargaTerAtas = hargaTerBawah = tLot = tWeightPrice = hargaBEP = 0.0;
   }
   
};

sData dataPos[2];
/*
 dataPos[0] >> BUY
 dataPos[1] >> SELL
*/

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//---
   if (StringFind(Symbol(), "XAUUSD", 0) < 0) { Print("Khusus pair XAUUSD saja."); return(INIT_FAILED); }
   
   oSym.Name(Symbol() );
   oTrade.SetExpertMagicNumber(IN_MagicNumber);
   oTrade.SetDeviationInPoints(20);
   
   
//---
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
//---
   if (IsNewCandle() ){
      //Print ("testing masuk sini");
      
      transaksi();
      
      SetTPSL();
      
   }
   
  }
//+------------------------------------------------------------------+

void updateData(){
   ZeroMemory(dataPos);
   //dataPos[0].sData();
   //dataPos[1].sData();
   
   int tPos = PositionsTotal();
   for (int i=tPos-1; i>=0; i--){
      ulong ticket = PositionGetTicket(i);
      if (ticket > 0){
         if (PositionGetInteger(POSITION_MAGIC) == IN_MagicNumber 
            && PositionGetString(POSITION_SYMBOL) == oSym.Name() )
         {
            long type = PositionGetInteger(POSITION_TYPE);
            dataPos[type].totalPos++;
            if (dataPos[type].hargaTerAtas < PositionGetDouble(POSITION_PRICE_OPEN) ){
               dataPos[type].hargaTerAtas = PositionGetDouble(POSITION_PRICE_OPEN);
            }
            if (dataPos[type].hargaTerBawah > PositionGetDouble(POSITION_PRICE_OPEN) || dataPos[type].hargaTerBawah == 0 ){
               dataPos[type].hargaTerBawah = PositionGetDouble(POSITION_PRICE_OPEN);
            }
            
            dataPos[type].tLot += PositionGetDouble(POSITION_VOLUME);
            dataPos[type].tWeightPrice += PositionGetDouble(POSITION_VOLUME) * PositionGetDouble(POSITION_PRICE_OPEN);
            
         }
      }
   }
   
   dataPos[0].hargaBEP = (dataPos[0].tLot>0)? dataPos[0].tWeightPrice / dataPos[0].tLot : 0.0; //BEP BUY
   dataPos[1].hargaBEP = (dataPos[1].tLot>0)? dataPos[1].tWeightPrice / dataPos[1].tLot : 0.0; //BEP SELL
   
}

void transaksi(){
   updateData();
   
   double vol = 0.0;
   string pair = oSym.Name();
   double sl = 0.0, tp = 0.0;
   string comment = "EA Gold Viral";
   
   //open buy
   if (dataPos[0].totalPos == 0){
      vol = GetVolume(0);
      if (!oTrade.Buy(vol, pair, 0.0, sl, tp, comment) ){
         Print("Gagal open posisi BUY");
      }else{
         Print ("Berhasil open posisi BUY");
      }
   }
   
   //open sell
   if (dataPos[1].totalPos == 0){
      vol = GetVolume(0);
      if (!oTrade.Sell(vol, pair, 0.0, sl, tp, comment) ){
         Print("Gagal open posisi SELL");
      }else{
         Print ("Berhasil open posisi SELL");
      }
   }
   
   //Averaging Down
   if (dataPos[0].totalPos > 0 && dataPos[0].totalPos < IN_MaxOrder 
      && dataPos[0].hargaTerBawah - pipToPrice(IN_JarakLayer) >= oSym.Ask() )
   {
      vol = GetVolume(dataPos[0].totalPos);
      if (!oTrade.Buy(vol, pair, 0.0, sl, tp, comment) ){
         Print("Gagal open posisi BUY");
      }else{
         Print ("Berhasil open posisi BUY");
      }
   }
   
   if (dataPos[1].totalPos > 0 && dataPos[1].totalPos < IN_MaxOrder 
      && dataPos[1].hargaTerAtas + pipToPrice(IN_JarakLayer) <= oSym.Bid() )
   {
      vol = GetVolume(dataPos[1].totalPos);
      if (!oTrade.Sell(vol, pair, 0.0, sl, tp, comment) ){
         Print("Gagal open posisi SELL");
      }else{
         Print ("Berhasil open posisi SELL");
      }
   }
   
   
   //Averaging UP
   if (dataPos[0].totalPos > 0 && dataPos[0].totalPos < IN_MaxOrder 
      && dataPos[0].hargaTerAtas + pipToPrice(IN_JarakLayer) <= oSym.Ask() )
   {
      vol = GetVolume(dataPos[0].totalPos);
      if (!oTrade.Buy(vol, pair, 0.0, sl, tp, comment) ){
         Print("Gagal open posisi BUY");
      }else{
         Print ("Berhasil open posisi BUY");
      }
   }
   
   if (dataPos[1].totalPos > 0 && dataPos[1].totalPos < IN_MaxOrder 
      && dataPos[1].hargaTerBawah - pipToPrice(IN_JarakLayer) >= oSym.Bid() )
   {
      vol = GetVolume(dataPos[1].totalPos);
      if (!oTrade.Sell(vol, pair, 0.0, sl, tp, comment) ){
         Print("Gagal open posisi SELL");
      }else{
         Print ("Berhasil open posisi SELL");
      }
   }
   
   
}

void SetTPSL(){
   updateData();
   
   oSym.RefreshRates();
   
   double BID = oSym.Bid();
   double ASK = oSym.Ask();
   //Print ("========== pair: ", oSym.Name(), " BID: ", BID, " ASK : ", ASK);
   
   int tBuy = dataPos[0].totalPos;
   int tSell= dataPos[1].totalPos;
   double hargaBEP_BUY = dataPos[0].hargaBEP;
   double hargaBEP_SELL= dataPos[1].hargaBEP;
   
   double TP_Buy = 0.0, SL_Buy = 0.0;
   double TP_Sell= 0.0, SL_Sell = 0.0;
   int jarakTP = 0;
   jarakTP = getJarakTP(tSell);
   TP_Buy = hargaBEP_BUY + pipToPrice(jarakTP);
   
   jarakTP = getJarakTP(tBuy);
   TP_Sell = hargaBEP_SELL - pipToPrice(jarakTP);
   //Print ("tBuy: ", tBuy, " tpSELL: ", TP_Sell, " tSell: ", tSell);
   
   int digit = Digits();
   
   
   int tPos = PositionsTotal();
   for (int i=tPos-1; i>=0; i--){
      ulong ticket = PositionGetTicket(i);
      if (ticket > 0){
         if (PositionGetInteger(POSITION_MAGIC) == IN_MagicNumber 
            && PositionGetString(POSITION_SYMBOL) == oSym.Name() )
         {
            long type = PositionGetInteger(POSITION_TYPE);
            
            if (type == POSITION_TYPE_BUY){
               SL_Buy = PositionGetDouble(POSITION_SL);
               
               if (IN_IsTrailingStop==true && ( (SL_Buy + pipToPrice(IN_TrailingStart+IN_TrailingStep)) <= BID && hargaBEP_BUY+pipToPrice(IN_TrailingStart) <= BID) ){
                  SL_Buy = BID - pipToPrice(IN_TrailingStart);
               }
               
               SL_Buy = NormalizeDouble(SL_Buy, digit);
               TP_Buy = NormalizeDouble(TP_Buy, digit);
               
               if (SL_Buy != PositionGetDouble(POSITION_SL) || TP_Buy != PositionGetDouble(POSITION_TP) ){
                  if (!oTrade.PositionModify(ticket, SL_Buy, TP_Buy)){
                     Print ("Gagal set TP/SL");
                  }
               }
            }
            
            if (type == POSITION_TYPE_SELL){
               SL_Sell = PositionGetDouble(POSITION_SL);
               //Print (" ================  SL awal: ", SL_Sell);
               
               if (IN_IsTrailingStop==true && ( ( (SL_Sell - pipToPrice(IN_TrailingStart+IN_TrailingStep)) >= ASK  || SL_Sell == 0) && hargaBEP_SELL-pipToPrice(IN_TrailingStart) >= ASK) ){
                  SL_Sell = ASK + pipToPrice(IN_TrailingStart);
               }
               
               //Print ("SL SELL:", SL_Sell, " Ask: ", ASK, " pipToPrice(IN_TrailingStart): ", pipToPrice(IN_TrailingStart));
               
               SL_Sell = NormalizeDouble(SL_Sell, digit);
               TP_Sell = NormalizeDouble(TP_Sell, digit);
               
               if (SL_Sell != PositionGetDouble(POSITION_SL) || TP_Sell != PositionGetDouble(POSITION_TP) ){
                  if (!oTrade.PositionModify(ticket, SL_Sell, TP_Sell)){
                     Print ("Gagal set TP/SL");
                  }
               }
            }
            
         }
      }
   } 

}



int getJarakTP(int jumlahPos)
{
   if (jumlahPos > 15) return (IN_TakeProfit3);
   else if (jumlahPos > 10) return (IN_TakeProfit2);
   else if (jumlahPos > 0) return (IN_TakeProfit1);
   
   return(0);
   
}  


double pipToPrice(int jarakLayer){
   double point = oSym.Point();
   int digit = oSym.Digits();
   double pips = point;
   if (digit % 2 == 1){
      pips = point * 10;
   }
   return (pips);
}

void validasiLotSize(double &vol){
   double lotMin = oSym.LotsMin();
   double lotMax = oSym.LotsMax();
   double lotStep = oSym.LotsStep();
   
   vol   = MathRound(vol / lotStep) * lotStep;
   vol   = MathMin (lotMax, MathMax(vol, lotMin));
   vol   = NormalizeDouble(vol, 2);
   
}

double GetVolume(int tPos){
   double vol = 0.0;
   vol = IN_LotSize * MathPow(IN_Multiplier, tPos);
   
   validasiLotSize(vol);
   
   return (vol);
}


bool IsNewCandle(){
   static datetime wkt = TimeCurrent();
   string pair = oSym.Name();
   if (wkt < iTime(pair, PERIOD_CURRENT, 0) ){
      wkt = iTime(pair, PERIOD_CURRENT, 0);
      return (true);
   }
   return (false);
}