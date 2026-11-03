// =========================================
// PriceRange.mqh
// Kelas CPriceRange
//
// ALUR KELAS:
// 1. Init()
//    simpan simbol, TF, jam sesi
// 2. CalculateToday()
//    hitung high/low sesi hari ini
//    dengan loop bar
// 3. GetHigh() / GetLow()
//    baca hasil (getter)
// 4. BreakUp() / BreakDown()
//    cek harga menembus atas / bawah
// =========================================
#ifndef __PRICE_RANGE_MQH__
#define __PRICE_RANGE_MQH__

class CPriceRange
  {
private:
   // --- pengaturan dasar ---
   // simbol chart
   string            m_symbol;
   // timeframe
   ENUM_TIMEFRAMES   m_tf;
   // jam & menit mulai sesi
   int               m_start_hour;
   int               m_start_min;
   // jam & menit akhir sesi
   int               m_end_hour;
   int               m_end_min;

   // --- hasil perhitungan ---
   // high & low sesi
   double            m_high;
   double            m_low;
   // waktu mulai & akhir sesi
   datetime          m_range_start;
   datetime          m_range_end;
   // tanggal terakhir dihitung
   datetime          m_calc_day;
   // range sudah sah?
   bool              m_valid;

   // ambil jam 00:00 dari waktu t
   datetime DayStart(datetime t)
     {
      return(t - (t % 86400));
     }

public:
                     CPriceRange(void);
                    ~CPriceRange(void) {}

   // isi pengaturan awal
   void Init(const string symbol,
             const ENUM_TIMEFRAMES tf,
             const int start_hour,
             const int start_min,
             const int end_hour,
             const int end_min);

   // hitung range hari ini
   bool CalculateToday(void);

   // --- getter ---
   // variabel private dibaca lewat sini
   double GetHigh(void) const
     {
      return(m_high);
     }
   double GetLow(void) const
     {
      return(m_low);
     }
   datetime GetRangeStart(void) const
     {
      return(m_range_start);
     }
   datetime GetRangeEnd(void) const
     {
      return(m_range_end);
     }
   datetime GetCalcDay(void) const
     {
      return(m_calc_day);
     }
   bool IsValid(void) const
     {
      return(m_valid);
     }

   // waktu t masih di dalam sesi?
   bool IsInsideRange(const datetime t) const
     {
      return(t >= m_range_start &&
             t <  m_range_end);
     }

   // waktu t sudah lewat sesi?
   bool IsAfterRange(const datetime t) const
     {
      return(t >= m_range_end);
     }

   // BreakUp versi 1 parameter
   // harga saat ini di atas high?
   bool BreakUp(const double price) const
     {
      return(m_valid && price > m_high);
     }

   // BreakUp versi 2 parameter
   // body candle menutup di atas high?
   bool BreakUp(const double open,
                const double close) const
     {
      return(m_valid &&
             open  <= m_high &&
             close >  m_high);
     }

   // BreakDown versi 1 parameter
   // harga saat ini di bawah low?
   bool BreakDown(const double price) const
     {
      return(m_valid && price < m_low);
     }

   // BreakDown versi 2 parameter
   // body candle menutup di bawah low?
   bool BreakDown(const double open,
                  const double close) const
     {
      return(m_valid &&
             open  >= m_low &&
             close <  m_low);
     }
  };

// =========================================
// Konstruktor: isi nilai default
// =========================================
CPriceRange::CPriceRange(void)
  {
   m_symbol      = _Symbol;
   m_tf          = PERIOD_CURRENT;
   m_start_hour  = 0;
   m_start_min   = 0;
   m_end_hour    = 0;
   m_end_min     = 0;
   m_high        = 0.0;
   m_low         = 0.0;
   m_range_start = 0;
   m_range_end   = 0;
   m_calc_day    = 0;
   m_valid       = false;
  }

// =========================================
// Init: simpan pengaturan dari EA
// =========================================
void CPriceRange::Init(const string symbol,
                       const ENUM_TIMEFRAMES tf,
                       const int start_hour,
                       const int start_min,
                       const int end_hour,
                       const int end_min)
  {
   m_symbol     = symbol;
   m_tf         = tf;
   m_start_hour = start_hour;
   m_start_min  = start_min;
   m_end_hour   = end_hour;
   m_end_min    = end_min;
   // reset, belum dihitung
   m_valid      = false;
  }

// =========================================
// CalculateToday
// Langkah:
//  a. tentukan waktu mulai & akhir sesi
//  b. sesi belum selesai -> false
//  c. cari index bar awal & akhir sesi
//  d. loop bar, ambil high & low
//  e. simpan hasil, tandai valid
// =========================================
bool CPriceRange::CalculateToday(void)
  {
   // a. waktu sesi hari ini (waktu server)
   datetime now  = TimeCurrent();
   datetime day  = DayStart(now);
   m_range_start = day
                 + m_start_hour * 3600
                 + m_start_min  * 60;
   m_range_end   = day
                 + m_end_hour * 3600
                 + m_end_min  * 60;
   m_calc_day    = day;
   m_valid       = false;

   // jam akhir harus > jam mulai
   if(m_range_end <= m_range_start)
      return(false);

   // b. sesi belum selesai
   if(now < m_range_end)
      return(false);

   // c. index bar
   // start_idx = bar terlama dalam sesi
   // end_idx   = bar terbaru dalam sesi
   int start_idx = iBarShift(m_symbol, m_tf,
                             m_range_start,
                             false);
   int end_idx   = iBarShift(m_symbol, m_tf,
                             m_range_end - 1,
                             false);
   if(start_idx < 0 || end_idx < 0)
      return(false);

   // d. loop sederhana cari high & low
   // hi mulai sangat kecil
   // lo mulai sangat besar
   double hi = -DBL_MAX;
   double lo =  DBL_MAX;

   for(int i = end_idx; i <= start_idx; i++)
     {
      datetime bt = iTime(m_symbol, m_tf, i);

      // lewati bar di luar jam sesi
      if(bt < m_range_start ||
         bt >= m_range_end)
         continue;

      double h = iHigh(m_symbol, m_tf, i);
      double l = iLow(m_symbol, m_tf, i);

      // high baru lebih tinggi?
      if(h > hi)
         hi = h;
      // low baru lebih rendah?
      if(l < lo)
         lo = l;
     }

   // tidak ada bar sama sekali
   if(hi == -DBL_MAX || lo == DBL_MAX)
      return(false);

   // e. simpan hasil
   m_high  = hi;
   m_low   = lo;
   m_valid = true;
   return(true);
  }

#endif