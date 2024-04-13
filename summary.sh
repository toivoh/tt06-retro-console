
echo "Linter output"
echo "============="
cat runs/wokwi/logs/synthesis/linter.log
echo

echo "Cell usage"
echo "=========="
#cat runs/wokwi/reports/synthesis/1-synthesis.AREA_0.stat.rpt
grep "Number of" runs/wokwi/reports/synthesis/1-synthesis.AREA_0.stat.rpt
grep "dfxtp" runs/wokwi/reports/synthesis/1-synthesis.AREA_0.stat.rpt
grep "Chip area" runs/wokwi/reports/synthesis/1-synthesis.AREA_0.stat.rpt
echo

echo "Utilization"
echo "==========="
echo "## 7-global.log"
grep Util runs/wokwi/logs/placement/6-global.log
echo
echo "## 21-grt_sta.log"
grep utilization runs/wokwi/logs/routing/21-grt_sta.log
echo

echo "STA"
echo "==="
grep "worst.slack" runs/wokwi/reports/signoff/28-sta-rcx_max/multi_corner_sta.summary.rpt
echo

echo "Fanout etc"
echo "=========="
grep "violations count" runs/wokwi/reports/signoff/30-sta-rcx_nom/multi_corner_sta.checks.rpt
echo
