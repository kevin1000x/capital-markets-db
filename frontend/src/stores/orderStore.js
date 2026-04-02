// Pinia store — manages order state and API calls to Spring Boot backend
import { defineStore } from 'pinia'
import axios from 'axios'

const API = '/api/orders'

export const useOrderStore = defineStore('orders', {
    state: () => ({
        orders: [],
        loading: false,
        error: null,
        currentTraderId: 1
    }),

    actions: {
        async fetchOrders() {
            this.loading = true
            this.error = null
            try {
                const response = await axios.get(`${API}/${this.currentTraderId}`)
                this.orders = response.data
            } catch (err) {
                this.error = 'Failed to load orders: ' + err.message
            } finally {
                this.loading = false
            }
        },

        async createOrder(orderData) {
            this.loading = true
            this.error = null
            try {
                const response = await axios.post(API, orderData)
                return response.data
            } catch (err) {
                this.error = 'Failed to create order: ' + err.message
                throw err
            } finally {
                this.loading = false
            }
        },

        async cancelOrder(orderId) {
            this.loading = true
            this.error = null
            try {
                const response = await axios.post(
                    `${API}/${orderId}/cancel`,
                    null,
                    { params: { traderId: this.currentTraderId } }
                )
                if (response.data.success === true) {
                    alert('Order cancelled! Refund: $' + response.data.refundAmount)
                    await this.fetchOrders()
                } else {
                    this.error = response.data.message
                }
            } catch (err) {
                this.error = 'Cancel request failed: ' + err.message
            } finally {
                this.loading = false
            }
        }
    }
})
