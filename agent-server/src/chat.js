import OpenAI from 'openai';
import { loadConfig } from './config.js';

/**
 * POST /api/chat
 * Body: { messages: [{role, content}], provider?: string, model?: string }
 * Returns: SSE stream with data: {delta, done}
 */
export async function handleChat(req, res) {
  const { messages, provider: providerId, model: modelId } = req.body;

  if (!messages || !Array.isArray(messages)) {
    return res.status(400).json({ error: 'messages array required' });
  }

  try {
    const config = await loadConfig();
    const provider = resolveProvider(config, providerId);

    if (!provider) {
      return res.status(400).json({ error: 'No AI provider configured. Set up an API key first.' });
    }

    const model = modelId || provider.defaultModel || 'gpt-4o';

    // Set SSE headers
    res.writeHead(200, {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache',
      'Connection': 'keep-alive',
      'X-Accel-Buffering': 'no',
    });

    if (provider.type === 'openai' || provider.baseUrl?.includes('openai')) {
      await streamOpenAI(res, provider, model, messages);
    } else if (provider.type === 'anthropic') {
      await streamAnthropic(res, provider, model, messages);
    } else {
      // Generic OpenAI-compatible
      await streamOpenAI(res, provider, model, messages);
    }

    res.write('data: [DONE]\n\n');
    res.end();
  } catch (e) {
    if (!res.headersSent) {
      return res.status(500).json({ error: e.message });
    }
    res.write(`data: ${JSON.stringify({ error: e.message })}\n\n`);
    res.end();
  }
}

async function streamOpenAI(res, provider, model, messages) {
  const client = new OpenAI({
    apiKey: provider.apiKey,
    baseURL: provider.baseUrl || 'https://api.openai.com/v1',
  });

  const stream = await client.chat.completions.create({
    model,
    messages: messages.map(m => ({ role: m.role, content: m.content })),
    stream: true,
  });

  for await (const chunk of stream) {
    const delta = chunk.choices?.[0]?.delta?.content;
    if (delta) {
      res.write(`data: ${JSON.stringify({ delta })}\n\n`);
    }
    if (chunk.choices?.[0]?.finish_reason) {
      res.write(`data: ${JSON.stringify({ done: true, finish_reason: chunk.choices[0].finish_reason })}\n\n`);
    }
  }
}

async function streamAnthropic(res, provider, model, messages) {
  // Use OpenAI-compatible endpoint if available, otherwise use Anthropic SDK
  // Most providers expose OpenAI-compatible API nowadays
  const client = new OpenAI({
    apiKey: provider.apiKey,
    baseURL: provider.baseUrl || 'https://api.anthropic.com/v1',
  });

  const stream = await client.chat.completions.create({
    model,
    messages: messages.map(m => ({ role: m.role, content: m.content })),
    stream: true,
  });

  for await (const chunk of stream) {
    const delta = chunk.choices?.[0]?.delta?.content;
    if (delta) {
      res.write(`data: ${JSON.stringify({ delta })}\n\n`);
    }
    if (chunk.choices?.[0]?.finish_reason) {
      res.write(`data: ${JSON.stringify({ done: true })}\n\n`);
    }
  }
}

function resolveProvider(config, providerId) {
  const models = config.models;
  if (!models || !models.providers) return null;

  const providers = models.providers;
  if (providerId && providers[providerId]) {
    const p = providers[providerId];
    return {
      ...p,
      type: providerId,
      defaultModel: p.models?.[0]?.id || 'gpt-4o',
    };
  }

  // Pick first configured provider
  const keys = Object.keys(providers);
  if (keys.length === 0) return null;
  const first = providers[keys[0]];
  return {
    ...first,
    type: keys[0],
    defaultModel: first.models?.[0]?.id || 'gpt-4o',
  };
}
