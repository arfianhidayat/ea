//+------------------------------------------------------------------+
//|                                              ZigZag_Analyzer.mq5 |
//+------------------------------------------------------------------+
#property copyright "Trader Saham & Forex"
#property version   "1.10"

// Parameter Input ZigZag Standar
input int InpDepth     = 12; // Depth
input int InpDeviation = 5;  // Deviation
input int InpBackstep  = 3;  // Backstep

int zzHandle;

int OnInit() {
    // Memuat indikator ZigZag standar dari MT5
    zzHandle = iCustom(_Symbol, _Period, "Examples\\ZigZag", InpDepth, InpDeviation, InpBackstep);
    if(zzHandle == INVALID_HANDLE) {
        Print("Gagal memuat indikator ZigZag.");
        return INIT_FAILED;
    }
    
    // EKSEKUSI PASAR TUTUP: Render langsung saat EA ditarik ke chart
    UpdateZigZag();
    
    return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) {
    ObjectsDeleteAll(0, "ZZ_Line_"); 
    Comment("");                     
}

void OnTick() {
    // EKSEKUSI PASAR BUKA: Perbarui otomatis setiap ada pergerakan harga
    UpdateZigZag();
}

// Fungsi Khusus Pemetaan ZigZag
void UpdateZigZag() {
    double zzBuffer[];
    ArraySetAsSeries(zzBuffer, true);
    
    if(CopyBuffer(zzHandle, 0, 0, 200, zzBuffer) <= 0) return;

    double swingHighs[3] = {0, 0, 0};
    double swingLows[3]  = {0, 0, 0};
    int highCount = 0;
    int lowCount  = 0;
    
    struct ZZPoint { datetime time; double price; };
    ZZPoint lastPoints[6]; 
    int pointCount = 0;

    datetime time[];
    double high[], low[];
    ArraySetAsSeries(time, true);
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    
    CopyTime(_Symbol, _Period, 0, 200, time);
    CopyHigh(_Symbol, _Period, 0, 200, high);
    CopyLow(_Symbol, _Period, 0, 200, low);

    for(int i = 1; i < 200; i++) {
        if(highCount >= 3 && lowCount >= 3) break; 
        
        if(zzBuffer[i] > 0.0 && zzBuffer[i] != EMPTY_VALUE) {
            
            if(pointCount < 6) {
                lastPoints[pointCount].time = time[i];
                lastPoints[pointCount].price = zzBuffer[i];
                pointCount++;
            }

            if(zzBuffer[i] == high[i] && highCount < 3) {
                swingHighs[highCount] = zzBuffer[i];
                highCount++;
            } else if(zzBuffer[i] == low[i] && lowCount < 3) {
                swingLows[lowCount] = zzBuffer[i];
                lowCount++;
            }
        }
    }

    ObjectsDeleteAll(0, "ZZ_Line_"); 
    for(int p = 0; p < pointCount - 1; p++) {
        string lineName = "ZZ_Line_" + IntegerToString(p);
        ObjectCreate(0, lineName, OBJ_TREND, 0, lastPoints[p].time, lastPoints[p].price, lastPoints[p+1].time, lastPoints[p+1].price);
        ObjectSetInteger(0, lineName, OBJPROP_RAY_RIGHT, false); 
        ObjectSetInteger(0, lineName, OBJPROP_RAY_LEFT, false);  
        ObjectSetInteger(0, lineName, OBJPROP_COLOR, clrDodgerBlue);
        ObjectSetInteger(0, lineName, OBJPROP_WIDTH, 2);
    }

    string display = "=== DATA ZIGZAG ===\n\n[ SWING HIGHS ]\n";
    for(int h = 0; h < 3; h++) {
        display += "H" + IntegerToString(h+1) + " :  " + DoubleToString(swingHighs[h], _Digits) + "\n";
    }
    
    display += "\n[ SWING LOWS ]\n";
    for(int l = 0; l < 3; l++) {
        display += "L" + IntegerToString(l+1) + " :  " + DoubleToString(swingLows[l], _Digits) + "\n";
    }
    
    Comment(display);
}
