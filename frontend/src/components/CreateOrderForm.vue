<!-- CreateOrderForm.vue: Simple form to create a new order via POST /api/orders -->
<template>
  <div style="padding: 20px; border: 1px solid #ccc; margin-bottom: 20px; font-family: Arial, sans-serif;">
    <h3>Create New Order</h3>
    <div v-if="error" style="color: red; margin-bottom: 10px;">{{ error }}</div>

    <div style="display: flex; gap: 10px; flex-wrap: wrap; align-items: end;">
      <label>Asset ID
        <br><input v-model.number="form.assetId" type="number" min="1" style="width: 80px;">
      </label>
      <label>Portfolio ID
        <br><input v-model.number="form.portfolioId" type="number" min="1" style="width: 80px;">
      </label>
      <label>Side
        <br><select v-model="form.orderSide" style="width: 80px;">
          <option value="BUY">BUY</option>
          <option value="SELL">SELL</option>
        </select>
      </label>
      <label>Type
        <br><select v-model="form.orderType" style="width: 120px;">
          <option value="MARKET">MARKET</option>
          <option value="LIMIT">LIMIT</option>
          <option value="STOP">STOP</option>
          <option value="STOP_LIMIT">STOP_LIMIT</option>
        </select>
      </label>
      <label>Quantity
        <br><input v-model.number="form.quantity" type="number" min="1" style="width: 80px;">
      </label>
      <label v-if="form.orderType === 'LIMIT' || form.orderType === 'STOP_LIMIT'">Limit Price
        <br><input v-model.number="form.limitPrice" type="number" min="0" step="0.01" style="width: 100px;">
      </label>
      <button @click="submit" :disabled="submitting"
              style="background-color: #27ae60; color: white; padding: 6px 16px; cursor: pointer;">
        {{ submitting ? 'Submitting...' : 'Submit Order' }}
      </button>
    </div>
  </div>
</template>

<script setup>
import { reactive, ref } from 'vue'
import { useOrderStore } from '../stores/orderStore'

const store = useOrderStore()
const error = ref(null)
const submitting = ref(false)

const form = reactive({
  assetId: 1,
  portfolioId: 1,
  orderSide: 'BUY',
  orderType: 'MARKET',
  quantity: 100,
  limitPrice: null
})

async function submit() {
  error.value = null
  submitting.value = true
  try {
    const payload = {
      traderId: store.currentTraderId,
      assetId: form.assetId,
      portfolioId: form.portfolioId,
      orderSide: form.orderSide,
      orderType: form.orderType,
      quantity: form.quantity,
      limitPrice: (form.orderType === 'LIMIT' || form.orderType === 'STOP_LIMIT') ? form.limitPrice : null
    }
    await store.createOrder(payload)
    await store.fetchOrders()
  } catch (err) {
    error.value = 'Failed to create order: ' + err.message
  } finally {
    submitting.value = false
  }
}
</script>
