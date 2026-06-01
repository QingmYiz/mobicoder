import { loadConfig } from './config.js';
import { createChatCompletion, streamChatCompletion } from './newapi.js';

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

    await streamOpenAICompatible(res, provider, model, messages);

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

async function streamOpenAICompatible(res, provider, model, messages) {
  await streamChatCompletion({
    apiKey: provider.apiKey,
    baseUrl: provider.baseUrl,
    model,
    messages,
    temperature: provider.temperature,
    topP: provider.topP,
    maxTokens: provider.maxTokens,
    maxCompletionTokens: provider.maxCompletionTokens,
    reasoningEffort: provider.reasoningEffort,
    onDelta: (delta) => {
      res.write(`data: ${JSON.stringify({ delta })}\n\n`);
    },
    onDone: (event) => {
      if (event?.finish_reason) {
        res.write(`data: ${JSON.stringify({ done: true, finish_reason: event.finish_reason })}\n\n`);
      }
    },
  });
}

export async function createChatCompletionOnce({ provider, model, messages, ...options }) {
  return createChatCompletion({
    apiKey: provider.apiKey,
    baseUrl: provider.baseUrl,
    model,
    messages,
    stream: false,
    ...options,
  });
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
