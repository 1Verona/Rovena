import { Router } from 'express';
import { OpenAI } from 'openai';
import type { AuthedRequest } from '../middleware/auth';

const router = Router();

const openai = new OpenAI({
  apiKey: process.env.OPENAI_API_KEY,
});

router.post('/', async (req: AuthedRequest, res) => {
  if (!req.user) return res.status(401).json({ error: 'Unauthorized' });

  const { prompt } = req.body as { prompt?: string };

  if (!prompt) {
    return res.status(400).json({ error: 'prompt is required' });
  }

  try {
    // TODO: check user quota/plan before calling provider

    const result = await openai.images.generate({
      model: 'dall-e-3',
      prompt,
      n: 1,
      size: '1024x1024',
    });

    const url = result.data[0]?.url;
    if (!url) {
      return res.status(500).json({ error: 'Image provider did not return URL' });
    }

    // In a more advanced version you might proxy/download and store on your own CDN.
    return res.json({ url });
  } catch (err: any) {
    console.error('[image] error', err.response?.data || err.message || err);
    return res.status(500).json({ error: 'Image provider error', details: err.message });
  }
});

export const imageRouter = router;
