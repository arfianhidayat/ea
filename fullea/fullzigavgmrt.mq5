//+------------------------------------------------------------------+
//|                                              ZigZag_Analyzer.mq5 |
//+------------------------------------------------------------------+
#property copyright "Trader Saham & Forex"
#property version   "1.30"

// Parameter Input ZigZag Standar
input int InpDepth     = 12; 
input int InpDeviation = 5;  
input int InpBackstep  = 3;  

int zzHandle;

int OnInit() {
    zzHandle = iCustom(_Symbol, _Period, "Examples\\ZigZag", InpDepth, InpDeviation, InpBackstep);
    if(zzHandle == INVALID_HANDLE) {
        Print("Gagal memuat indikator ZigZag.");
        return INIT_FAILED;
    }
    
    UpdateZigZag();
    return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) {
    ObjectsDeleteAll(0, "ZZ_Line_"); 
    Comment("");                     
}

void OnTick() {
    UpdateZigZag();
}

void UpdateZigZag() {
    double zzBuffer[];
    ArraySetAsSeries(zzBuffer, true);
    
    if(CopyBuffer(zzHandle, 0, 0, 500, zzBuffer) <= 0) return;

    struct ZZPoint { datetime time; double price; };
    ZZPoint lastPoints[10]; 
    int pointCount = 0;

    datetime time[];
    ArraySetAsSeries(time, true);
    CopyTime(_Symbol, _Period, 0, 500, time);

    for(int i = 1; i < 500; i++) {
        if(pointCount >= 10) break; 
        
        if(zzBuffer[i] > 0.0 && zzBuffer[i] != EMPTY_VALUE) {
            lastPoints[pointCount].time = time[i];
            lastPoints[pointCount].price = zzBuffer[i];
            pointCount++;
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

    string display = "=== 10 TITIK ZIGZAG TERAKHIR ===\n\n";
    for(int k = 0; k < pointCount; k++) {
        display += "Titik " + IntegerToString(k+1) + " :  " + 
                   DoubleToString(lastPoints[k].price, _Digits) + 
                   "   [" + TimeToString(lastPoints[k].time, TIME_DATE|TIME_MINUTES) + "]\n";
    }
    
    // Blok Kalkulasi Lebar & Deteksi Sideway
    if(pointCount >= 5) {
        // Indeks array dimulai dari 0 (Titik 1 = indeks 0, Titik 2 = indeks 1, dst)
        double lebar1 = MathAbs(lastPoints[1].price - lastPoints[2].price); // Titik ke-2 dan ke-3
        double lebar2 = MathAbs(lastPoints[3].price - lastPoints[4].price); // Titik ke-4 dan ke-5
        
        display += "\n=== ANALISIS LEBAR AYUNAN ===\n";
        display += "Lebar Pertama (Titik 2 & 3) : " + DoubleToString(lebar1, _Digits) + "\n";
        display += "Lebar Kedua   (Titik 4 & 5) : " + DoubleToString(lebar2, _Digits) + "\n";
        
        // Logika Sideway: Lebar ayunan terbaru lebih kecil dari ayunan sebelumnya
        if(lebar1 < lebar2) {
            display += "\n>> STATUS PASAR: SIDEWAY <<\n";
        }
    }
    
    Comment(display);
}
