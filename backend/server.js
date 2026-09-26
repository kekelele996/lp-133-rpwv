const { createApp } = require('./src/app');
const env = require('./src/config/env');
const messages = require('./src/constants/messages');
const logger = require('./src/utils/logger');
const pool = require('./db');
const ensureSchema = require('./src/utils/ensureSchema');

const startServer = async () => {
  await ensureSchema(pool);
  const app = createApp();

  app.listen(env.port, () => {
    logger.info(`${messages.server.started}，端口: ${env.port}`);
  });
};

startServer().catch((error) => {
  logger.error('数据库结构检查失败，服务无法启动', error);
  process.exit(1);
});
