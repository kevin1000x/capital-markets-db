// REST controller — 3 endpoints for orders CRUD and stored procedure cancellation
package com.trading.controller;

import com.trading.model.Order;
import com.trading.repository.OrderRepository;
import jakarta.persistence.EntityManager;
import jakarta.persistence.ParameterMode;
import jakarta.persistence.StoredProcedureQuery;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.math.BigDecimal;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/orders")
@CrossOrigin(origins = "http://localhost:5173")
public class OrderController {

    private final OrderRepository orderRepository;
    private final EntityManager entityManager;

    public OrderController(OrderRepository orderRepository, EntityManager entityManager) {
        this.orderRepository = orderRepository;
        this.entityManager = entityManager;
    }

    // GET /api/orders/{traderId} — returns all orders for a trader
    @GetMapping("/{traderId}")
    public ResponseEntity<List<Order>> getOrders(@PathVariable Long traderId) {
        return ResponseEntity.ok(orderRepository.findByTraderId(traderId));
    }

    // POST /api/orders — creates a new order
    @PostMapping
    public ResponseEntity<Order> createOrder(@RequestBody Order order) {
        Order saved = orderRepository.save(order);
        return ResponseEntity.status(201).body(saved);
    }

    // POST /api/orders/{orderId}/cancel — calls sp_cancel_order_refund
    @PostMapping("/{orderId}/cancel")
    public ResponseEntity<Map<String, Object>> cancelOrder(
            @PathVariable Long orderId,
            @RequestParam Long traderId) {

        StoredProcedureQuery query = entityManager
                .createStoredProcedureQuery("sp_cancel_order_refund")
                .registerStoredProcedureParameter("p_order_id", Long.class, ParameterMode.IN)
                .registerStoredProcedureParameter("p_trader_id", Long.class, ParameterMode.IN)
                .registerStoredProcedureParameter("p_success", Boolean.class, ParameterMode.OUT)
                .registerStoredProcedureParameter("p_refund_amount", BigDecimal.class, ParameterMode.OUT)
                .registerStoredProcedureParameter("p_message", String.class, ParameterMode.OUT)
                .setParameter("p_order_id", orderId)
                .setParameter("p_trader_id", traderId);

        query.execute();

        Map<String, Object> result = Map.of(
                "success", query.getOutputParameterValue("p_success"),
                "refundAmount", query.getOutputParameterValue("p_refund_amount"),
                "message", query.getOutputParameterValue("p_message")
        );
        return ResponseEntity.ok(result);
    }
}
