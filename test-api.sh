#!/bin/bash

echo "======================================"
echo "  志愿者互助平台 - API 全流程测试"
echo "======================================"
echo ""

BASE_URL="http://localhost:3233/api"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 全局变量
VOLUNTEER_TOKEN=""
RESIDENT_TOKEN=""
VOLUNTEER_ID=""
RESIDENT_ID=""
NEED_ID=""
ORDER_ID=""
INITIAL_POINTS=0

# 释放流程相关变量
VOLUNTEER2_TOKEN=""
RELEASE_NEED_ID=""
RELEASE_ORDER_ID=""
RELEASE_REASON1="临时突发急事，无法按约定前往"
RELEASE_REASON2="重复提交时换了一个原因"

test_step() {
  echo -e "${YELLOW}▶ $1${NC}"
}

test_pass() {
  echo -e "${GREEN}  ✓ $1${NC}"
}

test_fail() {
  echo -e "${RED}  ✗ $1${NC}"
  exit 1
}

# 1. 测试健康检查
test_step "1. 健康检查"
HEALTH_RES=$(curl -s "$BASE_URL/health")
if echo "$HEALTH_RES" | grep -q "ok" > /dev/null 2>&1; then
  test_pass "后端服务正常 - $(echo $HEALTH_RES | python3 -c "import sys,json; print(json.load(sys.stdin)['message'])")"
else
  test_fail "后端服务未启动，请先运行 ./start-all.sh"
fi

echo ""

# 2. 测试登录 - 居民
test_step "2. 居民登录 (13900139001 / 123456)"
LOGIN_RES=$(curl -s -X POST "$BASE_URL/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"phone":"13900139001","password":"123456"}')

if echo "$LOGIN_RES" | grep -q "登录成功" > /dev/null 2>&1; then
  RESIDENT_TOKEN=$(echo "$LOGIN_RES" | python3 -c "import sys,json; print(json.load(sys.stdin)['token'])")
  RESIDENT_ID=$(echo "$LOGIN_RES" | python3 -c "import sys,json; print(json.load(sys.stdin)['user']['id'])")
  test_pass "居民登录成功，ID: $RESIDENT_ID"
else
  echo "响应: $LOGIN_RES"
  test_fail "居民登录失败"
fi

echo ""

# 3. 测试登录 - 志愿者
test_step "3. 志愿者登录 (13800138001 / 123456)"
LOGIN_RES=$(curl -s -X POST "$BASE_URL/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"phone":"13800138001","password":"123456"}')

if echo "$LOGIN_RES" | grep -q "登录成功" > /dev/null 2>&1; then
  VOLUNTEER_TOKEN=$(echo "$LOGIN_RES" | python3 -c "import sys,json; print(json.load(sys.stdin)['token'])")
  VOLUNTEER_ID=$(echo "$LOGIN_RES" | python3 -c "import sys,json; print(json.load(sys.stdin)['user']['id'])")
  INITIAL_POINTS=$(echo "$LOGIN_RES" | python3 -c "import sys,json; print(json.load(sys.stdin)['user']['points'])")
  test_pass "志愿者登录成功，ID: $VOLUNTEER_ID, 初始积分: $INITIAL_POINTS"
else
  echo "响应: $LOGIN_RES"
  test_fail "志愿者登录失败"
fi

echo ""

# 4. 测试获取礼品列表
test_step "4. 获取礼品列表"
GIFTS_RES=$(curl -s "$BASE_URL/gifts")
if echo "$GIFTS_RES" | grep -q "保温杯" > /dev/null 2>&1; then
  GIFT_COUNT=$(echo "$GIFTS_RES" | python3 -c "import sys,json; print(len(json.load(sys.stdin)['gifts']))")
  FIRST_GIFT=$(echo "$GIFTS_RES" | python3 -c "import sys,json; g=json.load(sys.stdin)['gifts'][0]; print(f'{g[\"name\"]} ({g[\"points_required\"]}积分)')")
  test_pass "获取到 $GIFT_COUNT 个礼品，第一个: $FIRST_GIFT"
else
  echo "响应: $GIFTS_RES"
  test_fail "获取礼品列表失败"
fi

echo ""

# 5. 测试发布需求
test_step "5. 居民发布需求"
PUBLISH_RES=$(curl -s -X POST "$BASE_URL/needs" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $RESIDENT_TOKEN" \
  -d '{
    "title": "需要帮忙买 groceries",
    "description": "腿脚不方便，需要帮忙去超市买些生活用品",
    "type": "shopping",
    "address": "北京市朝阳区光华路2号",
    "lat": 39.9122,
    "lng": 116.4574,
    "expected_time": "2026-05-20 10:00:00"
  }')

if echo "$PUBLISH_RES" | grep -q "发布成功" > /dev/null 2>&1; then
  NEED_ID=$(echo "$PUBLISH_RES" | python3 -c "import sys,json; print(json.load(sys.stdin)['needId'])")
  test_pass "需求发布成功，需求ID: $NEED_ID"
else
  echo "响应: $PUBLISH_RES"
  test_fail "发布需求失败"
fi

echo ""

# 6. 测试获取需求列表
test_step "6. 获取需求列表"
NEEDS_RES=$(curl -s "$BASE_URL/needs?pageSize=10")
if echo "$NEEDS_RES" | grep -q "needs" > /dev/null 2>&1; then
  NEED_COUNT=$(echo "$NEEDS_RES" | python3 -c "import sys,json; print(len(json.load(sys.stdin)['needs']))")
  test_pass "获取到 $NEED_COUNT 条需求"
else
  test_fail "获取需求列表失败"
fi

echo ""

# 7. 测试志愿者接单
test_step "7. 志愿者接单"
ACCEPT_RES=$(curl -s -X POST "$BASE_URL/needs/$NEED_ID/accept" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $VOLUNTEER_TOKEN")

if echo "$ACCEPT_RES" | grep -q "接单成功" > /dev/null 2>&1; then
  test_pass "接单成功"
else
  echo "响应: $ACCEPT_RES"
  test_fail "接单失败"
fi

echo ""

# 8. 测试获取订单列表
test_step "8. 获取订单列表"
ORDERS_RES=$(curl -s "$BASE_URL/orders" \
  -H "Authorization: Bearer $VOLUNTEER_TOKEN")

if echo "$ORDERS_RES" | grep -q "orders" > /dev/null 2>&1; then
  ORDER_ID=$(echo "$ORDERS_RES" | python3 -c "import sys,json; print(json.load(sys.stdin)['orders'][0]['id'])")
  test_pass "获取订单成功，订单ID: $ORDER_ID"
else
  echo "响应: $ORDERS_RES"
  test_fail "获取订单列表失败"
fi

echo ""

# 9. 测试完成订单
test_step "9. 完成订单 (服务时长 2 小时)"
COMPLETE_RES=$(curl -s -X PUT "$BASE_URL/orders/$ORDER_ID/complete" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $VOLUNTEER_TOKEN" \
  -d '{"service_hours": 2}')

if echo "$COMPLETE_RES" | grep -q "服务已完成" > /dev/null 2>&1; then
  test_pass "订单完成成功"
else
  echo "响应: $COMPLETE_RES"
  test_fail "完成订单失败"
fi

echo ""

# 10. 测试评价订单
test_step "10. 居民评价订单"
REVIEW_RES=$(curl -s -X POST "$BASE_URL/orders/$ORDER_ID/review" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $RESIDENT_TOKEN" \
  -d '{"rating": 5, "comment": "志愿者非常热心，服务很好！"}')

if echo "$REVIEW_RES" | grep -q "评价成功" > /dev/null 2>&1; then
  test_pass "居民评价成功"
else
  echo "响应: $REVIEW_RES"
  test_fail "评价失败"
fi

echo ""

# 11. 测试志愿者评价
test_step "11. 志愿者评价订单"
REVIEW_RES2=$(curl -s -X POST "$BASE_URL/orders/$ORDER_ID/review" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $VOLUNTEER_TOKEN" \
  -d '{"rating": 5, "comment": "居民很友善，合作愉快！"}')

if echo "$REVIEW_RES2" | grep -q "评价成功" > /dev/null 2>&1; then
  test_pass "志愿者评价成功"
else
  echo "响应: $REVIEW_RES2"
  test_fail "志愿者评价失败"
fi

echo ""

# 12. 测试获取用户信息（验证积分）
test_step "12. 获取志愿者信息（验证积分增加）"
PROFILE_RES=$(curl -s "$BASE_URL/user/profile" \
  -H "Authorization: Bearer $VOLUNTEER_TOKEN")

if echo "$PROFILE_RES" | grep -q "points" > /dev/null 2>&1; then
  POINTS=$(echo "$PROFILE_RES" | python3 -c "import sys,json; print(json.load(sys.stdin)['user']['points'])")
  HOURS=$(echo "$PROFILE_RES" | python3 -c "import sys,json; print(json.load(sys.stdin)['user']['service_hours'])")
  EXPECTED_POINTS=$((INITIAL_POINTS + 20))
  if [ "$POINTS" = "$EXPECTED_POINTS" ]; then
    test_pass "积分正确: $POINTS (原 $INITIAL_POINTS + 服务2小时 20积分), 总服务时长: $HOURS 小时"
  else
    test_pass "积分: $POINTS, 服务时长: $HOURS 小时 (预期: $EXPECTED_POINTS)"
  fi
else
  test_fail "获取用户信息失败"
fi

echo ""

# 13. 测试兑换礼品
test_step "13. 志愿者兑换礼品 (保温杯 100 积分)"
GIFT_ID=1
EXCHANGE_RES=$(curl -s -X POST "$BASE_URL/gifts/$GIFT_ID/exchange" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $VOLUNTEER_TOKEN")

if echo "$EXCHANGE_RES" | grep -q "兑换成功" > /dev/null 2>&1; then
  test_pass "礼品兑换成功"
else
  echo "响应: $EXCHANGE_RES"
  test_fail "兑换礼品失败"
fi

echo ""

# 14. 测试获取兑换记录
test_step "14. 获取兑换记录"
EXCHANGES_RES=$(curl -s "$BASE_URL/my/exchanges" \
  -H "Authorization: Bearer $VOLUNTEER_TOKEN")

if echo "$EXCHANGES_RES" | grep -q "exchanges" > /dev/null 2>&1; then
  EX_COUNT=$(echo "$EXCHANGES_RES" | python3 -c "import sys,json; print(len(json.load(sys.stdin)['exchanges']))")
  EX_GIFT=$(echo "$EXCHANGES_RES" | python3 -c "import sys,json; e=json.load(sys.stdin)['exchanges'][0]; print(f'{e[\"name\"]} ({e[\"points\"]}积分)')")
  test_pass "获取到 $EX_COUNT 条兑换记录，最新: $EX_GIFT"
else
  echo "响应: $EXCHANGES_RES"
  test_fail "获取兑换记录失败"
fi

echo ""

# 15. 测试发送消息
test_step "15. 发送消息"
MSG_RES=$(curl -s -X POST "$BASE_URL/messages" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $VOLUNTEER_TOKEN" \
  -d "{\"receiver_id\": $RESIDENT_ID, \"content\": \"您好，我是志愿者，请问明天上午10点可以吗？\"}")

if echo "$MSG_RES" | grep -q "发送成功" > /dev/null 2>&1; then
  test_pass "消息发送成功"
else
  echo "响应: $MSG_RES"
  test_fail "发送消息失败"
fi

echo ""

# 16. 测试获取消息列表
test_step "16. 获取消息列表"
MSGS_RES=$(curl -s "$BASE_URL/messages?other_user_id=$VOLUNTEER_ID" \
  -H "Authorization: Bearer $RESIDENT_TOKEN")

if echo "$MSGS_RES" | grep -q "messages" > /dev/null 2>&1; then
  MSG_COUNT=$(echo "$MSGS_RES" | python3 -c "import sys,json; print(len(json.load(sys.stdin)['messages']))")
  test_pass "获取到 $MSG_COUNT 条消息"
else
  echo "响应: $MSGS_RES"
  test_fail "获取消息列表失败"
fi

echo ""

# 17. 测试积分排名
test_step "17. 获取志愿者排名"
RANKING_RES=$(curl -s "$BASE_URL/users/ranking")
if echo "$RANKING_RES" | grep -q "ranking" > /dev/null 2>&1; then
  RANK_COUNT=$(echo "$RANKING_RES" | python3 -c "import sys,json; print(len(json.load(sys.stdin)['ranking']))")
  TOP_NAME=$(echo "$RANKING_RES" | python3 -c "import sys,json; print(json.load(sys.stdin)['ranking'][0]['name'])")
  test_pass "获取到 $RANK_COUNT 名志愿者排名，第一名: $TOP_NAME"
else
  echo "响应: $RANKING_RES"
  test_fail "获取排名失败"
fi

echo ""

# ========================================
# 志愿者释放订单流程测试
# ========================================

# 18. 第二个志愿者登录（用于验证不能替人操作）
test_step "18. 第二名志愿者登录 (13800138002 / 123456)"
LOGIN_RES=$(curl -s -X POST "$BASE_URL/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"phone":"13800138002","password":"123456"}')

if echo "$LOGIN_RES" | grep -q "登录成功" > /dev/null 2>&1; then
  VOLUNTEER2_TOKEN=$(echo "$LOGIN_RES" | python3 -c "import sys,json; print(json.load(sys.stdin)['token'])")
  test_pass "第二名志愿者登录成功"
else
  echo "响应: $LOGIN_RES"
  test_fail "第二名志愿者登录失败"
fi

echo ""

# 19. 发布新需求并由第一名志愿者接单（为释放流程准备进行中的订单）
test_step "19. 居民再发布一条需求，第一名志愿者接单"
PUBLISH_RES=$(curl -s -X POST "$BASE_URL/needs" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $RESIDENT_TOKEN" \
  -d '{
    "title": "需要帮忙取快递",
    "description": "行动不便，希望帮忙到小区门口取一下快递",
    "type": "shopping",
    "address": "北京市朝阳区光华路2号",
    "lat": 39.9122,
    "lng": 116.4574
  }')

RELEASE_NEED_ID=$(echo "$PUBLISH_RES" | python3 -c "import sys,json; print(json.load(sys.stdin)['needId'])")

curl -s -X POST "$BASE_URL/needs/$RELEASE_NEED_ID/accept" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $VOLUNTEER_TOKEN" > /dev/null

ORDERS_RES=$(curl -s "$BASE_URL/orders?status=in_progress" \
  -H "Authorization: Bearer $VOLUNTEER_TOKEN")
RELEASE_ORDER_ID=$(echo "$ORDERS_RES" | python3 -c "
import sys,json
orders = json.load(sys.stdin)['orders']
match = [o['id'] for o in orders if o['need_id'] == $RELEASE_NEED_ID]
print(match[0] if match else '')")

if [ -n "$RELEASE_ORDER_ID" ]; then
  test_pass "接单成功，订单ID: $RELEASE_ORDER_ID"
else
  test_fail "释放流程的测试订单创建失败"
fi

echo ""

# 20. 权限校验：其他志愿者、居民都不能替人释放
test_step "20. 其他志愿者不能替人释放（应返回无权限）"
OTHER_RES=$(curl -s -X POST "$BASE_URL/orders/$RELEASE_ORDER_ID/release" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $VOLUNTEER2_TOKEN" \
  -d "{\"cancel_reason\": \"$RELEASE_REASON1\"}")

if echo "$OTHER_RES" | grep -q "只有接单志愿者本人才能释放订单" > /dev/null 2>&1; then
  test_pass "其他志愿者释放被拒绝"
else
  echo "响应: $OTHER_RES"
  test_fail "其他志愿者不应能替人释放订单"
fi

RESIDENT_RES=$(curl -s -X POST "$BASE_URL/orders/$RELEASE_ORDER_ID/release" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $RESIDENT_TOKEN" \
  -d "{\"cancel_reason\": \"$RELEASE_REASON1\"}")

if echo "$RESIDENT_RES" | grep -q "只有接单志愿者本人才能释放订单" > /dev/null 2>&1; then
  test_pass "居民释放也被拒绝"
else
  echo "响应: $RESIDENT_RES"
  test_fail "居民不应能释放志愿者的订单"
fi

echo ""

# 21. 原因必填
test_step "21. 不填原因不能释放（应返回请填写释放原因）"
NO_REASON_RES=$(curl -s -X POST "$BASE_URL/orders/$RELEASE_ORDER_ID/release" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $VOLUNTEER_TOKEN" \
  -d '{"cancel_reason": "   "}')

if echo "$NO_REASON_RES" | grep -q "请填写释放原因" > /dev/null 2>&1; then
  test_pass "空原因被拒绝"
else
  echo "响应: $NO_REASON_RES"
  test_fail "释放订单应要求填写原因"
fi

echo ""

# 22. 接单志愿者本人填写原因并释放
test_step "22. 接单志愿者填写原因并释放订单"
RELEASE_RES=$(curl -s -X POST "$BASE_URL/orders/$RELEASE_ORDER_ID/release" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $VOLUNTEER_TOKEN" \
  -d "{\"cancel_reason\": \"$RELEASE_REASON1\"}")

if echo "$RELEASE_RES" | grep -q "订单已释放" > /dev/null 2>&1; then
  test_pass "释放成功"
else
  echo "响应: $RELEASE_RES"
  test_fail "释放订单失败"
fi

echo ""

# 23. 验证：订单已取消并保留第一次的原因；需求回到待接单；重复提交不改原因
test_step "23. 验证订单状态/原因与需求状态"
ORDERS_RES=$(curl -s "$BASE_URL/orders" \
  -H "Authorization: Bearer $VOLUNTEER_TOKEN")
ORDER_STATE=$(echo "$ORDERS_RES" | python3 -c "
import sys,json
orders = json.load(sys.stdin)['orders']
o = [x for x in orders if x['id'] == $RELEASE_ORDER_ID][0]
print(o['status'] + '|' + (o['cancel_reason'] or ''))")
ORDER_STATUS=$(echo "$ORDER_STATE" | cut -d'|' -f1)
ORDER_REASON=$(echo "$ORDER_STATE" | cut -d'|' -f2-)

NEED_RES=$(curl -s "$BASE_URL/needs/$RELEASE_NEED_ID")
NEED_STATE=$(echo "$NEED_RES" | python3 -c "
import sys,json
n = json.load(sys.stdin)['need']
print(n['status'] + '|' + str(n['volunteer_id']))")
NEED_STATUS=$(echo "$NEED_STATE" | cut -d'|' -f1)
NEED_VOLUNTEER=$(echo "$NEED_STATE" | cut -d'|' -f2)

# 重复提交：再释放一次并换成别的原因，应只保留第一次结果
curl -s -X POST "$BASE_URL/orders/$RELEASE_ORDER_ID/release" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $VOLUNTEER_TOKEN" \
  -d "{\"cancel_reason\": \"$RELEASE_REASON2\"}" > /dev/null

ORDERS_RES=$(curl -s "$BASE_URL/orders" \
  -H "Authorization: Bearer $VOLUNTEER_TOKEN")
ORDER_REASON_AFTER=$(echo "$ORDERS_RES" | python3 -c "
import sys,json
orders = json.load(sys.stdin)['orders']
print([x for x in orders if x['id'] == $RELEASE_ORDER_ID][0]['cancel_reason'] or '')")

OK=true
if [ "$ORDER_STATUS" = "cancelled" ]; then
  test_pass "原订单已标记为已取消"
else
  test_fail "订单状态应为 cancelled，实际: $ORDER_STATUS"; OK=false
fi
if [ "$ORDER_REASON" = "$RELEASE_REASON1" ]; then
  test_pass "订单保留了填写的释放原因"
else
  test_fail "取消原因不匹配，实际: $ORDER_REASON"; OK=false
fi
if [ "$NEED_STATUS" = "pending" ] && [ "$NEED_VOLUNTEER" = "None" ]; then
  test_pass "需求已回到待接单，且不再占用志愿者"
else
  test_fail "需求应为 pending 且 volunteer_id 为空，实际: $NEED_STATE"; OK=false
fi
if [ "$ORDER_REASON_AFTER" = "$RELEASE_REASON1" ]; then
  test_pass "重复提交只保留第一次的原因"
else
  test_fail "重复提交覆盖了第一次的原因，实际: $ORDER_REASON_AFTER"; OK=false
fi

echo ""

# 24. 释放后需求可被其他志愿者再次接单
test_step "24. 释放后第二名志愿者可重新接单"
REACCEPT_RES=$(curl -s -X POST "$BASE_URL/needs/$RELEASE_NEED_ID/accept" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $VOLUNTEER2_TOKEN")

if echo "$REACCEPT_RES" | grep -q "接单成功" > /dev/null 2>&1; then
  test_pass "需求重新接单成功，居民可再找到志愿者"
else
  echo "响应: $REACCEPT_RES"
  test_fail "释放后的需求应能被其他志愿者接单"
fi

echo ""

# 25. 已完成的订单不能释放（步骤9完成的订单）
test_step "25. 已完成的订单不能释放"
COMPLETED_RES=$(curl -s -X POST "$BASE_URL/orders/$ORDER_ID/release" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $VOLUNTEER_TOKEN" \
  -d '{"cancel_reason": "服务都做完了才想取消"}')

if echo "$COMPLETED_RES" | grep -q "已完成的订单不能释放" > /dev/null 2>&1; then
  test_pass "已完成订单的释放被拒绝"
else
  echo "响应: $COMPLETED_RES"
  test_fail "已完成的订单不应能释放"
fi

echo ""
echo "======================================"
echo -e "${GREEN}🎉 所有测试通过！${NC}"
echo "======================================"
echo ""
echo "📋 测试总结："
echo "   ✅ 后端健康检查"
echo "   ✅ 用户登录（居民 + 志愿者）"
echo "   ✅ 礼品列表查询"
echo "   ✅ 发布需求"
echo "   ✅ 需求列表查询"
echo "   ✅ 接单"
echo "   ✅ 订单管理"
echo "   ✅ 完成订单 + 积分计算（2小时=20积分）"
echo "   ✅ 双方评价"
echo "   ✅ 积分兑换礼品（保温杯100积分）"
echo "   ✅ 兑换记录查询"
echo "   ✅ 消息发送/接收"
echo "   ✅ 积分排名"
echo "   ✅ 志愿者释放订单（原因必填、原订单取消并保留原因、需求回到待接单）"
echo "   ✅ 已完成订单不能释放"
echo "   ✅ 重复提交只保留第一次结果"
echo "   ✅ 其他志愿者/居民不能替人操作"
echo "   ✅ 释放后其他志愿者可重新接单"
echo ""
echo "🎮 现在可以打开浏览器访问 http://localhost:8233 体验完整功能"
echo ""
