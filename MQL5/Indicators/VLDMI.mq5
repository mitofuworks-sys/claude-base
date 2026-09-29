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
//|   5. VLDMI = N 本分の上昇幅合計 / (上昇幅合計 + 下落幅合計) * 100    |
//|   ボラティリティが高いほど N が短くなり、低いほど長くなる。           |
//+------------------------------------------------------------------+
#property copyright   "mitofuworks"
#property version     "1.00"
#property description "Variable Length Dynamic Momentum Index (VLDMI)"
#property description "ボラティリティに応じて計算期間が変わるRSI"

#property indicator_separate_window
#property indicator_minimum 0
#property indicator_maximum 100
#property indicator_buffers 3
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
input int    InpStdDevPeriod    = 5;     // 標準偏差の期間
input int    InpStdDevAvgPeriod = 10;    // 標準偏差の平均期間
input int    InpBasePeriod      = 14;    // 基準期間
input int    InpMinPeriod       = 5;     // 最小期間
input int    InpMaxPeriod       = 30;    // 最大期間
input double InpOverbought      = 70.0;  // 買われすぎレベル
input double InpOversold        = 30.0;  // 売られすぎレベル
input bool   InpAlert           = false; // レベルクロスでアラート
input bool   InpPush            = false; // レベルクロスでプッシュ通知

//--- バッファ
double BufVLDMI[];
double BufPeriod[];
double BufStdDev[];

int      g_sdPeriod, g_avgPeriod, g_basePeriod, g_minPeriod, g_maxPeriod;
int      g_firstBar;
datetime g_lastAlertBar = 0;

//+------------------------------------------------------------------+
int OnInit()
  {
   g_sdPeriod   = MathMax(InpStdDevPeriod, 2);
   g_avgPeriod  = MathMax(InpStdDevAvgPeriod, 1);
   g_basePeriod = MathMax(InpBasePeriod, 1);
   g_minPeriod  = MathMax(InpMinPeriod, 1);
   g_maxPeriod  = MathMax(InpMaxPeriod, g_minPeriod);

   SetIndexBuffer(0, BufVLDMI,  INDICATOR_DATA);
   SetIndexBuffer(1, BufPeriod, INDICATOR_DATA);
   SetIndexBuffer(2, BufStdDev, INDICATOR_CALCULATIONS);

   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   IndicatorSetInteger(INDICATOR_DIGITS, 2);
   IndicatorSetInteger(INDICATOR_LEVELS, 3);
   IndicatorSetDouble(INDICATOR_LEVELVALUE, 0, InpOverbought);
   IndicatorSetDouble(INDICATOR_LEVELVALUE, 1, 50.0);
   IndicatorSetDouble(INDICATOR_LEVELVALUE, 2, InpOversold);
   IndicatorSetInteger(INDICATOR_LEVELCOLOR, clrSilver);
   IndicatorSetInteger(INDICATOR_LEVELSTYLE, STYLE_DOT);

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
      start = sdStart;
     }
   else
      start = prev_calculated - 1;

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

      //--- 5. N 本分でのRSI計算
      double up = 0.0, dn = 0.0;
      for(int k = 0; k < n; k++)
        {
         double diff = price[i - k] - price[i - k - 1];
         if(diff > 0.0) up += diff;
         else           dn -= diff;
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
