//+------------------------------------------------------------------+
//|                                                        VLDMI.mq5 |
//|        Variable Length Dynamic Momentum Index (可変長DMI)         |
//|                                                                  |
//| 計算方法（Tushar Chande / Stanley Kroll の Dynamic Momentum Index）|
//|   1. SD   = 価格の標準偏差（InpStdDevPeriod 本）                   |
//|   2. ASD  = SD の単純移動平均（InpStdDevAvgPeriod 本）              |
//|   3. VI   = SD / ASD                                ... ボラ比率  |
//|   4. N    = int(InpBasePeriod / VI) を                             |
//|             [InpMinPeriod, InpMaxPeriod] に制限     ... 可変期間  |
//|   5. VLDMI = 期間 N の RSI                                        |
//|        ワイルダー : MT4/MT5 標準 RSI と同じ平滑化（期間 N の値を使用）  |
//|        単純合計   : N 本分の上昇幅 / (上昇幅 + 下落幅) * 100           |
//|   ボラティリティが高いほど N が短くなり、低いほど長くなる。           |
//+------------------------------------------------------------------+
#property copyright   "mitofuworks"
#property version     "1.20"
#property description "Variable Length Dynamic Momentum Index (VLDMI)"
#property description "ボラティリティに応じて計算期間が変わるRSI"

#property indicator_separate_window
#property indicator_minimum 0
#property indicator_maximum 100
#property indicator_buffers 3

//--- RSI の計算方法
enum ENUM_RSI_MODE
  {
   RSI_WILDER = 0, // ワイルダー（標準RSIと同じ）
   RSI_SIMPLE = 1  // 単純合計（反応が速く 0/100 に張り付きやすい）
  };
#property indicator_plots   2

#property indicator_label1  "VLDMI"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrDodgerBlue
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

// 可変期間はデータウィンドウにのみ表示
#property indicator_label2  "Period"
#property indicator_type2   DRAW_NONE

//--- 入力パラメータ
input group "計算"
input int    InpStdDevPeriod    = 5;     // 標準偏差の期間
input int    InpStdDevAvgPeriod = 10;    // 標準偏差の平均期間
input int    InpBasePeriod      = 14;    // 基準期間
input int    InpMinPeriod       = 5;     // 最小期間
input int    InpMaxPeriod       = 30;    // 最大期間
input ENUM_RSI_MODE InpRsiMode  = RSI_WILDER; // RSIの計算方法
input group "レベルライン（-1 で非表示）"
input double          InpLevel1     = 85.0;       // レベル1
input double          InpLevel2     = 75.0;       // レベル2
input double          InpLevel3     = 50.0;       // レベル3
input double          InpLevel4     = 25.0;       // レベル4
input double          InpLevel5     = 15.0;       // レベル5
input color           InpLevelColor = clrSilver;  // レベルの色
input ENUM_LINE_STYLE InpLevelStyle = STYLE_DOT;  // レベルの線種
input group "通知"
input double InpOverbought      = 85.0;  // 上側の通知レベル（買われすぎ）
input double InpOversold        = 15.0;  // 下側の通知レベル（売られすぎ）
input bool   InpAlert           = false; // レベルクロスでアラート
input bool   InpPush            = false; // レベルクロスでプッシュ通知

//--- バッファ
double BufVLDMI[];
double BufPeriod[];
double BufStdDev[];

int      g_sdPeriod, g_avgPeriod, g_basePeriod, g_minPeriod, g_maxPeriod;
int      g_firstBar;
datetime g_lastAlertBar = 0;

//--- ワイルダー平滑化の状態（期間ごとの平均上昇幅・平均下落幅）
double   g_avgUp[], g_avgDn[];   // g_stateBar 時点で確定した値
double   g_tmpUp[], g_tmpDn[];   // 計算中のバーの値
int      g_stateBar = -1;

//+------------------------------------------------------------------+
int OnInit()
  {
   g_sdPeriod   = MathMax(InpStdDevPeriod, 2);
   g_avgPeriod  = MathMax(InpStdDevAvgPeriod, 1);
   g_basePeriod = MathMax(InpBasePeriod, 1);
   g_minPeriod  = MathMax(InpMinPeriod, 1);
   g_maxPeriod  = MathMax(InpMaxPeriod, g_minPeriod);

   ArrayResize(g_avgUp, g_maxPeriod + 1);
   ArrayResize(g_avgDn, g_maxPeriod + 1);
   ArrayResize(g_tmpUp, g_maxPeriod + 1);
   ArrayResize(g_tmpDn, g_maxPeriod + 1);

   SetIndexBuffer(0, BufVLDMI,  INDICATOR_DATA);
   SetIndexBuffer(1, BufPeriod, INDICATOR_DATA);
   SetIndexBuffer(2, BufStdDev, INDICATOR_CALCULATIONS);

   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   IndicatorSetInteger(INDICATOR_DIGITS, 2);
   //--- レベルライン（0〜100 の範囲外は非表示）
   double levels[5];
   levels[0] = InpLevel1;
   levels[1] = InpLevel2;
   levels[2] = InpLevel3;
   levels[3] = InpLevel4;
   levels[4] = InpLevel5;
   int count = 0;
   for(int j = 0; j < 5; j++)
      if(levels[j] >= 0.0 && levels[j] <= 100.0)
         levels[count++] = levels[j];
   IndicatorSetInteger(INDICATOR_LEVELS, count);
   for(int j = 0; j < count; j++)
     {
      IndicatorSetDouble(INDICATOR_LEVELVALUE, j, levels[j]);
      IndicatorSetInteger(INDICATOR_LEVELCOLOR, j, InpLevelColor);
      IndicatorSetInteger(INDICATOR_LEVELSTYLE, j, InpLevelStyle);
     }

   IndicatorSetString(INDICATOR_SHORTNAME,
                      StringFormat("VLDMI(%d,%d,%d,%d-%d)", g_sdPeriod, g_avgPeriod,
                                   g_basePeriod, g_minPeriod, g_maxPeriod));
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| 適用価格は「パラメータ」タブの「適用価格」で選択（終値・他指標など）  |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const int begin,
                const double &price[])
  {
   int sdStart = begin + g_sdPeriod - 1;                    // SD が有効になる最初のバー
   g_firstBar  = MathMax(sdStart + g_avgPeriod - 1,         // ASD が有効になる最初のバー
                         begin + g_maxPeriod);              // N 本の差分が取れる最初のバー
   if(rates_total <= g_firstBar)
      return(0);

   int start;
   if(prev_calculated == 0)
     {
      ArrayInitialize(BufVLDMI,  EMPTY_VALUE);
      ArrayInitialize(BufPeriod, EMPTY_VALUE);
      ArrayInitialize(BufStdDev, 0.0);
      PlotIndexSetInteger(0, PLOT_DRAW_BEGIN, g_firstBar);
      PlotIndexSetInteger(1, PLOT_DRAW_BEGIN, g_firstBar);
      g_stateBar = -1;
      start = sdStart;
     }
   else
     {
      start = prev_calculated - 1;
      if(InpRsiMode == RSI_WILDER && g_stateBar >= 0)
         start = MathMin(start, g_stateBar + 1);
     }

   for(int i = start; i < rates_total && !IsStopped(); i++)
     {
      //--- 1. 標準偏差（母標準偏差、MT5標準の iStdDev と同じ定義）
      double mean = 0.0;
      for(int k = 0; k < g_sdPeriod; k++)
         mean += price[i - k];
      mean /= g_sdPeriod;
      double var = 0.0;
      for(int k = 0; k < g_sdPeriod; k++)
        {
         double d = price[i - k] - mean;
         var += d * d;
        }
      BufStdDev[i] = MathSqrt(var / g_sdPeriod);

      if(i < g_firstBar)
         continue;

      //--- 2-4. ボラティリティ比率から可変期間を決定
      double asd = 0.0;
      for(int k = 0; k < g_avgPeriod; k++)
         asd += BufStdDev[i - k];
      asd /= g_avgPeriod;

      double vi = (asd > 0.0) ? BufStdDev[i] / asd : 1.0;
      int n = (vi > 0.0) ? (int)(g_basePeriod / vi) : g_maxPeriod;
      if(n < g_minPeriod) n = g_minPeriod;
      if(n > g_maxPeriod) n = g_maxPeriod;

      //--- 5. 期間 N のRSI
      double up = 0.0, dn = 0.0;
      if(InpRsiMode == RSI_WILDER)
        {
         UpdateWilder(i, price);
         up = g_tmpUp[n];
         dn = g_tmpDn[n];
         if(i < rates_total - 1)   // 確定足のみ状態を確定させる
           {
            ArrayCopy(g_avgUp, g_tmpUp);
            ArrayCopy(g_avgDn, g_tmpDn);
            g_stateBar = i;
           }
        }
      else
        {
         for(int k = 0; k < n; k++)
           {
            double diff = price[i - k] - price[i - k - 1];
            if(diff > 0.0) up += diff;
            else           dn -= diff;
           }
        }
      BufVLDMI[i]  = (up + dn > 0.0) ? 100.0 * up / (up + dn) : 50.0;
      BufPeriod[i] = n;
     }

   //--- 初回ロード時は過去のクロスで通知しない
   if(prev_calculated == 0)
      g_lastAlertBar = iTime(_Symbol, _Period, 1);
   else
      CheckAlert(rates_total);
   return(rates_total);
  }

//+------------------------------------------------------------------+
//| 全期間（最小〜最大）のワイルダー平均をバー i まで進める             |
//| 標準RSIと同様、初回は単純平均で初期化し以降は                       |
//|   avg = (前回avg * (p - 1) + 今回の値) / p                        |
//+------------------------------------------------------------------+
void UpdateWilder(const int i, const double &price[])
  {
   double diff = price[i] - price[i - 1];
   double u = (diff > 0.0) ?  diff : 0.0;
   double d = (diff < 0.0) ? -diff : 0.0;
   bool   seed = (g_stateBar != i - 1);

   for(int p = g_minPeriod; p <= g_maxPeriod; p++)
     {
      if(seed)
        {
         double su = 0.0, sd = 0.0;
         for(int k = 0; k < p; k++)
           {
            double df = price[i - k] - price[i - k - 1];
            if(df > 0.0) su += df;
            else         sd -= df;
           }
         g_tmpUp[p] = su / p;
         g_tmpDn[p] = sd / p;
        }
      else
        {
         g_tmpUp[p] = (g_avgUp[p] * (p - 1) + u) / p;
         g_tmpDn[p] = (g_avgDn[p] * (p - 1) + d) / p;
        }
     }
  }

//+------------------------------------------------------------------+
//| 確定足でのレベルクロスを通知                                      |
//+------------------------------------------------------------------+
void CheckAlert(const int rates_total)
  {
   if(!InpAlert && !InpPush)
      return;
   int cur = rates_total - 2;   // 直近の確定足
   int prv = rates_total - 3;
   if(prv < g_firstBar || BufVLDMI[cur] == EMPTY_VALUE || BufVLDMI[prv] == EMPTY_VALUE)
      return;

   datetime barTime = iTime(_Symbol, _Period, 1);
   if(barTime == g_lastAlertBar)
      return;

   string msg = "";
   if(BufVLDMI[prv] < InpOverbought && BufVLDMI[cur] >= InpOverbought)
      msg = StringFormat("上抜け %.0f（買われすぎ）", InpOverbought);
   else if(BufVLDMI[prv] > InpOverbought && BufVLDMI[cur] <= InpOverbought)
      msg = StringFormat("下抜け %.0f（買われすぎ解消）", InpOverbought);
   else if(BufVLDMI[prv] > InpOversold && BufVLDMI[cur] <= InpOversold)
      msg = StringFormat("下抜け %.0f（売られすぎ）", InpOversold);
   else if(BufVLDMI[prv] < InpOversold && BufVLDMI[cur] >= InpOversold)
      msg = StringFormat("上抜け %.0f（売られすぎ解消）", InpOversold);

   g_lastAlertBar = barTime;
   if(msg == "")
      return;

   msg = StringFormat("VLDMI %s %s: %s (%.2f)", _Symbol,
                      StringSubstr(EnumToString(_Period), 7), msg, BufVLDMI[cur]);
   if(InpAlert) Alert(msg);
   if(InpPush)  SendNotification(msg);
  }
//+------------------------------------------------------------------+
