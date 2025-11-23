import { Router } from 'express';
import { OpenAI } from 'openai';
import type { AuthedRequest } from '../middleware/auth';

const router = Router();

const openai = new OpenAI({
  apiKey: process.env.OPENAI_API_KEY,
});

router.post('/', async (req: AuthedRequest, res) => {
  if (!req.user) return res.status(401).json({ error: 'Unauthorized' });

  const { model, messages } = req.body as {
    model?: string;
    messages?: { role: string; content: string }[];
  };

  if (!model || !messages || !Array.isArray(messages)) {
    return res.status(400).json({ error: 'model and messages are required' });
  }

  try {
    // TODO: load user plan/limits from DB and check quota before calling provider

    const completion = await openai.chat.completions.create({
      model,
      messages: messages.map(m => ({ role: m.role as any, content: m.content })),
    });

    // TODO: read usage from completion.usage and store it per user (Firestore, etc.)

    return res.json(completion);
  } catch (err: any) {
    console.error('[chat] error', err.response?.data || err.message || err);
    return res.status(500).json({ error: 'Chat provider error', details: err.message });
  }
});

export const chatRouter = router;
