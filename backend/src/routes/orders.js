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

router.post('/:id/release', authenticateToken, asyncHandler(async (req, res) => {
  const rawCancelReason = req.body.cancel_reason ?? req.body.reason;
  const cancelReason = typeof rawCancelReason === 'string'
    ? rawCancelReason.trim()
    : '';
  const orderId = req.params.id;

  if (!cancelReason) {
    return res.status(400).json({ message: messages.orders.missingCancelReason });
  }

  const [existingOrders] = await pool.query('SELECT * FROM orders WHERE id = ?', [orderId]);
  if (existingOrders.length === 0) {
    return res.status(404).json({ message: messages.orders.notFound });
  }

  if (existingOrders[0].volunteer_id !== req.user.id) {
    return res.status(403).json({ message: messages.orders.onlyAssignedVolunteer });
  }

  if (existingOrders[0].status === 'completed') {
    return res.status(400).json({ message: messages.orders.completedCannotRelease });
  }

  if (existingOrders[0].status === 'cancelled') {
    return res.status(400).json({ message: messages.orders.alreadyCancelled });
  }

  if (existingOrders[0].status !== 'in_progress') {
    return res.status(400).json({ message: messages.orders.notInProgress });
  }

  const connection = await pool.getConnection();
  try {
    await connection.beginTransaction();

    const [needs] = await connection.query(
      'SELECT * FROM needs WHERE id = ? FOR UPDATE',
      [existingOrders[0].need_id],
    );
    const [orders] = await connection.query(
      'SELECT * FROM orders WHERE id = ? FOR UPDATE',
      [orderId],
    );
    const order = orders[0];

    if (!order || needs.length === 0 || order.status !== 'in_progress' || order.volunteer_id !== req.user.id) {
      await connection.rollback();
      if (!order) {
        return res.status(404).json({ message: messages.orders.notFound });
      }
      if (order.volunteer_id !== req.user.id) {
        return res.status(403).json({ message: messages.orders.onlyAssignedVolunteer });
      }
      if (order.status === 'completed') {
        return res.status(400).json({ message: messages.orders.completedCannotRelease });
      }
      if (order.status === 'cancelled') {
        return res.status(400).json({ message: messages.orders.alreadyCancelled });
      }
      return res.status(400).json({ message: messages.orders.notInProgress });
    }

    await connection.query(
      'UPDATE orders SET status = ?, cancel_reason = ? WHERE id = ?',
      ['cancelled', cancelReason, orderId],
    );

    const [needResult] = await connection.query(
      "UPDATE needs SET status = 'pending', volunteer_id = NULL WHERE id = ? AND volunteer_id = ? AND status = 'accepted'",
      [order.need_id, req.user.id],
    );

    if (needResult.affectedRows !== 1) {
      throw new Error('释放订单时需求状态不一致');
    }

    await connection.commit();
    res.json({ message: messages.orders.released });
  } catch (error) {
    await connection.rollback();
    throw error;
  } finally {
    connection.release();
  }
}));

router.put('/:id/complete', authenticateToken, asyncHandler(async (req, res) => {
  const { service_hours } = req.body;
  const orderId = req.params.id;
  const [orders] = await pool.query('SELECT * FROM orders WHERE id = ?', [orderId]);

  if (orders.length === 0) {
    return res.status(404).json({ message: messages.orders.notFound });
  }

  if (orders[0].user_id !== req.user.id && orders[0].volunteer_id !== req.user.id) {
    return res.status(403).json({ message: messages.orders.forbidden });
  }

  if (orders[0].status !== 'in_progress') {
    return res.status(400).json({ message: messages.orders.notInProgress });
  }

  const hours = service_hours || 1;
  const connection = await pool.getConnection();
  try {
    await connection.beginTransaction();

    const [needs] = await connection.query(
      'SELECT * FROM needs WHERE id = ? FOR UPDATE',
      [orders[0].need_id],
    );
    const [lockedOrders] = await connection.query(
      'SELECT * FROM orders WHERE id = ? FOR UPDATE',
      [orderId],
    );
    const order = lockedOrders[0];

    if (!order || needs.length === 0 || order.status !== 'in_progress') {
      await connection.rollback();
      if (!order) {
        return res.status(404).json({ message: messages.orders.notFound });
      }
      if (order.status === 'completed') {
        return res.status(400).json({ message: messages.orders.alreadyCompleted });
      }
      if (order.status === 'cancelled') {
        return res.status(400).json({ message: messages.orders.cancelledCannotComplete });
      }
      return res.status(400).json({ message: messages.orders.notInProgress });
    }

    await connection.query(
      "UPDATE orders SET status = 'completed', service_hours = ?, end_time = NOW() WHERE id = ?",
      [hours, orderId],
    );

    await connection.query(
      "UPDATE needs SET status = 'completed' WHERE id = ?",
      [order.need_id],
    );

    await connection.query(
      'UPDATE users SET service_hours = service_hours + ?, points = points + ? WHERE id = ?',
      [hours, hours * 10, order.volunteer_id],
    );

    await connection.commit();
    res.json({ message: messages.orders.completed });
  } catch (error) {
    await connection.rollback();
    throw error;
  } finally {
    connection.release();
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
