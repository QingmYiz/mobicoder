const DEFAULT_BASE_URL = 'https://api.openai.com/v1';

export class NewApiError extends Error {
  constructor(message, { status, code, type, param, body } = {}) {
    super(message);
    this.name = 'NewApiError';
    this.status = status;
    this.code = code;
    this.type = type;
    this.param = param;
    this.body = body;
  }
}

export function normalizeBaseUrl(baseUrl) {
  const value = (baseUrl || DEFAULT_BASE_URL).trim().replace(/\/+$/, '');
  return value.endsWith('/v1') ? value : `${value}/v1`;
}

export function buildChatCompletionUrl(baseUrl) {
  return `${normalizeBaseUrl(baseUrl)}/chat/completions`;
}

export function buildChatCompletionPayload({
  model,
  messages,
  stream = true,
  temperature,
  topP,
  maxTokens,
  maxCompletionTokens,
  stop,
  tools,
  toolChoice,
  responseFormat,
  reasoningEffort,
  seed,
  user,
}) {
  if (!model) {
    throw new NewApiError('model is required');
  }
  if (!Array.isArray(messages) || messages.length === 0) {
    throw new NewApiError('messages array required');
  }

  const payload = {
    model,
    messages: messages.map(normalizeMessage),
    stream,
  };

  assignIfDefined(payload, 'temperature', temperature);
  assignIfDefined(payload, 'top_p', topP);
  assignIfDefined(payload, 'max_tokens', maxTokens);
  assignIfDefined(payload, 'max_completion_tokens', maxCompletionTokens);
  assignIfDefined(payload, 'stop', stop);
  assignIfDefined(payload, 'tools', tools);
  assignIfDefined(payload, 'tool_choice', toolChoice);
  assignIfDefined(payload, 'response_format', responseFormat);
  assignIfDefined(payload, 'reasoning_effort', reasoningEffort);
  assignIfDefined(payload, 'seed', seed);
  assignIfDefined(payload, 'user', user);

  return payload;
}

export async function createChatCompletion({
  apiKey,
  baseUrl,
  model,
  messages,
  stream = false,
  signal,
  ...options
}) {
  if (!apiKey) {
    throw new NewApiError('API key is required');
  }

  const response = await fetch(buildChatCompletionUrl(baseUrl), {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(buildChatCompletionPayload({
      model,
      messages,
      stream,
      ...options,
    })),
    signal,
  });

  if (!response.ok) {
    throw await parseNewApiError(response);
  }

  if (stream) {
    return response.body;
  }

  return response.json();
}

export async function streamChatCompletion({
  apiKey,
  baseUrl,
  model,
  messages,
  onDelta,
  onDone,
  onToolCall,
  signal,
  ...options
}) {
  const body = await createChatCompletion({
    apiKey,
    baseUrl,
    model,
    messages,
    stream: true,
    signal,
    ...options,
  });

  if (!body) {
    throw new NewApiError('Empty stream response');
  }

  const decoder = new TextDecoder();
  let buffer = '';

  for await (const chunk of body) {
    buffer += decoder.decode(chunk, { stream: true });
    const lines = buffer.split(/\r?\n/);
    buffer = lines.pop() || '';

    for (const line of lines) {
      await consumeSseLine(line, { onDelta, onDone, onToolCall });
    }
  }

  if (buffer.trim()) {
    await consumeSseLine(buffer, { onDelta, onDone, onToolCall });
  }
}

async function consumeSseLine(line, handlers) {
  const trimmed = line.trim();
  if (!trimmed || trimmed.startsWith(':')) return;
  if (!trimmed.startsWith('data:')) return;

  const data = trimmed.slice(5).trim();
  if (!data) return;
  if (data === '[DONE]') {
    await handlers.onDone?.({ done: true });
    return;
  }

  let json;
  try {
    json = JSON.parse(data);
  } catch {
    return;
  }

  const choice = json.choices?.[0];
  const delta = choice?.delta;
  const text = delta?.content || delta?.reasoning_content;
  if (text) {
    await handlers.onDelta?.(text, json);
  }
  if (delta?.tool_calls?.length) {
    await handlers.onToolCall?.(delta.tool_calls, json);
  }
  if (choice?.finish_reason) {
    await handlers.onDone?.({ finish_reason: choice.finish_reason, raw: json });
  }
}

async function parseNewApiError(response) {
  let body;
  try {
    body = await response.json();
  } catch {
    body = { error: { message: await response.text() } };
  }

  const error = body?.error || {};
  return new NewApiError(
    error.message || `Chat completion request failed with HTTP ${response.status}`,
    {
      status: response.status,
      code: error.code,
      type: error.type,
      param: error.param,
      body,
    },
  );
}

function normalizeMessage(message) {
  if (!message || typeof message !== 'object') {
    throw new NewApiError('message must be an object');
  }
  const { role, content, name, tool_calls: toolCalls, tool_call_id: toolCallId } = message;
  if (!role) {
    throw new NewApiError('message.role is required');
  }

  const normalized = { role, content: content ?? '' };
  assignIfDefined(normalized, 'name', name);
  assignIfDefined(normalized, 'tool_calls', toolCalls);
  assignIfDefined(normalized, 'tool_call_id', toolCallId);
  return normalized;
}

function assignIfDefined(target, key, value) {
  if (value !== undefined && value !== null) {
    target[key] = value;
  }
}
