import express from 'express';
import cors from 'cors';
import "dotenv/config";

import { authMiddleware } from './middleware/auth';
import { chatRouter } from './routes/chat';
import { imageRouter } from './routes/image';

const app = express();
const port = process.env.PORT || 8787;

app.use(cors());
app.use(express.json({ limit: '2mb' }));

app.get('/health', (_req, res) => {
  res.json({ status: 'ok', service: 'rovena-backend' });
});

// All API routes require Firebase-authenticated user
app.use('/api', authMiddleware);
app.use('/api/chat', chatRouter);
app.use('/api/image', imageRouter);

app.listen(port, () => {
  console.log(`[rovena-backend] listening on port ${port}`);
});
