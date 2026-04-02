<!-- OrderList.vue: Displays all orders for the current trader.
     Shows a Cancel button for PENDING and PARTIALLY_FILLED orders. -->
<template>
  <div style="padding: 20px; font-family: Arial, sans-serif;">
    <h2>Order Management — Trader ID: {{ store.currentTraderId }}</h2>

    <button @click="store.fetchOrders()" style="margin-bottom: 10px;">
      Refresh Orders
    </button>

    <div v-if="store.loading" style="color: blue;">Loading...</div>
    <div v-if="store.error" style="color: red;">{{ store.error }}</div>

    <table v-if="store.orders.length > 0" border="1" cellpadding="8"
           style="border-collapse: collapse; width: 100%;">
      <thead style="background-color: #f0f0f0;">
        <tr>
          <th>Order ID</th>
          <th>Side</th>
          <th>Asset ID</th>
          <th>Qty</th>
          <th>Limit Price</th>
          <th>Status</th>
          <th>Order Time</th>
          <th>Action</th>
        </tr>
      </thead>
      <tbody>
        <tr v-for="order in store.orders" :key="order.orderId">
          <td>{{ order.orderId }}</td>
          <td :style="{ color: order.orderSide === 'BUY' ? 'green' : 'red' }">
            {{ order.orderSide }}
          </td>
          <td>{{ order.assetId }}</td>
          <td>{{ order.quantity }}</td>
          <td>{{ order.limitPrice ? '$' + order.limitPrice : 'MARKET' }}</td>
          <td>{{ order.orderStatus }}</td>
          <td>{{ order.orderTime }}</td>
          <td>
            <button
              v-if="['PENDING','PARTIALLY_FILLED'].includes(order.orderStatus)"
              @click="store.cancelOrder(order.orderId)"
              style="background-color: #e74c3c; color: white; cursor: pointer;">
              Cancel
            </button>
            <span v-else style="color: gray;">—</span>
          </td>
        </tr>
      </tbody>
    </table>

    <p v-else-if="!store.loading">No orders found for this trader.</p>
  </div>
</template>

<script setup>
import { onMounted } from 'vue'
import { useOrderStore } from '../stores/orderStore'
const store = useOrderStore()
onMounted(() => store.fetchOrders())
</script>
