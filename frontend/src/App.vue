<!-- App.vue: Root component — renders the OrderList dashboard -->
<template>
  <div style="max-width: 1200px; margin: 0 auto; padding: 20px;">
    <h1>Capital Markets Trading Platform</h1>
    <CreateOrderForm />
    <OrderList />
  </div>
</template>

<script setup>
import OrderList from './components/OrderList.vue'
import CreateOrderForm from './components/CreateOrderForm.vue'
</script>
