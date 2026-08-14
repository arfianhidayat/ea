//+------------------------------------------------------------------+
//|                                         Auto_Martingale_Grid.mq5 |
//|                                         Versi 3.3 (Fast Scalp)   |
//+------------------------------------------------------------------+
#property copyright "Strategi Trading"
#property link      "https://www.mql5.com"
#property version   "3.30"

#include <Trade\Trade.mqh>

//--- Input Parameters ---
input group "=== SETTING LOT & GRID ==="
input double   InpInitialLot         = 0.01;     // Lot Awal (Posisi Pertama)
input double   InpGridDistance       = 2.0;      // Jarak Buka Posisi Averaging
input double   InpTakeProfitSingle   = 1.0;      // Take Profit jika HANYA 1 Posisi
input double   InpTakeProfitBEP1     = 0.6;      // Take Profit BEP 1 (Averaging Awal)
input int      InpAktifTPBEP2Posisi  = 5;        // Aktif TP BEP 2 pada Posisi ke-
input double   InpTakeProfitBEP2     = 0.3;      // Take Profit BEP 2 (Averaging Lanjut)
input double   InpLotMultiplier      = 1.2;      // Multiplier Martingale
input ulong    InpMagicNumber        = 88888;    // Magic Number EA

input group "=== SETTING SESI TRADING (WAKTU WIB) ==="
input string   InpAsiaStart          = "09:30";  // Mulai Sesi Asia (WIB)
input string   InpAsiaEnd            = "12:30";  // Akhir Sesi Asia (WIB)
input string   InpEropaStart         = "15:30";  // Mulai Sesi Eropa (WIB)
input string   InpEropaEnd           = "17:30";  // Akhir Sesi Eropa (WIB)
input string   InpUSStart            = "22:30";  // Mulai Sesi Amerika (WIB)
input string   InpUSEnd              = "01:30";  // Akhir Sesi Amerika (WIB)

CTrade trade;

// Variabel Global untuk menyimpan konversi menit
int AsiaStartMin, AsiaEndMin;
int EropaStartMin, EropaEndMin;
int USStartMin, USEndMin;

// --- FUNGSI INISIALISASI ---
int OnInit()
  {
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(50); // Toleransi slippage
   
   // Konversi input string HH:MM menjadi total menit dalam sehari
   AsiaStartMin = TimeToMinutes(InpAsiaStart);
   AsiaEndMin = TimeToMinutes(InpAsiaEnd);
   EropaStartMin = TimeToMinutes(InpEropaStart);
   EropaEndMin = TimeToMinutes(InpEropaEnd);
   USStartMin = TimeToMinutes(InpUSStart);
   USEndMin = TimeToMinutes(InpUSEnd);
   
   return(INIT_SUCCEEDED);
  }

void OnTick()
  {
   int buy_count = 0;
   int sell_count = 0;
   
   double sum_buy_volume = 0, sum_buy_value = 0;
   double sum_sell_volume = 0, sum_sell_value = 0;
   
   double last_buy_price = 0, last_sell_price = 0;
   
   double initial_buy_lot = 0, initial_sell_lot = 0;
   datetime latest_buy_time = 0, latest_sell_time = 0;
   datetime oldest_buy_time = 0, oldest_sell_time = 0;
   
   // 1. Membaca Posisi Terbuka
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionGetString(POSITION_SYMBOL) == _Symbol)
        {
         ulong magic = PositionGetInteger(POSITION_MAGIC);
         if(magic == 0 || magic == InpMagicNumber)
           {
            long type = PositionGetInteger(POSITION_TYPE);
            double price = PositionGetDouble(POSITION_PRICE_OPEN);
            double vol = PositionGetDouble(POSITION_VOLUME);
            datetime time = (datetime)PositionGetInteger(POSITION_TIME);
            
            if(type == POSITION_TYPE_BUY)
              {
               buy_count++; sum_buy_volume += vol; sum_buy_value += (price * vol); 
               
               if(time >= latest_buy_time) { latest_buy_time = time; last_buy_price = price; }
               if(oldest_buy_time == 0 || time < oldest_buy_time) { oldest_buy_time = time; initial_buy_lot = vol; }
              }
            else if(type == POSITION_TYPE_SELL)
              {
               sell_count++; sum_sell_volume += vol; sum_sell_value += (price * vol); 
               
               if(time >= latest_sell_time) { latest_sell_time = time; last_sell_price = price; }
               if(oldest_sell_time == 0 || time < oldest_sell_time) { oldest_sell_time = time; initial_sell_lot = vol; }
              }
           }
        }
     }
     
   // ==========================================
   // 2. LOGIKA OPEN POSISI AWAL (DENGAN FILTER WIB)
   // ==========================================
   bool is_trading_time = IsTradingTime();
   
   // Jika tidak ada posisi SELL, DAN sedang dalam Sesi Trading, buka SELL baru
   if(sell_count == 0 && is_trading_time)
     {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double start_lot = CalculateLot(InpInitialLot);
      trade.Sell(start_lot, _Symbol, bid, 0, 0, "First Auto Sell");
      sell_count++; 
     }
     
   // Jika tidak ada posisi BUY, DAN sedang dalam Sesi Trading, buka BUY baru
   if(buy_count == 0 && is_trading_time)
     {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double start_lot = CalculateLot(InpInitialLot);
      trade.Buy(start_lot, _Symbol, ask, 0, 0, "First Auto Buy");
      buy_count++; 
     }

   // --- DASHBOARD DIAGNOSTIK ---
   datetime time_gmt = TimeGMT();
   datetime time_wib = time_gmt + (7 * 3600); // Hitung WIB saat ini
   string string_wib = TimeToString(time_wib, TIME_MINUTES);
   
   string dashboard = "=== EA MARTINGALE (WIB SESSION) ===\n";
   dashboard += "Jam Saat Ini (WIB): " + string_wib + "\n";
   
   string status_waktu = is_trading_time ? "ON (Sesi Aktif)" : "OFF (Menunggu Sesi)";
   dashboard += "Status Trading: " + status_waktu + "\n\n";
   dashboard += "Lot Awal (Start): " + DoubleToString(InpInitialLot, 2) + "\n";
   dashboard += "Jarak Averaging: " + DoubleToString(InpGridDistance, 2) + "\n";
   dashboard += "Multiplier Lot: " + DoubleToString(InpLotMultiplier, 2) + "\n";
   
   // ==========================================
   // 3. LOGIKA AVERAGING & TAKE PROFIT SELL (JALAN 24 JAM)
   // ==========================================
   if(sell_count > 0 && sum_sell_volume > 0) 
     {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID); 
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK); 
      
      double bep_sell = sum_sell_value / sum_sell_volume; 
      double target_price_sell;
      
      if(sell_count == 1) target_price_sell = bep_sell - InpTakeProfitSingle;
      else if(sell_count >= InpAktifTPBEP2Posisi) target_price_sell = bep_sell - InpTakeProfitBEP2;
      else target_price_sell = bep_sell - InpTakeProfitBEP1;
        
      double next_sell_price = last_sell_price + InpGridDistance;
      
      dashboard += "--- STATUS SELL ---\n";
      dashboard += "Total Posisi: " + IntegerToString(sell_count) + "\n";
      dashboard += "Harga Buka Selanjutnya: " + DoubleToString(next_sell_price, 3) + "\n";
      dashboard += "Target Close (TP): " + DoubleToString(target_price_sell, 3) + "\n";
      
      // Buka Posisi Martingale Baru 
      if(last_sell_price > 0 && bid >= next_sell_price)
        {
         double exact_calculated_lot = initial_sell_lot * MathPow(InpLotMultiplier, sell_count);
         double new_lot = CalculateLot(exact_calculated_lot);
         trade.Sell(new_lot, _Symbol, bid, 0, 0, "Auto Averaging Sell");
        }
        
      // Tutup Semua Posisi
      if(ask <= target_price_sell && target_price_sell > 0)
        {
         CloseAll(POSITION_TYPE_SELL);
        }
     }
     
   // ==========================================
   // 4. LOGIKA AVERAGING & TAKE PROFIT BUY (JALAN 24 JAM)
   // ==========================================
   if(buy_count > 0 && sum_buy_volume > 0)
     {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID); 
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK); 
      
      double bep_buy = sum_buy_value / sum_buy_volume; 
      double target_price_buy;
      
      if(buy_count == 1) target_price_buy = bep_buy + InpTakeProfitSingle;
      else if(buy_count >= InpAktifTPBEP2Posisi) target_price_buy = bep_buy + InpTakeProfitBEP2;
      else target_price_buy = bep_buy + InpTakeProfitBEP1;
        
      double next_buy_price = last_buy_price - InpGridDistance;
      
      dashboard += "--- STATUS BUY ---\n";
      dashboard += "Total Posisi: " + IntegerToString(buy_count) + "\n";
      dashboard += "Harga Buka Selanjutnya: " + DoubleToString(next_buy_price, 3) + "\n";
      dashboard += "Target Close (TP): " + DoubleToString(target_price_buy, 3) + "\n";
      
      // Buka Posisi Martingale Baru 
      if(last_buy_price > 0 && ask <= next_buy_price)
        {
         double exact_calculated_lot = initial_buy_lot * MathPow(InpLotMultiplier, buy_count);
         double new_lot = CalculateLot(exact_calculated_lot);
         trade.Buy(new_lot, _Symbol, ask, 0, 0, "Auto Averaging Buy");
        }
        
      // Tutup Semua Posisi
      if(bid >= target_price_buy && target_price_buy > 0)
        {
         CloseAll(POSITION_TYPE_BUY);
        }
     }
     
   Comment(dashboard);
  }

// --- FUNGSI TAMBAHAN (WAKTU & LOT) ---

int TimeToMinutes(string time_str)
  {
   string arr[];
   if(StringSplit(time_str, ':', arr) == 2)
     {
      return (int)StringToInteger(arr[0]) * 60 + (int)StringToInteger(arr[1]);
     }
   return 0; 
  }

bool CheckSession(int current_min, int start_min, int end_min)
  {
   if(start_min < end_min)
     {
      return (current_min >= start_min && current_min <= end_min);
     }
   else
     {
      return (current_min >= start_min || current_min <= end_min);
     }
  }

// Fungsi Pengecekan Waktu murni menggunakan WIB (GMT+7)
bool IsTradingTime()
  {
   // 1. Dapatkan jam GMT
   datetime time_gmt = TimeGMT();
   
   // 2. Tambahkan 7 jam (7 * 3600 detik) untuk menjadikannya WIB
   datetime time_wib = time_gmt + 25200; 
   
   // 3. Konversi ke struktur waktu untuk mengambil komponen Jam dan Menit
   MqlDateTime dt;
   TimeToStruct(time_wib, dt); 
   
   int current_min = dt.hour * 60 + dt.min;
   
   if(CheckSession(current_min, AsiaStartMin, AsiaEndMin)) return true;
   if(CheckSession(current_min, EropaStartMin, EropaEndMin)) return true;
   if(CheckSession(current_min, USStartMin, USEndMin)) return true;
   
   return false;
  }

void CloseAll(long pos_type)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionGetString(POSITION_SYMBOL) == _Symbol)
        {
         ulong magic = PositionGetInteger(POSITION_MAGIC);
         if(magic == 0 || magic == InpMagicNumber)
           {
            if(PositionGetInteger(POSITION_TYPE) == pos_type) { trade.PositionClose(ticket); }
           }
        }
     }
  }

double CalculateLot(double calculated_lot)
  {
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double final_lot = MathRound(calculated_lot / step) * step;
   if(final_lot < min_lot) final_lot = min_lot;
   if(final_lot > max_lot) final_lot = max_lot;
   return final_lot;
  }
