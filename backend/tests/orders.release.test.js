const test = require('node:test');
const assert = require('node:assert/strict');
const jwt = require('jsonwebtoken');
const pool = require('../db');
const env = require('../src/config/env');
const messages = require('../src/constants/messages');
const { createApp } = require('../src/app');

const originalQuery = pool.query;
const originalGetConnection = pool.getConnection;

let server;
let baseUrl;

const tokenFor = (user) => jwt.sign(user, env.jwtSecret, { expiresIn: '1h' });

const request = async (path, { method = 'GET', token, body } = {}) => {
  const response = await fetch(`${baseUrl}${path}`, {
    method,
    headers: {
      ...(body ? { 'Content-Type': 'application/json' } : {}),
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    ...(body ? { body: JSON.stringify(body) } : {}),
  });

  return {
    status: response.status,
    body: await response.json(),
  };
};

const mockReleaseDatabase = ({ order, need }) => {
  const state = {
    order: { ...order },
    need: { ...need },
    queries: [],
    getConnectionCalls: 0,
    committed: false,
    rolledBack: false,
    connectionReleased: false,
  };

  pool.query = async (sql, params) => {
    state.queries.push({ sql, params });

    if (sql === 'SELECT * FROM orders WHERE id = ?') {
      return [[{ ...state.order }]];
    }

    throw new Error(`未 mock 的查询: ${sql}`);
  };

  const connection = {
    beginTransaction: async () => {},
    commit: async () => {
      state.committed = true;
    },
    rollback: async () => {
      state.rolledBack = true;
    },
    release: () => {
      state.connectionReleased = true;
    },
    query: async (sql, params = []) => {
      state.queries.push({ sql, params });

      if (sql === 'SELECT * FROM needs WHERE id = ? FOR UPDATE') {
        return [[{ ...state.need }]];
      }

      if (sql === 'SELECT * FROM orders WHERE id = ? FOR UPDATE') {
        return [[{ ...state.order }]];
      }

      if (sql === 'UPDATE orders SET status = ?, cancel_reason = ? WHERE id = ?') {
        state.order.status = params[0];
        state.order.cancel_reason = params[1];
        return [{ affectedRows: 1 }];
      }

      if (sql === "UPDATE needs SET status = 'pending', volunteer_id = NULL WHERE id = ? AND volunteer_id = ? AND status = 'accepted'") {
        const canReleaseNeed = state.need.id === params[0]
          && state.need.volunteer_id === params[1]
          && state.need.status === 'accepted';

        if (!canReleaseNeed) {
          return [{ affectedRows: 0 }];
        }

        state.need.status = 'pending';
        state.need.volunteer_id = null;
        return [{ affectedRows: 1 }];
      }

      throw new Error(`未 mock 的事务查询: ${sql}`);
    },
  };

  pool.getConnection = async () => {
    state.getConnectionCalls += 1;
    return connection;
  };

  return state;
};

test.before(async () => {
  const app = createApp();
  await new Promise((resolve) => {
    server = app.listen(0, '127.0.0.1', resolve);
  });
  baseUrl = `http://127.0.0.1:${server.address().port}`;
});

test.after(async () => {
  pool.query = originalQuery;
  pool.getConnection = originalGetConnection;
  await new Promise((resolve) => server.close(resolve));
  await pool.end();
});

test('接单志愿者填写原因后释放订单，重复提交只保留第一次结果', async () => {
  const state = mockReleaseDatabase({
    order: {
      id: 10,
      need_id: 20,
      user_id: 4,
      volunteer_id: 2,
      status: 'in_progress',
      cancel_reason: null,
    },
    need: {
      id: 20,
      user_id: 4,
      volunteer_id: 2,
      status: 'accepted',
    },
  });
  const token = tokenFor({ id: 2, role: 'volunteer' });

  const first = await request('/api/orders/10/release', {
    method: 'POST',
    token,
    body: { cancel_reason: '  临时有事，无法按时上门  ' },
  });

  assert.equal(first.status, 200);
  assert.equal(first.body.message, messages.orders.released);
  assert.equal(state.order.status, 'cancelled');
  assert.equal(state.order.cancel_reason, '临时有事，无法按时上门');
  assert.deepEqual(
    { status: state.need.status, volunteer_id: state.need.volunteer_id },
    { status: 'pending', volunteer_id: null },
  );
  assert.equal(state.committed, true);
  assert.equal(state.connectionReleased, true);

  const second = await request('/api/orders/10/release', {
    method: 'POST',
    token,
    body: { cancel_reason: '第二次提交的原因' },
  });

  assert.equal(second.status, 400);
  assert.equal(second.body.message, messages.orders.alreadyCancelled);
  assert.equal(state.order.cancel_reason, '临时有事，无法按时上门');
  assert.equal(
    state.queries.filter(({ sql }) => sql === 'UPDATE orders SET status = ?, cancel_reason = ? WHERE id = ?').length,
    1,
  );
  assert.equal(state.getConnectionCalls, 1);
});

test('已完成的订单不能释放', async () => {
  const state = mockReleaseDatabase({
    order: {
      id: 11,
      need_id: 21,
      user_id: 4,
      volunteer_id: 2,
      status: 'completed',
      cancel_reason: null,
    },
    need: {
      id: 21,
      user_id: 4,
      volunteer_id: 2,
      status: 'completed',
    },
  });
  const token = tokenFor({ id: 2, role: 'volunteer' });

  const response = await request('/api/orders/11/release', {
    method: 'POST',
    token,
    body: { cancel_reason: '临时无法服务' },
  });

  assert.equal(response.status, 400);
  assert.equal(response.body.message, messages.orders.completedCannotRelease);
  assert.equal(state.order.status, 'completed');
  assert.equal(state.order.cancel_reason, null);
  assert.equal(state.need.status, 'completed');
  assert.equal(state.getConnectionCalls, 0);
});

test('其他志愿者不能替接单者释放订单', async () => {
  const state = mockReleaseDatabase({
    order: {
      id: 12,
      need_id: 22,
      user_id: 4,
      volunteer_id: 3,
      status: 'in_progress',
      cancel_reason: null,
    },
    need: {
      id: 22,
      user_id: 4,
      volunteer_id: 3,
      status: 'accepted',
    },
  });
  const token = tokenFor({ id: 2, role: 'volunteer' });

  const response = await request('/api/orders/12/release', {
    method: 'POST',
    token,
    body: { cancel_reason: '代替对方取消' },
  });

  assert.equal(response.status, 403);
  assert.equal(response.body.message, messages.orders.onlyAssignedVolunteer);
  assert.equal(state.order.status, 'in_progress');
  assert.equal(state.need.status, 'accepted');
  assert.equal(state.getConnectionCalls, 0);
});

test('释放订单必须填写原因', async () => {
  const state = mockReleaseDatabase({
    order: {
      id: 13,
      need_id: 23,
      user_id: 4,
      volunteer_id: 2,
      status: 'in_progress',
      cancel_reason: null,
    },
    need: {
      id: 23,
      user_id: 4,
      volunteer_id: 2,
      status: 'accepted',
    },
  });
  const token = tokenFor({ id: 2, role: 'volunteer' });

  const response = await request('/api/orders/13/release', {
    method: 'POST',
    token,
    body: { cancel_reason: '   ' },
  });

  assert.equal(response.status, 400);
  assert.equal(response.body.message, messages.orders.missingCancelReason);
  assert.equal(state.order.status, 'in_progress');
  assert.equal(state.need.status, 'accepted');
  assert.equal(state.getConnectionCalls, 0);
});
