const env = require('../config/env');

const ensureOrderCancelReason = async (pool) => {
  const [columns] = await pool.query(
    `SELECT COLUMN_NAME
     FROM INFORMATION_SCHEMA.COLUMNS
     WHERE TABLE_SCHEMA = ? AND TABLE_NAME = 'orders' AND COLUMN_NAME = 'cancel_reason'`,
    [env.database.name],
  );

  if (columns.length === 0) {
    await pool.query(
      "ALTER TABLE orders ADD COLUMN cancel_reason TEXT NULL COMMENT '取消原因' AFTER status",
    );
  }
};

const ensureSchema = async (pool) => {
  await ensureOrderCancelReason(pool);
};

module.exports = ensureSchema;
