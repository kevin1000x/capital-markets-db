// Spring Data JPA repository — query methods are auto-generated from method names
package com.trading.repository;

import com.trading.model.Order;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface OrderRepository extends JpaRepository<Order, Long> {

    List<Order> findByTraderId(Long traderId);

    List<Order> findByTraderIdAndOrderStatus(Long traderId, String orderStatus);
}
