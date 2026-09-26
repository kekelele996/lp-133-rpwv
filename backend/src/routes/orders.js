const { Router } = require('express');
const pool = require('../../db');
const messages = require('../constants/messages');
const { authenticateToken } = require('../middleware/auth');
const asyncHandler = require('../utils/asyncHandler');

const router = Router();

router.get('/', authenticateToken, asyncHandler(async (req, res) => {
  const { status } = req.query;
  let sql = `SELECT o.*, n.title, n.type, n.address,
    u1.name as user_name, u2.name as volunteer_name
    FROM orders o
    LEFT JOIN needs n ON o.need_id = n.id
    LEFT JOIN users u1 ON o.user_id = u1.id
    LEFT JOIN users u2 ON o.volunteer_id = u2.id
    WHERE o.user_id = ? OR o.volunteer_id = ?`;
  const params = [req.user.id, req.user.id];

  if (status) {
    sql += ' AND o.status = ?';
    params.push(status);
  }

  sql += ' ORDER BY o.created_at DESC';

  const [rows] = await pool.query(sql, params);
  res.json({ orders: rows });
}));

// 志愿者释放订单：填写原因 -> 订单取消并保留原因，需求回到待接单
router.post('/:id/release', authenticateToken, asyncHandler(async (req, res) => {
  const orderId = req.params.id;
  const cancelReason = typeof req.body.cancel_reason === 'string'
    ? req.body.cancel_reason.trim()
    : '';

  if (!cancelReason) {
    return res.status(400).json({ message: messages.orders.releaseReasonRequired });
  }

  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();

    // 行锁锁定订单，防止完成/释放并发提交
    const [orders] = await conn.query(
      'SELECT * FROM orders WHERE id = ? FOR UPDATE',
      [orderId],
    );

    if (orders.length === 0) {
      await conn.rollback();
      return res.status(404).json({ message: messages.orders.notFound });
    }

    const order = orders[0];

    // 只有接单志愿者本人可以释放，居民和其他志愿者都不能操作
    if (order.volunteer_id !== req.user.id) {
      await conn.rollback();
      return res.status(403).json({ message: messages.orders.onlyVolunteerCanRelease });
    }

    // 已经完成的订单不能释放
    if (order.status === 'completed') {
      await conn.rollback();
      return res.status(400).json({ message: messages.orders.completedCannotRelease });
    }

    // 重复提交只保留第一次结果：已取消的订单直接按成功返回，原原因不动
    if (order.status === 'cancelled') {
      await conn.commit();
      return res.json({ message: messages.orders.released });
    }

    // 条件更新保证“只留第一次结果”，affectedRows 为 0 说明已被并发处理
    const [cancelResult] = await conn.query(
      "UPDATE orders SET status = 'cancelled', cancel_reason = ? WHERE id = ? AND status = 'in_progress'",
      [cancelReason.slice(0, 500), orderId],
    );

    if (cancelResult.affectedRows === 0) {
      await conn.rollback();
      return res.status(400).json({ message: messages.orders.completedCannotRelease });
    }

    // 需求回到待接单，让出接单志愿者，居民和其他志愿者可再次接单
    const [needResult] = await conn.query(
      "UPDATE needs SET status = 'pending', volunteer_id = NULL WHERE id = ? AND status = 'accepted' AND volunteer_id = ?",
      [order.need_id, req.user.id],
    );

    if (needResult.affectedRows === 0) {
      // 订单已释放但需求状态与预期不一致，整体回滚避免出现“订单取消但需求仍占用”
      await conn.rollback();
      return res.status(400).json({ message: messages.needs.notFound });
    }

    await conn.commit();
    res.json({ message: messages.orders.released });
  } catch (err) {
    await conn.rollback();
    throw err;
  } finally {
    conn.release();
  }
}));

router.put('/:id/complete', authenticateToken, asyncHandler(async (req, res) => {
  const { service_hours } = req.body;
  const orderId = req.params.id;

  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();

    const [orders] = await conn.query(
      'SELECT * FROM orders WHERE id = ? FOR UPDATE',
      [orderId],
    );

    if (orders.length === 0) {
      await conn.rollback();
      return res.status(404).json({ message: messages.orders.notFound });
    }

    if (orders[0].user_id !== req.user.id && orders[0].volunteer_id !== req.user.id) {
      await conn.rollback();
      return res.status(403).json({ message: messages.orders.forbidden });
    }

    // 已完成或已释放（已取消）的订单不能再完成，重复提交只保留第一次结果
    if (orders[0].status !== 'in_progress') {
      await conn.rollback();
      const message = orders[0].status === 'completed'
        ? messages.orders.completedCannotRelease
        : messages.orders.cancelledCannotComplete;
      return res.status(400).json({ message });
    }

    const hours = service_hours || 1;

    const [completeResult] = await conn.query(
      "UPDATE orders SET status = 'completed', service_hours = ?, end_time = NOW() WHERE id = ? AND status = 'in_progress'",
      [hours, orderId],
    );

    if (completeResult.affectedRows === 0) {
      await conn.rollback();
      return res.status(400).json({ message: messages.orders.completedCannotRelease });
    }

    await conn.query(
      "UPDATE needs SET status = 'completed' WHERE id = ?",
      [orders[0].need_id],
    );

    await conn.query(
      'UPDATE users SET service_hours = service_hours + ?, points = points + ? WHERE id = ?',
      [hours, hours * 10, orders[0].volunteer_id],
    );

    await conn.commit();
    res.json({ message: messages.orders.completed });
  } catch (err) {
    await conn.rollback();
    throw err;
  } finally {
    conn.release();
  }
}));

router.post('/:id/review', authenticateToken, asyncHandler(async (req, res) => {
  const { rating, comment } = req.body;
  const orderId = req.params.id;
  const [orders] = await pool.query('SELECT * FROM orders WHERE id = ?', [orderId]);

  if (orders.length === 0) {
    return res.status(404).json({ message: messages.orders.notFound });
  }

  const targetId = orders[0].user_id === req.user.id
    ? orders[0].volunteer_id
    : orders[0].user_id;

  await pool.query(
    'INSERT INTO reviews (order_id, reviewer_id, target_id, rating, comment) VALUES (?, ?, ?, ?, ?)',
    [orderId, req.user.id, targetId, rating, comment],
  );

  res.json({ message: messages.orders.reviewed });
}));

module.exports = router;
