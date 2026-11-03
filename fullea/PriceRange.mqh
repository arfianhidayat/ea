//+------------------------------------------------------------------+
//|                                                   PriceRange.mqh |
//|  Kelas pembantu: hitung range (high/low) sesi harian &           |
//|  deteksi break up / break down.                                  |
//+------------------------------------------------------------------+
#ifndef __PRICE_RANGE_MQH__
#define __PRICE_RANGE_MQH__

class CPriceRange
  {
private:
   string            m_symbol;
   ENUM_TIMEFRAMES   m_tf;
   int               m_start_hour;
   int               m_start_min;
   int               m_end_hour;
   int               m_end_min;

   double            m_high;
   double            m_low;
   datetime          m_range_start;   // waktu mulai sesi (hari ini)
   datetime          m_range_end;     // waktu akhir sesi (hari ini)
   datetime          m_calc_day;      // tanggal terakhir range dihitung
   bool              m_valid;

   datetime          DayStart(datetime t) { return(t - (t % 86400)); }

public:
                     CPriceRange(void);
                    ~CPriceRange(void) {}

   // konfigurasi
   void              Init(const string symbol, const ENUM_TIMEFRAMES tf,
                          const int start_hour, const int start_min,
                          const int end_hour, const int end_min);

   // hitung range untuk hari ini (berdasarkan waktu server)
   bool              CalculateToday(void);

   // getter
   double            GetHigh(void)        const { return(m_high); }
   double            GetLow(void)         const { return(m_low);  }
   datetime          GetRangeStart(void)  const { return(m_range_start); }
   datetime          GetRangeEnd(void)    const { return(m_range_end);   }
   bool              IsValid(void)        const { return(m_valid); }
   datetime          GetCalcDay(void)     const { return(m_calc_day); }

   // posisi waktu relatif terhadap sesi
   bool              IsInsideRange(const datetime t) const
                       { return(t >= m_range_start && t < m_range_end); }
   bool              IsAfterRange(const datetime t) const
                       { return(t >= m_range_end); }

   // overloading: 1 parameter (harga) / 2 parameter (open & close candle)
   bool              BreakUp(const double price) const
                       { return(m_valid && price > m_high); }
   bool              BreakUp(const double open, const double close) const
                       { return(m_valid && open <= m_high && close > m_high); }

   bool              BreakDown(const double price) const
                       { return(m_valid && price < m_low); }
   bool              BreakDown(const double open, const double close) const
                       { return(m_valid && open >= m_low && close < m_low); }
  };

//+------------------------------------------------------------------+
CPriceRange::CPriceRange(void) : m_symbol(_Symbol), m_tf(PERIOD_CURRENT),
   m_start_hour(0), m_start_min(0), m_end_hour(0), m_end_min(0),
   m_high(0.0), m_low(0.0), m_range_start(0), m_range_end(0),
   m_calc_day(0), m_valid(false)
  {
  }

//+------------------------------------------------------------------+
void CPriceRange::Init(const string symbol, const ENUM_TIMEFRAMES tf,
                       const int start_hour, const int start_min,
                       const int end_hour, const int end_min)
  {
   m_symbol     = symbol;
   m_tf         = tf;
   m_start_hour = start_hour;
   m_start_min  = start_min;
   m_end_hour   = end_hour;
   m_end_min    = end_min;
   m_valid      = false;
  }

//+------------------------------------------------------------------+
//| Pindai bar antara start..end hari ini, cari high & low            |
//+------------------------------------------------------------------+
bool CPriceRange::CalculateToday(void)
  {
   datetime now   = TimeCurrent();
   datetime day   = DayStart(now);
   m_range_start  = day + m_start_hour * 3600 + m_start_min * 60;
   m_range_end    = day + m_end_hour   * 3600 + m_end_min   * 60;
   m_calc_day     = day;
   m_valid        = false;

   if(m_range_end <= m_range_start)
      return(false);

   // sesi belum selesai -> range belum final
   if(now < m_range_end)
      return(false);

   int start_idx = iBarShift(m_symbol, m_tf, m_range_start, false);
   int end_idx   = iBarShift(m_symbol, m_tf, m_range_end - 1, false);
   if(start_idx < 0 || end_idx < 0)
      return(false);

   double hi = -DBL_MAX;
   double lo =  DBL_MAX;

   // looping sederhana dari bar terbaru (end_idx) ke bar terlama (start_idx)
   for(int i = end_idx; i <= start_idx; i++)
     {
      datetime bt = iTime(m_symbol, m_tf, i);
      if(bt < m_range_start || bt >= m_range_end)
         continue;
      double h = iHigh(m_symbol, m_tf, i);
      double l = iLow(m_symbol, m_tf, i);
      if(h > hi) hi = h;
      if(l < lo) lo = l;
     }

   if(hi == -DBL_MAX || lo == DBL_MAX)
      return(false);

   m_high  = hi;
   m_low   = lo;
   m_valid = true;
   return(true);
  }

#endif // __PRICE_RANGE_MQH__
//+------------------------------------------------------------------+