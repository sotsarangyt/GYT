# GYT Multi-Engine — EA មាស (XAUUSD) សម្រាប់ MT5 · Exness Pro

EA ស្វ័យប្រវត្តិ ១០០% ដែលរួមបញ្ចូល **៦ ស្រទាប់**៖

| ស្រទាប់ | តួនាទី |
|---|---|
| ① Regime Detector (H4) | វាស់ Efficiency Ratio + ATR ដើម្បីកំណត់ថាផ្សារនៅក្នុង **TREND / RANGE / NEUTRAL / CHAOS** |
| ② Engine A – Trend Breakout (H1) | ទៀនបិទបំបែក Donchian 20 តាមទិស D1 (EMA50)។ SL 2×ATR, Trailing 3×ATR |
| ③ Engine B – Trend Pullback (H1) | តម្លៃស្រុតមកប៉ះ EMA20 រួចបដិសេធ តាមទិសនិន្នាការ។ TP 2R |
| ④ Engine C – Range Reversion (H1) | ធ្លាយ Bollinger ក្លែងក្លាយ + RSI។ TP = ខ្សែកណ្តាល |
| ⑤ Risk Brain | Risk 0.5%/ត្រេដ, Risk សរុប 1.5%, ឈប់ពេលខាត 2%/ថ្ងៃ និង 5%/សប្តាហ៍, តាមដានសុខភាព Engine, កាត់ Lot ពេល Volatility ខ្ពស់ |
| ⑥ Market Context | News Shield (Calendar MT5), USD Pulse (DXY សំយោគ), Silver divergence, Shock Breaker, **Daily Macro Bias** ពី Internet |

គ្មាន Martingale គ្មាន Grid ហើយត្រេដនីមួយៗសុទ្ធតែមាន SL។

---

## ⚡ ដំឡើង ឬ Update ដោយចុចពីរដងតែប៉ុណ្ណោះ (ងាយបំផុត)

1. ទាញយក [`tools/GYT_Install.bat`](tools/GYT_Install.bat) ទៅ Desktop
2. ចុចពីរដងលើ File នោះ។ បើលោត **"Windows protected your PC"** → ចុច **More info** → **Run anyway**
3. វាទាញយក EA ចុងក្រោយពី GitHub, ដាក់ចូល MT5 ទាំងអស់ក្នុងកុំព្យូទ័រ, ហើយ Compile ដោយស្វ័យប្រវត្តិ។ EA ដែលនៅលើ Chart ស្រាប់ នឹង Reload ជា Version ថ្មីដោយខ្លួនឯង
4. ពេលមាន Version ថ្មី គ្រាន់តែចុចពីរដងលើ File ដដែលម្តងទៀត

## 📥 ដំឡើងដោយដៃ

1. ទាញយក [`MQL5/Experts/GYT/GYT_MultiEngine.mq5`](MQL5/Experts/GYT/GYT_MultiEngine.mq5)
2. បើក MT5 → **File → Open Data Folder** → ចូល `MQL5/Experts/` → បង្កើត Folder `GYT` → ដាក់ File ចូល
3. បើក **MetaEditor** (F4) → បើក File → ចុច **Compile** (F7) ហើយត្រូវឃើញ `0 errors`
4. **សំខាន់:** MT5 → **Tools → Options → Expert Advisors**
   - ✅ Allow algorithmic trading
   - ✅ Allow WebRequest for listed URL → បន្ថែម `https://raw.githubusercontent.com`
5. **Market Watch** → ចុចស្តាំ → **Show All** (ដើម្បីឱ្យ EA អាន EURUSD, USDJPY, GBPUSD, USDCAD, USDSEK, USDCHF, XAGUSD បាន)
6. បើក Chart **XAUUSD** (Timeframe ណាក៏បាន ព្រោះ EA អាន H1/H4/D1 ដោយខ្លួនឯង) → អូស EA ដាក់លើ Chart → ✅ Allow Algo Trading
7. នៅជ្រុងខាងលើ Chart ត្រូវឃើញ Panel **GYT Multi-Engine v1.00**

### 🖥️ ដំណើរការ ២៤/៥
- ប្រើ **Exness VPS** (ឥតគិតថ្លៃ បើមានទុនគ្រប់លក្ខខណ្ឌ) ឬ **MQL5 VPS** (MT5 → ចុចស្តាំលើ Account → Register a Virtual Server)
- ⚠️ MQL5 VPS **មិនអនុញ្ញាត WebRequest** ទេ។ បើប្រើ MQL5 VPS Daily Macro Bias នឹងប្រើ Stale mode (Risk 0.75×)។ ប្រើ **Exness VPS** ឬ Windows VPS ផ្ទាល់ខ្លួនល្អជាង។

---

## 🧭 Daily Macro Bias (ស្វ័យប្រវត្តិ)

- Claude Routine ដំណើរការ **រាល់ថ្ងៃធ្វើការ ម៉ោង 11:50 (កម្ពុជា)** មុនផ្សារ London បើក
- វាអានព័ត៌មាន Fed, Yield, USD, ភូមិសាស្ត្រនយោបាយ និងប្រតិទិនសេដ្ឋកិច្ច ហើយដាក់ពិន្ទុ ៥ កត្តា
- វាសរសេរ [`bias/xau_bias.txt`](bias/xau_bias.txt) (EA អាន), [`bias/brief_KH.md`](bias/brief_KH.md) (បងអាន) និង [`bias/history.csv`](bias/history.csv) (កំណត់ត្រា)
- EA អាន File រៀងរាល់ 30 នាទី

| Bias | Buy | Sell |
|---|---|---|
| BULL | × risk_mult | × risk_mult × 0.5 |
| BEAR | × risk_mult × 0.5 | × risk_mult |
| NEUTRAL | × risk_mult | × risk_mult |
| OFF | ❌ ឈប់ | ❌ ឈប់ |
| ផុតកំណត់ / អានមិនបាន | × 0.75 | × 0.75 |

Bias អាច **កាត់ Risk ប៉ុណ្ណោះ** (`InpBiasMaxMult = 1.0`)។ វាមិនអាចបង្កើន Risk បានទេ រហូតដល់យើងវាស់ History ២–៣ ខែ ហើយឃើញថាវាពិតជាជួយ។

---

## ⚙️ Settings សំខាន់ (ទុន $10,000)

| Input | Default | ន័យ |
|---|---|---|
| InpRiskBalance | 10000 | EA គណនា Lot និង Loss limit ដូចជាគណនីមាន $10,000 ទោះបីគណនី Demo មានលុយច្រើនជាងក៏ដោយ (0 = ប្រើ Equity ពិត) |
| InpRiskPerTradePct | 0.5 | ≈ $50 ក្នុងមួយត្រេដ |
| InpMaxTotalRiskPct | 1.5 | Risk សរុបអតិបរមា ≈ $150 |
| InpDailyLossPct / InpWeeklyLossPct | 2 / 5 | ឈប់ត្រេដ ហើយបិទ Position។ វាស់តែការខាតរបស់ GYT ប៉ុណ្ណោះ មិនរាប់ EA ផ្សេងទេ |
| InpMaxSpreadUSD | 0.50 | Spread មាសលើ Exness Pro ធម្មតាទាបជាងនេះ |
| InpSessionStartGMT / EndGMT | 7 / 17 | 14:00–00:00 ម៉ោងកម្ពុជា |
| InpFridayCloseGMT | 20 | បិទទាំងអស់នៅថ្ងៃសុក្រ ម៉ោង 03:00 ព្រឹកថ្ងៃសៅរ៍ (កម្ពុជា) |

---

## 🧪 ជំហានមុនប្រើលុយពិត (កុំរំលង!)

1. **Backtest:** Strategy Tester → XAUUSD → Model **"Every tick based on real ticks"** → 2020-01-01 ដល់ថ្ងៃនេះ → Deposit 10000
   - ក្នុង Tester, News Shield និង Macro Bias ត្រូវបានបិទដោយស្វ័យប្រវត្តិ (MT5 មិនអនុញ្ញាត)
   - សូមផ្ញើ Report (Save as HTML) មកខ្ញុំ ដើម្បីវិភាគ
2. **Walk-forward:** Optimize តែលើ 2020–2023 រួចសាកលើ 2024–ថ្ងៃនេះ ដោយមិនកែ Settings
3. **Demo ៤ សប្តាហ៍** លើ Exness Pro Demo
4. **Live:** ចាប់ផ្តើមដោយ `InpRiskPerTradePct = 0.25` រយៈ ១ ខែ រួចទើបឡើងទៅ 0.5

⚠️ ការជួញដូរមាសមានហានិភ័យខ្ពស់។ លទ្ធផលពីមុនមិនធានាលទ្ធផលអនាគតទេ។

---

## ⚡ Engine P: Pulse (ត្រេដប្រចាំថ្ងៃ M5), ចាប់ពី v1.20

| ផ្នែក | ច្បាប់ |
|---|---|
| **Strength Meter 0–100** | វាស់ពីទៀន M5 ដែលទើបបិទ៖ ទំហំតួទៀន (25), Range ពង្រីក (15), Tick Volume ផ្ទុះ (20), ទីតាំងបិទ (10), Trend M5+M15 (20), DXY ដើរផ្ទុយពីមាស (10) |
| **ចូលត្រេដ** | Score ក្នុង 12% ខ្លាំងបំផុតនៃ 12 ម៉ោងចុងក្រោយ (ចន្លោះ 55–70) ក្នុងម៉ោង 14:00–03:00 (កម្ពុជា)។ អតិបរមា **10 ត្រេដក្នុងមួយថ្ងៃ** |
| **ត្រេដនីមួយៗមាន ២ ផ្នែក** | **TP leg** (TP1 = +0.7R) និង **Runner** (គ្មាន TP) |
| **Runner** | ពេលដល់ TP1 → SL រំកិលមក Entry។ ចាប់ពី +1R → Trailing 2×ATR។ បិទពេលកម្លាំងផ្ទុយ ≥ 60 ឬក្រោយ 6 ម៉ោង |
| **Risk** | 0.2% ក្នុងមួយត្រេដ (≈ $20), ឈប់ក្រោយខាតជាប់គ្នា 3 ដង, បិទទាំងអស់ម៉ោង 04:00 (កម្ពុជា) |
| **Log** | រាល់សញ្ញាត្រូវកត់ត្រាក្នុង `MQL5/Files/GYT_pulse_log.csv` សម្រាប់ការស្រាវជ្រាវ |

⚠️ Engine P ថ្មី ហើយមិនទាន់បាន Backtest ទេ។ សូមប្រើតែលើ Demo សិន។
