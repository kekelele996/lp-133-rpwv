<template>
  <div class="min-h-screen bg-gray-50">
    <div class="container mx-auto px-4 py-6">
      <h1 class="text-2xl font-bold text-gray-800 mb-6">我的订单</h1>
      
      <el-card class="mb-6">
        <el-tabs v-model="activeTab" @tab-change="fetchOrders">
          <el-tab-pane label="进行中" name="in_progress" />
          <el-tab-pane label="已完成" name="completed" />
          <el-tab-pane label="已取消" name="cancelled" />
          <el-tab-pane label="全部" name="" />
        </el-tabs>
      </el-card>
      
      <div v-if="loading" class="text-center py-16">
        <el-icon class="animate-spin text-4xl text-gray-400"><Loading /></el-icon>
      </div>
      
      <div v-else-if="orders.length === 0" class="text-center py-16">
        <el-icon class="text-6xl text-gray-300"><Document /></el-icon>
        <p class="mt-4 text-gray-500">暂无订单</p>
      </div>
      
      <div v-else class="space-y-4">
        <el-card v-for="order in orders" :key="order.id" class="hover:shadow-md">
          <div class="flex items-start justify-between">
            <div class="flex-1">
              <div class="flex items-center mb-2">
                <h3 class="font-medium text-lg mr-3">{{ order.title }}</h3>
                <el-tag :type="getTypeColor(order.type)" size="small">
                  {{ getTypeName(order.type) }}
                </el-tag>
                <el-tag v-if="order.status === 'in_progress'" type="warning" class="ml-2" size="small">进行中</el-tag>
                <el-tag v-else-if="order.status === 'completed'" type="success" class="ml-2" size="small">已完成</el-tag>
                <el-tag v-else-if="order.status === 'cancelled'" type="danger" class="ml-2" size="small">已取消</el-tag>
              </div>

              <div v-if="order.status === 'cancelled' && order.cancel_reason" class="text-sm text-gray-500 mb-3 bg-gray-100 rounded px-3 py-2">
                <el-icon class="mr-1 align-middle"><WarningFilled /></el-icon>
                <span class="align-middle">释放原因：{{ order.cancel_reason }}</span>
              </div>

              <div class="text-gray-600 text-sm mb-3">
                <p v-if="user?.role === 'volunteer'">
                  <el-icon class="mr-1"><User /></el-icon>
                  服务对象：{{ order.user_name }}
                </p>
                <p v-else>
                  <el-icon class="mr-1"><Service /></el-icon>
                  志愿者：{{ order.volunteer_name }}
                </p>
                <p class="mt-1">
                  <el-icon class="mr-1"><Location /></el-icon>
                  {{ order.address }}
                </p>
                <p v-if="order.service_hours" class="mt-1">
                  <el-icon class="mr-1"><Clock /></el-icon>
                  服务时长：{{ order.service_hours }} 小时
                </p>
              </div>
              
              <div class="text-xs text-gray-400">
                下单时间：{{ new Date(order.created_at).toLocaleString() }}
              </div>
            </div>
            
            <div class="flex flex-col gap-2">
              <el-button
                v-if="order.status === 'in_progress'"
                type="primary"
                size="small"
                @click="handleComplete(order)"
              >
                完成服务
              </el-button>
              <el-button
                v-if="order.status === 'in_progress' && user?.role === 'volunteer' && order.volunteer_id === user.id"
                type="danger"
                plain
                size="small"
                @click="showReleaseDialog(order)"
              >
                临时去不了，释放订单
              </el-button>
              <el-button 
                v-if="order.status === 'completed' && !hasReviewed(order.id)" 
                type="success" 
                size="small"
                @click="showReviewDialog(order)"
              >
                去评价
              </el-button>
              <el-button 
                type="text" 
                size="small"
                @click="handleMessage(order)"
              >
                <el-icon class="mr-1"><ChatDotRound /></el-icon>
                发消息
              </el-button>
            </div>
          </div>
        </el-card>
      </div>
    </div>
    
    <el-dialog v-model="reviewDialogVisible" title="服务评价" width="500px">
      <el-form :model="reviewForm" label-width="80px">
        <el-form-item label="评分">
          <el-rate v-model="reviewForm.rating" :max="5" show-score />
        </el-form-item>
        <el-form-item label="评价内容">
          <el-input v-model="reviewForm.comment" type="textarea" :rows="3" placeholder="请输入评价内容" />
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="reviewDialogVisible = false">取消</el-button>
        <el-button type="primary" :loading="submittingReview" @click="submitReview">提交评价</el-button>
      </template>
    </el-dialog>

    <el-dialog v-model="releaseDialogVisible" title="释放订单" width="500px">
      <el-alert
        type="warning"
        :closable="false"
        show-icon
        class="mb-4"
        title="释放后订单将标记为已取消，该需求会重新回到待接单，居民可再找其他志愿者。"
      />
      <el-form label-width="80px">
        <el-form-item label="释放原因" required>
          <el-input
            v-model="releaseReason"
            type="textarea"
            :rows="3"
            maxlength="500"
            show-word-limit
            placeholder="请填写临时无法前往的原因（必填）"
          />
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="releaseDialogVisible = false">取消</el-button>
        <el-button type="danger" :loading="submittingRelease" @click="submitRelease">确认释放</el-button>
      </template>
    </el-dialog>
  </div>
</template>

<script setup>
import { ref, onMounted, computed } from 'vue'
import { useRouter } from 'vue-router'
import { useUserStore } from '@/stores/user'
import api from '@/utils/api'
import { ElMessage, ElMessageBox } from 'element-plus'

const router = useRouter()
const userStore = useUserStore()
const user = computed(() => userStore.user)

const orders = ref([])
const loading = ref(false)
const activeTab = ref('in_progress')
const reviewDialogVisible = ref(false)
const submittingReview = ref(false)
const currentOrder = ref(null)
const reviewedOrders = ref([])

const releaseDialogVisible = ref(false)
const submittingRelease = ref(false)
const releaseReason = ref('')
const releasingOrder = ref(null)

const reviewForm = ref({
  rating: 5,
  comment: ''
})

const typeMap = {
  accompany: { name: '陪聊陪诊', color: 'blue' },
  shopping: { name: '代买代办', color: 'green' },
  repair: { name: '家电维修', color: 'orange' },
  housework: { name: '家政服务', color: 'purple' },
  other: { name: '其他帮助', color: 'gray' }
}

const getTypeName = (type) => typeMap[type]?.name || type
const getTypeColor = (type) => typeMap[type]?.color || 'info'

const hasReviewed = (orderId) => reviewedOrders.value.includes(orderId)

const fetchOrders = async () => {
  loading.value = true
  try {
    const params = activeTab.value ? { status: activeTab.value } : {}
    const res = await api.get('/orders', { params })
    orders.value = res.data.orders
  } finally {
    loading.value = false
  }
}

const handleComplete = async (order) => {
  try {
    await ElMessageBox.confirm('确认服务已完成吗？', '完成确认', {
      confirmButtonText: '确定',
      cancelButtonText: '取消',
      type: 'info'
    })
    
    await api.put(`/orders/${order.id}/complete`, { service_hours: 1 })
    ElMessage.success('服务已完成')
    fetchOrders()
    userStore.fetchUserInfo()
  } catch (e) {
    if (e !== 'cancel') {
      ElMessage.error(e.response?.data?.message || '操作失败')
    }
  }
}

const showReviewDialog = (order) => {
  currentOrder.value = order
  reviewForm.value = { rating: 5, comment: '' }
  reviewDialogVisible.value = true
}

const submitReview = async () => {
  try {
    submittingReview.value = true
    await api.post(`/orders/${currentOrder.value.id}/review`, reviewForm.value)
    reviewedOrders.value.push(currentOrder.value.id)
    ElMessage.success('评价成功')
    reviewDialogVisible.value = false
  } catch (e) {
    ElMessage.error(e.response?.data?.message || '评价失败')
  } finally {
    submittingReview.value = false
  }
}

const handleMessage = (order) => {
  const otherUserId = user.value.role === 'volunteer' ? order.user_id : order.volunteer_id
  router.push({
    path: '/messages',
    query: { userId: otherUserId }
  })
}

const showReleaseDialog = (order) => {
  releasingOrder.value = order
  releaseReason.value = ''
  releaseDialogVisible.value = true
}

const submitRelease = async () => {
  const reason = releaseReason.value.trim()
  if (!reason) {
    ElMessage.warning('请填写释放原因')
    return
  }

  try {
    submittingRelease.value = true
    await api.post(`/orders/${releasingOrder.value.id}/release`, {
      cancel_reason: reason
    })
    ElMessage.success('订单已释放，需求已重新开放')
    releaseDialogVisible.value = false
    fetchOrders()
  } catch (e) {
    // 错误信息已由 api 拦截器统一提示
  } finally {
    submittingRelease.value = false
  }
}

onMounted(() => {
  fetchOrders()
})
</script>
